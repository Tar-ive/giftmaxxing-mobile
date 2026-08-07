import SwiftUI

// Onboarding is purpose-driven, not a sign-up gauntlet: persona →
// contacts/birthdays → preferences → TASTE CALIBRATION → first micro-action →
// a real sample curation with a why-note. Completing it marks the CURRENT
// identity as onboarded (ContentView owns that contract) and queues the
// dashboard tour (CoachMarksView).
//
// The "Hey — I'm Maxi" splash that used to front this is gone. It cost a full
// screen to say something the app demonstrates two steps later, and it framed
// the product as a chatbot when the thing people actually do first is swipe.
// Maxi is one tap away from every tab, and its deeper taste consult still
// lives in You → Edit taste.
struct OnboardingView: View {
    @Binding var isOnboardingComplete: Bool

    var body: some View {
        PurposeOnboardingView {
            isOnboardingComplete = true
        }
    }
}
