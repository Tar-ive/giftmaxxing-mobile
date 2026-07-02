import Foundation
import AuthenticationServices
import CryptoKit
import UIKit

// Google Sign-In via ASWebAuthenticationSession + PKCE (authorization-code
// flow for iOS OAuth clients — no client secret required).
//
// SETUP (one-time): create an iOS OAuth client in Google Cloud Console
// (APIs & Services → Credentials → Create credentials → OAuth client ID →
// iOS, bundle id com.giftmaxxing.ios) and paste the client id below.
// The reversed-client-id callback scheme is derived automatically.
enum GoogleOAuthConfig {
    // e.g. "1234567890-abc123.apps.googleusercontent.com"
    static let clientID = ""

    static var isConfigured: Bool { !clientID.isEmpty }

    // "com.googleusercontent.apps.1234567890-abc123"
    static var callbackScheme: String {
        let parts = clientID.components(separatedBy: ".")
        return parts.reversed().joined(separator: ".")
    }

    static var redirectURI: String { "\(callbackScheme):/oauth2redirect" }
}

@MainActor
final class GoogleSignInService: NSObject {
    static let shared = GoogleSignInService()

    struct GoogleIdentity {
        let idToken: String
        let sub: String
        let email: String?
        let name: String?
    }

    enum GoogleSignInError: LocalizedError {
        case notConfigured
        case cancelled
        case exchangeFailed

        var errorDescription: String? {
            switch self {
            case .notConfigured:
                return "Google Sign-In isn't configured yet (missing OAuth client id)."
            case .cancelled:
                return ""
            case .exchangeFailed:
                return "Google sign-in failed. Please try again."
            }
        }
    }

    private var session: ASWebAuthenticationSession?

    func signIn() async throws -> GoogleIdentity {
        guard GoogleOAuthConfig.isConfigured else { throw GoogleSignInError.notConfigured }

        // PKCE pair
        let verifier = Self.randomURLSafeString(length: 64)
        let challenge = Self.s256(verifier)

        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: GoogleOAuthConfig.clientID),
            URLQueryItem(name: "redirect_uri", value: GoogleOAuthConfig.redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: "openid email profile"),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
        ]

        let callbackURL: URL = try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: components.url!,
                callbackURLScheme: GoogleOAuthConfig.callbackScheme
            ) { url, error in
                if let url {
                    continuation.resume(returning: url)
                } else if let error = error as? ASWebAuthenticationSessionError,
                          error.code == .canceledLogin {
                    continuation.resume(throwing: GoogleSignInError.cancelled)
                } else {
                    continuation.resume(throwing: GoogleSignInError.exchangeFailed)
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            self.session = session
            session.start()
        }

        guard let code = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "code" })?.value else {
            throw GoogleSignInError.exchangeFailed
        }

        return try await exchangeCode(code, verifier: verifier)
    }

    private func exchangeCode(_ code: String, verifier: String) async throws -> GoogleIdentity {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let params = [
            "client_id": GoogleOAuthConfig.clientID,
            "code": code,
            "code_verifier": verifier,
            "grant_type": "authorization_code",
            "redirect_uri": GoogleOAuthConfig.redirectURI,
        ]
        request.httpBody = params
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? $0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let idToken = json["id_token"] as? String else {
            throw GoogleSignInError.exchangeFailed
        }

        let claims = Self.decodeJWTClaims(idToken)
        guard let sub = claims["sub"] as? String else {
            throw GoogleSignInError.exchangeFailed
        }

        return GoogleIdentity(
            idToken: idToken,
            sub: sub,
            email: claims["email"] as? String,
            name: claims["name"] as? String
        )
    }

    // MARK: - Helpers

    private static func randomURLSafeString(length: Int) -> String {
        let chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
        return String((0..<length).compactMap { _ in chars.randomElement() })
    }

    private static func s256(_ input: String) -> String {
        let digest = SHA256.hash(data: Data(input.utf8))
        return Data(digest)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func decodeJWTClaims(_ jwt: String) -> [String: Any] {
        let parts = jwt.split(separator: ".")
        guard parts.count >= 2 else { return [:] }
        var payload = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while payload.count % 4 != 0 { payload += "=" }
        guard let data = Data(base64Encoded: payload),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return json
    }
}

extension GoogleSignInService: ASWebAuthenticationPresentationContextProviding {
    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap { $0.windows }
                .first { $0.isKeyWindow } ?? ASPresentationAnchor()
        }
    }
}
