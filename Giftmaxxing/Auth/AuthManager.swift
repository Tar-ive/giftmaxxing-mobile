import SwiftUI
import AuthenticationServices

@MainActor
final class AuthManager: ObservableObject {
    static let shared = AuthManager()

    @Published var isAuthenticated = false
    @Published var userId: String?
    @Published var displayName: String?
    @Published var email: String?
    @Published var isLoading = false
    @Published var error: String?

    private let cognitoClientId: String
    private let cognitoRegion: String
    private let tokenKey = "auth_id_token"
    private let refreshTokenKey = "auth_refresh_token"
    private let userIdKey = "auth_user_id"
    // Apple only sends name/email on the FIRST authorization ever — persist
    // them or the profile degrades to "Giftmaxxer" on the next launch.
    private let displayNameKey = "auth_display_name"
    private let emailKey = "auth_email"
    // 30-day first-party session JWT from POST /auth/session — outlives the
    // provider tokens (Apple ~10 min, Google ~1 h) that used to knock signed-in
    // users out of /maxi and /me mid-session.
    private let sessionTokenKey = "auth_session_token"

    private init() {
        self.cognitoClientId = Bundle.main.object(forInfoDictionaryKey: "CognitoClientId") as? String ?? ""
        self.cognitoRegion = Bundle.main.object(forInfoDictionaryKey: "CognitoRegion") as? String ?? "us-east-1"
        restoreSession()
    }

    var idToken: String? {
        KeychainStore.loadString(key: tokenKey)
    }

    // Identity (userId) outlives the bearer token: Apple identity tokens
    // expire in ~10 minutes and Google's in ~1 hour, but the account itself
    // is durable. Restore the signed-in state whenever a userId exists and
    // only attach the bearer if it's still fresh — auth-enforced routes will
    // just re-prompt when they need to.
    private func restoreSession() {
        guard let savedUserId = KeychainStore.loadString(key: userIdKey) else {
            clearSession()
            return
        }
        userId = savedUserId
        displayName = KeychainStore.loadString(key: displayNameKey)
        email = KeychainStore.loadString(key: emailKey)
        isAuthenticated = true
        // Prefer the long-lived session token; fall back to a still-fresh
        // provider token and trade it for a session in the background.
        if let sessionToken = KeychainStore.loadString(key: sessionTokenKey), !isTokenExpired(sessionToken) {
            Task {
                await APIClient.shared.setAuthToken(sessionToken)
            }
        } else if let token = KeychainStore.loadString(key: tokenKey), !isTokenExpired(token) {
            Task {
                await APIClient.shared.setAuthToken(token)
                await establishBackendSession()
            }
        }
    }

    // Trade the provider bearer for a first-party session and ADOPT the
    // canonical identity it returns. If this Gmail already has an account
    // from the web app, all its data (profile, events, taste) is now ours.
    private func establishBackendSession() async {
        guard let response = try? await APIClient.shared.establishSession(name: displayName) else { return }
        try? KeychainStore.saveString(key: sessionTokenKey, value: response.token)
        await APIClient.shared.setAuthToken(response.token)
        if response.userId != userId {
            try? KeychainStore.saveString(key: userIdKey, value: response.userId)
            userId = response.userId // triggers per-identity onboarding + feed refetch
        }
        if email == nil, let sessionEmail = response.email {
            email = sessionEmail
            try? KeychainStore.saveString(key: emailKey, value: sessionEmail)
        }
        await APIClient.shared.identify(userId: response.userId, name: displayName, email: email)
    }

    func handleAppleSignIn(result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let identityTokenData = credential.identityToken,
                  let identityToken = String(data: identityTokenData, encoding: .utf8) else {
                self.error = "Failed to get Apple ID token"
                return
            }

            establishAppleSession(credential: credential, identityToken: identityToken)

        case .failure(let authError):
            if (authError as NSError).code == ASAuthorizationError.canceled.rawValue {
                return
            }
            // "Unknown" (1000) here almost always means the Sign in with Apple
            // entitlement isn't provisioned \u{2014} free personal dev teams can't
            // use it. Give an actionable message instead of the OS one.
            if (authError as NSError).code == ASAuthorizationError.unknown.rawValue {
                self.error = "Sign in with Apple isn't available in this development build. Use Google instead."
            } else {
                self.error = authError.localizedDescription
            }
        }
    }

    // Google Sign-In (ASWebAuthenticationSession + PKCE). Establishes a local
    // session from the verified Google ID token; the token is sent as bearer
    // so the backend can adopt Google-federated auth when enforcement lands.
    func signInWithGoogle() async {
        isLoading = true
        error = nil

        do {
            let identity = try await GoogleSignInService.shared.signIn()

            try KeychainStore.saveString(key: tokenKey, value: identity.idToken)
            let userIdValue = "google_\(identity.sub)"
            try KeychainStore.saveString(key: userIdKey, value: userIdValue)

            userId = userIdValue
            displayName = identity.name
            email = identity.email
            if let name = identity.name { try? KeychainStore.saveString(key: displayNameKey, value: name) }
            if let email = identity.email { try? KeychainStore.saveString(key: emailKey, value: email) }
            isAuthenticated = true

            await APIClient.shared.setAuthToken(identity.idToken)

            // Merge-safe identity ping — PUT /me would REPLACE the row and wipe
            // the onboarding profile saved from any platform.
            await APIClient.shared.identify(userId: userIdValue, name: identity.name, email: identity.email)
            // Long-lived session + canonical (email-merged) identity adoption.
            await establishBackendSession()
        } catch let signInError as GoogleSignInService.GoogleSignInError {
            switch signInError {
            case .cancelled:
                break // user dismissed \u{2014} not an error
            case .notConfigured:
                error = "Google Sign-In needs a one-time setup (OAuth client id)."
            case .exchangeFailed:
                error = signInError.errorDescription
            }
        } catch {
            self.error = "Google sign-in failed. Please try again."
        }

        isLoading = false
    }

    // Local session from the verified Apple identity token — mirrors the
    // Google path (no Cognito hop; the token rides as bearer so the backend
    // can verify it when enforcement lands). `credential.user` is the stable
    // per-team Apple user id; name/email only arrive on the FIRST
    // authorization ever, so persist whatever we're given.
    private func establishAppleSession(credential: ASAuthorizationAppleIDCredential, identityToken: String) {
        do {
            try KeychainStore.saveString(key: tokenKey, value: identityToken)
            let userIdValue = "apple_\(credential.user)"
            try KeychainStore.saveString(key: userIdKey, value: userIdValue)

            userId = userIdValue
            if let name = credential.fullName {
                let joined = [name.givenName, name.familyName].compactMap { $0 }.joined(separator: " ")
                if !joined.isEmpty {
                    displayName = joined
                    try? KeychainStore.saveString(key: displayNameKey, value: joined)
                }
            }
            if let credentialEmail = credential.email {
                email = credentialEmail
                try? KeychainStore.saveString(key: emailKey, value: credentialEmail)
            }
            // Re-authorization: Apple withholds name/email — fall back to the
            // values persisted from the first grant.
            if displayName == nil { displayName = KeychainStore.loadString(key: displayNameKey) }
            if email == nil { email = KeychainStore.loadString(key: emailKey) }
            isAuthenticated = true
            error = nil

            Task {
                await APIClient.shared.setAuthToken(identityToken)
                await APIClient.shared.identify(userId: userIdValue, name: displayName, email: email)
                // Long-lived session + canonical (email-merged) identity adoption.
                await establishBackendSession()
            }
        } catch {
            self.error = "Couldn't save your session. Please try again."
        }
    }

    // Email + password against the Cognito user pool (USER_PASSWORD_AUTH).
    // No UI offers this — it exists for the E2E harness (E2ESupport.swift),
    // which signs in a real pool user so automated runs get a real, distinct
    // profile just like any tester. Same session plumbing as Apple/Google.
    func signInWithPassword(email: String, password: String) async {
        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            let url = URL(string: "https://cognito-idp.\(cognitoRegion).amazonaws.com/")!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/x-amz-json-1.1", forHTTPHeaderField: "Content-Type")
            request.setValue("AWSCognitoIdentityProviderService.InitiateAuth", forHTTPHeaderField: "X-Amz-Target")

            let body: [String: Any] = [
                "AuthFlow": "USER_PASSWORD_AUTH",
                "ClientId": cognitoClientId,
                "AuthParameters": [
                    "USERNAME": email,
                    "PASSWORD": password,
                ],
            ]
            request.httpBody = try JSONSerialization.data(withJSONObject: body)

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200,
                  let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let authResult = json["AuthenticationResult"] as? [String: Any],
                  let idToken = authResult["IdToken"] as? String else {
                self.error = "Email sign-in failed. Check the credentials."
                return
            }

            try KeychainStore.saveString(key: tokenKey, value: idToken)
            if let refreshToken = authResult["RefreshToken"] as? String {
                try? KeychainStore.saveString(key: refreshTokenKey, value: refreshToken)
            }

            let sub = extractSub(from: idToken) ?? email
            let userIdValue = "cognito_\(sub)"
            try KeychainStore.saveString(key: userIdKey, value: userIdValue)
            try? KeychainStore.saveString(key: emailKey, value: email)

            let name = extractClaim(from: idToken, key: "name") as? String
            if let name { try? KeychainStore.saveString(key: displayNameKey, value: name) }

            userId = userIdValue
            displayName = name
            self.email = email
            isAuthenticated = true

            await APIClient.shared.setAuthToken(idToken)
            await APIClient.shared.identify(userId: userIdValue, name: name, email: email)
        } catch {
            self.error = "Email sign-in failed. Please try again."
        }
    }

    func refreshTokenIfNeeded() async {
        guard let token = KeychainStore.loadString(key: tokenKey),
              isTokenExpiringSoon(token),
              let refreshToken = KeychainStore.loadString(key: refreshTokenKey) else {
            return
        }

        do {
            let url = URL(string: "https://cognito-idp.\(cognitoRegion).amazonaws.com/")!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/x-amz-json-1.1", forHTTPHeaderField: "Content-Type")
            request.setValue("AWSCognitoIdentityProviderService.InitiateAuth", forHTTPHeaderField: "X-Amz-Target")

            let body: [String: Any] = [
                "AuthFlow": "REFRESH_TOKEN_AUTH",
                "ClientId": cognitoClientId,
                "AuthParameters": [
                    "REFRESH_TOKEN": refreshToken,
                ],
            ]
            request.httpBody = try JSONSerialization.data(withJSONObject: body)

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else { return }

            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let authResult = json?["AuthenticationResult"] as? [String: Any]

            if let newIdToken = authResult?["IdToken"] as? String {
                try KeychainStore.saveString(key: tokenKey, value: newIdToken)
                await APIClient.shared.setAuthToken(newIdToken)
            }
        } catch {
            // silent refresh failure; user will re-auth on next launch
        }
    }

    func signOut() {
        KeychainStore.delete(key: tokenKey)
        KeychainStore.delete(key: refreshTokenKey)
        KeychainStore.delete(key: userIdKey)
        KeychainStore.delete(key: displayNameKey)
        KeychainStore.delete(key: emailKey)
        KeychainStore.delete(key: sessionTokenKey)
        clearSession()
        Task {
            await APIClient.shared.setAuthToken(nil)
        }
    }

    private func clearSession() {
        isAuthenticated = false
        userId = nil
        displayName = nil
        email = nil
    }

    private func isTokenExpired(_ token: String) -> Bool {
        guard let exp = extractExp(from: token) else { return true }
        return Date().timeIntervalSince1970 >= exp
    }

    private func isTokenExpiringSoon(_ token: String) -> Bool {
        guard let exp = extractExp(from: token) else { return true }
        return Date().timeIntervalSince1970 >= (exp - 300)
    }

    private func extractSub(from jwt: String) -> String? {
        extractClaim(from: jwt, key: "sub") as? String
    }

    private func extractExp(from jwt: String) -> Double? {
        extractClaim(from: jwt, key: "exp") as? Double
    }

    private func extractSub(fromAppleToken token: String) -> String? {
        extractSub(from: token)
    }

    private func extractClaim(from jwt: String, key: String) -> Any? {
        let parts = jwt.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var payload = String(parts[1])
        while payload.count % 4 != 0 { payload += "=" }
        guard let data = Data(base64Encoded: payload),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return json[key]
    }
}

struct CognitoTokenResponse {
    let idToken: String
    let accessToken: String?
    let refreshToken: String?
    let expiresIn: Int
}

enum AuthError: LocalizedError {
    case cognitoExchangeFailed
    case tokenRefreshFailed

    var errorDescription: String? {
        switch self {
        case .cognitoExchangeFailed: return "Failed to authenticate with Cognito"
        case .tokenRefreshFailed: return "Failed to refresh authentication token"
        }
    }
}
