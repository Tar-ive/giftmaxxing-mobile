import Foundation

// Proposed only: keep dimensions independent so one carousel can participate
// in several useful filters without inventing a single catch-all category.
enum CarouselThemeID: String, Codable, CaseIterable, Sendable {
    case schoolAndNextChapter = "school-and-next-chapter"
    case romanticPartner = "romantic-partner"
    case relationshipsAndMemory = "relationships-and-memory"
    case friendBirthday = "friend-birthday"
    case appreciationAtWork = "appreciation-at-work"
    case homeAndHosting = "home-and-hosting"
    case hobbiesAndPassions = "hobbies-and-passions"
    case outdoorsAndActive = "outdoors-and-active"
    case petPeople = "pet-people"
    case budgetAndValues = "budget-and-values"
    case giftsForHim = "gifts-for-him"
    case giftsForHer = "gifts-for-her"
    case kidsAndTweens = "kids-and-tweens"
    case giftBaskets = "gift-baskets"
    case betterGifting = "better-gifting"
}

enum CarouselOccasion: String, Codable, Sendable {
    case any, anniversary, backToSchool = "back-to-school", birthday
    case carePackage = "care-package", collegeSendoff = "college-sendoff"
    case friendiversary, graduation, holiday, housewarming, justBecause = "just-because"
    case memorial, newPet = "new-pet", nursesWeek = "nurses-week"
    case raceDay = "race-day", teacherAppreciation = "teacher-appreciation"
    case thankYou = "thank-you", valentines, wedding, hostGift = "host-gift"
}

enum CarouselBudget: String, Codable, Sendable {
    case any, budget, mixed, splurge
    case under25 = "under-25", under50 = "under-50"
}

enum CarouselIntent: String, Codable, Sendable {
    case shop, make, learn, inspire
}

enum ThemeConfidence: String, Codable, Sendable {
    case high, medium, low
}

struct CarouselThemeAssignment: Codable, Identifiable, Sendable {
    let id: String
    let filterLabel: String
    let themeId: CarouselThemeID
    let recipients: [String]
    let occasions: [CarouselOccasion]
    let interests: [String]
    let budget: CarouselBudget
    let intent: CarouselIntent
    let confidence: ThemeConfidence
    let navigationExcluded: Bool?
    let evidence: [String]
}
