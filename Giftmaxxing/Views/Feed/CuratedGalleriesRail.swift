import SwiftUI

// Home discovery rail: horizontally scrolling curated gift galleries. The
// first-launch "world of beautiful, intentional gifts" — tap a shelf to browse
// its picks. Always present (not just first launch); it's the app's editorial
// front door.
struct CuratedGalleriesRail: View {
    var onSelect: (CuratedCollection) -> Void

    private let collections = CuratedCollection.all
    @State private var coverImages: [String: String] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Gift galleries", systemImage: "square.grid.2x2.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.ink)
                Spacer()
                Text("Curated for you")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(collections) { collection in
                        Button { onSelect(collection) } label: {
                            card(collection)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 2)
            }
        }
        .padding(.vertical, 8)
        .background(Color.surface)
        .task { await loadCoverImages() }
    }

    private func card(_ c: CuratedCollection) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .bottomLeading) {
                // Color.gradient(for:) already returns a LinearGradient — use it
                // directly (same pattern as PostCardView / CollectionDetailView).
                Color.gradient(for: c.grad)
                if let image = coverImages[c.id] {
                    CachedAsyncImage(url: image, width: 500)
                } else {
                    Image(systemName: c.symbol)
                        .font(.system(size: 30, weight: .medium))
                        .foregroundStyle(.white.opacity(0.9))
                        .padding(12)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                }
            }
            .frame(width: 210, height: 120)
            .clipShape(RoundedRectangle(cornerRadius: 16))

            VStack(alignment: .leading, spacing: 2) {
                Text(c.title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.ink)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(c.subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.top, 8)
            .frame(width: 210, alignment: .leading)
        }
    }

    private func loadCoverImages() async {
        await withTaskGroup(of: (String, String?).self) { group in
            for collection in collections {
                group.addTask {
                    let posts = try? await APIClient.shared.fetchGallery(id: collection.id, limit: 12)
                    return (collection.id, posts?.first(where: { !$0.product.gallery.isEmpty })?.product.gallery.first)
                }
            }

            for await (id, image) in group {
                if let image { coverImages[id] = image }
            }
        }
    }
}
