import SwiftUI

// Lens-style query image: shows the photo with tappable anchor dots on the
// objects Vision found. Tap a dot → search just that item; tap the selected
// dot's frame corners mirror Amazon Lens's crop brackets.
struct RegionSearchImage: View {
    let image: UIImage
    let regions: [CGRect]      // normalized, top-left origin
    let selected: Int?
    let onSelect: (Int?) -> Void

    var body: some View {
        // Exact-fit frame (no clipping) so normalized rects map 1:1 to points.
        let aspect = image.size.height / max(image.size.width, 1)
        let width = min(UIScreen.main.bounds.width - 80, 300, 340 / max(aspect, 0.01))
        let height = width * aspect

        ZStack {
            Image(uiImage: image)
                .resizable()
                .frame(width: width, height: height)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .onTapGesture { onSelect(nil) }

            // Selected region bracket
            if let selected, regions.indices.contains(selected) {
                let r = regions[selected]
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(.white, lineWidth: 2.5)
                    .shadow(color: .black.opacity(0.4), radius: 3)
                    .frame(width: r.width * width, height: r.height * height)
                    .position(x: r.midX * width, y: r.midY * height)
                    .allowsHitTesting(false)
            }

            // Anchor dots
            ForEach(regions.indices, id: \.self) { index in
                let r = regions[index]
                Button {
                    onSelect(index)
                } label: {
                    ZStack {
                        Circle()
                            .fill(.white.opacity(index == selected ? 1 : 0.9))
                            .frame(width: 26, height: 26)
                            .shadow(color: .black.opacity(0.35), radius: 4)
                        Circle()
                            .fill(index == selected ? Color.coral : Color.ink.opacity(0.35))
                            .frame(width: 12, height: 12)
                    }
                }
                .buttonStyle(.plain)
                .position(x: r.midX * width, y: r.midY * height)
            }
        }
        .frame(width: width, height: height)
        .animation(.spring(response: 0.3), value: selected)
    }
}
