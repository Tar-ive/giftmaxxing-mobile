import Foundation

/// Bundled offline fallback. Online navigation is owned by `/v2/feed-taxonomy`.
struct FeedTheme: Identifiable, Hashable {
    let id: String
    let title: String
    let query: String
    let tags: [FeedTag]

    static let all: [FeedTheme] = [
        .init(id: "for-you", title: "For you", query: "", tags: []),
        .init(id: "school-and-next-chapter", title: "School & Next Chapter", query: "school-and-next-chapter", tags: [
            .init(id: "back-to-school-her", title: "Back to School — Her", query: "back-to-school woman college-student"),
            .init(id: "back-to-school-teacher", title: "Back to School — Teacher", query: "back-to-school teacher educator"),
            .init(id: "graduation-daughter", title: "Graduation — Daughter", query: "graduation daughter student"),
        ]),
        .init(id: "romantic-partner", title: "For Your Person", query: "romantic-partner relationships-and-memory", tags: [
            .init(id: "anniversary-him", title: "Anniversary — Him", query: "anniversary boyfriend man partner"),
            .init(id: "shared-memory", title: "Shared Memories", query: "shared-memories keepsakes partner"),
            .init(id: "just-because", title: "Just Because", query: "just-because partner"),
        ]),
        .init(id: "friend-birthday", title: "Best Friend Energy", query: "friend-birthday gift-baskets", tags: [
            .init(id: "best-friend-birthday", title: "Best Friend Birthday", query: "best-friend birthday"),
            .init(id: "care-package", title: "Care Package", query: "care-package friend"),
            .init(id: "under-25", title: "Under $25", query: "friend birthday", maxPrice: 25),
        ]),
        .init(id: "appreciation-at-work", title: "Thank-You Gifts", query: "appreciation-at-work", tags: [
            .init(id: "nurse", title: "Thank You — Nurse", query: "nurse thank-you"),
            .init(id: "teacher", title: "Teacher Appreciation", query: "teacher teacher-appreciation"),
        ]),
        .init(id: "home-and-hosting", title: "New Home & Hosting", query: "home-and-hosting", tags: [
            .init(id: "housewarming", title: "New Home — Useful", query: "housewarming new-homeowner"),
            .init(id: "small-brands", title: "Small Brands", query: "independent-makers home-design"),
            .init(id: "host", title: "For the Host", query: "host-gift hosting"),
        ]),
        .init(id: "hobbies-and-passions", title: "Deeply Into It", query: "hobbies-and-passions", tags: [
            .init(id: "artist", title: "For the Artist", query: "artist creative"),
            .init(id: "coffee", title: "For the Coffee Person", query: "coffee-lover home-barista"),
            .init(id: "beer", title: "For the Beer Lover", query: "beer-lover tasting"),
        ]),
        .init(id: "outdoors-and-active", title: "Outside & Active", query: "outdoors-and-active", tags: [
            .init(id: "hiker", title: "For the Hiker", query: "hiker trail-gear"),
            .init(id: "runner", title: "For the Runner", query: "runner running"),
            .init(id: "birdwatcher", title: "For the Birdwatcher", query: "birdwatcher birding"),
        ]),
        .init(id: "pet-people", title: "Pet People", query: "pet-people", tags: [
            .init(id: "dog-person", title: "For the Dog Person", query: "dog-owner dogs"),
        ]),
        .init(id: "budget-and-values", title: "Thoughtful by Budget", query: "budget-and-values", tags: [
            .init(id: "under-25", title: "Under $25", query: "budget-and-values", maxPrice: 25),
            .init(id: "under-50", title: "Under $50", query: "sustainable small-brands", maxPrice: 50),
            .init(id: "sustainable", title: "Sustainable", query: "sustainability eco-conscious"),
        ]),
    ]
}

struct FeedTag: Identifiable, Hashable {
    let id: String
    let title: String
    let query: String
    var maxPrice: Double?
}
