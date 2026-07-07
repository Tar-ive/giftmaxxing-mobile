import Foundation

// Headless sign-in for UI automation (Maestro — see .maestro/README.md).
//
// The sign-in wall is mandatory and the guest door is gone, so E2E runs
// authenticate the way a real tester would: with a real Cognito user pool
// account. Maestro passes credentials as launch arguments:
//
//   - launchApp:
//       arguments:
//         e2eEmail: ${E2E_EMAIL}
//         e2ePassword: ${E2E_PASSWORD}
//
// simctl turns `-e2eEmail value` pairs into the NSArgumentDomain, so they
// surface via UserDefaults. DEBUG builds only — Release ignores the hook
// entirely, so no TestFlight/App Store build can ever be driven this way.
enum E2ESupport {
    @MainActor
    static func autoSignInIfRequested(authManager: AuthManager) {
        #if DEBUG
        // Keychain sessions survive Maestro's clearState (app-container wipes
        // don't touch securityd) — `-e2eReset 1` forces a signed-out start.
        if UserDefaults.standard.bool(forKey: "e2eReset") {
            authManager.signOut()
        }
        guard !authManager.isAuthenticated,
              let email = UserDefaults.standard.string(forKey: "e2eEmail"),
              let password = UserDefaults.standard.string(forKey: "e2ePassword"),
              !email.isEmpty, !password.isEmpty else { return }
        Task {
            await authManager.signInWithPassword(email: email, password: password)
        }
        #endif
    }
}
