export const TAXONOMY_VERSION = "2026-08-v1";

export const FEED_TAXONOMY = [
  { id: "for-you", title: "For you", query: [], tags: [] },
  { id: "cozy", title: "Cozy", query: ["cozy"], tags: [
    { id: "candles", title: "Candles", query: ["candle"] },
    { id: "blankets", title: "Blankets", query: ["blanket", "throw"] },
    { id: "mugs", title: "Mugs", query: ["mug"] },
    { id: "under-30", title: "Under $30", query: ["cozy"], maxPrice: 30 },
  ] },
  { id: "beauty", title: "Beauty", query: ["makeup", "glam", "clean-beauty"], tags: [
    { id: "skincare", title: "Skincare", query: ["serum", "moisturizer", "skincare"] },
    { id: "lips", title: "Lips", query: ["lipstick", "gloss"] },
    { id: "fragrance", title: "Fragrance", query: ["perfume", "fragrance"] },
    { id: "brushes", title: "Brushes", query: ["brush", "palette"] },
    { id: "under-25", title: "Under $25", query: ["makeup"], maxPrice: 25 },
  ] },
  { id: "tech", title: "Tech", query: ["tech", "gadget", "edc"], tags: [
    { id: "audio", title: "Audio", query: ["headphones", "earbuds", "speaker"] },
    { id: "charging", title: "Charging", query: ["charger", "cable", "power"] },
    { id: "desk", title: "Desk", query: ["keyboard", "stand", "desk"] },
    { id: "carry", title: "Carry", query: ["wallet", "keychain", "organizer"] },
  ] },
  { id: "foodie", title: "Foodie", query: ["foodie", "coffee"], tags: [
    { id: "coffee", title: "Coffee", query: ["coffee", "espresso"] },
    { id: "tea", title: "Tea", query: ["tea", "matcha"] },
    { id: "kitchen", title: "Kitchen", query: ["kitchen", "cookware"] },
    { id: "sweets", title: "Sweets", query: ["chocolate", "cake", "dessert"] },
  ] },
  { id: "minimalist", title: "Minimalist", query: ["minimalist", "classic"], tags: [
    { id: "jewelry", title: "Jewelry", query: ["jewelry", "necklace", "ring"] },
    { id: "leather", title: "Leather", query: ["leather", "wallet"] },
    { id: "stationery", title: "Stationery", query: ["notebook", "pen", "stationery"] },
  ] },
  { id: "mens", title: "For him", query: ["mens", "grooming"], tags: [
    { id: "grooming", title: "Grooming", query: ["grooming", "beard", "shave"] },
    { id: "edc", title: "Everyday carry", query: ["edc", "knife", "multitool"] },
    { id: "apparel", title: "Apparel", query: ["shirt", "hoodie"] },
  ] },
  { id: "fitness", title: "Fitness", query: ["fitness", "sporty"], tags: [
    { id: "gym", title: "Gym", query: ["gym", "training"] },
    { id: "bottles", title: "Bottles", query: ["bottle", "flask", "hydration"] },
    { id: "shoes", title: "Shoes", query: ["shoes", "sneaker", "running"] },
  ] },
  { id: "outdoorsy", title: "Outdoors", query: ["outdoorsy", "rugged", "waterproof"], tags: [
    { id: "camp", title: "Camping", query: ["camping", "tent"] },
    { id: "trail", title: "Trail", query: ["hiking", "backpack"] },
  ] },
  { id: "sustainable", title: "Sustainable", query: ["sustainable", "natural", "handmade"], tags: [
    { id: "handmade", title: "Handmade", query: ["handmade"] },
    { id: "refill", title: "Refillable", query: ["refill", "reusable"] },
  ] },
  { id: "luxury", title: "Luxury", query: ["luxury", "premium"], tags: [
    { id: "jewelry", title: "Jewelry", query: ["jewelry"] },
    { id: "fragrance", title: "Fragrance", query: ["perfume", "fragrance"] },
    { id: "over-100", title: "Splurge", query: ["luxury"], minPrice: 100 },
  ] },
];

export function resolveFeedContext(themeId, tagId) {
  const theme = FEED_TAXONOMY.find((item) => item.id === themeId) ?? FEED_TAXONOMY[0];
  const tag = tagId ? theme.tags.find((item) => item.id === tagId) : null;
  return {
    theme,
    tag,
    terms: [...new Set([...(theme.query ?? []), ...(tag?.query ?? [])])],
    minPrice: tag?.minPrice,
    maxPrice: tag?.maxPrice,
  };
}
