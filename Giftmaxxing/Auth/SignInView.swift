import SwiftUI
import AuthenticationServices

struct SignInView: View {
    @EnvironmentObject private var authManager: AuthManager
    @Binding var showSignIn: Bool

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            VStack(spacing: 12) {
                Text("giftmaxxing")
                    .font(.system(size: 32, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.coral)

                Text("Sign in to save your preferences,\nsync across devices, and unlock\npersonalized recommendations.")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }

            VStack(spacing: 16) {
                SignInWithAppleButton(.signIn) { request in
                    request.requestedScopes = [.fullName, .email]
                } onCompletion: { result in
                    authManager.handleAppleSignIn(result: result)
                    if case .success = result {
                        showSignIn = false
                    }
                }
                .signInWithAppleButtonStyle(.black)
                .frame(height: 50)
                .cornerRadius(12)

                Button("Continue as Guest") {
                    showSignIn = false
                }
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 40)

            if authManager.isLoading {
                ProgressView()
                    .padding(.top, 8)
            }

            if let error = authManager.error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 40)
                    .multilineTextAlignment(.center)
            }

            Spacer()

            Text("By continuing, you agree to our\nPrivacy Policy and Terms of Service.")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.bottom, 24)
        }
        .background(Color.surface)
    }
}
