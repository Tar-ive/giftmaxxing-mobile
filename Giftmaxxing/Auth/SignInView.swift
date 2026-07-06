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

                Text("Create your profile so your taste,\nsaved gifts, and reminders are yours —\non any device.")
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

                Button {
                    Task {
                        await authManager.signInWithGoogle()
                        if authManager.isAuthenticated {
                            showSignIn = false
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        Text("G")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundStyle(Color(hex: "#4285F4"))
                        Text("Continue with Google")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color.ink)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Color.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(Color.line, lineWidth: 1)
                    )
                }

                // Beta collects per-tester behavior — every tester gets a real,
                // distinct profile. The guest door only exists in DEBUG builds.
                #if DEBUG
                Button("Continue as Guest") {
                    showSignIn = false
                }
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)
                #endif
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
