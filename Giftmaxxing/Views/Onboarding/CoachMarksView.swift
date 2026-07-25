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
            title: "Learn what they love",
            line: "Swipe for yourself, or send anyone a challenge and read their answers.",
            hint: "Tap Swipe",
            target: .tab(.swipe)
        ),
        Step(
            title: "Your gift calendar",
            line: "Birthdays and dates live in Circles — Maxi paces each one.",
            hint: "Tap Circles",
            target: .tab(.circles)
        ),
        Step(
            title: "Your profile and boards",
            line: "Your Gift Boards, your sizes, and how recipients really reacted.",
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

                // Touch absorbers around the cutout: everything outside the
                // hole is inert, so the ONLY tappable thing is the real
                // control shining through.
                absorberPanels(around: cutout, in: geo)

                // Already sitting on the target tab (e.g. replaying from You)?
                // Tapping the tab again is a no-op, so a tap on the cutout
                // itself advances.
                if case .tab(let tab) = step.target, appState.selectedTab == tab {
                    Color.clear
                        .contentShape(Rectangle())
                        .frame(width: cutout.width, height: cutout.height)
                        .position(x: cutout.midX, y: cutout.midY)
                        .onTapGesture { advance() }
                }

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
        .allowsHitTesting(false)
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
            let slots = CGFloat(Tab.allCases.count)
            let slot = CGFloat(Tab.allCases.firstIndex(of: tab) ?? 0)
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

    @ViewBuilder
    private func absorberPanels(around cutout: CGRect, in geo: GeometryProxy) -> some View {
        let w = geo.size.width + geo.safeAreaInsets.leading + geo.safeAreaInsets.trailing
        let h = geo.size.height + geo.safeAreaInsets.top + geo.safeAreaInsets.bottom

        Group {
            absorber(CGRect(x: 0, y: 0, width: w, height: cutout.minY))
            absorber(CGRect(x: 0, y: cutout.maxY, width: w, height: max(0, h - cutout.maxY)))
            absorber(CGRect(x: 0, y: cutout.minY, width: cutout.minX, height: cutout.height))
            absorber(CGRect(
                x: cutout.maxX, y: cutout.minY,
                width: max(0, w - cutout.maxX), height: cutout.height
            ))
        }
    }

    private func absorber(_ rect: CGRect) -> some View {
        Color.clear
            .contentShape(Rectangle())
            .frame(width: max(0, rect.width), height: max(0, rect.height))
            .position(x: rect.midX, y: rect.midY)
            .onTapGesture {} // absorb — only the real control is interactive
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
