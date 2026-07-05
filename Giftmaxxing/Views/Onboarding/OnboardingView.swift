import SwiftUI

// Onboarding IS the Gift Concierge: a new identity (guest or a freshly
// signed-in account) meets Maxi by running its first real consult. The heavy
// lifting lives in ConsultView (shared with the Concierge tab); this wrapper
// only owns the "done" contract with ContentView, which marks the CURRENT
// identity as onboarded (see PersonalizationStore.markOnboarded).
struct OnboardingView: View {
    @Binding var isOnboardingComplete: Bool

    var body: some View {
        ConsultView(isOnboarding: true) {
            isOnboardingComplete = true
        }
    }
}
