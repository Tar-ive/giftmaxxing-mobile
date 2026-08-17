import SwiftUI
import GiftmaxxingCore

// "Ready to buy" — the last mile of a gift.
//
// The presentation is half the gift and the part people improvise badly at
// 11pm. Because the cart is grouped by person, we know exactly what's going in
// one pile, so a vision model can look at those actual products and write a
// wrap plan for them specifically — materials, palette, steps — and render one
// picture of the result.
//
// This is a Maxi surface, so per DESIGN.md it gets the expressive budget: brand
// gradient, and `sparkles` pulsing while it thinks.
struct PackagingSheet: View {
    let section: CartSection

    @EnvironmentObject private var authManager: AuthManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var response: PackagingPlanResponse?
    @State private var isLoading = true
    @State private var failed = false
    @State private var browserTarget: BrowserTarget?

    // Only what's actually still being bought — no point wrapping something
    // that's already under the bed.
    private var items: [CartItem] {
        section.items.filter { !$0.bought }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: ThemeSpacing.lg) {
                    if items.isEmpty {
                        // Nothing to wrap is a state about the CART, not a
                        // failed plan — and the "Still to buy" list below would
                        // be an empty heading, which is what made this screen
                        // look broken rather than empty.
                        nothingToWrap
                    } else if isLoading {
                        loadingState
                    } else if let plan = response?.plan {
                        hero
                        planBody(plan)
                        buyList
                    } else {
                        failureState
                        buyList
                    }
                }
                .padding(.horizontal, ThemeSpacing.md)
                .padding(.bottom, ThemeSpacing.xl)
            }
            .background(Color.cream)
            // "Wrapping mom's" read as a truncated sentence. Say who it's for.
            .navigationTitle(section.isUnassigned ? "Wrapping" : "Wrapping for \(section.recipientName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Color.coral)
                }
            }
            .sheet(item: $browserTarget) { target in
                SafariView(url: target.url).ignoresSafeArea()
            }
        }
        .task { await load() }
    }

    // MARK: - States

    private var loadingState: some View {
        VStack(spacing: ThemeSpacing.sm) {
            Image(systemName: "sparkles")
                .font(.largeTitle)
                .foregroundStyle(Color.coral)
                .symbolEffect(.pulse, isActive: !reduceMotion)
            Text("Working out how to wrap these…")
                .font(.subheadline)
                .foregroundStyle(Color.inkSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 72)
    }

    // Distinguishes "you've bought everything" from "this section is empty" —
    // the old copy said "Nothing left to wrap" for both, which reads as a bug
    // when the section never had anything in it.
    private var nothingToWrap: some View {
        VStack(spacing: ThemeSpacing.sm) {
            Image(systemName: section.items.isEmpty ? "bag" : "checkmark.circle")
                .font(.largeTitle)
                .foregroundStyle(section.items.isEmpty ? Color.inkTertiary : Color.success)
            Text(section.items.isEmpty
                 ? "Nothing in \(section.isUnassigned ? "this section" : "\(section.recipientName)'s section") yet."
                 : "All bought — nothing left to wrap.")
                .font(.body)
                .foregroundStyle(Color.inkSecondary)
                .multilineTextAlignment(.center)
            if section.items.isEmpty {
                Text("Add a few gifts and I'll suggest how to wrap them together.")
                    .font(.footnote)
                    .foregroundStyle(Color.inkTertiary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 64)
    }

    private var failureState: some View {
        VStack(spacing: ThemeSpacing.sm) {
            Text(failed ? "Couldn't sketch a wrap this time." : "Nothing left to wrap.")
                .font(.body)
                .foregroundStyle(Color.inkSecondary)
            if failed {
                Button("Try again") {
                    Task { await load(force: true) }
                }
                .buttonStyle(SecondaryButtonStyle())
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }

    @ViewBuilder
    private var hero: some View {
        ZStack {
            Color.brandGradient
            if let imageUrl = response?.imageUrl {
                CachedAsyncImage(url: imageUrl, width: 900)
            } else {
                // No render — the gradient plus the plan's own title carries it.
                Image(systemName: "gift.fill")
                    .font(.largeTitle)
                    .foregroundStyle(Color.onPrimary.opacity(0.85))
            }
        }
        .frame(height: 220)
        .frame(maxWidth: .infinity)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: ThemeRadius.xl, style: .continuous))
    }

    private func planBody(_ plan: PackagingPlan) -> some View {
        VStack(alignment: .leading, spacing: ThemeSpacing.md) {
            VStack(alignment: .leading, spacing: ThemeSpacing.xs) {
                Text(plan.title ?? "A way to wrap it")
                    .font(.title2.weight(.bold))
                    .fontDesign(.rounded)
                    .foregroundStyle(Color.ink)

                if let palette = plan.palette, !palette.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(Array(palette.prefix(5).enumerated()), id: \.offset) { _, hex in
                            Circle()
                                .fill(Color(hex: hex))
                                .frame(width: 20, height: 20)
                                .overlay(Circle().stroke(Color.line, lineWidth: 0.5))
                        }
                    }
                    .accessibilityHidden(true)
                }

                if let vibe = plan.vibe, !vibe.isEmpty {
                    Text(vibe)
                        .font(.subheadline)
                        .foregroundStyle(Color.inkSecondary)
                }
            }

            if let materials = plan.materials, !materials.isEmpty {
                VStack(alignment: .leading, spacing: ThemeSpacing.xs) {
                    sectionTitle("You'll need")
                    MaterialChips(items: materials)
                }
            }

            if let steps = plan.steps, !steps.isEmpty {
                VStack(alignment: .leading, spacing: ThemeSpacing.xs) {
                    sectionTitle("How to")
                    ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .top, spacing: ThemeSpacing.xs) {
                            Text("\(index + 1)")
                                .font(.footnote.weight(.bold))
                                .monospacedDigit()
                                .foregroundStyle(Color.coral)
                                .frame(width: 20, alignment: .trailing)
                            Text(step)
                                .font(.subheadline)
                                .foregroundStyle(Color.ink)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }

            if let note = plan.noteIdea, !note.isEmpty {
                VStack(alignment: .leading, spacing: ThemeSpacing.xs) {
                    sectionTitle("A note to go with it")
                    Text(note)
                        .font(.body)
                        .italic()
                        .foregroundStyle(Color.ink)
                        .padding(ThemeSpacing.sm)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.surface)
                        .clipShape(RoundedRectangle(cornerRadius: ThemeRadius.md, style: .continuous))

                    if let boardId = section.boardId {
                        Button("Use this as the gift letter") {
                            SwipeListStore.shared.setLetter(note, for: boardId)
                        }
                        .buttonStyle(SecondaryButtonStyle())
                    }
                }
            }
        }
    }

    // The actual buying still happens at the retailer — list it out so
    // "ready to buy" ends somewhere real.
    private var buyList: some View {
        VStack(alignment: .leading, spacing: ThemeSpacing.xs) {
            sectionTitle("Still to buy")
            ForEach(items) { item in
                Button {
                    guard let url = Affiliate.productUrl(for: item.post) else { return }
                    OutboundRouter.open(url, postId: item.post.id, source: "packaging") {
                        browserTarget = BrowserTarget(url: $0)
                    }
                } label: {
                    HStack(spacing: ThemeSpacing.sm) {
                        Text(item.post.product.name)
                            .font(.subheadline)
                            .foregroundStyle(Color.ink)
                            .lineLimit(1)
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Color.coral)
                    }
                    .padding(.vertical, ThemeSpacing.sm)
                    .padding(.horizontal, ThemeSpacing.sm)
                    .background(Color.surface)
                    .clipShape(RoundedRectangle(cornerRadius: ThemeRadius.md, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.caption.weight(.medium))
            .tracking(0.5)
            .foregroundStyle(Color.inkTertiary)
    }

    private func load(force: Bool = false) async {
        guard !items.isEmpty else {
            isLoading = false
            return
        }
        if force { failed = false; isLoading = true }

        let payload = items.map { item in
            APIClient.PackagingRequestItem(
                postId: item.post.id,
                title: item.post.product.name,
                image: item.post.product.image,
                category: item.post.category ?? item.post.product.brand,
                price: item.post.product.price > 0 ? item.post.product.price : nil
            )
        }

        do {
            response = try await APIClient.shared.fetchPackaging(
                userId: authManager.userId,
                items: payload,
                occasion: section.occasion,
                recipientName: section.isUnassigned ? nil : section.recipientName
            )
        } catch {
            failed = true
        }
        isLoading = false
    }
}

// Materials read as a set of small things, not a paragraph — wrapping them as
// chips is the honest shape for a shopping list.
private struct MaterialChips: View {
    let items: [String]

    var body: some View {
        // A simple wrapping layout; `Layout` would be overkill for <8 chips.
        VStack(alignment: .leading, spacing: 6) {
            ForEach(rows, id: \.self) { row in
                HStack(spacing: 6) {
                    ForEach(row, id: \.self) { item in
                        Text(item)
                            .font(.subheadline)
                            .foregroundStyle(Color.ink)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Color.surface)
                            .overlay(Capsule().stroke(Color.line, lineWidth: 0.5))
                            .clipShape(Capsule())
                    }
                }
            }
        }
    }

    // Two per row keeps long material names ("sage satin ribbon") readable.
    private var rows: [[String]] {
        stride(from: 0, to: items.count, by: 2).map {
            Array(items[$0..<min($0 + 2, items.count)])
        }
    }
}
