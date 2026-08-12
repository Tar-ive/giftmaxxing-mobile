import AVFoundation
import AVKit
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct UGCCreateView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var authManager: AuthManager
    @StateObject private var model = UGCCreateViewModel()
    @State private var selection: [PhotosPickerItem] = []
    @State private var showSourcePicker = false
    @State private var showLibrary = false
    @State private var showCamera = false
    @State private var photoLibraryMode = true
    @State private var previewIndex = 0

    // Vertical for video and tall photos, square otherwise — the two shapes
    // the feed renders (MediaAspect).
    private var composerAspectRatio: CGFloat {
        guard let first = model.media.first else { return MediaAspect.square }
        if first.kind == .video { return MediaAspect.vertical }
        guard let size = first.previewImage?.size else { return MediaAspect.square }
        return MediaAspect.snap(width: size.width, height: size.height)
    }
    @State private var editRequest: UGCEditRequest?
    @State private var showMusic = false
    @State private var hapticTrigger = 0

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: ThemeSpacing.xl) {
                    if !model.media.isEmpty {
                        preview
                        musicPicker
                        caption
                        productLinks
                        publishButton
                    } else if model.isPreparing {
                        preparingCard
                    } else {
                        mediaPicker

                        // The shot you want is almost always one you just took,
                        // so put the tail of the camera roll right here instead
                        // of behind a system sheet.
                        RecentMediaStrip(
                            onSelect: { asset in Task { await model.load(asset: asset) } },
                            onOpenLibrary: { showSourcePicker = true }
                        )

                        CreateStarterRail(
                            focus: DebugSessionManager.active.createFocus,
                            onPickMedia: { showSourcePicker = true },
                            onUseTemplate: { prompt in
                                // Only prefill an untouched caption — never
                                // clobber something already typed.
                                if model.caption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    model.caption = prompt + " "
                                }
                            }
                        )
                    }
                    if !model.posts.isEmpty { posts }
                }
                .padding(ThemeSpacing.md)
            }
            .background(Color.cream)
            .navigationTitle("Create")
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .confirmationDialog("Add to your post", isPresented: $showSourcePicker) {
                Button("Photos (up to 10)") {
                    photoLibraryMode = true
                    selection = []
                    showLibrary = true
                }
                Button("One video (up to 1 minute)") {
                    photoLibraryMode = false
                    selection = []
                    showLibrary = true
                }
                if UGCCameraPicker.isAvailable {
                    Button("Camera") { showCamera = true }
                }
                Button("Cancel", role: .cancel) {}
            }
            .photosPicker(
                isPresented: $showLibrary,
                selection: $selection,
                maxSelectionCount: photoLibraryMode ? 10 : 1,
                matching: photoLibraryMode ? .images : .videos,
                preferredItemEncoding: .current
            )
            .fullScreenCover(isPresented: $showCamera) {
                UGCCameraPicker { media in
                    model.replaceDraft(with: media)
                    showCamera = false
                }
                .ignoresSafeArea()
            }
            .sheet(item: $editRequest) { request in
                if model.media.indices.contains(request.index),
                   let image = model.media[request.index].previewImage {
                    UGCPhotoEditor(image: image) { edited in
                        try? model.replacePhoto(at: request.index, with: edited)
                    }
                }
            }
            .onChange(of: selection) { _, items in
                guard !items.isEmpty else { return }
                Task {
                    await model.load(items)
                    previewIndex = 0
                }
            }
            .task { await model.refreshPosts() }
            .sensoryFeedback(.success, trigger: hapticTrigger)
            .alert("Couldn’t post", isPresented: Binding(
                get: { model.error != nil },
                set: { if !$0 { model.error = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(model.error ?? "Please try again.")
            }
        }
    }

    // Videos are re-encoded to H.264 on-device before upload (safety review
    // can't decode HEVC) — that can take a moment for long clips.
    private var preparingCard: some View {
        VStack(spacing: ThemeSpacing.md) {
            ProgressView()
            Text("Preparing your video…")
                .font(.headline)
                .foregroundStyle(Color.ink)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, ThemeSpacing.xl)
        .background(Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: ThemeRadius.xl, style: .continuous))
        .cardElevation()
    }

    // The primary action, and it should look like one target rather than a
    // white card that reads the same as every other card on the screen. A
    // dashed border is the universal "put something here" affordance.
    private var mediaPicker: some View {
        Button { showSourcePicker = true } label: {
            VStack(spacing: ThemeSpacing.sm) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.largeTitle)
                    .foregroundStyle(Color.coral)
                Text("Choose photos or a video")
                    .font(.headline)
                    .foregroundStyle(Color.ink)
                Text("Up to 10 photos, or one video under a minute")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, ThemeSpacing.xl)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.coralSoft.opacity(0.5))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(
                        Color.coral.opacity(0.55),
                        style: StrokeStyle(lineWidth: 1.5, dash: [6])
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Choose up to ten photos or one video to post")
    }

    private var preview: some View {
        ZStack(alignment: .topTrailing) {
            TabView(selection: $previewIndex) {
                ForEach(Array(model.media.enumerated()), id: \.offset) { index, media in
                    Group {
                        switch media.kind {
                        case .image:
                            if let image = media.previewImage {
                                Image(uiImage: image).resizable().scaledToFill()
                            }
                        case .video:
                            VideoPlayer(player: AVPlayer(url: media.fileURL))
                        }
                    }
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: model.media.count > 1 ? .always : .never))
            .frame(maxWidth: .infinity)
            // Preview at the shape it will actually publish as.
            .aspectRatio(composerAspectRatio, contentMode: .fit)
            .background(Color.surfaceSunken)
            .clipShape(RoundedRectangle(cornerRadius: ThemeRadius.xl, style: .continuous))

            Button {
                model.removeMedia(at: previewIndex)
                previewIndex = min(previewIndex, max(0, model.media.count - 1))
                if model.media.isEmpty { selection = [] }
            } label: {
                Image(systemName: "xmark")
                    .font(.headline)
                    .foregroundStyle(Color.ink)
                    .frame(minWidth: 44, minHeight: 44)
                    .background(.ultraThinMaterial)
                    .clipShape(Circle())
            }
            .padding(ThemeSpacing.sm)
            .accessibilityLabel("Remove this item")
        }
        .overlay(alignment: .bottomTrailing) {
            if model.media.indices.contains(previewIndex),
               model.media[previewIndex].kind == .image {
                Button {
                    editRequest = UGCEditRequest(index: previewIndex)
                } label: {
                    Label("Edit", systemImage: "slider.horizontal.3")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Color.ink)
                        .padding(.horizontal, ThemeSpacing.sm)
                        .frame(minHeight: 44)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .padding(ThemeSpacing.sm)
            }
        }
    }

    private var musicPicker: some View {
        Button { showMusic = true } label: {
            HStack(spacing: ThemeSpacing.sm) {
                Image(systemName: model.music == nil ? "music.note" : "waveform")
                    .foregroundStyle(Color.coral)
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.music?.title ?? "Add music")
                        .font(.subheadline.weight(.semibold))
                    Text(model.music.map { "\($0.artist) · up to 60 sec" } ?? "Rights-cleared original tracks")
                        .font(.caption).foregroundStyle(Color.inkSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(Color.inkTertiary)
            }
            .foregroundStyle(Color.ink)
            .padding(ThemeSpacing.md)
            .background(Color.surface)
            .clipShape(RoundedRectangle(cornerRadius: ThemeRadius.lg, style: .continuous))
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showMusic) {
            UGCMusicPicker(selection: $model.music)
        }
    }

    private var caption: some View {
        VStack(alignment: .leading, spacing: ThemeSpacing.xs) {
            Text("Caption")
                .font(.headline)
                .foregroundStyle(Color.ink)
            TextEditor(text: $model.caption)
                .font(.body)
                .foregroundStyle(Color.ink)
                .scrollContentBackground(.hidden)
                .padding(ThemeSpacing.sm)
                .frame(minHeight: 132)
                .background(Color.surface)
                .clipShape(RoundedRectangle(cornerRadius: ThemeRadius.lg, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: ThemeRadius.lg, style: .continuous)
                        .stroke(Color.line, lineWidth: 1)
                }
                .onChange(of: model.caption) { _, value in
                    if value.count > 2200 { model.caption = String(value.prefix(2200)) }
                }
            Text("\(model.caption.count)/2,200")
                .font(.caption)
                .foregroundStyle(Color.inkTertiary)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private var publishButton: some View {
        VStack(spacing: ThemeSpacing.sm) {
            if model.isPublishing {
                ProgressView(value: model.progress)
                    .tint(Color.coral)
                Text(model.progressLabel)
                    .font(.footnote)
                    .foregroundStyle(Color.inkSecondary)
            }
            Button {
                Task {
                    if await model.publish() {
                        hapticTrigger += 1
                        appState.selectedTab = .feed
                    }
                }
            } label: {
                Label(model.isPublishing ? "Posting…" : "Post", systemImage: "arrow.up.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(model.isPublishing || model.caption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityLabel("Publish post")
        }
    }

    private var productLinks: some View {
        VStack(alignment: .leading, spacing: ThemeSpacing.sm) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Products in this post")
                        .font(.headline)
                        .foregroundStyle(Color.ink)
                    Text("Optional, but strongly recommended so people can shop the exact items.")
                        .font(.caption)
                        .foregroundStyle(Color.inkSecondary)
                }
                Spacer()
                Button {
                    model.productLinks.append(UGCProductLink(name: "", url: ""))
                } label: {
                    Image(systemName: "plus.circle.fill").frame(minWidth: 44, minHeight: 44)
                }
                .disabled(model.productLinks.count >= 8)
                .accessibilityLabel("Add product link")
            }

            ForEach(model.productLinks.indices, id: \.self) { index in
                VStack(spacing: ThemeSpacing.xs) {
                    TextField("Product name", text: $model.productLinks[index].name)
                    TextField("https://store.com/product", text: $model.productLinks[index].url)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                    Button("Remove", role: .destructive) { model.productLinks.remove(at: index) }
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .textFieldStyle(.roundedBorder)
                .padding(ThemeSpacing.sm)
                .background(Color.surface)
                .clipShape(RoundedRectangle(cornerRadius: ThemeRadius.md, style: .continuous))
            }
        }
    }

    private var posts: some View {
        VStack(alignment: .leading, spacing: ThemeSpacing.sm) {
            HStack {
                Text("Your posts")
                    .font(.title3.weight(.semibold))
                    .fontDesign(.rounded)
                    .foregroundStyle(Color.ink)
                Spacer()
                Button { Task { await model.refreshPosts() } } label: {
                    Image(systemName: "arrow.clockwise")
                        .frame(minWidth: 44, minHeight: 44)
                }
                .foregroundStyle(Color.coral)
                .accessibilityLabel("Refresh post statuses")
            }
            ForEach(model.posts) { post in
                UGCPostStatusCard(post: post)
            }
        }
    }
}

private struct UGCPostStatusCard: View {
    let post: UGCPost

    var body: some View {
        HStack(spacing: ThemeSpacing.sm) {
            ZStack {
                if let image = post.posterUrl ?? post.mediaUrls?.first ?? (post.mediaType == "image" ? post.mediaUrl : nil) {
                    CachedAsyncImage(url: image, width: 180)
                } else {
                    Color.surfaceSunken
                    Image(systemName: post.mediaType == "video" ? "video.fill" : "photo.fill")
                        .foregroundStyle(Color.inkTertiary)
                }
            }
            .frame(width: 72, height: 88)
            .clipShape(RoundedRectangle(cornerRadius: ThemeRadius.md, style: .continuous))

            VStack(alignment: .leading, spacing: ThemeSpacing.xs) {
                Text(post.caption)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.ink)
                    .lineLimit(2)
                Label(statusLabel, systemImage: statusIcon)
                    .font(.caption)
                    .foregroundStyle(statusColor)
            }
            Spacer()
        }
        .padding(ThemeSpacing.sm)
        .background(Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: ThemeRadius.lg, style: .continuous))
    }

    private var statusLabel: String {
        switch post.processingStatus {
        case "READY": "Live"
        case "REJECTED": "Not published — failed safety review"
        case "FAILED": "Processing failed — try again"
        default: "Safety review in progress"
        }
    }

    private var statusIcon: String {
        switch post.processingStatus {
        case "READY": "checkmark.circle.fill"
        case "REJECTED", "FAILED": "exclamationmark.triangle.fill"
        default: "clock.fill"
        }
    }

    private var statusColor: Color {
        switch post.processingStatus {
        case "READY": Color.success
        case "REJECTED", "FAILED": Color.danger
        default: Color.inkSecondary
        }
    }
}

private struct UGCEditRequest: Identifiable {
    let index: Int
    var id: Int { index }
}

private struct UGCPhotoEditor: View {
    let original: UIImage
    let onSave: (UIImage) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage

    init(image: UIImage, onSave: @escaping (UIImage) -> Void) {
        original = image
        self.onSave = onSave
        _image = State(initialValue: image)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: ThemeSpacing.md) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.surfaceSunken)
                    .clipShape(RoundedRectangle(cornerRadius: ThemeRadius.lg, style: .continuous))

                HStack(spacing: ThemeSpacing.sm) {
                    editButton("Rotate", icon: "rotate.right") { image = image.rotatedClockwise() }
                    editButton("Square", icon: "square") { image = image.centerCropped(to: 1) }
                    editButton("Portrait", icon: "rectangle.portrait") { image = image.centerCropped(to: 4.0 / 5.0) }
                    editButton("Reset", icon: "arrow.counterclockwise") { image = original }
                }
            }
            .padding(ThemeSpacing.md)
            .background(Color.cream)
            .navigationTitle("Edit photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onSave(image)
                        dismiss()
                    }
                    .fontWeight(.bold)
                }
            }
        }
    }

    private func editButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: ThemeSpacing.xs) {
                Image(systemName: icon).font(.headline)
                Text(title).font(.caption.weight(.semibold))
            }
            .foregroundStyle(Color.ink)
            .frame(maxWidth: .infinity, minHeight: 60)
            .background(Color.surface)
            .clipShape(RoundedRectangle(cornerRadius: ThemeRadius.md, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private extension UIImage {
    func rotatedClockwise() -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        let target = CGSize(width: size.height, height: size.width)
        return UIGraphicsImageRenderer(size: target, format: format).image { context in
            context.cgContext.translateBy(x: target.width, y: 0)
            context.cgContext.rotate(by: .pi / 2)
            draw(in: CGRect(origin: .zero, size: size))
        }
    }

    func centerCropped(to targetAspect: CGFloat) -> UIImage {
        guard size.width > 0, size.height > 0 else { return self }
        let sourceAspect = size.width / size.height
        let cropSize = sourceAspect > targetAspect
            ? CGSize(width: size.height * targetAspect, height: size.height)
            : CGSize(width: size.width, height: size.width / targetAspect)
        let cropRect = CGRect(
            x: (size.width - cropSize.width) / 2,
            y: (size.height - cropSize.height) / 2,
            width: cropSize.width,
            height: cropSize.height
        )
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        return UIGraphicsImageRenderer(size: cropSize, format: format).image { _ in
            draw(at: CGPoint(x: -cropRect.minX, y: -cropRect.minY))
        }
    }
}

@MainActor
final class UGCCreateViewModel: ObservableObject {
    @Published var media: [SelectedUGCMedia] = []
    @Published var music: UGCMusicTrack?
    @Published var caption = ""
    @Published var productLinks: [UGCProductLink] = []
    @Published var posts: [UGCPost] = []
    @Published var isPreparing = false
    @Published var isPublishing = false
    @Published var progress = 0.0
    @Published var progressLabel = "Preparing upload"
    @Published var error: String?

    func load(_ items: [PhotosPickerItem]) async {
        isPreparing = true
        defer { isPreparing = false }
        var prepared: [SelectedUGCMedia] = []
        do {
            media.forEach { $0.removeTemporaryFiles() }
            for item in items.prefix(10) {
                if item.supportedContentTypes.contains(where: { $0.conforms(to: .movie) }) {
                    guard items.count == 1 else { throw UGCSelectionError.mixedMedia }
                    guard let movie = try await item.loadTransferable(type: TransferableVideo.self) else {
                        throw UGCSelectionError.unreadable
                    }
                    prepared.append(try await SelectedUGCMedia.video(url: movie.url))
                } else if let data = try await item.loadTransferable(type: Data.self) {
                    prepared.append(try SelectedUGCMedia.image(data: data))
                } else {
                    throw UGCSelectionError.unreadable
                }
            }
            media = prepared
        } catch {
            prepared.forEach { $0.removeTemporaryFiles() }
            media.forEach { $0.removeTemporaryFiles() }
            media = []
            self.error = error is UGCSelectionError && (error as? UGCSelectionError) == .videoTooLong
                ? "Videos must be one minute or shorter."
                : "That item couldn’t be prepared. Choose another photo or video."
        }
    }

    /// One asset tapped in the recent strip. Routed through the same
    /// SelectedUGCMedia preparation as the system picker — including the H.264
    /// re-encode that video moderation depends on — so a shortcut cannot skip
    /// a step the upload path assumes has run.
    func load(asset: PHAsset) async {
        isPreparing = true
        defer { isPreparing = false }
        do {
            media.forEach { $0.removeTemporaryFiles() }
            let prepared: SelectedUGCMedia
            switch asset.mediaType {
            case .video:
                let url = try await Self.videoURL(for: asset)
                prepared = try await SelectedUGCMedia.video(url: url)
            default:
                let data = try await Self.imageData(for: asset)
                prepared = try SelectedUGCMedia.image(data: data)
            }
            media = [prepared]
        } catch {
            media.forEach { $0.removeTemporaryFiles() }
            media = []
            self.error = (error as? UGCSelectionError) == .videoTooLong
                ? "Videos must be one minute or shorter."
                : "That item couldn’t be prepared. Choose another photo or video."
        }
    }

    private static func imageData(for asset: PHAsset) async throws -> Data {
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = true   // iCloud-only originals
        options.deliveryMode = .highQualityFormat
        options.isSynchronous = false
        return try await withCheckedThrowingContinuation { continuation in
            PHImageManager.default().requestImageDataAndOrientation(
                for: asset, options: options
            ) { data, _, _, _ in
                if let data { continuation.resume(returning: data) }
                else { continuation.resume(throwing: UGCSelectionError.unreadable) }
            }
        }
    }

    private static func videoURL(for asset: PHAsset) async throws -> URL {
        let options = PHVideoRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .highQualityFormat
        return try await withCheckedThrowingContinuation { continuation in
            PHImageManager.default().requestAVAsset(
                forVideo: asset, options: options
            ) { avAsset, _, _ in
                guard let url = (avAsset as? AVURLAsset)?.url else {
                    continuation.resume(throwing: UGCSelectionError.unreadable)
                    return
                }
                continuation.resume(returning: url)
            }
        }
    }

    func replaceDraft(with value: SelectedUGCMedia) {
        media.forEach { $0.removeTemporaryFiles() }
        media = [value]
    }

    func removeMedia(at index: Int) {
        guard media.indices.contains(index) else { return }
        media.remove(at: index).removeTemporaryFiles()
    }

    func replacePhoto(at index: Int, with image: UIImage) throws {
        guard media.indices.contains(index), media[index].kind == .image else { return }
        let replacement = try SelectedUGCMedia.image(image: image)
        let old = media[index]
        media[index] = replacement
        old.removeTemporaryFiles()
    }

    func clearDraft() {
        media.forEach { $0.removeTemporaryFiles() }
        media = []
        music = nil
        caption = ""
        productLinks = []
    }

    func refreshPosts() async {
        do { posts = try await APIClient.shared.fetchMyUGCPosts() } catch { }
    }

    func publish() async -> Bool {
        guard !media.isEmpty else { return false }
        let cleanCaption = caption.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanCaption.isEmpty else { return false }
        isPublishing = true
        progress = 0.1
        progressLabel = "Preparing upload"
        defer { isPublishing = false }
        do {
            let descriptors = try media.map { value in
                ["mediaType": value.kind.rawValue, "mimeType": value.mimeType, "fileSize": try value.fileSize()] as [String: Any]
            }
            let upload = try await APIClient.shared.createUGCUpload(
                media: descriptors,
                caption: cleanCaption,
                musicTrackId: music?.trackId,
                productLinks: validProductLinks
            )
            let targets = upload.uploads ?? [UGCUploadTarget(index: 0, uploadUrl: upload.uploadUrl, uploadHeaders: upload.uploadHeaders)]
            if let posterURL = upload.posterUploadUrl,
               let poster = media.first?.posterURL {
                progressLabel = "Uploading preview"
                try await APIClient.shared.uploadUGC(
                    fileURL: poster,
                    to: posterURL,
                    headers: upload.posterUploadHeaders ?? ["Content-Type": "image/jpeg"]
                )
            }
            for (position, target) in targets.sorted(by: { $0.index < $1.index }).enumerated() {
                guard media.indices.contains(target.index) else { throw UGCSelectionError.unreadable }
                progress = 0.25 + (Double(position) / Double(max(1, targets.count))) * 0.55
                progressLabel = targets.count > 1 ? "Uploading photo \(position + 1) of \(targets.count)" : "Uploading media"
                try await APIClient.shared.uploadUGC(fileURL: media[target.index].fileURL, to: target.uploadUrl, headers: target.uploadHeaders)
            }
            progress = 0.85
            progressLabel = "Starting safety review"
            try await APIClient.shared.completeUGCUpload(postId: upload.post.postId)
            progress = 1
            progressLabel = "Sent for review"
            posts.insert(upload.post, at: 0)
            UGCPostingStore.shared.begin(upload.post, preview: media.first?.previewImage)
            clearDraft()
            Task { await poll(postId: upload.post.postId) }
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }

    private var validProductLinks: [UGCProductLink] {
        productLinks.compactMap { link in
            let name = link.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let raw = link.url.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, let url = URL(string: raw), ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return nil }
            return UGCProductLink(name: name, url: raw)
        }
    }

    // Video safety review is an async Rekognition job that routinely takes a
    // couple of minutes — poll long enough to catch the terminal state.
    private func poll(postId: String) async {
        for _ in 0..<45 {
            try? await Task.sleep(for: .seconds(4))
            guard let post = try? await APIClient.shared.fetchUGCPost(postId: postId) else { continue }
            if let index = posts.firstIndex(where: { $0.id == post.id }) { posts[index] = post }
            UGCPostingStore.shared.update(post)
            if post.isTerminal { return }
        }
    }
}

struct SelectedUGCMedia {
    enum Kind: String { case image, video }
    let kind: Kind
    let fileURL: URL
    let posterURL: URL?
    let previewImage: UIImage?
    let mimeType: String

    static func image(data: Data) throws -> SelectedUGCMedia {
        guard let source = UIImage(data: data) else { throw UGCSelectionError.unreadable }
        return try image(image: source)
    }

    static func image(image source: UIImage) throws -> SelectedUGCMedia {
        let image = source.preparingThumbnail(of: CGSize(width: 2048, height: 2048)) ?? source
        guard let jpeg = image.jpegData(compressionQuality: 0.86) else { throw UGCSelectionError.unreadable }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ugc-\(UUID().uuidString).jpg")
        try jpeg.write(to: url, options: .atomic)
        return SelectedUGCMedia(kind: .image, fileURL: url, posterURL: nil, previewImage: image, mimeType: "image/jpeg")
    }

    static func video(url: URL) async throws -> SelectedUGCMedia {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        guard duration.seconds.isFinite, duration.seconds <= 60 else {
            throw UGCSelectionError.videoTooLong
        }
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        let (frame, _) = try await generator.image(at: .zero)
        let image = UIImage(cgImage: frame)
        let poster = FileManager.default.temporaryDirectory.appendingPathComponent("ugc-poster-\(UUID().uuidString).jpg")
        try image.jpegData(compressionQuality: 0.82)?.write(to: poster, options: .atomic)
        let (fileURL, mimeType) = try await normalizeForModeration(asset: asset, originalURL: url)
        return SelectedUGCMedia(kind: .video, fileURL: fileURL, posterURL: poster, previewImage: image, mimeType: mimeType)
    }

    // Server-side safety review runs Rekognition Video, which only decodes
    // H.264 — iPhones capture HEVC by default, so those uploads came back
    // "Processing failed". Anything not already H.264 gets exported to an
    // H.264 MP4 here before upload.
    private static func normalizeForModeration(asset: AVURLAsset, originalURL: URL) async throws -> (URL, String) {
        let tracks = try await asset.loadTracks(withMediaType: .video)
        guard let track = tracks.first else { throw UGCSelectionError.unreadable }
        let descriptions = try await track.load(.formatDescriptions)
        let isH264 = descriptions.contains { CMFormatDescriptionGetMediaSubType($0) == kCMVideoCodecType_H264 }
        if isH264 {
            let type = UTType(filenameExtension: originalURL.pathExtension)?.preferredMIMEType ?? "video/quicktime"
            return (originalURL, type)
        }
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPreset1920x1080) else {
            throw UGCSelectionError.unreadable
        }
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("ugc-h264-\(UUID().uuidString).mp4")
        session.outputURL = output
        session.outputFileType = .mp4
        session.shouldOptimizeForNetworkUse = true
        await withCheckedContinuation { continuation in
            session.exportAsynchronously { continuation.resume() }
        }
        guard session.status == .completed else {
            throw session.error ?? UGCSelectionError.unreadable
        }
        try? FileManager.default.removeItem(at: originalURL)
        return (output, "video/mp4")
    }

    func fileSize() throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        return (attributes[.size] as? NSNumber)?.intValue ?? 0
    }

    func removeTemporaryFiles() {
        try? FileManager.default.removeItem(at: fileURL)
        if let posterURL { try? FileManager.default.removeItem(at: posterURL) }
    }
}

private struct TransferableVideo: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .movie) { received in
            let destination = FileManager.default.temporaryDirectory
                .appendingPathComponent("ugc-\(UUID().uuidString).\(received.file.pathExtension.isEmpty ? "mov" : received.file.pathExtension)")
            try FileManager.default.copyItem(at: received.file, to: destination)
            return Self(url: destination)
        }
    }
}

private enum UGCSelectionError: Error, Equatable { case unreadable, mixedMedia, videoTooLong }

private struct UGCMusicPicker: View {
    @Binding var selection: UGCMusicTrack?
    @Environment(\.dismiss) private var dismiss
    @State private var tracks: [UGCMusicTrack] = []
    @State private var player: AVPlayer?
    @State private var playingId: String?

    var body: some View {
        NavigationStack {
            List {
                Button("No music") {
                    player?.pause()
                    selection = nil
                    dismiss()
                }
                .foregroundStyle(Color.ink)

                ForEach(tracks) { track in
                    HStack(spacing: ThemeSpacing.sm) {
                        Button { toggle(track) } label: {
                            Image(systemName: playingId == track.id ? "pause.circle.fill" : "play.circle.fill")
                                .font(.title2).foregroundStyle(Color.coral)
                        }
                        .buttonStyle(.plain)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(track.title).font(.subheadline.weight(.semibold))
                            Text("\(track.artist) · \(track.durationSeconds)s · \(track.license)")
                                .font(.caption).foregroundStyle(Color.inkSecondary)
                        }
                        Spacer()
                        Button("Use") {
                            player?.pause()
                            selection = track
                            dismiss()
                        }
                        .font(.subheadline.weight(.bold)).foregroundStyle(Color.coral)
                    }
                }

                if tracks.isEmpty {
                    ContentUnavailableView(
                        "Music is being prepared",
                        systemImage: "music.note",
                        description: Text("Only rights-cleared original tracks appear here.")
                    )
                }
            }
            .navigationTitle("Add music")
            .navigationBarTitleDisplayMode(.inline)
            .task { tracks = (try? await APIClient.shared.fetchUGCMusicTracks()) ?? [] }
            .onDisappear { player?.pause() }
        }
    }

    private func toggle(_ track: UGCMusicTrack) {
        if playingId == track.id {
            player?.pause()
            playingId = nil
            return
        }
        guard let url = URL(string: track.audioUrl) else { return }
        player?.pause()
        let next = AVPlayer(url: url)
        player = next
        playingId = track.id
        next.play()
    }
}

private struct UGCCameraPicker: UIViewControllerRepresentable {
    let onMedia: (SelectedUGCMedia) -> Void
    @Environment(\.dismiss) private var dismiss

    static var isAvailable: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.mediaTypes = [UTType.image.identifier, UTType.movie.identifier]
        picker.videoMaximumDuration = 60
        picker.videoQuality = .typeHigh
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: UGCCameraPicker
        init(parent: UGCCameraPicker) { self.parent = parent }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage,
               let data = image.jpegData(compressionQuality: 0.86),
               let media = try? SelectedUGCMedia.image(data: data) {
                parent.onMedia(media)
                return
            }
            if let url = info[.mediaURL] as? URL {
                Task {
                    let copy = FileManager.default.temporaryDirectory.appendingPathComponent("ugc-\(UUID().uuidString).mov")
                    try? FileManager.default.copyItem(at: url, to: copy)
                    if let media = try? await SelectedUGCMedia.video(url: copy) { parent.onMedia(media) }
                }
                return
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
    }
}
