// ── Feed content-quality classifier (Layer A, deterministic, zero-cost) ───────
// Decides whether a pin is a single BUYABLE product (belongs in the scroll feed)
// or editorial/listicle content (a "gift guide", "33 gifts for her", "DIY gifts
// for him", a recipe, spam…) that should be routed elsewhere — NOT deleted.
//
// Pure function of fields every surface already has (title, domain, link, price),
// so it can run at serve time over DynamoDB items AND S3 Vectors metadata with no
// backfill. Refined later by the LLM/embedding pass (see docs/data-quality-plan.md).

// Head-domain reputation (covers ~60% of volume; the long tail leans on captions).
const RETAILER = new Set([
  "etsy.com", "etsy.me", "sephora.com", "seph.me", "thegrommet.com", "anthropologie.com",
  "papersource.com", "ebay.com", "lowes.com", "urbanoutfitters.com", "uncommongoods.com",
  "altardstate.com", "amazon.com", "amzn.to", "poshmark.com", "pukkagifts.uk", "kisaf.com",
  "nordstrom.com", "target.com", "walmart.com", "madewell.com", "ulta.com", "westelm.com",
  "crateandbarrel.com", "potterybarn.com", "bathandbodyworks.com", "society6.com",
  "redbubble.com", "minted.com", "notonthehighstreet.com", "cb2.com", "wayfair.com",
]);
// Blogs / SEO-content / ad-farms / non-commerce — never feed-eligible.
const CONTENT = new Set([
  "sites.google.com", "thecanadianguy.com", "loveandlavender.com", "blossomhomelife.com",
  "minimizemymess.com", "within-yourhome.com", "everydaysavvy.com", "newtrendsetter.com",
  "goodmomliving.com", "sunshinencoffeemornings.com", "mindfulnessinspo.com",
  "thecreativebite.com", "luxeandleanblog.com", "moritzfinedesigns.com", "greenweddingshoes.com",
  "m.youtube.com", "youtube.com", "flickr.com", "linktw.in", "presentatlas.com",
  "thelifestyleloft.blogspot.com",
]);
const RECIPE_DOMAIN = /(rasamalaysia|allrecipes|foodnetwork|seriouseats|delish|tasty|recipe)/i;
const CONTENT_SUFFIX = /\.(blogspot|wordpress|wixsite|substack)\.com$|\.blog$/i;

const norm = (s) => String(s || "").toLowerCase().replace(/^www\./, "").trim();
function domainClass(domain) {
  const d = norm(domain);
  if (!d) return "unknown";
  if (RECIPE_DOMAIN.test(d)) return "recipe";
  if (CONTENT.has(d) || CONTENT_SUFFIX.test(d)) return "content";
  if (RETAILER.has(d) || [...RETAILER].some((r) => d.endsWith("." + r))) return "retailer";
  return "unknown";
}

// ── Caption signals ──────────────────────────────────────────────────────────
const STARTS_NUMBER = /^\s*\d{1,3}\b/; //                      "33 gifts for her…"
const N_GIFTS = /\b\d{1,3}\s*\+?\s*[\w\s]{0,20}?\bgifts?\b/i; // "30 birthday gifts"
const GIFT_GUIDE = /\bgift\s+(guide|ideas?|lists?|roundups?)\b/i;
const GIFT_IDEA = /\bgift\s+ideas?\b/i; //                     "prettiest gift idea for…"
const GIFTS_FOR = /\bgifts\s+(for|under|that|your|to|she|he|who)\b/i; // "gifts for him"
const DIY_GIFTS = /\bdiy\s+gifts?\b/i; //                      "DIY gifts for him"
const ADJ_GIFTS = /\b(best|top|unique|prettiest|coolest|cutest|thoughtful|perfect|ultimate|cool|cheap|inexpensive|budget|last[- ]minute|amazing)\b[\w\s]{0,15}\bgifts\b/i;
const EDITORIAL = /\b(ideas|inspiration|inspo|roundup|how to|tutorial|diy)\b/i;
const RECIPE_WORD = /\b(recipe|recipes|soup|salad|casserole|smoothie|cocktail|appetizers?|brunch)\b/i;
const SEASONAL = /\b(father'?s|mother'?s|valentine'?s|christmas|halloween|thanksgiving)\s+day\b.*\b(is|coming|almost|here|sale|\d{1,2}(st|nd|rd|th)?)\b/i;

const RECIPIENTS = [
  ["boyfriend", /\bboyfriend\b/i], ["girlfriend", /\bgirlfriend\b/i],
  ["husband", /\bhusband\b/i], ["wife", /\bwife\b/i],
  ["mom", /\b(mom|mother|mum)\b/i], ["dad", /\b(dad|father)\b/i],
  ["sister", /\bsister\b/i], ["brother", /\bbrother\b/i],
  ["grandma", /\b(grandma|grandmother|nana)\b/i], ["grandpa", /\b(grandpa|grandfather)\b/i],
  ["kids", /\b(kids?|children|toddler|baby)\b/i], ["teen", /\b(teens?|teenagers?)\b/i],
  ["coworker", /\b(coworker|colleague|boss|employee)\b/i], ["friend", /\b(friends?|bff|bestie)\b/i],
  ["partner", /\bpartner\b/i],
  ["her", /\b(for )?(her|women|woman|she)\b/i], ["him", /\b(for )?(him|men|man|he|guys?)\b/i],
];
function extractRecipient(t) {
  for (const [name, re] of RECIPIENTS) if (re.test(t)) return name;
  return null;
}

/**
 * Classify one pin.
 * @returns {{contentType, feedEligible, route, recipient, qualityScore, reasons}}
 *   contentType: single_product | gift_guide | editorial | recipe | seasonal | spam
 *   route:       feed | recipient | group_gifts | drop
 */
export function classifyPin({ title = "", domain = "", link = "", price = 0, giftType = "" } = {}) {
  const t = String(title);
  const lt = t.toLowerCase();
  const dc = domainClass(domain);
  const p = typeof price === "number" ? price : Number(price) || 0;
  const reasons = [];
  const recipient = extractRecipient(lt);

  const result = (contentType, route, qualityScore) => ({
    contentType,
    feedEligible: contentType === "single_product",
    route,
    recipient: route === "recipient" || route === "group_gifts" ? recipient : null,
    qualityScore: Math.max(0, Math.min(1, qualityScore)),
    reasons,
  });

  // 0) Curated SERVICES (a year of Netflix/Prime/Costco…) are hand-picked gift
  // items, not scraped pins — every text/domain heuristic below misfires on
  // them (e.g. youtube.com is a blocked content domain, "Membership — 1 Year"
  // has no PDP path). Trust the ingest-time tag and keep them in the feed.
  if (giftType === "service") {
    reasons.push("curated_service");
    return result("single_product", "feed", 0.85);
  }

  // 1) Recipes — off-domain content, never giftable here.
  if (dc === "recipe" || (RECIPE_WORD.test(lt) && p <= 0)) {
    reasons.push("recipe");
    return result("recipe", "drop", 0.05);
  }

  // 2) Listicles / gift guides — checked BEFORE the blog-domain drop so guides
  // that live on blogs are KEPT (tagged for the group-gift / recipient surfaces),
  // not discarded. We only remove them from the scroll feed.
  const numbered = STARTS_NUMBER.test(t) || N_GIFTS.test(t);
  const guide = GIFT_GUIDE.test(t) || GIFT_IDEA.test(t) || GIFTS_FOR.test(t) || DIY_GIFTS.test(t) || ADJ_GIFTS.test(t);
  if (numbered || guide) {
    if (numbered) reasons.push("numbered_listicle");
    if (guide) reasons.push("gift_guide_phrasing");
    // Numbered multi-item roundups → group-gift / "how to gift" surface.
    // Singular recipient-targeted ideas → that recipient's gift recs.
    const route = numbered && !DIY_GIFTS.test(t) ? "group_gifts" : "recipient";
    return result("gift_guide", route, 0.2);
  }

  // 3) Known content/blog/spam domains (non-gift) — drop.
  if (dc === "content") {
    reasons.push("content_domain");
    return result("spam", "drop", 0.08);
  }
  // 4) Seasonal promos / banners with no product.
  if (SEASONAL.test(lt) && p <= 0) {
    reasons.push("seasonal_promo");
    return result("seasonal", "drop", 0.1);
  }

  // 5) Generic editorial ("…Ideas", "Inspiration", "DIY", "How to") with no price.
  if (EDITORIAL.test(lt) && p <= 0 && dc !== "retailer") {
    reasons.push("editorial");
    return result("editorial", recipient ? "recipient" : "drop", 0.15);
  }

  // 6) Otherwise: a single product → FEED. Score by buy-signal strength.
  let q = 0.5;
  if (p > 0) { q += 0.3; reasons.push("has_price"); }
  if (dc === "retailer") { q += 0.2; reasons.push("retailer"); }
  if (/\/(dp|gp\/product|listing|products?|p|item|sku)\//i.test(link)) { q += 0.1; reasons.push("pdp_path"); }
  if (t.length > 0 && t.length <= 60) q += 0.05;
  if (dc === "unknown" && p <= 0) { q -= 0.15; reasons.push("weak_signals"); }
  return result("single_product", "feed", q);
}

export default classifyPin;
