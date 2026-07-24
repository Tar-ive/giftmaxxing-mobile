import SwiftUI

// First-run navigation tour — the TikTok-style "Swipe up for more" overlay,
// adapted to gifting. Shown ONCE, right after a new user finishes onboarding
// (existing users are grandfathered in silently): a dark scrim, one big
// animated glyph per step, and a single line of what to do. Tap anywhere to
// advance.
enum CoachMarks {
    private static let seenKey = "giftmaxxing_coach_marks_seen"

    static var seen: Bool {
        get { UserDefaults.standard.bool(forKey: seenKey) }
        set { UserDefaults.standard.set(newValue, forKey: seenKey) }
    }
}

extension Notification.Name {
    // Settings → "Replay app tour" — ContentView re-presents CoachMarksView.
    static let replayCoachMarks = Notification.Name("giftmaxxing.replayCoachMarks")
}

struct CoachMarksView: View {
    var onFinish: () -> Void

    private struct Step {
        let icon: String
        let title: String
        let line: String
        let hint: String
    }

    // The dashboard tour (onboarding step 6): where the things you just made
    // live — your boards, your gift calendar, and the insights that grow.
    private static let steps: [Step] = [
        Step(
            icon: "rectangle.stack.badge.plus",
            title: "Your Gift Boards",
            line: "One board per person. Share it and they swipe yes/no.",
            hint: "Swipe tab → Gift Boards"
        ),
        Step(
            icon: "calendar",
            title: "Your gift calendar",
            line: "Birthdays and dates live in Circles — Maxi paces each one.",
            hint: "Circles tab"
        ),
        Step(
            icon: "chart.line.uptrend.xyaxis",
            title: "Your Gifting Mind",
            line: "Points, badges, and how recipients really reacted.",
            hint: "You tab"
        ),
        Step(
            icon: "camera.viewfinder",
            title: "Search with your camera",
            line: "Snap or screenshot anything — Maxi finds similar gifts at real stores.",
            hint: "Camera button, top of Home"
        ),
    ]

    @State private var index = 0
    @State private var pulse = false

    private var step: Step { Self.steps[index] }
    private var isLast: Bool { index == Self.steps.count - 1 }

    var body: some View {
        ZStack {
            Color.black.opacity(0.78)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button("Skip") { finish() }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))
                        .padding(16)
                }

                Spacer()

                // One persistent Image whose symbol swaps in place — the
                // repeat-forever pulse keeps running across steps.
                Image(systemName: step.icon)
                    .font(.system(size: 64, weight: .medium))
                    .foregroundStyle(.white)
                    .scaleEffect(pulse ? 1.08 : 0.96)
                    .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: pulse)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(height: 90)

                Text(step.title)
                    .font(.system(size: 28, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.top, 24)

                Text(step.line)
                    .font(.system(size: 15))
                    .foregroundStyle(.white.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 44)
                    .padding(.top, 10)

                HStack(spacing: 6) {
                    Image(systemName: "hand.tap.fill")
                        .font(.system(size: 11))
                    Text(step.hint)
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(Color.coral)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.white.opacity(0.12))
                .clipShape(Capsule())
                .padding(.top, 18)

                Spacer()

                HStack(spacing: 6) {
                    ForEach(0..<Self.steps.count, id: \.self) { i in
                        Capsule()
                            .fill(i == index ? Color.coral : .white.opacity(0.3))
                            .frame(width: i == index ? 18 : 6, height: 6)
                    }
                }
                .animation(.spring(response: 0.3), value: index)

                Button {
                    advance()
                } label: {
                    Text(isLast ? "Start exploring" : "Next")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(Color.coral)
                        .clipShape(Capsule())
                }
                .padding(.horizontal, 40)
                .padding(.top, 22)
                .padding(.bottom, 40)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { advance() }
        .onAppear {
            pulse = true
            AnalyticsEngine.shared.trackScreenView(screen: "coach_marks")
        }
        .transition(.opacity)
    }

    private func advance() {
        if isLast {
            finish()
        } else {
            withAnimation(.spring(response: 0.3)) { index += 1 }
        }
    }

    private func finish() {
        CoachMarks.seen = true
        onFinish()
    }
}
