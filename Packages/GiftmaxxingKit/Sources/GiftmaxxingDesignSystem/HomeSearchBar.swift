// The design system is UIKit-backed (UIColor trait resolution, UIViewRepresentable
// pickers, UIImage caching), so it only exists where UIKit does. The guard keeps
// `swift build` / `swift test` working natively on macOS for the other three
// targets — which is what makes the sub-second test loop possible.
#if canImport(UIKit)
import SwiftUI
import GiftmaxxingCore

// Home's search field.
//
// Just a search field. The camera and microphone buttons that used to live
// inside it are gone: three tap targets in one control made the row read as a
// toolbar rather than a search box, and neither shortcut was the thing people
// came to the field to do. Visual search still lives in the search screen this
// opens; Maxi is a floating button, not a glyph hidden in a text input.
public struct HomeSearchBar: View {
    public var onSearchTap: () -> Void

    public var body: some View {
        Button(action: onSearchTap) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text("Search gifts, brands…")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity)
            .frame(height: 40)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(Color.cream)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}


#endif
