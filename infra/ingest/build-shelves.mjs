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
// gets embedded — write it like a caption of the ideal item, not keywords.
const SHELVES = [
  { id: "anniversary-under-50", title: "Anniversary Gifts Under $50",
    theme: "romantic anniversary gift for a partner: keepsake jewelry, engraved token, scented candle, framed memento", maxPrice: 50, requirePrice: true },
  { id: "golf-lover", title: "For the Golf Lover",
    theme: "golf gift: golf balls, putting accessories, golf glove, sporty outdoor gear for a golfer" },
  { id: "coffee-obsessed", title: "For the Coffee Obsessed",
    theme: "coffee lover gift: espresso maker, pour-over brewer, coffee beans, ceramic mug, barista tools" },
  { id: "tech-wishlist", title: "The Tech Lover's Wishlist",
    theme: "tech gadget gift: wireless charger, headphones, smart device, sleek desk accessory, cable organizer" },
  { id: "beauty-glow", title: "Beauty & Glow",
    theme: "beauty and self-care gift: makeup palette, lipstick, skincare set, glowing skin routine" },
  { id: "for-him-essentials", title: "For Him: The Essentials",
    theme: "men's everyday essentials gift: leather wallet, grooming kit, classic menswear staple, watch" },
  { id: "cozy-nights", title: "Cozy Nights In",
    theme: "cozy night at home gift: scented candle, soft throw blanket, herbal tea set, warm loungewear, book" },
  { id: "under-25", title: "Little Luxuries Under $25",
    theme: "small delightful gift: stocking stuffer, cute desk trinket, mini treat, fun affordable surprise", maxPrice: 25, requirePrice: true },
  { id: "birthday-showstoppers", title: "Birthday Showstoppers",
    theme: "standout birthday gift that wows: celebration-worthy, fun, trendy, memorable present" },
  { id: "sustainable", title: "Sustainable & Thoughtful",
    theme: "eco-friendly sustainable gift: reusable, natural materials, zero waste, ethically made goods" },
  { id: "fitness-fanatic", title: "For the Fitness Fanatic",
    theme: "fitness gift: gym gear, workout accessories, running equipment, yoga mat, athletic recovery tools" },
  { id: "minimalist", title: "Minimalist Picks",
    theme: "minimalist design gift: clean lines, premium simple everyday object, understated quality" },
];

const SHELF_SIZE = 60;
const BRAND_CAP = 8;     // per shelf — no store owns a gallery
const BUNDLE_SLOT_ITEMS = 4;
const BUNDLES_PER_RECIPIENT = 3;

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
  const itemIds = [];
  for (const v of hits) {
    const m = v.metadata ?? {};
    const price = Number(m.price) || 0;
    if (shelf.maxPrice) {
      if (shelf.requirePrice && !(price > 0)) continue; // "Under $X" must hold
      if (price > shelf.maxPrice) continue;
    }
    if (!eligible(v)) continue;
    const brand = m.sourceUser || m.domain || "";
    const n = perBrand.get(brand) ?? 0;
    if (n >= BRAND_CAP) continue;
    perBrand.set(brand, n + 1);
    itemIds.push(v.key);
    if (itemIds.length >= SHELF_SIZE) break;
  }
  console.log(`  ${shelf.id}: ${itemIds.length} items from ${perBrand.size} brands`);
  if (!dry) {
    await ddb.send(new PutCommand({
      TableName: CONFIG_TABLE,
      Item: { key: `gallery#${shelf.id}`, type: "gallery", title: shelf.title, itemIds, updatedAt: Date.now() },
    }));
  }
}

async function resolveBundleSlot(idea) {
  const vec = await embedText(`${idea.label} gift`);
  const hits = await knn(vec, 40);
  const seenBrands = new Set();
  const itemIds = [];
  for (const v of hits) {
    if (!eligible(v)) continue;
    const brand = (v.metadata ?? {}).sourceUser || (v.metadata ?? {}).domain || v.key;
    if (seenBrands.has(brand)) continue; // 4 options = 4 different sellers
    seenBrands.add(brand);
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
  if (!dry) {
    await ddb.send(new PutCommand({
      TableName: CONFIG_TABLE,
      Item: { key: "bundles#index", type: "bundles-index", recipients, updatedAt: Date.now() },
    }));
  }
  console.log(`bundles built for ${recipients.length} recipients`);
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
