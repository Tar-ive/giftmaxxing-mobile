import SwiftUI
import UIKit

@MainActor
final class UGCPostingStore: ObservableObject {
    static let shared = UGCPostingStore()

    struct Item: Identifiable {
        let id: String
        let caption: String
        let mediaType: String
        let preview: UIImage?
        var status: String
    }

    @Published private(set) var items: [Item] = []

    func begin(_ post: UGCPost, preview: UIImage?) {
        items.removeAll { $0.id == post.id }
        items.insert(Item(
            id: post.id,
            caption: post.caption,
            mediaType: post.mediaType,
            preview: preview,
            status: "Posting…"
        ), at: 0)
    }

    func update(_ post: UGCPost) {
        guard let index = items.firstIndex(where: { $0.id == post.id }) else { return }
        switch post.processingStatus {
        case "READY":
            items.remove(at: index)
            NotificationCenter.default.post(name: .ugcPostReady, object: post)
        case "REJECTED": items[index].status = "Not published — failed safety review"
        case "FAILED": items[index].status = "Processing failed — try again"
        default: items[index].status = "Safety review…"
        }
    }
}

extension Notification.Name {
    static let ugcPostReady = Notification.Name("ugcPostReady")
}

struct PendingUGCFeedCard: View {
    let item: UGCPostingStore.Item

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 9) {
                Image(systemName: "person.crop.circle.fill")
                    .font(.title2)
                    .foregroundStyle(Color.coral)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Your post").font(.subheadline.weight(.semibold))
                    Text(item.status).font(.caption).foregroundStyle(Color.inkSecondary)
                }
                Spacer()
                ProgressView().tint(Color.coral)
            }
            if let preview = item.preview {
                Image(uiImage: preview)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .aspectRatio(
                        MediaAspect.snap(width: preview.size.width, height: preview.size.height),
                        contentMode: .fit
                    )
                    .clipped()
            }
            Text(item.caption).font(.subheadline).lineLimit(2)
        }
        .padding(14)
        .background(Color.surface)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Your post is \(item.status)")
    }
}
