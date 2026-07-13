import SwiftUI

// Instagram-style viewport impression tracker. Wraps any view and fires
// trackImpression/trackImpressionEnd when the view enters/leaves the visible
// viewport. Combined with GeometryReader, this gives us per-post dwell time
// identical to how Instagram measures "time on post" for their ranking algorithm.

struct ImpressionTracker: ViewModifier {
    let postId: String
    let position: Int
    let source: String
    // Fires with the measured dwell (ms) when the view leaves the viewport —
    // lets the taste profile weight impressions by attention, not just count
    // them (analytics collected dwell for months; ranking never used it).
    var onDwell: ((Double) -> Void)? = nil

    @State private var appearedAt: Date?

    func body(content: Content) -> some View {
        content
            .onAppear {
                appearedAt = Date()
                AnalyticsEngine.shared.trackImpression(
                    postId: postId,
                    position: position,
                    source: source
                )
            }
            .onDisappear {
                AnalyticsEngine.shared.trackImpressionEnd(
                    postId: postId,
                    position: position
                )
                if let start = appearedAt {
                    onDwell?(Date().timeIntervalSince(start) * 1000)
                }
                appearedAt = nil
            }
    }
}

extension View {
    func trackImpression(
        postId: String,
        position: Int,
        source: String = "feed",
        onDwell: ((Double) -> Void)? = nil
    ) -> some View {
        modifier(ImpressionTracker(postId: postId, position: position, source: source, onDwell: onDwell))
    }
}

// Tracks scroll position and velocity for Instagram-style scroll depth analytics.
// Attach to a ScrollView's content to measure how far users scroll and how fast.
struct ScrollAnalyticsTracker: ViewModifier {
    let currentPosition: Int

    @State private var lastOffset: CGFloat = 0
    @State private var lastTime: Date = Date()

    func body(content: Content) -> some View {
        content
            .background(
                GeometryReader { geometry in
                    Color.clear
                        .onChange(of: geometry.frame(in: .global).minY) { _, newValue in
                            let now = Date()
                            let dt = now.timeIntervalSince(lastTime)
                            guard dt > 0.05 else { return } // throttle to ~20fps

                            let dy = Double(newValue - lastOffset)
                            let velocity = dy / dt

                            AnalyticsEngine.shared.trackScrollVelocity(
                                velocity: velocity,
                                currentPosition: currentPosition
                            )

                            lastOffset = newValue
                            lastTime = now
                        }
                }
            )
    }
}

extension View {
    func trackScrollAnalytics(currentPosition: Int) -> some View {
        modifier(ScrollAnalyticsTracker(currentPosition: currentPosition))
    }
}
