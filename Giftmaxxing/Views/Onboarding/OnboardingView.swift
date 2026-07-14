import SwiftUI

// Onboarding is purpose-driven, not a sign-up gauntlet: the glassmorphism
// intro hands off to PurposeOnboardingView's six-step flow (persona →
// contacts/birthdays → preferences → first micro-action → a real sample
// curation with a why-note). Completing it marks the CURRENT identity as
// onboarded (ContentView owns that contract) and queues the dashboard tour
// (CoachMarksView). Maxi's deeper taste consult stays available any time in
// You → Edit taste.
struct OnboardingView: View {
    @Binding var isOnboardingComplete: Bool

    @State private var showGlassmorphismIntro = true

    var body: some View {
        ZStack {
            PurposeOnboardingView {
                isOnboardingComplete = true
            }
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
