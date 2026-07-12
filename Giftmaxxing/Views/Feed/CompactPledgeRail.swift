import AVKit
import SwiftUI

/// A compact, Amazon-inspired horizontal recommendation rail for group gifting.
/// It intentionally shows two cards at once on a standard iPhone: enough
/// context to browse quickly without turning Home into another full-screen deck.
struct CompactPledgeRail: View {
    let posts: [Post]
    let onPledge: (Post) -> Void
    let onProductTap: (Post) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Pledge picks", systemImage: "person.2.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.ink)
                Spacer()
                Text("Swipe to browse")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 10) {
                    ForEach(posts) { post in
                        CompactPledgeCard(
                            post: post,
                            onPledge: { onPledge(post) },
                            onProductTap: { onProductTap(post) }
                        )
                    }
                }
                .scrollTargetLayout()
                .padding(.horizontal, 14)
                .padding(.vertical, 2)
            }
            .scrollTargetBehavior(.viewAligned)
        }
        .padding(.vertical, 8)
        .background(Color.surface)
    }
}

private struct CompactPledgeCard: View {
    let post: Post
    let onPledge: () -> Void
    let onProductTap: () -> Void

    private let width: CGFloat = 158

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onProductTap) {
                CompactPostMedia(post: post)
                    .frame(width: width, height: 112)
                    .clipped()
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 5) {
                Text(post.product.name)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.ink)
                    .lineLimit(2)
                    .frame(height: 30, alignment: .topLeading)

                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("$\(Int(post.product.price))")
                        .font(.system(size: 14, weight: .heavy))
                    Text(post.product.brand)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Button(action: onPledge) {
                    Label("Pledge", systemImage: "person.2.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.coral)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Pledge toward \(post.product.name)")
            }
            .padding(9)
        }
        .frame(width: width, height: 207)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.black.opacity(0.07), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.06), radius: 3, y: 1)
        .scrollTransition(.animated, axis: .horizontal) { content, phase in
            content
                .scaleEffect(phase.isIdentity ? 1 : 0.97)
                .opacity(phase.isIdentity ? 1 : 0.88)
        }
    }
}

private struct CompactPostMedia: View {
    let post: Post

    private var videoURL: URL? {
        guard post.contentType?.lowercased().contains("video") == true,
              let mediaUrl = post.mediaUrl
        else { return nil }
        return URL(string: mediaUrl)
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Color.gradient(for: post.product.grad)

            Text(post.product.emoji)
                .font(.system(size: 38))

            if let videoURL {
                VideoPlayer(player: AVPlayer(url: videoURL))
                    .disabled(true)
                    .overlay(alignment: .topTrailing) {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(.white)
                            .shadow(radius: 2)
                            .padding(8)
                    }
            } else if let image = post.product.image ?? post.posterUrl {
                CachedAsyncImage(url: image, width: 300)
            }

            Text(post.contentType?.lowercased().contains("video") == true ? "VIDEO" : "PICK")
                .font(.system(size: 9, weight: .heavy))
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(.black.opacity(0.62))
                .clipShape(Capsule())
                .padding(7)
        }
    }
}
