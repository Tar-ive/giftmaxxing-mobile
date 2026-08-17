import Foundation

// The app's icon vocabulary, in one place. Emoji were doing the work of icons
// (event types, gallery art, the brand mark) — they render inconsistently
// across OS versions, ignore Dynamic Type and tint, look wrong in dark mode,
// and DESIGN.md bans them as icons/logos/category art.
//
// These are real vector assets: SF Symbols ship with the OS, so they scale with
// text, inherit the coral tint, adapt per appearance, and add nothing to the
// bundle — strictly better than exported PNG/SVG art for this job. Bundle art
// only if a mark genuinely can't be expressed as a symbol or a Shape.
public enum AppIcons {
    /// Occasion → symbol. Keep in sync with GiftEvent.type values.
    public static func event(_ type: String?) -> String {
        switch (type ?? "").lowercased() {
        case "birthday": return "birthday.cake.fill"
        case "anniversary": return "heart.circle.fill"
        case "holiday", "christmas": return "snowflake"
        case "graduation": return "graduationcap.fill"
        case "wedding": return "bell.fill"
        case "housewarming": return "house.fill"
        case "baby_shower", "baby-shower": return "figure.and.child.holdinghands"
        case "valentines": return "heart.fill"
        case "mothers-day", "fathers-day": return "figure.2.and.child.holdinghands"
        default: return "gift.fill"
        }
    }

    /// Curated-gallery art.
    public static func collection(_ id: String) -> String {
        switch id {
        case let x where x.contains("golf"): return "figure.golf"
        case let x where x.contains("coffee"): return "cup.and.saucer.fill"
        case let x where x.contains("tech"): return "headphones"
        case let x where x.contains("beauty"): return "sparkles"
        case let x where x.contains("style"), let x where x.contains("fashion"): return "tshirt.fill"
        case let x where x.contains("cozy"), let x where x.contains("home"): return "lamp.table.fill"
        case let x where x.contains("birthday"): return "birthday.cake.fill"
        case let x where x.contains("eco"), let x where x.contains("green"): return "leaf.fill"
        case let x where x.contains("fitness"), let x where x.contains("active"): return "figure.run"
        case let x where x.contains("anniversary"), let x where x.contains("romance"): return "heart.fill"
        case let x where x.contains("under"), let x where x.contains("budget"): return "tag.fill"
        default: return "square.grid.2x2.fill"
        }
    }

    public static let brand = "gift.fill"
    public static let pool = "banknote.fill"
    public static let circle = "person.2.fill"
    public static let celebrate = "party.popper.fill"
}
