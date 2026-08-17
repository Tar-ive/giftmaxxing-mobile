import SwiftUI

// Home-header entry to the per-person surprise plan.
// Mirrors the notification bell's badge treatment beside it so the header
// reads as one row of controls rather than two competing systems.
struct CartButton: View {
    var action: () -> Void

    @ObservedObject private var cart = CartStore.shared

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "bag")
                    .font(.title3)
                    .foregroundStyle(Color.ink)

                if cart.pendingCount > 0 {
                    Text("\(min(cart.pendingCount, 9))")
                        .font(.caption2.weight(.bold))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .foregroundStyle(Color.onPrimary)
                        .frame(width: 15, height: 15)
                        .background(Color.coral)
                        .clipShape(Circle())
                        .offset(x: 7, y: -6)
                }
            }
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            cart.pendingCount > 0
                ? "Surprise plan, \(cart.pendingCount) gifts left to prepare"
                : "Surprise plan"
        )
        .sensoryFeedback(.selection, trigger: cart.pendingCount)
    }
}
