export const carouselThemeIds = [
  "school-and-next-chapter", "romantic-partner", "relationships-and-memory",
  "friend-birthday", "appreciation-at-work", "home-and-hosting",
  "hobbies-and-passions", "outdoors-and-active", "pet-people",
  "budget-and-values", "gifts-for-him", "gifts-for-her", "kids-and-tweens",
  "gift-baskets", "better-gifting",
] as const;

export type CarouselThemeId = typeof carouselThemeIds[number];
export type CarouselBudget = "any" | "budget" | "mixed" | "splurge" | "under-25" | "under-50";
export type CarouselIntent = "shop" | "make" | "learn" | "inspire";
export type ThemeConfidence = "high" | "medium" | "low";

export type CarouselOccasion =
  | "any" | "anniversary" | "back-to-school" | "birthday" | "care-package"
  | "college-sendoff" | "friendiversary" | "graduation" | "holiday"
  | "host-gift" | "housewarming" | "just-because" | "memorial" | "new-pet"
  | "nurses-week" | "race-day" | "teacher-appreciation" | "thank-you"
  | "valentines" | "wedding";

export interface CarouselThemeAssignment {
  id: string;
  filterLabel: string;
  themeId: CarouselThemeId;
  recipients: readonly string[];
  occasions: readonly CarouselOccasion[];
  interests: readonly string[];
  budget: CarouselBudget;
  intent: CarouselIntent;
  confidence: ThemeConfidence;
  navigationExcluded?: boolean;
  evidence: readonly string[];
}

// CI/runtime boundary: validate JSON with a schema library before casting.
export interface CarouselThemeMap {
  schemaVersion: "1.0.0";
  catalogVersion: string;
  themes: readonly { id: CarouselThemeId; title: string }[];
  carousels: readonly CarouselThemeAssignment[];
}
