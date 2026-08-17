import SwiftUI

// Interactive spotlight tour — a scrim with a hole punched over the REAL
// control for each step. The user advances by tapping the actual control
// through the cutout (the rest of the screen absorbs touches), so the tour
// builds muscle memory instead of narrating. Shown once after onboarding;
// replayable via Settings → "Replay app tour".
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

    @EnvironmentObject private var appState: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Target: Equatable {
        case tab(Tab)
        case homeSearchBar
    }

    private struct Step {
        let title: String
        let line: String
        let hint: String
        let target: Target
    }

    private static let steps: [Step] = [
        Step(
            title: "Teach it your taste",
            line: "Every swipe sharpens what the app finds for you.",
            hint: "Tap Swipe",
            target: .tab(.swipe)
        ),
        Step(
            title: "Your boards and calendar",
            line: "Gift Boards, your sizes, and every date you're shopping for.",
            hint: "Tap You",
            target: .tab(.you)
        ),
        Step(
            title: "Search with your camera",
            line: "Snap or screenshot anything — Maxi finds similar gifts at real stores.",
            hint: "Tap the search bar",
            target: .homeSearchBar
        ),
    ]

    @State private var index = 0
    @State private var pulse = false

    private var step: Step { Self.steps[index] }

    var body: some View {
        GeometryReader { geo in
            let cutout = cutoutRect(in: geo)

            ZStack {
                // Scrim with the spotlight hole punched out. Visual only —
                // hit testing is handled by the absorber panels below.
                Color.black.opacity(0.78)
                    .overlay(
                        cutoutShape(cutout)
                            .fill(Color.white)
                            .blendMode(.destinationOut)
                    )
                    .compositingGroup()
                    .allowsHitTesting(false)

                // Tapping anywhere advances. The cutout still highlights the
                // real control, but the tour must never depend on one specific
                // hit-test landing — that's what stranded people mid-tour.
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { advance() }

                // Spotlight ring — barely-breathing coral stroke (first-run
                // affordance exception; static under Reduce Motion).
                RoundedRectangle(
                    cornerRadius: min(cutout.height, cutout.width) / 2 + 5,
                    style: .continuous
                )
                .stroke(Color.coral, lineWidth: 2)
                .frame(width: cutout.width + 10, height: cutout.height + 10)
                .scaleEffect(reduceMotion ? 1 : (pulse ? 1.04 : 0.98))
                .animation(
                    reduceMotion
                        ? nil
                        : .easeInOut(duration: 0.9).repeatForever(autoreverses: true),
                    value: pulse
                )
                .position(x: cutout.midX, y: cutout.midY)
                .allowsHitTesting(false)

                // Step card — copy + progress, kept clear of the cutout.
                VStack(spacing: 0) {
                    HStack {
                        Spacer()
                        Button("Skip") { finish() }
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.7))
                            .padding(ThemeSpacing.md)
                    }
                    Spacer()
                    stepCard
                    Spacer()
                    // Leave the bottom third open so tab-bar cutouts breathe.
                    Color.clear.frame(height: geo.size.height * 0.3)
                }
                .allowsHitTesting(true)
            }
            .ignoresSafeArea()
        }
        .onAppear {
            pulse = true
            AnalyticsEngine.shared.trackScreenView(screen: "coach_marks")
        }
        .onChange(of: appState.selectedTab) { _, newTab in
            if case .tab(let target) = step.target, newTab == target {
                advance()
            }
        }
        .onChange(of: appState.showSearch) { _, isShown in
            if step.target == .homeSearchBar, isShown {
                finish()
            }
        }
        .transition(.opacity)
    }

    private var stepCard: some View {
        VStack(spacing: 10) {
            Text(step.title)
                .font(.system(size: 28, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
            Text(step.line)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.85))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 44)

            HStack(spacing: 6) {
                Image(systemName: "hand.tap.fill")
                    .font(.caption)
                Text(step.hint)
                    .font(.footnote.weight(.semibold))
            }
            .foregroundStyle(Color.coral)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.white.opacity(0.12))
            .clipShape(Capsule())
            .padding(.top, 8)

            Button(index == Self.steps.count - 1 ? "Done" : "Next") { advance() }
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 30)
                .padding(.vertical, 12)
                .background(Color.coral, in: Capsule())
                .padding(.top, 18)

            HStack(spacing: 6) {
                ForEach(0..<Self.steps.count, id: \.self) { i in
                    Capsule()
                        .fill(i == index ? Color.coral : .white.opacity(0.3))
                        .frame(width: i == index ? 18 : 6, height: 6)
                }
            }
            .animation(.snappy, value: index)
            .padding(.top, 14)
        }
    }

    // ── Geometry ──────────────────────────────────────────────────────────

    private func cutoutRect(in geo: GeometryProxy) -> CGRect {
        let size = geo.size
        let safe = geo.safeAreaInsets
        // GeometryReader content ignores safe areas (see .ignoresSafeArea()),
        // so raw size covers the full screen.
        let fullHeight = size.height + safe.top + safe.bottom
        let fullWidth = size.width + safe.leading + safe.trailing

        switch step.target {
        case .tab(let tab):
            // Measured against the tabs actually rendered — Circles only
            // exists once an invite code is redeemed.
            let tabs = Tab.visible(inviteUnlocked: InviteAccess.isUnlockedNow)
            let slots = CGFloat(tabs.count)
            let slot = CGFloat(tabs.firstIndex(of: tab) ?? 0)
            let centerX = (slot + 0.5) / slots * fullWidth
            let centerY = fullHeight - safe.bottom - 24
            return CGRect(x: centerX - 34, y: centerY - 34, width: 68, height: 68)

        case .homeSearchBar:
            // The Home search bar row: gutter 14, bell + messages ≈ 96pt on
            // the right, ~44pt tall just under the status bar.
            return CGRect(
                x: 14,
                y: safe.top + 4,
                width: fullWidth - 14 - 100,
                height: 46
            )
        }
    }

    private func cutoutShape(_ rect: CGRect) -> some Shape {
        RoundedRectangle(cornerRadius: min(rect.height, rect.width) / 2, style: .continuous)
            .path(in: rect)
            .asShape()
    }

    // ── Flow ──────────────────────────────────────────────────────────────

    private func advance() {
        if index == Self.steps.count - 1 {
            finish()
            return
        }
        withAnimation(.snappy) { index += 1 }
        // The camera step spotlights Home's search bar — bring Home back.
        if Self.steps[index].target == .homeSearchBar {
            appState.selectedTab = .feed
        }
    }

    private func finish() {
        CoachMarks.seen = true
        onFinish()
    }
}

// Wrap a concrete Path in a Shape so cutouts can be both filled (scrim punch)
// and stroked (spotlight ring) at a fixed screen rect.
private struct FixedPathShape: Shape {
    let fixed: Path
    func path(in rect: CGRect) -> Path { fixed }
}

private extension Path {
    func asShape() -> FixedPathShape { FixedPathShape(fixed: self) }
}
