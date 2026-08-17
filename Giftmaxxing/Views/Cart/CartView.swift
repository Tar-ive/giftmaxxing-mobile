import SwiftUI
import GiftmaxxingCore

// The cart, grouped by the person each gift is for.
//
// This is the "I've decided" surface — the counterpart to Gift Boards, which
// are the "I'm still looking" surface. Each section is one recipient's pile:
// its own subtotal, its own buy checklist, and its own packaging plan, because
// gifts get wrapped per person, not per order.
struct CartView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var cart = CartStore.shared

    @State private var packagingSection: CartSection?
    @State private var editingSection: CartSection?
    @State private var movingItem: MovingItem?
    @State private var selectedPost: Post?
    @State private var browserTarget: BrowserTarget?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: ThemeSpacing.xl) {
                if cart.isEmpty {
                    emptyState
                } else {
                    preparationProgress
                    ForEach(cart.sortedSections) { section in
                        if !section.items.isEmpty {
                            sectionCard(section)
                        }
                    }
                    grandTotal
                }
            }
            .padding(.horizontal, ThemeSpacing.md)
            .padding(.top, ThemeSpacing.sm)
            .padding(.bottom, 100) // tab bar + FAB clearance
        }
        .background(Color.cream)
        .navigationTitle("Prepare a surprise")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $packagingSection) { section in
            PackagingSheet(section: section)
        }
        .sheet(item: $editingSection) { section in
            CartSectionEditSheet(section: section)
        }
        .sheet(item: $movingItem) { moving in
            MoveItemSheet(item: moving)
        }
        .sheet(item: $selectedPost) { post in
            PostDetailView(post: post)
        }
        .sheet(item: $browserTarget) { target in
            SafariView(url: target.url).ignoresSafeArea()
        }
        .task { AnalyticsEngine.shared.trackScreenView(screen: "cart") }
    }

    // MARK: - Empty

    private var emptyState: some View {
        VStack(spacing: ThemeSpacing.md) {
            Image(systemName: "bag")
                .font(.largeTitle)
                .foregroundStyle(Color.inkTertiary)
            Text("Start a surprise for someone.")
                .font(.body)
                .foregroundStyle(Color.inkSecondary)
            Button {
                appState.showMaxi = true
            } label: {
                Label("Ask Maxi to start", systemImage: "sparkles")
            }
            .buttonStyle(SecondaryButtonStyle())
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 64)
    }

    private var preparationProgress: some View {
        let progress = CartPreparationProgress(sections: cart.sections)
        return VStack(alignment: .leading, spacing: ThemeSpacing.sm) {
            Label("SURPRISE PLAN", systemImage: "gift.fill")
                .font(.caption.weight(.semibold))
                .tracking(0.5)
                .foregroundStyle(Color.coral)
            Text(progress.totalPeople == 0
                 ? "Choose who these gifts are for"
                 : "Gifts prepared for \(progress.preparedPeople) of \(progress.totalPeople) people")
                .font(.headline)
                .fontDesign(.rounded)
                .foregroundStyle(Color.ink)
            ProgressView(value: progress.fraction)
                .tint(Color.coral)
                .accessibilityLabel("Surprise preparation progress")
                .accessibilityValue("\(progress.preparedPeople) of \(progress.totalPeople) people prepared")
        }
        .padding(ThemeSpacing.md)
        .background(Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: ThemeRadius.lg, style: .continuous))
    }

    // MARK: - Section

    private func sectionCard(_ section: CartSection) -> some View {
        VStack(alignment: .leading, spacing: ThemeSpacing.sm) {
            sectionHeader(section)

            VStack(spacing: 0) {
                ForEach(section.items) { item in
                    itemRow(item, in: section)
                    if item.id != section.items.last?.id {
                        Divider().padding(.leading, 76)
                    }
                }
            }
            .background(Color.surface)
            .clipShape(RoundedRectangle(cornerRadius: ThemeRadius.lg, style: .continuous))
            .shadow(
                color: ThemeElevation.card.color,
                radius: ThemeElevation.card.radius,
                y: ThemeElevation.card.y
            )

            sectionActions(section)
        }
    }

    private func sectionHeader(_ section: CartSection) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: ThemeSpacing.xs) {
            VStack(alignment: .leading, spacing: 2) {
                Text(section.recipientName)
                    .font(.title3.weight(.semibold))
                    .fontDesign(.rounded)
                    .foregroundStyle(Color.ink)
                if let detail = sectionDetail(section) {
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(Color.inkTertiary)
                }
            }
            Spacer()
            Text(section.subtotal, format: .currency(code: "USD").precision(.fractionLength(0)))
                .font(.headline)
                .monospacedDigit()
                .contentTransition(.numericText())
                .foregroundStyle(Color.ink)

            Menu {
                Button {
                    editingSection = section
                } label: {
                    Label("Edit person", systemImage: "pencil")
                }
                Button {
                    appState.maxiSeedRecipient = section.recipientName
                    appState.showMaxi = true
                } label: {
                    Label("Ask Maxi about \(section.recipientName)", systemImage: "sparkles")
                }
                Button(role: .destructive) {
                    cart.deleteSection(id: section.id)
                } label: {
                    Label("Clear section", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.headline)
                    .foregroundStyle(Color.inkSecondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Options for \(section.recipientName)")
        }
    }

    // "3 left to prepare · birthday in 12 days" — only what's true.
    private func sectionDetail(_ section: CartSection) -> String? {
        var parts: [String] = []
        let toBuy = section.items.filter { !$0.bought }.count
        if section.isComplete {
            parts.append("surprise ready")
        } else if toBuy > 0 {
            parts.append("\(toBuy) left to prepare")
        }
        if let occasion = section.occasion, !occasion.isEmpty { parts.append(occasion) }
        if let relationship = section.relationship, !relationship.isEmpty { parts.append(relationship) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func sectionActions(_ section: CartSection) -> some View {
        HStack(spacing: ThemeSpacing.sm) {
            Button {
                packagingSection = section
            } label: {
                Label("Prepare the surprise", systemImage: "shippingbox")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle())

            Button {
                appState.maxiSeedRecipient = section.recipientName
                appState.showMaxi = true
            } label: {
                Image(systemName: "sparkles")
                    .frame(width: 50, height: 50)
            }
            .buttonStyle(SecondaryButtonStyle())
            .accessibilityLabel("Ask Maxi about \(section.recipientName)")
        }
    }

    // MARK: - Item

    private func itemRow(_ item: CartItem, in section: CartSection) -> some View {
        HStack(spacing: ThemeSpacing.sm) {
            Button {
                cart.toggleBought(postId: item.id, in: section.id)
            } label: {
                Image(systemName: item.bought ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(item.bought ? Color.success : Color.line)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(item.bought ? "Mark as still preparing" : "Mark as prepared")
            .sensoryFeedback(.selection, trigger: item.bought)

            thumbnail(item.post)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.post.product.name)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(item.bought ? Color.inkTertiary : Color.ink)
                    .strikethrough(item.bought)
                    .lineLimit(2)

                HStack(spacing: ThemeSpacing.xs) {
                    Text(item.post.product.price > 0
                         ? item.lineTotal.formatted(.currency(code: "USD").precision(.fractionLength(0)))
                         : "Check price")
                        .font(.footnote.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(Color.coral)
                    if item.qty > 1 {
                        Text("× \(item.qty)")
                            .font(.footnote)
                            .foregroundStyle(Color.inkTertiary)
                    }
                }
            }

            Spacer(minLength: 0)

            Menu {
                Button {
                    openProduct(item.post)
                } label: {
                    Label("Open product page", systemImage: "safari")
                }
                Button {
                    selectedPost = item.post
                } label: {
                    Label("Details", systemImage: "info.circle")
                }
                Button {
                    cart.setQuantity(item.qty + 1, for: item.id, in: section.id)
                } label: {
                    Label("Add another", systemImage: "plus")
                }
                if item.qty > 1 {
                    Button {
                        cart.setQuantity(item.qty - 1, for: item.id, in: section.id)
                    } label: {
                        Label("Remove one", systemImage: "minus")
                    }
                }
                Button {
                    movingItem = MovingItem(item: item, fromSectionId: section.id)
                } label: {
                    Label("Move to someone else", systemImage: "arrow.right.circle")
                }
                Button(role: .destructive) {
                    cart.remove(postId: item.id, from: section.id)
                } label: {
                    Label("Remove", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.subheadline)
                    .foregroundStyle(Color.inkTertiary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Options for \(item.post.product.name)")
        }
        .padding(.trailing, ThemeSpacing.xs)
        .contentShape(Rectangle())
        .onTapGesture { selectedPost = item.post }
    }

    private var grandTotal: some View {
        HStack {
            Text("Estimated gift total")
                .font(.subheadline)
                .foregroundStyle(Color.inkSecondary)
            Spacer()
            Text(cart.total, format: .currency(code: "USD").precision(.fractionLength(0)))
                .font(.title3.weight(.bold))
                .monospacedDigit()
                .contentTransition(.numericText())
                .foregroundStyle(Color.ink)
        }
        .padding(ThemeSpacing.md)
        .background(Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: ThemeRadius.lg, style: .continuous))
    }

    private func openProduct(_ post: Post) {
        guard let url = Affiliate.productUrl(for: post) else { return }
        OutboundRouter.open(url, postId: post.id, source: "cart") {
            browserTarget = BrowserTarget(url: $0)
        }
    }

    private func thumbnail(_ post: Post) -> some View {
        ZStack {
            Color.gradient(for: post.product.grad)
            if let image = post.product.image {
                CachedAsyncImage(url: image, width: 200)
            }
        }
        .frame(width: 52, height: 52)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: ThemeRadius.md, style: .continuous))
    }

    struct MovingItem: Identifiable {
        var id: String { item.id }
        let item: CartItem
        let fromSectionId: String
    }
}

// Re-home one item. Small enough to be a list of names, no free text — a
// section that doesn't exist yet is made from the cart's own picker instead.
private struct MoveItemSheet: View {
    let item: CartView.MovingItem

    @ObservedObject private var cart = CartStore.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(cart.sortedSections.filter { $0.id != item.fromSectionId }) { section in
                    Button {
                        cart.move(
                            postId: item.item.id,
                            from: item.fromSectionId,
                            to: section.recipientName
                        )
                        dismiss()
                    } label: {
                        Text(section.recipientName)
                            .font(.body)
                            .foregroundStyle(Color.ink)
                    }
                }
            }
            .navigationTitle("Move to")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// Naming the unassigned pile, or correcting a name Maxi guessed.
private struct CartSectionEditSheet: View {
    let section: CartSection

    @ObservedObject private var cart = CartStore.shared
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var relationship: String = ""
    @State private var occasion: String = ""

    private let relationships = [
        "partner", "parent", "sibling", "child", "friend", "colleague", "grandparent"
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                    TextField("Occasion (birthday, anniversary…)", text: $occasion)
                }
                Section {
                    Picker("Relationship", selection: $relationship) {
                        Text("Not set").tag("")
                        ForEach(relationships, id: \.self) { r in
                            Text(r.capitalized).tag(r)
                        }
                    }
                    .pickerStyle(.menu)
                } header: {
                    Text("Relationship")
                } footer: {
                    Text("Shapes what Maxi suggests and how it wraps.")
                }
            }
            .navigationTitle("Who this is for")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        cart.updateSection(
                            id: section.id,
                            recipientName: name,
                            relationship: relationship.isEmpty ? nil : relationship,
                            occasion: occasion.isEmpty ? nil : occasion
                        )
                        dismiss()
                    }
                    .font(.headline)
                    .foregroundStyle(Color.coral)
                }
            }
            .onAppear {
                name = section.isUnassigned ? "" : section.recipientName
                relationship = section.relationship ?? ""
                occasion = section.occasion ?? ""
            }
        }
        .presentationDetents([.medium])
    }
}
