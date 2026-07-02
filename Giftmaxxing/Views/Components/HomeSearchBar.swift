import SwiftUI

// Amazon-style home top bar: ONE search pill with the camera (visual search)
// and mic (talk to Maxi) living INSIDE the field — a single calm row instead
// of three competing controls.
struct HomeSearchBar: View {
    var onSearchTap: () -> Void
    var onCameraTap: () -> Void
    var onMicTap: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Button(action: onSearchTap) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text("Search gifts, brands, people…")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .padding(.leading, 12)
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(action: onCameraTap) {
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.coral)
                    .frame(width: 38, height: 40)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Visual search")

            Button(action: onMicTap) {
                Image(systemName: "mic.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.coral)
                    .frame(width: 38, height: 40)
                    .contentShape(Rectangle())
                    .padding(.trailing, 2)
            }
            .accessibilityLabel("Talk to Maxi")
        }
        .background(Color.cream)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
