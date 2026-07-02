import SwiftUI

// Amazon-style home top bar: a search pill with camera (visual search) and
// mic (talk to Maxi) actions living right at the top of the feed.
struct HomeSearchBar: View {
    var onSearchTap: () -> Void
    var onCameraTap: () -> Void
    var onMicTap: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onSearchTap) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text("Search gifts, brands, people…")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12)
                .frame(height: 42)
                .background(Color.cream)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)

            Button(action: onCameraTap) {
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.coral)
                    .frame(width: 42, height: 42)
                    .background(Color.coralSoft)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .accessibilityLabel("Visual search")

            Button(action: onMicTap) {
                Image(systemName: "mic.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(
                        LinearGradient(
                            colors: [Color.coral, Color(hex: "#FF9A76")],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .accessibilityLabel("Talk to Maxi")
        }
    }
}
