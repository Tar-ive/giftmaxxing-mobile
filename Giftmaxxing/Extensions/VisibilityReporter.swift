import SwiftUI

// Real on-screen visibility, as a fraction of the view's own height.
//
// `onAppear`/`onDisappear` are NOT visibility: inside a LazyVStack they fire
// when SwiftUI creates and releases the row, which happens well outside the
// viewport. Anything gated on them — autoplaying media, an auto-advancing
// carousel — runs for cards the user has never seen. That is both wrong and
// wasteful (a carousel three screens down burns its slides before you arrive).
//
// This measures the view's frame against the screen and reports the visible
// fraction, so callers can act on "the user is actually looking at this".
//
// iOS 18 has `onScrollVisibilityChange`; this app targets iOS 17, so the
// measurement is a GeometryReader in a background layer — no layout impact.
struct VisibilityReporter: ViewModifier {
    /// Fraction of the view's height that must be on screen to count as visible.
    let threshold: Double
    let onChange: (Bool) -> Void

    @State private var isVisible = false

    func body(content: Content) -> some View {
        content.background(
            GeometryReader { geo in
                Color.clear
                    .onChange(of: geo.frame(in: .global)) { _, frame in
                        update(frame)
                    }
                    .onAppear { update(geo.frame(in: .global)) }
                    .onDisappear {
                        // Leaving the hierarchy is not-visible by definition,
                        // and the geometry callback won't fire again.
                        if isVisible { isVisible = false; onChange(false) }
                    }
            }
        )
    }

    private func update(_ frame: CGRect) {
        let screen = UIScreen.main.bounds
        let overlap = frame.intersection(screen).height
        // A card taller than the screen can never reach a high fraction of its
        // own height, so measure against whichever is smaller.
        let reference = max(1, min(frame.height, screen.height))
        let visible = overlap / reference >= threshold

        guard visible != isVisible else { return }
        isVisible = visible
        onChange(visible)
    }
}

extension View {
    /// Fires when the view crosses `threshold` of its height on screen.
    /// Default 0.6 — enough of the card is in frame that the user is looking at
    /// it, without demanding it be perfectly centred.
    func onVisibilityChange(
        threshold: Double = 0.6,
        _ onChange: @escaping (Bool) -> Void
    ) -> some View {
        modifier(VisibilityReporter(threshold: threshold, onChange: onChange))
    }
}

// "Is this scroll view moving right now?"
//
// iOS 18 has `onScrollPhaseChange`; this app targets iOS 17, so the fallback
// watches the content's own offset and debounces back to idle when it stops.
// Used to fade the Maxi FAB out mid-scroll — it shares the bottom-right corner
// with each feed card's Pool / Gift-board buttons, and those scroll, so no
// fixed inset can clear them. Getting out of the way while the feed moves is
// the only rule that does.
struct ScrollActivityReporter: ViewModifier {
    let onChange: (Bool) -> Void

    @State private var lastOffset: CGFloat = .greatestFiniteMagnitude
    @State private var isScrolling = false
    @State private var idleTask: Task<Void, Never>?

    func body(content: Content) -> some View {
        content.background(
            GeometryReader { geo in
                Color.clear
                    .onChange(of: geo.frame(in: .global).minY) { _, y in
                        // First measurement is layout, not a scroll.
                        guard lastOffset != .greatestFiniteMagnitude else {
                            lastOffset = y
                            return
                        }
                        guard abs(y - lastOffset) > 1 else { return }
                        lastOffset = y

                        if !isScrolling {
                            isScrolling = true
                            onChange(true)
                        }
                        idleTask?.cancel()
                        idleTask = Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(220))
                            guard !Task.isCancelled else { return }
                            isScrolling = false
                            onChange(false)
                        }
                    }
            }
        )
    }
}

extension View {
    /// Fires `true` while the enclosing scroll view is moving, `false` when it
    /// has been still for ~220ms.
    func onScrollActivityChange(_ onChange: @escaping (Bool) -> Void) -> some View {
        modifier(ScrollActivityReporter(onChange: onChange))
    }
}

// Raw vertical scroll offset, for callers that need DIRECTION rather than
// merely "is it moving" (ScrollActivityReporter). Used to hide the Tier-2
// filter bar on down-scroll and restore it on up-scroll.
struct ScrollOffsetReporter: ViewModifier {
    let onChange: (CGFloat) -> Void

    func body(content: Content) -> some View {
        content.background(
            GeometryReader { geo in
                Color.clear
                    .onChange(of: geo.frame(in: .global).minY) { _, y in onChange(y) }
            }
        )
    }
}

extension View {
    func onScrollOffsetChange(_ onChange: @escaping (CGFloat) -> Void) -> some View {
        modifier(ScrollOffsetReporter(onChange: onChange))
    }
}
