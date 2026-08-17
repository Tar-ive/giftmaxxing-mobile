import Foundation
import GiftmaxxingCore

// Who is this product actually FOR? The catalog's `attrs.audience` tag is
// missing on most pins (Pinterest-sourced, heavily feminine), so recipient
// personalization had nothing to bite on — a "for him / dad" consult could
// surface a pink bling phone case. This infers men/women from the product
// text with intentionally one-sided keywords; anything ambiguous stays nil
// (neutral) so unisex gifts (books, mugs, plants) are never excluded.
// Mirrors inferAudience() in infra/src/handler.mjs — keep the lists in sync.
public enum AudienceClassifier {

    private static let womenPattern = #"""
    \b(her|hers|woman|women|womens|girl|girls|girly|girlfriend|wife|mom|mama|mother|sister|aunt|auntie|grandma|nana|bride|bridal|bridesmaid|princess|queen|goddess|babe|lady|ladies|feminine)\b|makeup|skincare|lipstick|lip gloss|lip oil|lip tint|lip butter|mascara|eyeshadow|eyelash|nail polish|press.?on nail|manicure|scrunchie|claw clip|hair clip|barrette|handbag|purse|crossbody|shoulder bag|mini bag|baggu|heels\b|floral|rose gold|blush|dainty|bling|glitter|sparkl|kawaii|perfume|parfum|eau de|fragrance|body mist|earring|necklace|pendant|charm bracelet|bralette|leggings?\b|bodysuit|\bdress\b|skirt\b
    """#

    private static let menPattern = #"""
    \b(him|his|man|men|mens|guy|guys|dude|boyfriend|husband|dad|father|papa|grandpa|uncle|brother|groom|groomsman|groomsmen|gentleman|gentlemen|masculine)\b|beard|mustache|shaving|aftershave|cologne|whiskey|whisky|bourbon|scotch|cigar|\bedc\b|tactical|multi.?tool|pocket knife|cufflink|necktie|tie clip|tie bar|\bbbq\b|grilling|garage|woodworking|decanter|flask|pint glass|\bbeer\b|jerky|hot sauce|poker|golf\b|fishing|camping|hatchet|dopp kit|leather wallet|leather belt|suspenders|humidor
    """#

    private static let womenRegex = try? NSRegularExpression(
        pattern: womenPattern.trimmingCharacters(in: .whitespacesAndNewlines),
        options: [.caseInsensitive]
    )
    private static let menRegex = try? NSRegularExpression(
        pattern: menPattern.trimmingCharacters(in: .whitespacesAndNewlines),
        options: [.caseInsensitive]
    )

    // "men" / "women" when the text clearly leans one way, else nil.
    public static func infer(from text: String) -> String? {
        guard !text.isEmpty else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        let women = womenRegex?.numberOfMatches(in: text, range: range) ?? 0
        let men = menRegex?.numberOfMatches(in: text, range: range) ?? 0
        if women > men { return "women" }
        if men > women { return "men" }
        return nil
    }

    // Post text worth classifying: caption + product name.
    public static func infer(for post: Post) -> String? {
        infer(from: "\(post.caption) \(post.product.name)")
    }
}
