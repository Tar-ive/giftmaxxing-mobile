import SwiftUI

// First-deck gesture rehearsal (interactive affordance cue): a hand glyph
// traces the swipe-right then swipe-left path over the REAL top card, with
// love/pass ghost badges in sync. The overlay never intercepts touches —
// the rehearsal ends only when the user actually commits their first swipe
// (SwipeView watches yes+no count). Static caption under Reduce Motion.
enum SwipeRehearsal {
    private static let seenKey = "giftmaxxing_swipe_rehearsal_seen"

    static var seen: Bool {
        get { UserDefaults.standard.bool(forKey: seenKey) }
        set { UserDefaults.standard.set(newValue, forKey: seenKey) }
    }
}

struct SwipeRehearsalCue: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct Phase {
        var handX: CGFloat = 0
        var handTilt: Double = 0
        var handOpacity: Double = 0
        var loveOpacity: Double = 0
        var passOpacity: Double = 0
    }

    var body: some View {
        Group {
            if reduceMotion {
                staticHint
            } else {
                animatedCue
            }
        }
        .allowsHitTesting(false)
        .onAppear { AnalyticsEngine.shared.trackScreenView(screen: "swipe_rehearsal") }
        .transition(.opacity)
        .accessibilityLabel("Swipe right to love a gift, left to pass")
    }

    private var staticHint: some View {
        HStack(spacing: 10) {
            Label("Pass", systemImage: "arrow.left")
            Text("·")
                .foregroundStyle(.white.opacity(0.5))
            Label("Love it", systemImage: "arrow.right")
        }
        .font(.footnote.weight(.semibold))
        .foregroundStyle(.white)
        .padding(.horizontal, ThemeSpacing.md)
        .padding(.vertical, ThemeSpacing.xs)
        .background(Color.ink.opacity(0.85))
        .clipShape(Capsule())
    }

    private var animatedCue: some View {
        Image(systemName: "hand.draw.fill")
            .font(.system(size: 44))
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.35), radius: 6, y: 2)
            .keyframeAnimator(initialValue: Phase(), repeating: true) { content, phase in
                ZStack {
                    HStack {
                        ghostBadge("xmark", "Pass", background: Color.ink.opacity(0.78))
                            .opacity(phase.passOpacity)
                        Spacer()
                        ghostBadge("heart.fill", "Love it", background: Color.coral)
                            .opacity(phase.loveOpacity)
                    }
                    .padding(.horizontal, 30)

                    content
                        .offset(x: phase.handX, y: 12)
                        .rotationEffect(.degrees(phase.handTilt))
                        .opacity(phase.handOpacity)
                }
            } keyframes: { _ in
                // One 4.2s pass: fade in center → trace right (love) → back →
                // trace left (pass) → back → fade out → beat of rest.
                KeyframeTrack(\.handX) {
                    CubicKeyframe(0, duration: 0.4)
                    CubicKeyframe(90, duration: 0.8)
                    CubicKeyframe(90, duration: 0.3)
                    CubicKeyframe(0, duration: 0.5)
                    CubicKeyframe(-90, duration: 0.8)
                    CubicKeyframe(-90, duration: 0.3)
                    CubicKeyframe(0, duration: 0.5)
                    CubicKeyframe(0, duration: 0.6)
                }
                KeyframeTrack(\.handTilt) {
                    CubicKeyframe(0, duration: 0.4)
                    CubicKeyframe(14, duration: 0.8)
                    CubicKeyframe(14, duration: 0.3)
                    CubicKeyframe(0, duration: 0.5)
                    CubicKeyframe(-14, duration: 0.8)
                    CubicKeyframe(-14, duration: 0.3)
                    CubicKeyframe(0, duration: 0.5)
                    CubicKeyframe(0, duration: 0.6)
                }
                KeyframeTrack(\.handOpacity) {
                    LinearKeyframe(1, duration: 0.4)
                    LinearKeyframe(1, duration: 3.2)
                    LinearKeyframe(0, duration: 0.3)
                    LinearKeyframe(0, duration: 0.3)
                }
                KeyframeTrack(\.loveOpacity) {
                    LinearKeyframe(0, duration: 0.5)
                    LinearKeyframe(1, duration: 0.7)
                    LinearKeyframe(1, duration: 0.4)
                    LinearKeyframe(0, duration: 0.4)
                    LinearKeyframe(0, duration: 2.2)
                }
                KeyframeTrack(\.passOpacity) {
                    LinearKeyframe(0, duration: 2.0)
                    LinearKeyframe(1, duration: 0.6)
                    LinearKeyframe(1, duration: 0.4)
                    LinearKeyframe(0, duration: 0.4)
                    LinearKeyframe(0, duration: 0.8)
                }
            }
            .frame(maxWidth: .infinity)
    }

    private func ghostBadge(_ icon: String, _ text: String, background: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.footnote.weight(.bold))
            Text(text)
                .font(.footnote.weight(.bold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, ThemeSpacing.sm)
        .padding(.vertical, ThemeSpacing.xs)
        .background(background)
        .clipShape(Capsule())
    }
}
