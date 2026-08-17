import Foundation

/// Bundled offline fallback. Online navigation is owned by `/v2/feed-taxonomy`.
public struct FeedTheme: Identifiable, Hashable {
    public let id: String
    public let title: String
    public let query: String
    public let tags: [FeedTag]

    public init(
        id: String,
        title: String,
        query: String,
        tags: [FeedTag]
    ) {
        self.id = id
        self.title = title
        self.query = query
        self.tags = tags
    }


    public static let all: [FeedTheme] = [
        .init(id: "for-you", title: "For you", query: "", tags: []),
        .init(id: "school-and-next-chapter", title: "School & Next Chapter", query: "back-to-school woman college-student teacher educator graduation daughter student", tags: [
            .init(id: "back-to-school-her", title: "Back to School — Her", query: "back-to-school woman college-student"),
            .init(id: "back-to-school-teacher", title: "Back to School — Teacher", query: "back-to-school teacher educator"),
            .init(id: "graduation-daughter", title: "Graduation — Daughter", query: "graduation daughter student"),
        ]),
        .init(id: "romantic-partner", title: "For Your Person", query: "anniversary boyfriend man partner shared-memories keepsakes just-because", tags: [
            .init(id: "anniversary-him", title: "Anniversary — Him", query: "anniversary boyfriend man partner"),
            .init(id: "shared-memory", title: "Shared Memories", query: "shared-memories keepsakes partner"),
            .init(id: "just-because", title: "Just Because", query: "just-because partner"),
        ]),
        .init(id: "friend-birthday", title: "Best Friend Energy", query: "best-friend birthday care-package friend", tags: [
            .init(id: "best-friend-birthday", title: "Best Friend Birthday", query: "best-friend birthday"),
            .init(id: "care-package", title: "Care Package", query: "care-package friend"),
            .init(id: "under-25", title: "Under $25", query: "friend birthday", maxPrice: 25),
        ]),
        .init(id: "appreciation-at-work", title: "Thank-You Gifts", query: "nurse thank-you teacher teacher-appreciation", tags: [
            .init(id: "nurse", title: "Thank You — Nurse", query: "nurse thank-you"),
            .init(id: "teacher", title: "Teacher Appreciation", query: "teacher teacher-appreciation"),
        ]),
        .init(id: "home-and-hosting", title: "New Home & Hosting", query: "housewarming new-homeowner independent-makers home-design host-gift hosting", tags: [
            .init(id: "housewarming", title: "New Home — Useful", query: "housewarming new-homeowner"),
            .init(id: "small-brands", title: "Small Brands", query: "independent-makers home-design"),
            .init(id: "host", title: "For the Host", query: "host-gift hosting"),
        ]),
        .init(id: "hobbies-and-passions", title: "Deeply Into It", query: "artist creative coffee-lover home-barista beer-lover tasting", tags: [
            .init(id: "artist", title: "For the Artist", query: "artist creative"),
            .init(id: "coffee", title: "For the Coffee Person", query: "coffee-lover home-barista"),
            .init(id: "beer", title: "For the Beer Lover", query: "beer-lover tasting"),
        ]),
        .init(id: "outdoors-and-active", title: "Outside & Active", query: "hiker trail-gear runner running birdwatcher birding", tags: [
            .init(id: "hiker", title: "For the Hiker", query: "hiker trail-gear"),
            .init(id: "runner", title: "For the Runner", query: "runner running"),
            .init(id: "birdwatcher", title: "For the Birdwatcher", query: "birdwatcher birding"),
        ]),
        .init(id: "pet-people", title: "Pet People", query: "dog-owner dogs", tags: [
            .init(id: "dog-person", title: "For the Dog Person", query: "dog-owner dogs"),
        ]),
        .init(id: "budget-and-values", title: "Thoughtful by Budget", query: "budget-and-values sustainable small-brands sustainability eco-conscious", tags: [
            .init(id: "under-25", title: "Under $25", query: "budget-and-values", maxPrice: 25),
            .init(id: "under-50", title: "Under $50", query: "sustainable small-brands", maxPrice: 50),
            .init(id: "sustainable", title: "Sustainable", query: "sustainability eco-conscious"),
        ]),
    ]
}

public struct FeedTag: Identifiable, Hashable {
    public let id: String
    public let title: String
    public let query: String
    public var maxPrice: Double?

    public init(
        id: String,
        title: String,
        query: String,
        maxPrice: Double? = nil
    ) {
        self.id = id
        self.title = title
        self.query = query
        self.maxPrice = maxPrice
    }

}
