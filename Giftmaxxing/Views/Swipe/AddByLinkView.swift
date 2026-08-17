import SwiftUI
import UIKit
import GiftmaxxingCore
import GiftmaxxingDesignSystem

// Paste any product link — SHEIN, Target, Walmart, Sephora, HEB, a Shopify
// store, anything with a URL — and it becomes a swipeable card you can drop
// into a Gift Board and send to someone. They swipe yes/no; you learn what
// they'd actually want, subtly. One URL per line, so a whole shopping-tab dump
// lands in one go. Whatever can't be scraped becomes an honest name-only card
// (LinkIngest) — the link always works.
struct AddByLinkView: View {
    // When set, links drop straight into this board. When nil, the user picks
    // (or creates) a board after building the cards.
    var targetListId: String? = nil
    var onFinished: (() -> Void)? = nil

    @ObservedObject private var store = SwipeListStore.shared
    @Environment(\.dismiss) private var dismiss

    @State private var input = ""
    @State private var built: [Post] = []
    @State private var isBuilding = false
    @State private var builtCount = 0
    @State private var previewPost: Post?
    @State private var showBoardPicker = false
    @State private var addedToName: String?

    private var targetList: SwipeList? {
        targetListId.flatMap { id in store.lists.first { $0.id == id } }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let addedToName {
                        successBanner(addedToName)
                    }
                    inputCard
                    if isBuilding { buildingRow }
                    if !built.isEmpty { builtSection }
                }
                .padding(16)
            }
            .background(Color.surface)
            .navigationTitle(targetList.map { "Add links to \($0.name)" } ?? "Add by link")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { finish() }
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Color.coral)
                }
            }
            .sheet(item: $previewPost) { post in
                PostDetailView(post: post)
            }
            .sheet(isPresented: $showBoardPicker) {
                BoardChooserSheet(posts: built) { listName in
                    addedToName = listName
                    built = []
                    input = ""
                }
            }
            .onAppear(perform: prefillFromClipboard)
        }
    }

    // MARK: - Sections

    private var inputCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Paste product links — one per line")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            ZStack(alignment: .topLeading) {
                if input.isEmpty {
                    Text("https://…\nhttps://…")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.line)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 14)
                }
                TextEditor(text: $input)
                    .font(.system(size: 14))
                    .frame(minHeight: 110)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            }
            .background(Color.cream)
            .clipShape(RoundedRectangle(cornerRadius: 14))

            HStack(spacing: 10) {
                Button {
                    if let clip = UIPasteboard.general.string, !clip.isEmpty {
                        input = input.isEmpty ? clip : input + "\n" + clip
                    }
                } label: {
                    Label("Paste", systemImage: "doc.on.clipboard")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.coral)
                }
                Spacer()
                Button {
                    Task { await build() }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "wand.and.stars")
                        Text(urlLines.count > 1 ? "Fetch \(urlLines.count) links" : "Fetch link")
                            .font(.labelBold)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(urlLines.isEmpty ? Color.coral.opacity(0.4) : Color.coral)
                    .clipShape(Capsule())
                }
                .disabled(urlLines.isEmpty || isBuilding)
            }
        }
    }

    private var buildingRow: some View {
        HStack(spacing: 10) {
            ProgressView()
            Text("Fetching \(builtCount)/\(urlLines.count)…")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 8)
    }

    private var builtSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\(built.count) ready — tap to preview, then add")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            ForEach(built) { post in
                builtRow(post)
            }

            Button(action: addAll) {
                HStack {
                    Spacer()
                    Image(systemName: "rectangle.stack.badge.plus")
                    Text(targetList != nil
                         ? "Add \(built.count) to this board"
                         : "Add \(built.count) to a Gift Board")
                        .font(.labelBold)
                    Spacer()
                }
                .foregroundStyle(.white)
                .padding(.vertical, 14)
                .background(Color.coral)
                .clipShape(Capsule())
            }
            .padding(.top, 4)
        }
    }

    private func builtRow(_ post: Post) -> some View {
        HStack(spacing: 12) {
            Button { previewPost = post } label: {
                HStack(spacing: 12) {
                    ZStack {
                        Color.gradient(for: post.product.grad)
                        Text(post.product.emoji).font(.system(size: 20))
                        if let image = post.product.image {
                            CachedAsyncImage(url: image, width: 200)
                        }
                    }
                    .frame(width: 52, height: 52)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(post.product.name)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.ink)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        Text(metaLine(post))
                            .font(.captionMedium)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                }
            }
            .buttonStyle(.plain)

            Button {
                built.removeAll { $0.id == post.id }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(Color.line)
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(Color.cream)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func successBanner(_ name: String) -> some View {
        Label("Added to \(name) — send the board when it's ready.", systemImage: "checkmark.seal.fill")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Color.coral)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.coralSoft)
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Logic

    private var urlLines: [String] {
        input
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.lowercased().hasPrefix("http") }
    }

    private func build() async {
        let lines = urlLines
        guard !lines.isEmpty else { return }
        isBuilding = true
        builtCount = 0
        var results: [Post] = []
        // Sequential (not a fan-out): keeps retailer sites from seeing a burst
        // of simultaneous hits, and lets the counter tick honestly.
        for line in lines {
            if let post = await LinkIngest.post(from: line) {
                if !results.contains(where: { $0.id == post.id }),
                   !built.contains(where: { $0.id == post.id }) {
                    results.append(post)
                }
            }
            builtCount += 1
        }
        built.append(contentsOf: results)
        input = ""
        isBuilding = false
    }

    private func addAll() {
        guard !built.isEmpty else { return }
        if let id = targetListId {
            store.add(built, to: id)
            finish()
        } else {
            showBoardPicker = true
        }
    }

    private func finish() {
        onFinished?()
        dismiss()
    }

    private func metaLine(_ post: Post) -> String {
        var parts = [post.product.brand]
        if post.product.price > 0 { parts.append("$\(Int(post.product.price))") }
        if post.product.image == nil { parts.append("no preview image") }
        return parts.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private func prefillFromClipboard() {
        guard input.isEmpty,
              let clip = UIPasteboard.general.string,
              clip.lowercased().contains("http") else { return }
        input = clip
    }
}

// Pick or spin up a Gift Board for a batch of pasted finds, then drop them all
// in at once. Mirrors SwipeListPickerSheet's create-inline pattern, but adds an
// array instead of toggling one.
struct BoardChooserSheet: View {
    let posts: [Post]
    var onAdded: (String) -> Void

    @ObservedObject private var store = SwipeListStore.shared
    @Environment(\.dismiss) private var dismiss

    @State private var showNew = false
    @State private var newName = ""
    @State private var newRecipient = ""
    @FocusState private var nameFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 10) {
                    Text("\(posts.count) find\(posts.count == 1 ? "" : "s") → which board?")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.top, 8)

                    if showNew || store.lists.isEmpty {
                        newCard
                    } else {
                        Button {
                            withAnimation(.spring(response: 0.3)) { showNew = true }
                            nameFocused = true
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
                        Button {
                            store.add(posts, to: list.id)
                            onAdded(list.name)
                            dismiss()
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "gift")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(Color.coral)
                                    .frame(width: 44, height: 44)
                                    .background(Color.coralSoft)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(list.name)
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(Color.ink)
                                        .lineLimit(1)
                                    Text(subtitle(list))
                                        .font(.captionMedium)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "plus.circle")
                                    .font(.system(size: 22))
                                    .foregroundStyle(Color.coral)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 6)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.bottom, 20)
            }
            .background(Color.surface)
            .navigationTitle("Add to a Gift Board")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var newCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("NEW GIFT BOARD")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.secondary)
            TextField("Board name (e.g. Sarah's birthday)", text: $newName)
                .textFieldStyle(.roundedBorder)
                .focused($nameFocused)
            TextField("Who's it for? (optional)", text: $newRecipient)
                .textFieldStyle(.roundedBorder)
            Button {
                let recipient = newRecipient.trimmingCharacters(in: .whitespaces)
                var name = newName.trimmingCharacters(in: .whitespaces)
                if name.isEmpty { name = recipient.isEmpty ? "New Gift Board" : "For \(recipient)" }
                let list = store.createList(name: name, recipientName: recipient.isEmpty ? nil : recipient)
                store.add(posts, to: list.id)
                onAdded(list.name)
                dismiss()
            } label: {
                Text("Create & add \(posts.count)")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(Color.coral)
                    .clipShape(Capsule())
            }
            .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty
                      && newRecipient.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(14)
        .background(Color.cream)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 16)
    }

    private func subtitle(_ list: SwipeList) -> String {
        var parts: [String] = []
        if let r = list.recipientName, !r.isEmpty { parts.append("for \(r)") }
        parts.append("\(list.posts.count) idea\(list.posts.count == 1 ? "" : "s")")
        return parts.joined(separator: " · ")
    }
}
