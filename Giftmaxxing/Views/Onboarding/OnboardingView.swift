import SwiftUI

// Onboarding IS the Gift Concierge: a new identity (guest or a freshly
// signed-in account) meets Maxi by running its first real consult. The heavy
// lifting lives in ConsultView (shared with the Concierge tab); this wrapper
// only owns the "done" contract with ContentView, which marks the CURRENT
// identity as onboarded (see PersonalizationStore.markOnboarded).
//
// The flow now opens with a glassmorphism intro screen (inspired by a Figma
// community onboarding design — a glowing gift orb replaces the sun) and then
// hands off to ConsultView's question flow.
struct OnboardingView: View {
    @Binding var isOnboardingComplete: Bool

    @State private var showGlassmorphismIntro = true

    var body: some View {
        ZStack {
            ConsultView(
                isOnboarding: true,
                skipIntro: true,
                onDone: {
                    isOnboardingComplete = true
                }
            )
            if showGlassmorphismIntro {
                GlassmorphismOnboardingView {
                    withAnimation(.easeOut(duration: 0.45)) {
                        showGlassmorphismIntro = false
                    }
                }
                .transition(.opacity)
                .zIndex(1)
            }
        }
    }
}
