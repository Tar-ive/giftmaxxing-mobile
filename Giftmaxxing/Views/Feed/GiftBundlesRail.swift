import SwiftUI

// "Goes well together" — Reddit-mined gift bundles resolved to real products.
// The KNOWLEDGE table learned which gift ideas people suggest TOGETHER per
// recipient ("flowers + plant" for mom); build-shelves.mjs matched each idea
// to buyable catalog items, and this rail puts that pairing wisdom in the
// feed. Renders nothing until the server has bundle data — safe by default.
struct GiftBundlesRail: View {
    @State private var bundles: [APIClient.GiftBundle] = []
    @State private var selected: APIClient.GiftBundle?

    var body: some View {
        Group {
            if bundles.isEmpty {
                EmptyView()
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label("Goes well together", systemImage: "gift.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Color.ink)
                        Spacer()
                        Text("From real gifters")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 14)

                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 12) {
                            ForEach(bundles) { bundle in
                                Button { selected = bundle } label: {
                                    card(bundle)
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
            }
        }
        .task {
            guard bundles.isEmpty else { return }
            bundles = (try? await APIClient.shared.fetchGiftBundles(limit: 6)) ?? []
        }
        .sheet(item: $selected) { bundle in
            GiftBundleDetailView(bundle: bundle)
        }
    }

    private func card(_ bundle: APIClient.GiftBundle) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Collage: one thumbnail per slot (the pairing IS the content).
            HStack(spacing: 4) {
                ForEach(bundle.slots.prefix(3)) { slot in
                    ZStack {
                        if let post = slot.items.first {
                            Color.gradient(for: post.product.grad)
                            if let image = post.product.image {
                                CachedAsyncImage(url: image, width: 200)
                            } else {
                                Text(slot.emoji).font(.system(size: 26))
                            }
                        }
                    }
                    .frame(width: 66, height: 82)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(bundle.slots.map(\.label).joined(separator: " + "))
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.ink)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text("For \(bundle.recipient)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 210, alignment: .leading)
        .padding(10)
        .background(Color.surfaceSunken.opacity(0.6), in: RoundedRectangle(cornerRadius: 16))
    }
}

// One bundle, expanded: a section per idea with its buyable options.
struct GiftBundleDetailView: View {
    let bundle: APIClient.GiftBundle
    @State private var selectedPost: Post?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(bundle.why)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 14)

                    ForEach(bundle.slots) { slot in
                        VStack(alignment: .leading, spacing: 8) {
                            Text("\(slot.emoji)  \(slot.label)")
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                                .foregroundStyle(Color.ink)
                                .padding(.horizontal, 14)

                            ScrollView(.horizontal, showsIndicators: false) {
                                LazyHStack(spacing: 12) {
                                    ForEach(slot.items) { post in
                                        Button { selectedPost = post } label: {
                                            optionCard(post)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.horizontal, 14)
                            }
                        }
                    }
                }
                .padding(.vertical, 14)
            }
            .navigationTitle("For \(bundle.recipient)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .sheet(item: $selectedPost) { post in
            PostDetailView(post: post)
        }
    }

    private func optionCard(_ post: Post) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                Color.gradient(for: post.product.grad)
                if let image = post.product.image {
                    CachedAsyncImage(url: image, width: 300)
                } else {
                    Text(post.product.emoji).font(.system(size: 30))
                }
            }
            .frame(width: 140, height: 150)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 12))

            Text(post.product.name)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.ink)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            if post.product.price > 0 {
                Text("$\(Int(post.product.price))")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.coral)
            }
        }
        .frame(width: 140, alignment: .leading)
    }
}
