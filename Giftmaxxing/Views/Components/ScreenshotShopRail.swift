import SwiftUI
import Photos

// "Shop your screenshots" — the other half of the Instagram → Amazon bridge.
// People already screenshot things they (or their people) love; this rail
// surfaces the latest screenshots and one tap runs visual search over the
// gift index. All matching happens on our backend; photos never leave the
// device except the one the user explicitly taps.
@MainActor
final class ScreenshotStore: ObservableObject {
    @Published var thumbnails: [(id: String, image: UIImage)] = []
    @Published var status: PHAuthorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)

    private var assets: [String: PHAsset] = [:]
    private let manager = PHCachingImageManager()

    var needsPermission: Bool {
        status == .notDetermined
    }

    var isDenied: Bool {
        status == .denied || status == .restricted
    }

    func requestAndLoad() {
        Task {
            let granted = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
            status = granted
            if granted == .authorized || granted == .limited {
                loadScreenshots()
            }
        }
    }

    func loadIfAuthorized() {
        status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if status == .authorized || status == .limited {
            loadScreenshots()
        }
    }

    private func loadScreenshots() {
        let collections = PHAssetCollection.fetchAssetCollections(
            with: .smartAlbum,
            subtype: .smartAlbumScreenshots,
            options: nil
        )
        guard let album = collections.firstObject else { return }

        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        fetchOptions.fetchLimit = 12
        let result = PHAsset.fetchAssets(in: album, options: fetchOptions)

        var fetched: [PHAsset] = []
        result.enumerateObjects { asset, _, _ in
            fetched.append(asset)
        }

        // Skip the rebuild when nothing changed (called on every foreground).
        let ids = fetched.map(\.localIdentifier)
        guard ids != thumbnails.map(\.id) || thumbnails.isEmpty else { return }

        assets = Dictionary(uniqueKeysWithValues: fetched.map { ($0.localIdentifier, $0) })

        let thumbOptions = PHImageRequestOptions()
        thumbOptions.deliveryMode = .opportunistic
        thumbOptions.isNetworkAccessAllowed = true

        // Keep order stable (newest first) regardless of async delivery order.
        thumbnails = []
        var pending: [String: UIImage] = [:]

        for asset in fetched {
            manager.requestImage(
                for: asset,
                targetSize: CGSize(width: 240, height: 240),
                contentMode: .aspectFill,
                options: thumbOptions
            ) { [weak self] image, _ in
                guard let self, let image else { return }
                Task { @MainActor in
                    pending[asset.localIdentifier] = image
                    self.thumbnails = ids.compactMap { id in
                        pending[id].map { (id: id, image: $0) }
                    }
                }
            }
        }
    }

    // Full-resolution (capped) image for the tapped screenshot.
    func fullImage(for id: String) async -> UIImage? {
        guard let asset = assets[id] else { return nil }
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true

        return await withCheckedContinuation { continuation in
            var resumed = false
            manager.requestImage(
                for: asset,
                targetSize: CGSize(width: 1024, height: 1024),
                contentMode: .aspectFit,
                options: options
            ) { image, info in
                let degraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                guard !degraded, !resumed else { return }
                resumed = true
                continuation.resume(returning: image)
            }
        }
    }
}

struct ScreenshotShopRail: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var store = ScreenshotStore()
    @Environment(\.scenePhase) private var scenePhase
    @State private var loadingId: String?

    var body: some View {
        Group {
            if store.isDenied {
                EmptyView()
            } else if store.needsPermission {
                permissionCard
            } else if !store.thumbnails.isEmpty {
                rail
            }
        }
        .onAppear {
            store.loadIfAuthorized()
        }
        // The whole point is "screenshot in Instagram → come back → shop it",
        // so refresh whenever the app returns to the foreground.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                store.loadIfAuthorized()
            }
        }
    }

    private var permissionCard: some View {
        Button {
            store.requestAndLoad()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "photo.stack")
                    .font(.system(size: 22))
                    .foregroundStyle(Color.coral)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Shop your screenshots")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color.ink)
                    Text("Screenshotted something they'd love? Find it as a gift.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .background(Color.coralSoft)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    private var rail: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "photo.stack")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.coral)
                Text("Shop your screenshots")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.ink)
                Spacer()
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(store.thumbnails, id: \.id) { thumb in
                        Button {
                            loadingId = thumb.id
                            Task {
                                if let full = await store.fullImage(for: thumb.id) {
                                    appState.handleCapture(image: full)
                                }
                                loadingId = nil
                            }
                        } label: {
                            ZStack {
                                Image(uiImage: thumb.image)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 84, height: 84)
                                    .clipped()
                                    .clipShape(RoundedRectangle(cornerRadius: 12))

                                if loadingId == thumb.id {
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(.black.opacity(0.4))
                                        .frame(width: 84, height: 84)
                                    ProgressView().tint(.white)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}
