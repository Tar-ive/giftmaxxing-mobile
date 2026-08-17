import SwiftUI

// Floating Maxi entry point — the one always-visible door to the concierge.
//
// Maxi owns the app's expressive budget (DESIGN.md → Components), so this is
// the single place a brand-gradient fill, a coral glow, and a `repeatForever`
// pulse are sanctioned. The pulse is what makes it read as "alive and waiting"
// rather than another toolbar icon; it is suppressed under Reduce Motion,
// where the sparkles symbol's own breathe effect carries the affordance.
struct MaxiFloatingButton: View {
    var action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    private let diameter: CGFloat = 56

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(Color.brandGradient)
                    .frame(width: diameter, height: diameter)
                    .shadow(
                        color: Color.coral.opacity(0.35),
                        radius: pulse ? 16 : 10,
                        y: 4
                    )

                // The same mark as the chat avatar — tapping a spark should be
                // answered by a spark.
                MaxiIcon(size: diameter * 0.62, showsBackground: false)
            }
            .scaleEffect(pulse ? 1.04 : 1.0)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Ask Maxi")
        .accessibilityHint("Opens a chat with your gift concierge")
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
        .onChange(of: reduceMotion) { _, isReduced in
            // Honour the setting flipping mid-session: stop the loop and settle
            // the bubble back to rest.
            guard isReduced else { return }
            withAnimation(.snappy) { pulse = false }
        }
    }
}
