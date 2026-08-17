import Foundation
import GiftmaxxingCore
import GiftmaxxingNetworking

// Bridges a networking DTO into the Core value type. This lives in the app
// because GiftmaxxingCore must not know the API layer exists.
extension IdeaPack {

    static func from(_ bundle: APIClient.GiftBundle) -> IdeaPack {
        let sections = bundle.slots.map { slot in
            IdeaSection(id: slot.id, label: slot.label, emoji: slot.emoji, items: slot.items)
        }
        return IdeaPack(
            id: "bundle:\(bundle.id)",
            kind: .bundle,
            title: bundle.slots.map(\.label).joined(separator: " + "),
            subtitle: RecipientLabel.display(bundle.recipient),
            why: bundle.why,
            symbol: "gift.fill",
            grad: GradientStyle.allCases[abs(bundle.id.hashValue) % GradientStyle.allCases.count],
            coverImage: sections.first?.items.first?.product.image,
            sections: sections
        )
    }
}
