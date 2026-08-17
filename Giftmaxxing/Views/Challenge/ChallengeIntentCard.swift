import SwiftUI

// Intent capture for a swipe challenge.
//
// Sending a deck is frictionless today, which is why people do it — and why we
// learn almost nothing from it. A deck built from "birthday" alone is a deck
// about nobody, so the recipient's swipes teach us about the CATALOG rather
// than about them, and the sender gets a worse verdict.
//
// The fix is not a form. Every control here is optional and every one visibly
// sharpens the deck the moment you touch it — the strength meter at the bottom
// is the whole design argument, because it turns "answer our questions" into
// "tune your deck". Skipping still sends, exactly as before.
struct ChallengeIntentCard: View {
    @Binding var relationship: String?
    @Binding var budgetBand: BudgetBand?
    @Binding var interests: Set<String>
    @Binding var avoid: Set<String>

    enum BudgetBand: String, CaseIterable, Identifiable {
        case under25, under50, under100, over100
        var id: String { rawValue }
        var label: String {
            switch self {
            case .under25: return "Under $25"
            case .under50: return "$25–50"
            case .under100: return "$50–100"
            case .over100: return "$100+"
            }
        }
        /// Cap used to filter the deck.
        var maxPrice: Double {
            switch self {
            case .under25: return 25
            case .under50: return 50
            case .under100: return 100
            case .over100: return 100_000
            }
        }
    }

    static let relationships = [
        "Partner", "Parent", "Sibling", "Friend", "Colleague", "Kid",
    ]

    static let interestOptions = [
        "Cooking", "Coffee", "Fitness", "Beauty", "Tech", "Books",
        "Outdoors", "Music", "Art", "Gaming", "Travel", "Plants",
        "Fashion", "Home", "Pets", "Self-care",
    ]

    static let avoidOptions = [
        "Alcohol", "Sweets", "Candles", "Clothing", "Jewellery", "Screens",
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("MAKE THE DECK ABOUT THEM")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("Optional")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.inkTertiary)
            }

            group("How do you know them?") {
                ChipRow(
                    options: Self.relationships,
                    isSelected: { relationship == $0 },
                    toggle: { relationship = relationship == $0 ? nil : $0 }
                )
            }

            group("Roughly what are you spending?") {
                ChipRow(
                    options: BudgetBand.allCases.map(\.label),
                    isSelected: { budgetBand?.label == $0 },
                    toggle: { label in
                        let band = BudgetBand.allCases.first { $0.label == label }
                        budgetBand = budgetBand == band ? nil : band
                    }
                )
            }

            group("What are they into?") {
                ChipRow(
                    options: Self.interestOptions,
                    isSelected: { interests.contains($0) },
                    toggle: { interests.formSymmetricDifference([$0]) }
                )
            }

            group("Anything to steer clear of?") {
                ChipRow(
                    options: Self.avoidOptions,
                    isSelected: { avoid.contains($0) },
                    toggle: { avoid.formSymmetricDifference([$0]) },
                    tint: Color.danger
                )
            }

            strengthMeter
        }
    }

    // MARK: - Deck strength

    /// 0...1. Interests are weighted heaviest because they are the only signal
    /// that changes WHICH items get retrieved; the others mostly filter.
    var strength: Double {
        var score = 0.15 // an occasion is always set
        if relationship != nil { score += 0.2 }
        if budgetBand != nil { score += 0.15 }
        score += min(0.4, Double(interests.count) * 0.14)
        if !avoid.isEmpty { score += 0.1 }
        return min(1, score)
    }

    private var strengthLabel: String {
        switch strength {
        case ..<0.35: return "Generic deck"
        case ..<0.6: return "Getting warmer"
        case ..<0.85: return "Good deck"
        default: return "Sharp deck"
        }
    }

    private var strengthMeter: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(strengthLabel)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(strength < 0.35 ? Color.inkSecondary : Color.coral)
                Spacer()
                Text("\(Int(strength * 100))%")
                    .font(.system(size: 12, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Color.inkTertiary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.surfaceSunken)
                    Capsule()
                        .fill(Color.coral)
                        .frame(width: geo.size.width * strength)
                }
            }
            .frame(height: 6)
            Text("Each answer narrows what they'll swipe on — and sharpens what you learn back.")
                .font(.system(size: 11))
                .foregroundStyle(Color.inkTertiary)
        }
        .animation(.snappy, value: strength)
    }

    @ViewBuilder
    private func group<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.ink)
            content()
        }
    }
}

// Wrapping chip row — a horizontal ScrollView would hide options off the edge,
// and an option you cannot see is an option you will not answer.
private struct ChipRow: View {
    let options: [String]
    let isSelected: (String) -> Bool
    let toggle: (String) -> Void
    var tint: Color = Color.coral

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(options, id: \.self) { option in
                let on = isSelected(option)
                Button { toggle(option) } label: {
                    Text(option)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(on ? Color.onPrimary : Color.ink)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 7)
                        .background(on ? tint : Color.surface, in: Capsule())
                        .overlay {
                            Capsule().strokeBorder(on ? .clear : Color.line, lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
                .sensoryFeedback(.selection, trigger: on)
            }
        }
    }
}

// Minimal flow layout — chips wrap to as many lines as they need.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: proposal.width ?? x, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
