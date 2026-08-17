// The design system is UIKit-backed (UIColor trait resolution, UIViewRepresentable
// pickers, UIImage caching), so it only exists where UIKit does. The guard keeps
// `swift build` / `swift test` working natively on macOS for the other three
// targets — which is what makes the sub-second test loop possible.
#if canImport(UIKit)
import SwiftUI
import GiftmaxxingCore
import Combine

// Hidden design-variant switcher, unlocked by account.
//
// Auth login → check the signed-in email → if it is an allowlisted operator,
// expose the variant menu and whatever key it has set. Everyone else gets
// `.variantA` (the shipped design) and never sees that a switch exists.
//
// The gate is the account, not a build flag, so variants can be compared on a
// real TestFlight build against real data — which is the only place a design
// question actually gets answered.
//
// NOTE ON TRUST: this controls presentation only — which card layout draws,
// which accent paints. It grants no data access and unlocks no privileged API,
// so a client-side email check is the right amount of rigour. Anything that
// touched other people's data would need a server-issued claim instead.
public enum DesignVariant: String, CaseIterable, Identifiable {
    case variantA
    case variantB
    case variantC

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .variantA: return "A · Control"
        case .variantB: return "B · Inspiration-led"
        case .variantC: return "C · Template-led"
        }
    }

    public var blurb: String {
        switch self {
        case .variantA: return "Create opens straight to camera/gallery. Circles reads as groups. Coral."
        case .variantB: return "Create leads with post formats to copy. Circles reads as a calendar. Blue."
        case .variantC: return "Create leads with testimonial + song templates. Circles reads as relationships. Indigo."
        }
    }

    /// Accent override. A keeps the shipped coral precisely because it is the
    /// control — changing its accent would confound the comparison.
    public var accentHex: (light: String, dark: String)? {
        switch self {
        case .variantA: return nil
        case .variantB: return ("#1A73C7", "#5FA8FF")   // blue
        case .variantC: return ("#4B3FBF", "#9B8CFF")   // indigo
        }
    }

    /// What the Create tab leads with.
    public var createFocus: CreateFocus {
        switch self {
        case .variantA: return .cameraGallery
        case .variantB: return .postInspiration
        case .variantC: return .templates
        }
    }

    public enum CreateFocus {
        case cameraGallery
        case postInspiration
        case templates
    }

    /// Circles-tab iconography. Same information, three different metaphors —
    /// whether people read "circles" as a group, a calendar or a relationship
    /// is exactly the kind of thing you cannot settle by argument.
    public var circleIcons: CircleIconSet {
        switch self {
        case .variantA: return CircleIconSet(
            circle: "person.3.fill",
            addEvent: "calendar.badge.plus",
            messages: "paperplane",
            streak: "flame.fill",
            groupGift: "gift.fill"
        )
        // Calendar-forward: Circles is really "the dates I must not miss".
        case .variantB: return CircleIconSet(
            circle: "calendar.circle.fill",
            addEvent: "plus.circle",
            messages: "bubble.left.and.bubble.right",
            streak: "chart.line.uptrend.xyaxis",
            groupGift: "shippingbox.fill"
        )
        // Relationship-forward: it is about the people, not the schedule.
        case .variantC: return CircleIconSet(
            circle: "heart.circle.fill",
            addEvent: "calendar.badge.plus",
            messages: "message",
            streak: "sparkles",
            groupGift: "hands.and.sparkles.fill"
        )
        }
    }

    public struct CircleIconSet {
        public let circle: String
        public let addEvent: String
        public let messages: String
        public let streak: String
        public let groupGift: String
    }
}

@MainActor
public final class DebugSessionManager: ObservableObject {
    public static let shared = DebugSessionManager()

    /// Operators who see the menu. Lowercased comparison.
    private static let allowlist: Set<String> = [
        "adhsaksham27@gmail.com",
    ]

    private static let variantKey = "giftmaxxing_design_variant"

    /// True only for an allowlisted signed-in account.
    @Published public private(set) var isUnlocked = false

    @Published public var variant: DesignVariant {
        didSet {
            guard variant != oldValue else { return }
            UserDefaults.standard.set(variant.rawValue, forKey: Self.variantKey)
            // Tokens read this synchronously at draw time.
            DebugSessionManager.cachedVariant = variant
        }
    }

    private init() {
        let saved = UserDefaults.standard.string(forKey: Self.variantKey)
        let restored = saved.flatMap(DesignVariant.init(rawValue:)) ?? .variantA
        variant = restored
        DebugSessionManager.cachedVariant = restored
    }

    /// Called on every auth state change. A non-operator account resets the
    /// variant, so signing in as someone else never leaves an experimental
    /// layout on screen.
    public func handleIdentityChange(email: String?) {
        let normalized = (email ?? "").lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let unlocked = Self.allowlist.contains(normalized)
        // Persisted so `active` — which is read synchronously from draw code —
        // can answer without touching the main actor.
        UserDefaults.standard.set(unlocked, forKey: Self.unlockedKey)
        guard unlocked != isUnlocked else { return }
        isUnlocked = unlocked
        if !unlocked, variant != .variantA {
            variant = .variantA
        }
    }

    fileprivate static let unlockedKey = "giftmaxxing_debug_unlocked"

    // Read from view bodies and colour tokens without an actor hop.
    nonisolated(unsafe) private static var cachedVariant: DesignVariant = .variantA

    /// The variant that should DRAW right now. Locked to A unless unlocked, so
    /// a stale UserDefaults value can never leak an experiment to a real user.
    public nonisolated static var active: DesignVariant {
        guard UserDefaults.standard.bool(forKey: unlockedKey) else { return .variantA }
        return cachedVariant
    }
}


#endif
