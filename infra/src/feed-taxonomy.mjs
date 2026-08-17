export const TAXONOMY_VERSION = "2026-08-v3";

const tag = (id, title, terms, price = {}) => ({ id, title, terms, ...price });

// API-owned navigation. These are gift intents backed by the reviewed carousel
// map; interests such as tech and beauty remain ranking signals, not tabs.
export const FEED_TAXONOMY = [
  { id: "for-you", title: "For you", terms: [], tags: [] },
  { id: "school-and-next-chapter", title: "School & Next Chapter", terms: ["school-and-next-chapter"], tags: [
    tag("back-to-school-her", "Back to School — Her", ["back-to-school", "woman", "college-student"]),
    tag("back-to-school-teacher", "Back to School — Teacher", ["back-to-school", "teacher", "educator"]),
    tag("graduation-daughter", "Graduation — Daughter", ["graduation", "daughter", "student"]),
  ] },
  { id: "romantic-partner", title: "For Your Person", terms: ["romantic-partner", "relationships-and-memory"], tags: [
    tag("anniversary-him", "Anniversary — Him", ["anniversary", "boyfriend", "man", "partner"]),
    tag("shared-memory", "Shared Memories", ["shared-memories", "keepsakes", "partner"]),
    tag("just-because", "Just Because", ["just-because", "partner"]),
  ] },
  { id: "friend-birthday", title: "Best Friend Energy", terms: ["friend-birthday", "gift-baskets"], tags: [
    tag("best-friend-birthday", "Best Friend Birthday", ["best-friend", "birthday"]),
    tag("care-package", "Care Package", ["care-package", "friend"]),
    tag("under-25", "Under $25", ["friend", "birthday"], { maxPrice: 25 }),
  ] },
  { id: "appreciation-at-work", title: "Thank-You Gifts", terms: ["appreciation-at-work"], tags: [
    tag("nurse", "Thank You — Nurse", ["nurse", "thank-you"]),
    tag("teacher", "Teacher Appreciation", ["teacher", "teacher-appreciation"]),
  ] },
  { id: "home-and-hosting", title: "New Home & Hosting", terms: ["home-and-hosting"], tags: [
    tag("housewarming", "New Home — Useful", ["housewarming", "new-homeowner"]),
    tag("small-brands", "Small Brands", ["independent-makers", "home-design"]),
    tag("host", "For the Host", ["host-gift", "hosting"]),
  ] },
  { id: "hobbies-and-passions", title: "Deeply Into It", terms: ["hobbies-and-passions"], tags: [
    tag("artist", "For the Artist", ["artist", "creative"]),
    tag("coffee", "For the Coffee Person", ["coffee-lover", "home-barista"]),
    tag("beer", "For the Beer Lover", ["beer-lover", "tasting"]),
  ] },
  { id: "outdoors-and-active", title: "Outside & Active", terms: ["outdoors-and-active"], tags: [
    tag("hiker", "For the Hiker", ["hiker", "trail-gear"]),
    tag("runner", "For the Runner", ["runner", "running"]),
    tag("birdwatcher", "For the Birdwatcher", ["birdwatcher", "birding"]),
  ] },
  { id: "pet-people", title: "Pet People", terms: ["pet-people"], tags: [
    tag("dog-person", "For the Dog Person", ["dog-owner", "dogs"]),
  ] },
  { id: "budget-and-values", title: "Thoughtful by Budget", terms: ["budget-and-values"], tags: [
    tag("under-25", "Under $25", ["budget-and-values"], { maxPrice: 25 }),
    tag("under-50", "Under $50", ["sustainable", "small-brands"], { maxPrice: 50 }),
    tag("sustainable", "Sustainable", ["sustainability", "eco-conscious"]),
  ] },
];

export function resolveFeedContext(themeId, tagId) {
  const theme = FEED_TAXONOMY.find((item) => item.id === themeId) ?? FEED_TAXONOMY[0];
  const selectedTag = tagId ? theme.tags.find((item) => item.id === tagId) : null;
  const childTerms = selectedTag
    ? selectedTag.terms ?? []
    : theme.tags.flatMap((item) => item.terms ?? []);
  return {
    theme,
    tag: selectedTag,
    // "All" is the union of every child filter, not a separate empty shelf.
    terms: [...new Set([...(theme.terms ?? []), ...childTerms])],
    matchTerms: [...new Set(childTerms.length ? childTerms : theme.terms ?? [])],
    minPrice: selectedTag?.minPrice,
    maxPrice: selectedTag?.maxPrice,
  };
}
