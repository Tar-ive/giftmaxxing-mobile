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
    // Runs BEFORE the first onboarding evaluation (ContentView awaits this),
    // so the consult-vs-wall decision is always made for the signed-in E2E
    // identity — iOS versions disagree on who wins simultaneous sheet/cover
    // presentations, and this sequencing sidesteps the race entirely.
    @MainActor
    static func autoSignInIfRequested(authManager: AuthManager) async {
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
        // Freshly-booted CI simulators drop the first network calls while the
        // stack warms up — retry briefly instead of failing the whole run.
        for attempt in 1...5 {
            await authManager.signInWithPassword(email: email, password: password)
            if authManager.isAuthenticated { return }
            try? await Task.sleep(for: .seconds(Double(attempt)))
        }
        #endif
    }
}
