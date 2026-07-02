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

    private init() {
        self.cognitoClientId = Bundle.main.object(forInfoDictionaryKey: "CognitoClientId") as? String ?? ""
        self.cognitoRegion = Bundle.main.object(forInfoDictionaryKey: "CognitoRegion") as? String ?? "us-east-1"
        restoreSession()
    }

    var idToken: String? {
        KeychainStore.loadString(key: tokenKey)
    }

    private func restoreSession() {
        guard let token = KeychainStore.loadString(key: tokenKey),
              let savedUserId = KeychainStore.loadString(key: userIdKey),
              !isTokenExpired(token) else {
            clearSession()
            return
        }
        userId = savedUserId
        isAuthenticated = true
        Task {
            await APIClient.shared.setAuthToken(token)
        }
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

            Task {
                await authenticateWithCognito(
                    appleToken: identityToken,
                    fullName: credential.fullName,
                    email: credential.email
                )
            }

        case .failure(let authError):
            if (authError as NSError).code == ASAuthorizationError.canceled.rawValue {
                return
            }
            self.error = authError.localizedDescription
        }
    }

    private func authenticateWithCognito(appleToken: String, fullName: PersonNameComponents?, email: String?) async {
        isLoading = true
        error = nil

        do {
            let tokenResponse = try await exchangeAppleTokenForCognito(appleToken: appleToken)

            try KeychainStore.saveString(key: tokenKey, value: tokenResponse.idToken)
            if let refreshToken = tokenResponse.refreshToken {
                try KeychainStore.saveString(key: refreshTokenKey, value: refreshToken)
            }

            let sub = extractSub(from: tokenResponse.idToken) ?? UUID().uuidString
            try KeychainStore.saveString(key: userIdKey, value: sub)

            userId = sub
            isAuthenticated = true

            if let name = fullName {
                displayName = [name.givenName, name.familyName]
                    .compactMap { $0 }
                    .joined(separator: " ")
            }
            self.email = email

            await APIClient.shared.setAuthToken(tokenResponse.idToken)

            if let name = displayName ?? email {
                try? await APIClient.shared.saveMe(userId: sub, profile: ["name": name])
            }
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }

    private func exchangeAppleTokenForCognito(appleToken: String) async throws -> CognitoTokenResponse {
        let url = URL(string: "https://cognito-idp.\(cognitoRegion).amazonaws.com/")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-amz-json-1.1", forHTTPHeaderField: "Content-Type")
        request.setValue("AWSCognitoIdentityProviderService.InitiateAuth", forHTTPHeaderField: "X-Amz-Target")

        let body: [String: Any] = [
            "AuthFlow": "USER_SRP_AUTH",
            "ClientId": cognitoClientId,
            "AuthParameters": [
                "USERNAME": "Apple_\(extractSub(fromAppleToken: appleToken) ?? UUID().uuidString)",
                "SRP_A": appleToken,
            ],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw AuthError.cognitoExchangeFailed
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let authResult = json?["AuthenticationResult"] as? [String: Any]

        return CognitoTokenResponse(
            idToken: authResult?["IdToken"] as? String ?? appleToken,
            accessToken: authResult?["AccessToken"] as? String,
            refreshToken: authResult?["RefreshToken"] as? String,
            expiresIn: authResult?["ExpiresIn"] as? Int ?? 3600
        )
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
