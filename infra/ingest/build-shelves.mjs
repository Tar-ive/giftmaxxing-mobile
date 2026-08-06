// Build REAL membership for the client's curated gift galleries and resolve
// the Reddit-mined "goes together" bundles to buyable products.
//
// Why: the iOS gift galleries were "curation by query" — vibe keywords sent to
// /feed, where vibes are only a +0.25 soft boost over store-level tags, so
// every shelf returned the same generic top-of-catalog soup ("Cozy Nights In"
// full of outerwear). This script curates each shelf by MEANING instead:
// Titan Multimodal embeds the shelf's theme sentence into the SAME vector
// space as the catalog images, so kNN retrieval is semantic, then quality /
// price / brand-cap filters enforce the shelf's promise.
//
//   gallery#<id>      one CONFIG row per shelf   { title, itemIds[] }
//   bundles#<recipient> one CONFIG row per recipient {
//       bundles: [{ why, score, slots: [{ key, label, emoji, itemIds[] }] }] }
//   bundles#index     { recipients: [...] } — lets /bundles serve a sampler
//
// Served by GET /galleries/{id} and GET /bundles (handler.mjs). Re-run any
// time the catalog changes: writes are idempotent upserts.
//
// Usage:  set -a; source ../../.env; set +a
//         node build-shelves.mjs [--galleries] [--bundles] [--dry-run]
import { DynamoDBClient } from "@aws-sdk/client-dynamodb";
import { DynamoDBDocumentClient, PutCommand, ScanCommand } from "@aws-sdk/lib-dynamodb";
import { BedrockRuntimeClient, InvokeModelCommand } from "@aws-sdk/client-bedrock-runtime";
import { S3VectorsClient, QueryVectorsCommand } from "@aws-sdk/client-s3vectors";
import { classifyPin } from "../src/quality.mjs";

const REGION = process.env.AWS_REGION || "us-east-1";
const VECTOR_BUCKET = process.env.VECTOR_BUCKET || "giftmaxxing-dev-vectors";
const VECTOR_INDEX = process.env.VECTOR_INDEX || "pins";
const MODEL = process.env.BEDROCK_EMBED_MODEL_ID || "amazon.titan-embed-image-v1";
const DIM = Number(process.env.VECTOR_DIM || 1024);
const ENV_PREFIX = process.env.ENV_PREFIX || "giftmaxxing-dev";
const CONFIG_TABLE = process.env.CONFIG_TABLE || `${ENV_PREFIX}-config`;
const KNOWLEDGE_TABLE = process.env.KNOWLEDGE_TABLE || `${ENV_PREFIX}-knowledge`;

const ddb = DynamoDBDocumentClient.from(new DynamoDBClient({ region: REGION }), {
  marshallOptions: { removeUndefinedValues: true },
});
const bedrock = new BedrockRuntimeClient({ region: REGION });
const s3v = new S3VectorsClient({ region: REGION });

// Mirrors Giftmaxxing/Models/CuratedCollection.swift ids. themeText is what
// gets embedded — write it like a caption of the ideal ITEM (the object, the
// scene), and never say "gift": the catalog is full of generic "Gift Box/Set"
// listings whose embeddings sit right on top of gift-language queries, so a
// theme containing "gift" returns the same self-care boxes for every shelf
// (verified against the live index before this wording).
const SHELVES = [
  { id: "anniversary-under-50", title: "Anniversary Gifts Under $50",
    theme: "romantic keepsake for a partner: engraved jewelry, love-letter token, scented candle, framed photo memento", maxPrice: 50, requirePrice: true },
  { id: "golf-lover", title: "For the Golf Lover",
    theme: "golf equipment and golfer style: golf balls, putting practice set, golf glove, polo shirt, course accessories" },
  { id: "coffee-obsessed", title: "For the Coffee Obsessed",
    theme: "espresso machine, pour-over coffee brewer, roasted coffee beans, ceramic mug, barista tools" },
  { id: "tech-wishlist", title: "The Tech Lover's Wishlist",
    theme: "tech gadgets: wireless charger, headphones, smart device, sleek desk setup, cable organizer" },
  { id: "beauty-glow", title: "Beauty & Glow",
    theme: "makeup palette, lipstick, skincare serum, blush brush, glowing skin routine" },
  { id: "for-him-essentials", title: "For Him: The Essentials",
    theme: "men's everyday carry: leather wallet, beard grooming kit, classic menswear staple, watch" },
  { id: "cozy-nights", title: "Cozy Nights In",
    theme: "scented candle, soft throw blanket, herbal tea, warm loungewear, a good book by the fire" },
  { id: "under-25", title: "Little Luxuries Under $25",
    theme: "small delightful trinket: cute desk object, mini treat, playful surprise, stocking stuffer", maxPrice: 25, requirePrice: true },
  { id: "birthday-showstoppers", title: "Birthday Showstoppers",
    theme: "celebration showpiece: confetti-worthy, fun, trendy, memorable party centerpiece item" },
  { id: "sustainable", title: "Sustainable & Thoughtful",
    theme: "eco-friendly reusable goods: natural materials, zero waste, ethically made everyday objects" },
  { id: "fitness-fanatic", title: "For the Fitness Fanatic",
    theme: "gym workout gear: dumbbells, running shoes, yoga mat, athletic wear, muscle recovery tools" },
  { id: "minimalist", title: "Minimalist Picks",
    theme: "minimalist design object: clean lines, premium simple everyday item, understated quality" },
];

// Age-group idea packs.
//
// The Reddit KNOWLEDGE base is keyed by RELATIONSHIP (mom, wife, coworker…) —
// only "kids" and "teen" are age-shaped, so there is nothing to mine for "what
// do you get a 9-year-old". These bands are hand-authored and then run through
// the SAME resolveBundleSlot() machinery as the mined bundles: each slot label
// is Titan-embedded, kNN'd against the catalog, and quality/brand-filtered. So
// the items are as real as everywhere else — only the idea is editorial.
//
// Slot labels are written as PRODUCT CAPTIONS, never containing "gift" — see
// the note above SHELVES for why that word poisons the embedding.
const AGE_PACKS = [
  {
    key: "age-kids-5-8",
    label: "Ages 5–8",
    why: "What actually lands with early-elementary kids",
    childSafe: true,
    slots: [
      { key: "blocks", label: "wooden building blocks construction set for children", emoji: "🧱" },
      { key: "book", label: "illustrated children's picture story book hardcover", emoji: "📚" },
      { key: "art", label: "kids art supplies set crayons markers sketch pad", emoji: "🎨" },
      { key: "outdoor", label: "kids scooter helmet outdoor play", emoji: "🛴" },
    ],
  },
  {
    key: "age-tween-9-12",
    label: "Ages 9–12",
    why: "The in-between years, handled",
    childSafe: true,
    slots: [
      { key: "stem", label: "science experiment kit crystal growing robotics for kids", emoji: "🔬" },
      { key: "craft", label: "friendship bracelet making kit beads jewelry craft", emoji: "🧶" },
      { key: "active", label: "skateboard roller skates for kids", emoji: "🛹" },
      { key: "handheld", label: "handheld electronic game console for kids", emoji: "🎮" },
    ],
  },
  {
    key: "age-teen-13-17",
    label: "Ages 13–17",
    why: "Teen-approved, not try-hard",
    childSafe: true,
    slots: [
      { key: "audio", label: "over ear wireless headphones", emoji: "🎧" },
      { key: "camera", label: "instant print camera with film", emoji: "📸" },
      { key: "room", label: "LED strip lights bedroom decor", emoji: "💡" },
      { key: "skin", label: "skincare set cleanser moisturizer sunscreen", emoji: "🧴" },
    ],
  },
  {
    key: "age-young-adult-18-25",
    label: "Ages 18–25",
    why: "First-apartment energy",
    slots: [
      { key: "coffee", label: "espresso maker pour over coffee brewer", emoji: "☕️" },
      { key: "speaker", label: "portable bluetooth speaker waterproof", emoji: "🔊" },
      { key: "cozy", label: "soft throw blanket for a small apartment", emoji: "🛋️" },
      { key: "carry", label: "laptop backpack canvas leather", emoji: "🎒" },
    ],
  },
  {
    key: "age-adult-26-39",
    label: "Ages 26–39",
    why: "Upgrades to the things they already use daily",
    slots: [
      { key: "kitchen", label: "cast iron skillet dutch oven cookware", emoji: "🍳" },
      { key: "sleep", label: "weighted blanket silk pillowcase", emoji: "🌙" },
      { key: "carry", label: "leather dopp kit toiletry bag", emoji: "🧳" },
      { key: "bar", label: "cocktail shaker bar tool set glassware", emoji: "🍸" },
    ],
  },
  {
    key: "age-40-54",
    label: "Ages 40–54",
    why: "Small luxuries they'd never buy themselves",
    slots: [
      { key: "recover", label: "massage gun heated neck shoulder wrap", emoji: "💆" },
      { key: "audio", label: "record player turntable vinyl", emoji: "🎶" },
      { key: "outdoor", label: "gardening tool set kneeler pruning shears", emoji: "🌱" },
      { key: "wine", label: "wine decanter aerator glass set", emoji: "🍷" },
    ],
  },
  {
    key: "age-55-plus",
    label: "Ages 55+",
    why: "Comfort, craft, and time outdoors",
    slots: [
      { key: "warm", label: "cashmere merino wool scarf gloves", emoji: "🧣" },
      { key: "puzzle", label: "jigsaw puzzle board game for adults", emoji: "🧩" },
      { key: "frame", label: "digital photo frame wifi", emoji: "🖼️" },
      { key: "tea", label: "loose leaf tea sampler teapot", emoji: "🍵" },
    ],
  },
];

// Age-gated categories must never resolve into a child band. Mirrors
// knowledge.mjs's ADULT_ONLY guard, applied here by title since these slots
// don't come from the mined lexicon.
const ADULT_ONLY_RE = /\b(wine|whisk(?:e)?y|bourbon|scotch|vodka|gin|rum|tequila|liqueur|champagne|prosecco|beer|cocktail|barware|decanter|flask|cigar|lighter|vape)\b/i;

const SHELF_SIZE = 60;
const BRAND_CAP = 8;     // per shelf — no store owns a gallery
const GIFTBOX_CAP = 6;   // generic "Gift Box/Set/Bundle" listings per shelf
const MAX_DISTANCE = 0.62; // same relevance gate as /visual-search — beyond
                           // this the kNN neighbors are "nearest" but unrelated
const BUNDLE_SLOT_ITEMS = 4;
const BUNDLES_PER_RECIPIENT = 3;

// Near-duplicate listings (the same product re-ingested under several ids /
// variants) flood kNN results — dedup on a normalized title prefix.
const titleKey = (m) => String(m?.title ?? "").toLowerCase().replace(/[^a-z0-9]+/g, " ").trim().slice(0, 48);
const isGiftBox = (m) => /gift (box|set|basket)|bundle|care package/i.test(String(m?.title ?? ""));
// Dead/delisted pages scraped before the product vanished.
const isDeadListing = (m) => /unavailable|sold out|out of stock|page not found/i.test(String(m?.title ?? ""));

async function embedText(text) {
  const out = await bedrock.send(new InvokeModelCommand({
    modelId: MODEL,
    contentType: "application/json",
    accept: "application/json",
    body: JSON.stringify({ inputText: text.slice(0, 200), embeddingConfig: { outputEmbeddingLength: DIM } }),
  }));
  return JSON.parse(Buffer.from(out.body).toString("utf8")).embedding;
}

async function knn(vector, topK) {
  const out = await s3v.send(new QueryVectorsCommand({
    vectorBucketName: VECTOR_BUCKET, indexName: VECTOR_INDEX,
    topK, queryVector: { float32: vector }, returnMetadata: true, returnDistance: true,
  }));
  return out.vectors ?? [];
}

function eligible(v) {
  const m = v.metadata ?? {};
  const q = classifyPin({
    title: m.title, domain: m.domain,
    link: m.link || m.pinUrl, price: Number(m.price) || 0,
    giftType: m.giftType === "service" ? "service" : "product",
  });
  return q.feedEligible;
}

async function curateShelf(shelf, dry) {
  const vec = await embedText(shelf.theme);
  const hits = await knn(vec, 300);
  const perBrand = new Map();
  const seenTitles = new Set();
  let giftBoxes = 0;
  const itemIds = [];
  for (const v of hits) {
    const m = v.metadata ?? {};
    if (typeof v.distance === "number" && v.distance > MAX_DISTANCE) break; // sorted by distance
    const price = Number(m.price) || 0;
    if (shelf.maxPrice) {
      if (shelf.requirePrice && !(price > 0)) continue; // "Under $X" must hold
      if (price > shelf.maxPrice) continue;
    }
    if (!eligible(v) || isDeadListing(m)) continue;
    const tk = titleKey(m);
    if (tk && seenTitles.has(tk)) continue; // near-duplicate listing
    if (isGiftBox(m) && giftBoxes >= GIFTBOX_CAP) continue;
    const brand = m.sourceUser || m.domain || "";
    const n = perBrand.get(brand) ?? 0;
    if (n >= BRAND_CAP) continue;
    perBrand.set(brand, n + 1);
    if (tk) seenTitles.add(tk);
    if (isGiftBox(m)) giftBoxes++;
    itemIds.push(v.key);
    if (itemIds.length >= SHELF_SIZE) break;
  }
  console.log(`  ${shelf.id}: ${itemIds.length} items from ${perBrand.size} brands`);
  if (dry) {
    const byKey = new Map(hits.map((v) => [v.key, v.metadata?.title ?? ""]));
    for (const id of itemIds.slice(0, 5)) console.log(`      · ${String(byKey.get(id)).slice(0, 64)}`);
  }
  if (!dry) {
    await ddb.send(new PutCommand({
      TableName: CONFIG_TABLE,
      Item: { key: `gallery#${shelf.id}`, type: "gallery", title: shelf.title, itemIds, updatedAt: Date.now() },
    }));
  }
}

async function resolveBundleSlot(idea, { childSafe = false } = {}) {
  // Embed the idea NOUN only — appending "gift" drags in generic gift boxes.
  const vec = await embedText(idea.label);
  const hits = await knn(vec, 40);
  const seenBrands = new Set();
  const seenTitles = new Set();
  const itemIds = [];
  for (const v of hits) {
    if (typeof v.distance === "number" && v.distance > MAX_DISTANCE) break;
    const m = v.metadata ?? {};
    if (!eligible(v) || isDeadListing(m)) continue;
    // A kNN neighbour of "kids art supplies" can still be a wine-themed craft
    // kit. Nothing age-gated reaches a child band.
    if (childSafe && ADULT_ONLY_RE.test(String(m.title ?? ""))) continue;
    const tk = titleKey(m);
    if (tk && seenTitles.has(tk)) continue;
    const brand = m.sourceUser || m.domain || v.key;
    if (seenBrands.has(brand)) continue; // 4 options = 4 different sellers
    seenBrands.add(brand);
    if (tk) seenTitles.add(tk);
    itemIds.push(v.key);
    if (itemIds.length >= BUNDLE_SLOT_ITEMS) break;
  }
  return { key: idea.key, label: idea.label, emoji: idea.emoji || "🎁", itemIds };
}

async function buildBundles(dry) {
  const out = await ddb.send(new ScanCommand({ TableName: KNOWLEDGE_TABLE }));
  const recipients = [];
  for (const row of out.Items ?? []) {
    const top = (row.bundles ?? [])
      .filter((b) => Array.isArray(b.items) && b.items.length >= 2)
      .sort((a, b) => (b.score ?? 0) - (a.score ?? 0))
      .slice(0, BUNDLES_PER_RECIPIENT);
    if (!top.length) continue;
    const bundles = [];
    for (const b of top) {
      const slots = [];
      for (const idea of b.items.slice(0, 4)) slots.push(await resolveBundleSlot(idea));
      const filled = slots.filter((s) => s.itemIds.length);
      if (filled.length >= 2) {
        bundles.push({ why: b.why || "Often suggested together", score: b.score ?? 0, slots: filled });
      }
    }
    if (!bundles.length) continue;
    recipients.push(row.recipient);
    console.log(`  ${row.recipient}: ${bundles.length} bundles (${bundles.map((b) => b.slots.map((s) => s.label).join(" + ")).join(" | ")})`);
    if (!dry) {
      await ddb.send(new PutCommand({
        TableName: CONFIG_TABLE,
        Item: { key: `bundles#${row.recipient}`, type: "bundles", recipient: row.recipient, bundles, updatedAt: Date.now() },
      }));
    }
  }

  // Age packs share the index, so they MUST be resolved before it's written —
  // the index is rewritten wholesale from `recipients`, and anything missing
  // from this array silently disappears from the /bundles sampler.
  await buildAgePacks(dry, recipients);

  if (!dry) {
    await ddb.send(new PutCommand({
      TableName: CONFIG_TABLE,
      Item: { key: "bundles#index", type: "bundles-index", recipients, updatedAt: Date.now() },
    }));
  }
  console.log(`bundles built for ${recipients.length} recipients`);
}

// Hand-authored age bands, resolved to real products through the same kNN path
// as the mined bundles. Written as ordinary `bundles#<key>` rows so GET
// /bundles serves them with no server change at all.
async function buildAgePacks(dry, recipientsOut) {
  for (const pack of AGE_PACKS) {
    const slots = [];
    for (const slot of pack.slots) {
      slots.push(await resolveBundleSlot(slot, { childSafe: pack.childSafe }));
    }
    const filled = slots.filter((s) => s.itemIds.length);
    console.log(
      `  ${pack.key}: ${filled.length}/${pack.slots.length} slots (${filled.map((s) => s.key).join(" + ") || "none"})`
    );
    // /bundles drops anything with fewer than 2 resolvable slots, so don't
    // write a row that can never be served.
    if (filled.length < 2) {
      console.warn(`    skipped — only ${filled.length} slot(s) resolved`);
      continue;
    }
    if (!dry) {
      await ddb.send(new PutCommand({
        TableName: CONFIG_TABLE,
        Item: {
          key: `bundles#${pack.key}`,
          type: "bundles",
          recipient: pack.key,
          bundles: [{ why: `${pack.label} · ${pack.why}`, score: 1, slots: filled }],
          updatedAt: Date.now(),
        },
      }));
    }
    recipientsOut.push(pack.key);
  }
}

const args = new Set(process.argv.slice(2));
const dry = args.has("--dry-run");
const doGalleries = args.has("--galleries") || (!args.has("--bundles"));
const doBundles = args.has("--bundles") || (!args.has("--galleries"));
if (doGalleries) {
  console.log(`curating ${SHELVES.length} shelves${dry ? " (dry run)" : ""}…`);
  for (const s of SHELVES) await curateShelf(s, dry);
}
if (doBundles) {
  console.log(`resolving knowledge bundles${dry ? " (dry run)" : ""}…`);
  await buildBundles(dry);
}
