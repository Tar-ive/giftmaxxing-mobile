import Foundation

// How a giver behaves, which scales how hard intentionality pulls in ranking.
// The classification itself reads app state (the Thoughtfulness ledger), so
// `GiftMindset.current()` lives in the app — see GiftGraphRanker.swift.
public enum GiftMindset: String {
    case thoughtfulPlanner
    case spontaneousFunGiver
    case lastMinuteHero
    case balanced

    // How hard intentionality should pull for this user.
    public var intentionalityWeight: Double {
        switch self {
        case .thoughtfulPlanner: return 0.40
        case .balanced: return 0.25
        case .spontaneousFunGiver: return 0.15
        case .lastMinuteHero: return 0.10
        }
    }
}
