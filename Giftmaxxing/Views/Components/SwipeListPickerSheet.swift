import SwiftUI
import GiftmaxxingCore

// Instagram-collections-style "save to board" sheet. Tapping "Gift board"
// anywhere in the app lands here: pick which person's Gift Board the find
// belongs to (toggle in/out), or spin up a new board inline ("Sarah's
// birthday") without leaving the moment.
struct SwipeListPickerSheet: View {
    let post: Post

    @ObservedObject private var store = SwipeListStore.shared
    @Environment(\.dismiss) private var dismiss

    @State private var showNewList = false
    @State private var newListName = ""
    @State private var newRecipientName = ""
    @FocusState private var nameFieldFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 10) {
                    // The find being saved — anchors the sheet visually.
                    HStack(spacing: 12) {
                        postThumbnail(post, size: 48)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(post.product.name)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Color.ink)
                                .lineLimit(1)
                            if post.product.price > 0 {
                                Text("$\(Int(post.product.price))")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(Color.coral)
                            }
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                    if showNewList || store.lists.isEmpty {
                        newListCard
                    } else {
                        Button {
                            withAnimation(.spring(response: 0.3)) { showNewList = true }
                            nameFieldFocused = true
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "plus")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundStyle(Color.coral)
                                    .frame(width: 44, height: 44)
                                    .background(Color.coralSoft)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                Text("New board — for a person or occasion")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(Color.ink)
                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 6)
                        }
                        .buttonStyle(.plain)
                    }

                    ForEach(store.lists) { list in
                        listRow(list)
                    }
                }
                .padding(.bottom, 20)
            }
            .background(Color.surface)
            .navigationTitle("Save to a Gift Board")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Color.coral)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // Inline create — name + who it's for, then the find lands in it directly.
    private var newListCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("NEW GIFT BOARD")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.secondary)
            TextField("Board name (e.g. Sarah's birthday)", text: $newListName)
                .textFieldStyle(.roundedBorder)
                .focused($nameFieldFocused)
            TextField("Who's it for? (optional)", text: $newRecipientName)
                .textFieldStyle(.roundedBorder)
            Button {
                createAndAdd()
            } label: {
                Text("Create & add")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(Color.coral)
                    .clipShape(Capsule())
            }
            .disabled(newListName.trimmingCharacters(in: .whitespaces).isEmpty
                      && newRecipientName.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(14)
        .background(Color.cream)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 16)
    }

    private func createAndAdd() {
        let recipient = newRecipientName.trimmingCharacters(in: .whitespaces)
        var name = newListName.trimmingCharacters(in: .whitespaces)
        if name.isEmpty { name = recipient.isEmpty ? "New Gift Board" : "For \(recipient)" }
        let list = store.createList(name: name, recipientName: recipient.isEmpty ? nil : recipient)
        store.toggle(post, in: list.id)
        newListName = ""
        newRecipientName = ""
        // The save is done — close the moment and confirm with a toast whose
        // "View" link teaches where boards live (Instagram-collections model).
        dismiss()
        BoardToastCenter.shared.show(boardId: list.id, boardName: list.name)
    }

    private func listRow(_ list: SwipeList) -> some View {
        let isIn = list.posts.contains(where: { $0.id == post.id })
        return Button {
            store.toggle(post, in: list.id)
            // Adding closes the sheet with a toast; removing stays put so the
            // user can keep managing membership.
            if !isIn {
                dismiss()
                BoardToastCenter.shared.show(boardId: list.id, boardName: list.name)
            }
        } label: {
            HStack(spacing: 12) {
                if let cover = list.posts.first {
                    postThumbnail(cover, size: 44)
                } else {
                    Image(systemName: "gift")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.coral)
                        .frame(width: 44, height: 44)
                        .background(Color.coralSoft)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(list.name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.ink)
                        .lineLimit(1)
                    Text(subtitle(for: list))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: isIn ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(isIn ? Color.coral : Color.line)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
    }

    private func subtitle(for list: SwipeList) -> String {
        var parts: [String] = []
        if let recipient = list.recipientName, !recipient.isEmpty { parts.append("for \(recipient)") }
        parts.append("\(list.posts.count) idea\(list.posts.count == 1 ? "" : "s")")
        if list.challengeId != nil { parts.append("shared") }
        return parts.joined(separator: " · ")
    }

    private func postThumbnail(_ post: Post, size: CGFloat) -> some View {
        ZStack {
            Color.gradient(for: post.product.grad)
            Text(post.product.emoji).font(.system(size: size * 0.4))
            if let image = post.product.image {
                CachedAsyncImage(url: image, width: 200)
            }
        }
        .frame(width: size, height: size)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
