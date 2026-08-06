import SwiftUI

// "Who's this for?" — the one question that turns a pile of finds into a cart.
//
// Shown when committing an item (or a whole idea pack) to the cart. Offers the
// people you're already shopping for — existing cart sections first, then the
// recipients on your Gift Boards — so the common case is one tap and nobody
// types a name twice.
struct RecipientPickerSheet: View {
    /// What's being committed. One item, or a whole pack/board.
    let posts: [Post]
    /// Where these came from, for analytics + the cart item's provenance.
    var source: String = "feed"
    /// Pre-links the new section back to the Gift Board it grew out of.
    var boardId: String?
    var occasion: String?
    var onDone: ((CartSection) -> Void)?

    @ObservedObject private var cart = CartStore.shared
    @ObservedObject private var boards = SwipeListStore.shared
    @Environment(\.dismiss) private var dismiss

    @State private var newName = ""
    @FocusState private var nameFocused: Bool

    private var title: String {
        posts.count == 1 ? "Add to cart" : "Add \(posts.count) to cart"
    }

    // Everyone we already know they shop for, cart sections first, deduped.
    private var suggestions: [Suggestion] {
        var seen = Set<String>()
        var out: [Suggestion] = []

        for section in cart.sortedSections where !section.isUnassigned {
            let key = section.recipientName.lowercased()
            guard seen.insert(key).inserted else { continue }
            out.append(Suggestion(
                name: section.recipientName,
                detail: section.items.isEmpty
                    ? "in your cart"
                    : "\(section.items.count) in cart",
                relationship: section.relationship,
                occasion: section.occasion
            ))
        }

        for board in boards.lists {
            let name = board.recipientName?.trimmingCharacters(in: .whitespaces)
            guard let name, !name.isEmpty else { continue }
            let key = name.lowercased()
            guard seen.insert(key).inserted else { continue }
            out.append(Suggestion(
                name: name,
                detail: "\(board.posts.count) on their board",
                relationship: board.relationship,
                occasion: board.occasion
            ))
        }
        return out
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: ThemeSpacing.sm) {
                    header

                    newPersonField

                    if !suggestions.isEmpty {
                        Text("SHOPPING FOR")
                            .font(.caption.weight(.medium))
                            .tracking(0.5)
                            .foregroundStyle(Color.inkTertiary)
                            .padding(.horizontal, ThemeSpacing.md)
                            .padding(.top, ThemeSpacing.xs)

                        ForEach(suggestions) { suggestion in
                            personRow(suggestion)
                        }
                    }

                    Button {
                        commit(to: nil)
                    } label: {
                        Label("Decide later", systemImage: "tray")
                            .font(.subheadline)
                            .foregroundStyle(Color.inkSecondary)
                            .padding(.horizontal, ThemeSpacing.md)
                            .padding(.vertical, ThemeSpacing.sm)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.bottom, ThemeSpacing.lg)
            }
            .background(Color.surface)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.inkSecondary)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // What's being committed — anchors the sheet so the choice has a subject.
    private var header: some View {
        HStack(spacing: ThemeSpacing.sm) {
            ForEach(posts.prefix(3)) { post in
                thumbnail(post, size: 48)
            }
            if posts.count > 3 {
                Text("+\(posts.count - 3)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.inkSecondary)
            }
            Spacer()
        }
        .padding(.horizontal, ThemeSpacing.md)
        .padding(.top, ThemeSpacing.xs)
    }

    private var newPersonField: some View {
        HStack(spacing: ThemeSpacing.sm) {
            Image(systemName: "person.badge.plus")
                .font(.headline)
                .foregroundStyle(Color.coral)
                .frame(width: 44, height: 44)
                .background(Color.coralSoft)
                .clipShape(RoundedRectangle(cornerRadius: ThemeRadius.md, style: .continuous))

            TextField("Someone new", text: $newName)
                .font(.body)
                .textFieldStyle(.plain)
                .focused($nameFocused)
                .submitLabel(.done)
                .onSubmit { commitNewName() }

            if !newName.trimmingCharacters(in: .whitespaces).isEmpty {
                Button("Add") { commitNewName() }
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Color.coral)
            }
        }
        .padding(.horizontal, ThemeSpacing.md)
        .padding(.vertical, ThemeSpacing.xs)
    }

    private func personRow(_ suggestion: Suggestion) -> some View {
        Button {
            commit(to: suggestion)
        } label: {
            HStack(spacing: ThemeSpacing.sm) {
                Text(initials(suggestion.name))
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Color.coral)
                    .frame(width: 44, height: 44)
                    .background(Color.coralSoft)
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(suggestion.name)
                        .font(.headline)
                        .foregroundStyle(Color.ink)
                        .lineLimit(1)
                    Text(suggestion.detail)
                        .font(.footnote)
                        .foregroundStyle(Color.inkTertiary)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "plus.circle.fill")
                    .font(.title3)
                    .foregroundStyle(Color.coral)
            }
            .padding(.horizontal, ThemeSpacing.md)
            .padding(.vertical, ThemeSpacing.xs)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add to \(suggestion.name)'s cart")
    }

    private func commitNewName() {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        commit(to: Suggestion(name: name, detail: "", relationship: nil, occasion: nil))
    }

    private func commit(to suggestion: Suggestion?) {
        cart.addAll(
            posts,
            for: suggestion?.name,
            relationship: suggestion?.relationship,
            occasion: occasion ?? suggestion?.occasion,
            boardId: boardId,
            source: source
        )
        for post in posts {
            AnalyticsEngine.shared.trackContentAction(.contentSave, postId: post.id)
        }
        let section = cart.sectionFor(recipientName: suggestion?.name)
        onDone?(section)
        dismiss()
    }

    private func initials(_ name: String) -> String {
        let parts = name.split(separator: " ").prefix(2)
        let letters = parts.compactMap { $0.first }.map(String.init)
        return letters.isEmpty ? "?" : letters.joined().uppercased()
    }

    private func thumbnail(_ post: Post, size: CGFloat) -> some View {
        ZStack {
            Color.gradient(for: post.product.grad)
            if let image = post.product.image {
                CachedAsyncImage(url: image, width: 200)
            }
        }
        .frame(width: size, height: size)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: ThemeRadius.md, style: .continuous))
    }

    struct Suggestion: Identifiable {
        var id: String { name.lowercased() }
        let name: String
        let detail: String
        let relationship: String?
        let occasion: String?
    }
}
