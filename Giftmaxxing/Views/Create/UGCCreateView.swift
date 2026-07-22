import AVFoundation
import AVKit
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct UGCCreateView: View {
    @EnvironmentObject private var authManager: AuthManager
    @StateObject private var model = UGCCreateViewModel()
    @State private var selection: PhotosPickerItem?
    @State private var showSourcePicker = false
    @State private var showLibrary = false
    @State private var showCamera = false
    @State private var hapticTrigger = 0

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: ThemeSpacing.xl) {
                    intro
                    if let media = model.media {
                        preview(media)
                        caption
                        publishButton
                    } else {
                        mediaPicker
                    }
                    if !model.posts.isEmpty { posts }
                }
                .padding(ThemeSpacing.md)
            }
            .background(Color.cream)
            .navigationTitle("Create")
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .confirmationDialog("Add a photo or video", isPresented: $showSourcePicker) {
                Button("Photo Library") { showLibrary = true }
                if UGCCameraPicker.isAvailable {
                    Button("Camera") { showCamera = true }
                }
                Button("Cancel", role: .cancel) {}
            }
            .photosPicker(
                isPresented: $showLibrary,
                selection: $selection,
                matching: .any(of: [.images, .videos]),
                preferredItemEncoding: .current
            )
            .fullScreenCover(isPresented: $showCamera) {
                UGCCameraPicker { media in
                    model.media = media
                    showCamera = false
                }
                .ignoresSafeArea()
            }
            .onChange(of: selection) { _, item in
                guard let item else { return }
                Task { await model.load(item) }
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

    private var intro: some View {
        VStack(alignment: .leading, spacing: ThemeSpacing.xs) {
            Text("Share a gift find")
                .font(.title2.weight(.bold))
                .fontDesign(.rounded)
                .foregroundStyle(Color.ink)
            Text("Post an unboxing, a thoughtful idea, or something worth gifting.")
                .font(.body)
                .foregroundStyle(Color.inkSecondary)
            Label("Every upload is screened before it can appear in the feed.", systemImage: "checkmark.shield.fill")
                .font(.footnote)
                .foregroundStyle(Color.inkSecondary)
        }
    }

    private var mediaPicker: some View {
        Button { showSourcePicker = true } label: {
            VStack(spacing: ThemeSpacing.md) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.largeTitle)
                    .foregroundStyle(Color.coral)
                Text("Choose a photo or video")
                    .font(.headline)
                Text("Photos up to 20 MB · videos up to 200 MB")
                    .font(.footnote)
                    .foregroundStyle(Color.inkSecondary)
            }
            .foregroundStyle(Color.ink)
            .frame(maxWidth: .infinity)
            .padding(.vertical, ThemeSpacing.xl)
            .background(Color.surface)
            .clipShape(RoundedRectangle(cornerRadius: ThemeRadius.xl, style: .continuous))
            .cardElevation()
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Choose a photo or video to post")
    }

    private func preview(_ media: SelectedUGCMedia) -> some View {
        ZStack(alignment: .topTrailing) {
            Group {
                switch media.kind {
                case .image:
                    if let image = media.previewImage {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                    }
                case .video:
                    VideoPlayer(player: AVPlayer(url: media.fileURL))
                }
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(4 / 5, contentMode: .fit)
            .background(Color.surfaceSunken)
            .clipShape(RoundedRectangle(cornerRadius: ThemeRadius.xl, style: .continuous))

            Button {
                model.clearDraft()
                selection = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.headline)
                    .foregroundStyle(Color.ink)
                    .frame(minWidth: 44, minHeight: 44)
                    .background(.ultraThinMaterial)
                    .clipShape(Circle())
            }
            .padding(ThemeSpacing.sm)
            .accessibilityLabel("Remove selected media")
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
                    if await model.publish() { hapticTrigger += 1 }
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
                if let image = post.posterUrl ?? (post.mediaType == "image" ? post.mediaUrl : nil) {
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

@MainActor
final class UGCCreateViewModel: ObservableObject {
    @Published var media: SelectedUGCMedia?
    @Published var caption = ""
    @Published var posts: [UGCPost] = []
    @Published var isPublishing = false
    @Published var progress = 0.0
    @Published var progressLabel = "Preparing upload"
    @Published var error: String?

    func load(_ item: PhotosPickerItem) async {
        do {
            if item.supportedContentTypes.contains(where: { $0.conforms(to: .movie) }) {
                guard let movie = try await item.loadTransferable(type: TransferableVideo.self) else {
                    throw UGCSelectionError.unreadable
                }
                media = try await SelectedUGCMedia.video(url: movie.url)
            } else if let data = try await item.loadTransferable(type: Data.self) {
                media = try SelectedUGCMedia.image(data: data)
            } else {
                throw UGCSelectionError.unreadable
            }
        } catch {
            self.error = "That item couldn’t be prepared. Choose another photo or video."
        }
    }

    func clearDraft() {
        media?.removeTemporaryFiles()
        media = nil
        caption = ""
    }

    func refreshPosts() async {
        do { posts = try await APIClient.shared.fetchMyUGCPosts() } catch { }
    }

    func publish() async -> Bool {
        guard let media else { return false }
        let cleanCaption = caption.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanCaption.isEmpty else { return false }
        isPublishing = true
        progress = 0.1
        progressLabel = "Preparing upload"
        defer { isPublishing = false }
        do {
            let size = try media.fileSize()
            let upload = try await APIClient.shared.createUGCUpload(
                mediaType: media.kind.rawValue,
                mimeType: media.mimeType,
                fileSize: size,
                caption: cleanCaption
            )
            if let posterURL = upload.posterUploadUrl,
               let poster = media.posterURL {
                progressLabel = "Uploading preview"
                try await APIClient.shared.uploadUGC(
                    fileURL: poster,
                    to: posterURL,
                    headers: upload.posterUploadHeaders ?? ["Content-Type": "image/jpeg"]
                )
            }
            progress = 0.3
            progressLabel = "Uploading media"
            try await APIClient.shared.uploadUGC(fileURL: media.fileURL, to: upload.uploadUrl, headers: upload.uploadHeaders)
            progress = 0.85
            progressLabel = "Starting safety review"
            try await APIClient.shared.completeUGCUpload(postId: upload.post.postId)
            progress = 1
            progressLabel = "Sent for review"
            posts.insert(upload.post, at: 0)
            clearDraft()
            await poll(postId: upload.post.postId)
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }

    private func poll(postId: String) async {
        for _ in 0..<20 {
            try? await Task.sleep(for: .seconds(2))
            guard let post = try? await APIClient.shared.fetchUGCPost(postId: postId) else { continue }
            if let index = posts.firstIndex(where: { $0.id == post.id }) { posts[index] = post }
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
        let image = source.preparingThumbnail(of: CGSize(width: 2048, height: 2048)) ?? source
        guard let jpeg = image.jpegData(compressionQuality: 0.86) else { throw UGCSelectionError.unreadable }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ugc-\(UUID().uuidString).jpg")
        try jpeg.write(to: url, options: .atomic)
        return SelectedUGCMedia(kind: .image, fileURL: url, posterURL: nil, previewImage: image, mimeType: "image/jpeg")
    }

    static func video(url: URL) async throws -> SelectedUGCMedia {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        let (frame, _) = try await generator.image(at: .zero)
        let image = UIImage(cgImage: frame)
        let poster = FileManager.default.temporaryDirectory.appendingPathComponent("ugc-poster-\(UUID().uuidString).jpg")
        try image.jpegData(compressionQuality: 0.82)?.write(to: poster, options: .atomic)
        let type = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "video/quicktime"
        return SelectedUGCMedia(kind: .video, fileURL: url, posterURL: poster, previewImage: image, mimeType: type)
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

private enum UGCSelectionError: Error { case unreadable }

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
