import SwiftUI
import Photos
import GiftmaxxingCore

// The user's most recent photos and videos, inline.
//
// The old empty state asked you to tap a button, then wait for a system sheet,
// then find the shot you almost certainly took minutes ago. Instagram solved
// this years ago by putting the camera roll's tail right in the composer: the
// thing you want is usually the first or second tile, so posting becomes one
// tap instead of four.
//
// Authorization is requested lazily — only when the Post tab is actually opened,
// never at launch — and `.limited` access is handled as a first-class state
// rather than treated as denial.
@MainActor
final class RecentMediaLoader: ObservableObject {
    @Published private(set) var assets: [PHAsset] = []
    @Published private(set) var status: PHAuthorizationStatus = .notDetermined
    @Published private(set) var didLoad = false

    private let imageManager = PHCachingImageManager()

    func loadIfNeeded(limit: Int = 24) async {
        guard !didLoad else { return }
        didLoad = true

        status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if status == .notDetermined {
            status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        }
        guard status == .authorized || status == .limited else { return }

        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.fetchLimit = limit
        // Photos and videos only — no audio, no hidden albums.
        options.predicate = NSPredicate(
            format: "mediaType == %d || mediaType == %d",
            PHAssetMediaType.image.rawValue,
            PHAssetMediaType.video.rawValue
        )

        let result = PHAsset.fetchAssets(with: options)
        var found: [PHAsset] = []
        result.enumerateObjects { asset, _, _ in found.append(asset) }
        assets = found
    }

    /// Thumbnail for one asset. Returns nil rather than a placeholder so the
    /// tile can keep its own skeleton.
    func thumbnail(for asset: PHAsset, size: CGFloat) async -> UIImage? {
        let scale = UIScreen.main.scale
        let target = CGSize(width: size * scale, height: size * scale)
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true

        return await withCheckedContinuation { continuation in
            var resumed = false
            imageManager.requestImage(
                for: asset,
                targetSize: target,
                contentMode: .aspectFill,
                options: options
            ) { image, info in
                // `.opportunistic` fires twice (degraded, then full). Resume once.
                let degraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                guard !degraded, !resumed else { return }
                resumed = true
                continuation.resume(returning: image)
            }
        }
    }
}

struct RecentMediaStrip: View {
    @StateObject private var loader = RecentMediaLoader()
    /// Tapping a tile hands the picked asset up; the composer loads the full
    /// resolution itself through the existing media pipeline.
    var onSelect: (PHAsset) -> Void
    /// "Open the full library" — the existing source picker.
    var onOpenLibrary: () -> Void

    private let tile: CGFloat = 92

    var body: some View {
        Group {
            switch loader.status {
            case .authorized, .limited:
                if loader.assets.isEmpty {
                    EmptyView()
                } else {
                    strip
                }
            default:
                EmptyView()   // Not granted — the drop zone is the whole story.
            }
        }
        .task { await loader.loadIfNeeded() }
    }

    private var strip: some View {
        VStack(alignment: .leading, spacing: ThemeSpacing.xs) {
            SectionHeader("Recent")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(loader.assets, id: \.localIdentifier) { asset in
                        Button { onSelect(asset) } label: {
                            RecentMediaTile(asset: asset, size: tile, loader: loader)
                        }
                        .buttonStyle(.plain)
                    }

                    // `.limited` means the user chose specific photos; the way
                    // back to the rest is the system picker, so say so.
                    Button(action: onOpenLibrary) {
                        VStack(spacing: 6) {
                            Image(systemName: "photo.stack")
                                .font(.system(size: 18, weight: .semibold))
                            Text(loader.status == .limited ? "More…" : "Library")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundStyle(Color.inkSecondary)
                        .frame(width: tile, height: tile)
                        .background(Color.surfaceSunken)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

private struct RecentMediaTile: View {
    let asset: PHAsset
    let size: CGFloat
    @ObservedObject var loader: RecentMediaLoader

    @State private var image: UIImage?

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Color.surfaceSunken
            }

            if asset.mediaType == .video {
                Image(systemName: "video.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(4)
                    .background(.black.opacity(0.45), in: Circle())
                    .padding(5)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .task {
            guard image == nil else { return }
            image = await loader.thumbnail(for: asset, size: size)
        }
    }
}

// One header style for the whole app: uppercase, caption, secondary. Replaces
// the stack of competing title weights that made every screen look like it had
// three headings.
struct SectionHeader: View {
    let title: String

    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title)
            .font(.caption)
            .textCase(.uppercase)
            .tracking(0.6)
            .foregroundStyle(.secondary)
    }
}
