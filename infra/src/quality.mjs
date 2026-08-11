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

// Big-box US retailers shoppers actually buy gifts from. Used to bias visual
// search / recommendation ordering so, among near-equal matches, the links
// people will really use (Amazon/Target/Walmart…) beat niche shops.
const MAJOR_US_RETAILERS = new Set([
  "amazon.com", "amzn.to", "a.co", "target.com", "walmart.com", "bestbuy.com",
  "nordstrom.com", "macys.com", "kohls.com", "costco.com", "homedepot.com",
  "wayfair.com", "sephora.com", "ulta.com", "rei.com", "dickssportinggoods.com",
  "crateandbarrel.com", "potterybarn.com", "westelm.com", "williams-sonoma.com",
]);

const norm = (s) => String(s || "").toLowerCase().replace(/^www\./, "").trim();
function domainClass(domain) {
  const d = norm(domain);
  if (!d) return "unknown";
  if (RECIPE_DOMAIN.test(d)) return "recipe";
  if (CONTENT.has(d) || CONTENT_SUFFIX.test(d)) return "content";
  if (RETAILER.has(d) || [...RETAILER].some((r) => d.endsWith("." + r))) return "retailer";
  if (MAJOR_US_RETAILERS.has(d) || [...MAJOR_US_RETAILERS].some((r) => d.endsWith("." + r))) {
    return "retailer";
  }
  return "unknown";
}

export function isMajorUSRetailer(domain) {
  const d = norm(domain);
  if (!d) return false;
  return MAJOR_US_RETAILERS.has(d) || [...MAJOR_US_RETAILERS].some((r) => d.endsWith("." + r));
}

// ── Non-giftable merchandise ─────────────────────────────────────────────────
// Real products on allowlisted retailers that nobody GIFTS: replacement auto
// parts and plumbing/appliance hardware (eBay is full of them), and digital
// pattern files / printables (Etsy). They carry every commerce signal — price,
// retailer domain, PDP path — so they need their own gate. Live examples that
// reached the feed: "Bm1240164 Replacement Front Driver Side Fender Fits
// 2014-2016 Bmw 428i", "To1288213 Replacement Washer Fluid Reservoir Fits
// 2013-2018 Toyota Rav4", "PDF File for Crochet Pattern (English), Junction
// Beanie, Pictures and Video Tutorials Included".
const PART_NUMBER = /^\s*[A-Za-z]{1,4}\d{5,}\b/; //           "Bm1240164 Replacement…"
const FITS_YEARS = /\bfits?\b[^,;]{0,40}\b(19|20)\d{2}\s*[-–]\s*(19|20)?\d{2}\b/i; // "Fits 2014-2016 Bmw"
const REPLACEMENT_PART = /\breplacement\b[\w\s]{0,30}\b(part|fender|bumper|reservoir|assembly|housing|panel|filter|pump|motor|valve|sensor|cartridge|blade|belt|hose|lens|glass|screen)\b/i;
// Unambiguously automotive terms — enough on their own.
const AUTO_PART = /\b(catalytic converter|muffler|alternator|carburetor|spark plugs?|brake (pads?|rotors?|calipers?)|shock absorbers?|drive\s?shaft|crankshaft|camshaft|wiper blades?|washer fluid|coolant reservoir|fluid reservoir|ignition coil|ignition switch|timing belt|serpentine belt|exhaust (pipe|manifold)|hubcaps?|mud\s?flaps?|obd2?\s?(scanner|reader)|(door )?lock actuators?|actuator motors?|wheel studs?|lug nuts?|tie rod( ends?)?|ball joints?|wheel (bearings?|hubs?)|control arms?|sway bar|cv (axle|joint)|(oxygen|o2|abs|camshaft|crankshaft) sensors?|window regulators?)\b/i;
// Aftermarket auto-part brands that sell nothing giftable — a brand hit alone
// is decisive ("Dorman 937-080 Door Lock Actuator", "Dorman 610368.1 Wheel Stud").
const AUTO_BRAND = /\b(dorman|motorcraft|acdelco|duralast|cardone|timken|moog|febi bilstein|delphi)\b/i;
// Terms that are also gift-adjacent (a Fender guitar, a bike headlight, a
// radiator cover) — only automotive when the caption reads like a car listing.
const AUTO_PART_AMBIG = /\b(fenders?|bumpers?|tail\s?lights?|headlights?|headlamps?|grilles?|struts?|axles?|gaskets?|radiators?|fuel pumps?|starter motors?)\b/i;
const AUTO_CONTEXT = /\b(car|cars|truck|suv|sedan|coupe|vehicle|auto(motive)?|driver'?s? side|passenger'?s? side|front (left|right)|rear (left|right)|oem)\b/i;
const HARDWARE_PART = /\b(plumbing|faucet cartridge|sink strainer|drain (valve|plug|assembly|stopper|snake)|p-?trap|sump pump|shut-?off valve|pipe (fitting|wrench)|pvc (pipe|fitting)|toilet (flange|flapper|fill valve|seat|repair)|water heater (element|thermostat)|garbage disposal|caulk(ing)?|grout|drywall|circuit breaker|junction box|weather stripping|hvac|furnace filter|condenser coil|compressor unit)\b/i;
// Household consumables, tyres/wheels, fixtures and event stationery. All three
// carry price + retailer + PDP path, so they sailed through every gate above and
// reached the swipe deck, where they are indefensible: nobody swipes right on
// "Zep Antibacterial 32-fl oz Lemon Disinfectant", "Fuel Maverick 15" Wheels
// Black 32" Outlaw Max Tires", "Gold Clothing Racks, Metal Clothes Rack With 8
// Straight Arms" or "We Couldn't Wait Reception Invitation - Elopement
// Announcement". These are supplies, fitments and paper goods, not gifts.
const CLEANING_SUPPLY = /\b(disinfectant|bleach|all[- ]purpose cleaner|degreaser|drain cleaner|toilet (bowl )?cleaner|laundry detergent|fabric softener|dish soap|dishwasher (pods?|detergent)|trash bags?|paper towels?|toilet paper|mop refills?|floor cleaner|glass cleaner|air freshener|pest (control|spray)|insecticide|weed killer|motor oil|antifreeze|windshield washer fluid)\b/i;
const TIRES_WHEELS = /\b(\d{2}"?\s*(wheels?|rims?)|tires?\s*(and|&|\+)\s*wheels?|wheels?\s*(and|&|\+)\s*tires?|all[- ]terrain tires?|mud tires?|atv tires?|utv|wheel and tire (package|kit)|tire package)\b/i;
// Fixtures and furniture that exist to store or mount other things.
const FIXTURE = /\b(clothes? racks?|clothing racks?|garment racks?|shoe racks?|storage (racks?|shelv(es|ing)|bins?)|shelving units?|closet organizers?|curtain rods?|towel bars?|cabinet (pulls?|knobs?|hinges?)|door (knobs?|handles?|hinges?)|(window|mini|vertical|roller) blinds?|window screens?|ceiling fans?|light fixtures?|floor tiles?|backsplash|countertops?|vanity units?|mailboxes?|fence panels?|gutter guards?)\b/i;
// Event paper goods: invitations, announcements, save-the-dates, RSVP cards,
// place cards. Bought by the event host in bulk; never given as a gift.
const EVENT_STATIONERY = /\b(invitations?|announcements?|save[- ]the[- ]dates?|rsvp cards?|place cards?|escort cards?|seating charts?|menu cards?|table numbers?|wedding (invites?|stationery))\b/i;
const DIGITAL_FILE = /\b(pdf (file|pattern|download)|digital (download|file|print|pattern|planner)|printables?|instant download|svg (file|bundle|cut file)|cut files?|(crochet|knitting|knit|sewing|cross-?stitch|embroidery|quilt(ing)?|amigurumi) patterns?|clip\s?art|cricut|silhouette cameo|lightroom presets?|procreate brush(es)?)\b/i;

// ── Caption signals ──────────────────────────────────────────────────────────
const STARTS_NUMBER = /^\s*\d{1,3}\b/; //                      "33 gifts for her…"
// "30 birthday gifts" — a count of gifts, i.e. a roundup. Plural only, and
// never a PRICE: "the under-$200 Apple gift" is product copy, not a listicle
// (live false positive that dropped AirPods from the feed).
const N_GIFTS = /(?<![$€£])\b\d{1,3}\s*\+?\s*[\w\s]{0,20}?\bgifts\b/i;
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
 *   contentType: single_product | gift_guide | editorial | recipe | seasonal | spam | non_gift
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

  // 1.5) Non-giftable merchandise — replacement auto/plumbing parts and digital
  // pattern files pass every commerce heuristic below (price + retailer + PDP
  // path), so the caption itself is the gate. Checked before the listicle pass:
  // these are real single products, just not gifts.
  const partish =
    PART_NUMBER.test(t) || FITS_YEARS.test(t) || REPLACEMENT_PART.test(lt) ||
    AUTO_PART.test(lt) || AUTO_BRAND.test(lt) ||
    (AUTO_PART_AMBIG.test(lt) && AUTO_CONTEXT.test(lt)) ||
    HARDWARE_PART.test(lt);
  const supply =
    CLEANING_SUPPLY.test(lt) || TIRES_WHEELS.test(lt) ||
    FIXTURE.test(lt) || EVENT_STATIONERY.test(lt);
  if (partish || supply || DIGITAL_FILE.test(lt)) {
    reasons.push(partish ? "non_gift_part" : supply ? "non_gift_supply" : "digital_file");
    return result("non_gift", "drop", 0.05);
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
