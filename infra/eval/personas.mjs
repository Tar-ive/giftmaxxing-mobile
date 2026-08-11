export const PERSONAS = [
  ["cozy-homebody", "Cozy homebody", ["cozy", "candles", "blankets", "mugs"], ["rugged", "fitness"], 60, ["ugc_post", "story", "product"]],
  ["beauty-fragrance", "Beauty and fragrance enthusiast", ["beauty", "makeup", "skincare", "fragrance"], ["outdoorsy", "tools"], 120, ["product", "ugc_post"]],
  ["minimalist-design", "Minimalist design lover", ["minimalist", "classic", "design", "stationery"], ["glam", "novelty"], 150, ["product", "story"]],
  ["tech-edc", "Tech and everyday-carry fan", ["tech", "gadget", "edc", "audio"], ["makeup", "romantic"], 250, ["product", "service"]],
  ["foodie-barista", "Foodie and barista", ["foodie", "coffee", "kitchen", "tea"], ["fitness", "gaming"], 100, ["product", "story"]],
  ["outdoors-sustainable", "Outdoors and sustainability shopper", ["outdoorsy", "sustainable", "rugged", "handmade"], ["glam", "fast-fashion"], 180, ["product", "service", "ugc_post"]],
  ["fitness-wellness", "Fitness and wellness shopper", ["fitness", "sporty", "wellness", "recovery"], ["stationery", "luxury"], 160, ["product", "service"]],
  ["luxury-fashion", "Luxury and fashion shopper", ["luxury", "premium", "fashion", "jewelry"], ["budget", "rugged"], 600, ["product", "ugc_post"]],
  ["sentimental-story", "Sentimental story-led giver", ["sentimental", "personalized", "handmade", "story"], ["generic", "gadget"], 180, ["story", "ugc_post", "product"]],
  ["experience-first", "Experience and service-first recipient", ["experience", "service", "travel", "foodie"], ["clutter", "decor"], 300, ["service", "story"]],
].map(([id, name, positiveLabels, negativeLabels, budget, kindPreferences]) => ({
  id, name, profileId: `taste:eval:${id}`, positiveLabels, negativeLabels, budget, kindPreferences,
  seedLikes: [], seedDislikes: [], expectedChallengeAnswers: { love: positiveLabels.slice(0, 2), reject: negativeLabels.slice(0, 2) },
}));
