#!/usr/bin/env node
//
// Instagram inspiration ingest (Apify → S3 → DynamoDB).
//
// WHY THIS EXISTS. The catalog is products; this is *inspiration*. Instagram
// seeded its early feed with recommendation content rather than waiting for
// users to post, and that is exactly the shape of the problem here: a new
// account's Home feed is only as good as the candidate pool behind it.
//
// WHAT IT DOES NOT DO. It does not pretend inspiration is shoppable. Every post
// lands with `shoppable: false` and no price until `inspo-gap.mjs` has matched
// it against the catalog — closing the gap between "nice photo" and "thing you
// can actually buy" is a separate, measured step, not an assumption.
//
// Usage (after `set -a; source ../../.env; set +a`):
//   node ingest-apify-instagram.mjs --dataset <id> --dry-run
//   node ingest-apify-instagram.mjs --dataset <id> --upload --apply
//
// Flags:
//   --run <id> / --dataset <id>   Apify run or dataset to read
//   --file <path>                 read a local JSON dump instead (offline)
//   --limit N                     cap posts processed
//   --upload                      archive images to S3 (else keep IG CDN urls)
//   --apply                       write to DynamoDB (default: dry run)
//   --min-score N                 acceptance threshold (default 45)
//   --out <path>                  write the manifest here

import { readFile, writeFile } from "node:fs/promises";
import { resolve } from "node:path";
import { fileURLToPath } from "node:url";

const CDN = process.env.CDN_BASE || "https://d21osnvwewgoao.cloudfront.net";
const DEFAULT_TABLE = process.env.POSTS_TABLE || "giftmaxxing-dev-posts";
const SOURCE_USER = "gift1dea";

// ── Caption signals ──────────────────────────────────────────────────────────
// An inspiration post earns its place by naming a GIFT or a RECIPIENT. A pretty
// photo with a caption of pure hashtags teaches the ranker nothing and gives the
// gap analysis nothing to search on.
const GIFT_WORD = /\b(gift|gifts|gifting|present|presents|surprise|treat)\b/i;
const RECIPIENT_WORD = /\b(mom|mum|mother|dad|father|wife|husband|girlfriend|boyfriend|partner|sister|brother|friend|bestie|bff|teacher|colleague|coworker|grandma|grandpa|kids?|teen|him|her)\b/i;
const OCCASION_WORD = /\b(birthday|anniversary|christmas|valentine|wedding|graduation|housewarming|baby shower|mother'?s day|father'?s day|holiday)\b/i;
// Engagement-bait and affiliate spam add nothing and drag the feed's tone down.
const SPAM = /\b(link in bio|dm for order|dm to order|follow for more|comment ["“]?\w+["”]? (below|and)|giveaway|tag \d+ friends|use code|shop now|order now)\b/i;

// MEASURED on the gift1dea corpus (999 posts): 26% of captions describe
// something the poster MADE — a scrapbook, an interactive card, a personalised
// magazine, a template. Those are real gift inspiration but they are NOT a
// sourcing gap: there is no product to stock, because the gift IS the making of
// it. Tagging them here keeps inspo-gap.mjs from reporting "we don't sell this"
// about 250 things nobody sells.
const DIY_WORD = /\b(diy|handmade|hand made|i made|made (it|this|him|her|them)|scrapbook|craft|crafting|template|tutorial|how to make|homemade|painted|knit|crochet)\b/i;

const clean = (value) => String(value || "").replace(/\s+/g, " ").trim();

export function intentOf(item) {
  const text = `${clean(item?.caption)} ${clean(item?.alt)}`;
  return DIY_WORD.test(text) ? "make" : "buy";
}

/**
 * Which kind of thing is this post? The answer decides whether it can be a feed
 * card at all, and it is the number the brief asks for ("how many are images").
 */
export function classifyMedia(item) {
  const type = String(item?.type || "").toLowerCase();
  const children = Array.isArray(item?.childPosts) ? item.childPosts : [];
  if (type === "video" || item?.videoUrl) return "video";
  if (type === "sidecar" || children.length > 1) return "carousel";
  if (type === "image" || item?.displayUrl) return "image";
  return "unknown";
}

/** Every still image in the post, in order, deduped. */
export function imagesOf(item) {
  const urls = [];
  const push = (url) => {
    const value = clean(url);
    if (value.startsWith("https://") && !urls.includes(value)) urls.push(value);
  };
  // For a reel this is the COVER FRAME, which is exactly what we want: 80.6% of
  // this corpus is video, every one has a cover, and those covers are flat-lays
  // of the gift. Dropping video would have discarded four fifths of the source.
  push(item?.displayUrl);
  for (const url of item?.images || []) push(url);
  for (const child of item?.childPosts || []) {
    if (child?.type === "Video" || child?.videoUrl) continue;
    push(child?.displayUrl);
  }
  return urls;
}

/**
 * Accept / reject with a reason, so a run is auditable rather than a black box.
 * Reels are KEPT via their cover frame (see imagesOf) but never rehosted — the
 * card links out to Instagram for the video itself.
 */
export function scorePost(item, { minScore = 45 } = {}) {
  const reasons = [];
  const media = classifyMedia(item);
  const images = imagesOf(item);
  const caption = clean(item?.caption);
  const alt = clean(item?.alt);
  const text = `${caption} ${alt} ${(item?.hashtags || []).join(" ")}`;

  if (!images.length) return { media, images, score: 0, accepted: false, reasons: ["no_image"] };
  // HARD reject, not a penalty. "DM for order details" scored 48 against a
  // threshold of 45 because the gift and recipient words rescued it — but the
  // whole point of a hand-off account like this is tone, and one dropshipper
  // caption in the feed costs more than the post is worth.
  if (SPAM.test(text)) return { media, images, score: 0, accepted: false, reasons: ["engagement_bait"] };

  let score = 30;
  if (GIFT_WORD.test(text)) { score += 20; reasons.push("gift_intent"); }
  if (RECIPIENT_WORD.test(text)) { score += 12; reasons.push("recipient"); }
  if (OCCASION_WORD.test(text)) { score += 10; reasons.push("occasion"); }
  if (media === "carousel") { score += 8; reasons.push("carousel"); }
  // A reel contributes its cover frame only — still useful, but one still is
  // less to learn from than a six-slide carousel.
  if (media === "video") { score -= 4; reasons.push("reel_cover"); }

  // Engagement is a weak but real signal; log-scaled so one viral post cannot
  // dominate the ordering.
  const likes = Math.max(0, Number(item?.likesCount) || 0);
  score += Math.min(20, Math.log10(likes + 1) * 7);

  if (!caption) { score -= 15; reasons.push("no_caption"); }
  // A caption that is only hashtags gives the gap analysis nothing to query on.
  if (caption && caption.replace(/#\S+/g, "").trim().length < 12) {
    score -= 18; reasons.push("hashtags_only");
  }

  score = Math.round(Math.max(0, Math.min(100, score)));
  return { media, images, score, accepted: score >= minScore, reasons };
}

/** True width÷height from the source, when it gave us dimensions. */
export function aspectOf(item) {
  const w = Number(item?.originalWidth) || Number(item?.dimensionsWidth) || 0;
  const h = Number(item?.originalHeight) || Number(item?.dimensionsHeight) || 0;
  if (w > 0 && h > 0) return Number((w / h).toFixed(4));
  // A carousel's first child carries the shape when the parent doesn't.
  const child = (item?.childPosts || [])[0];
  const cw = Number(child?.originalWidth) || Number(child?.dimensionsWidth) || 0;
  const ch = Number(child?.originalHeight) || Number(child?.dimensionsHeight) || 0;
  if (cw > 0 && ch > 0) return Number((cw / ch).toFixed(4));
  return null;
}

/** A short, human title from the caption's first meaningful line. */
export function titleOf(item) {
  const caption = clean(item?.caption).replace(/#\S+/g, "").trim();
  const first = caption.split(/[.!?\n]/).map(clean).find((part) => part.length > 8);
  const title = first || clean(item?.alt) || "Gift inspiration";
  return title.length > 90 ? `${title.slice(0, 87)}…` : title;
}

export function recipientOf(item) {
  const text = `${clean(item?.caption)} ${(item?.hashtags || []).join(" ")}`;
  const match = RECIPIENT_WORD.exec(text);
  return match ? match[0].toLowerCase() : null;
}

export function occasionOf(item) {
  const text = `${clean(item?.caption)} ${(item?.hashtags || []).join(" ")}`;
  const match = OCCASION_WORD.exec(text);
  return match ? match[0].toLowerCase().replace(/'/g, "") : null;
}

/**
 * The DynamoDB row. Deliberately NOT shaped like a product:
 *   price 0, `shoppable: false`, `contentType: "inspiration"`.
 * The feed's own gates already drop zero-price items from product surfaces, so
 * this content cannot leak into "buy" flows before inspo-gap.mjs links it.
 */
export function postFor(item, quality, provenance, { maxGallery = 10 } = {}) {
  // Later carousel slides are usually the same gift from another angle, so a
  // deep gallery costs egress and embedding budget without adding information.
  const images = quality.images.slice(0, maxGallery);
  const shortCode = clean(item?.shortCode) || clean(item?.id);
  return {
    postId: `ig-${shortCode}`,
    feedPk: "all",
    author: "giftmaxxing",
    sourceUser: SOURCE_USER,
    source: "instagram",
    createdAt: Date.parse(item?.timestamp || "") || Date.now(),
    likes: Math.max(0, Number(item?.likesCount) || 0),
    comments: Math.max(0, Number(item?.commentsCount) || 0),
    caption: clean(item?.caption).slice(0, 2000),
    reason: "Gift inspiration",
    recipient: recipientOf(item),
    occasion: occasionOf(item),
    hashtags: (item?.hashtags || []).slice(0, 20),
    mediaKind: quality.media,
    // The poster framed this shot; keep its shape. Without it the grid and the
    // detail sheet both fall back to an editorial crop, which cuts the gift out
    // of its own photo.
    aspectRatio: aspectOf(item),
    // "make" = DIY/handmade; the gift is the making, so there is nothing to
    // stock and nothing to link. inspo-gap.mjs skips these entirely.
    intent: intentOf(item),
    contentType: "inspiration",
    // Inspiration is feed-eligible but NOT shoppable until matched.
    feedEligible: true,
    shoppable: false,
    matchState: "unmatched",
    qualityScore: quality.score / 100,
    status: "find",
    priceTier: "unknown",
    price: 0,
    // Provenance, so a takedown or an attribution question is answerable.
    // Reels are NOT rehosted — only the cover frame is. The card links out to
    // the original post, which is both the honest affordance and the correct
    // attribution.
    outboundUrl: clean(item?.url),
    instagram: {
      shortCode,
      url: clean(item?.url),
      ownerUsername: clean(item?.ownerUsername),
      postedAt: clean(item?.timestamp),
      ...provenance,
    },
    product: {
      id: `ig-${shortCode}`,
      name: titleOf(item),
      brand: "",
      price: 0,
      grad: "rose",
      emoji: "🎁",
      image: images[0],
      images: images.slice(1),
    },
  };
}

// ── Runner ───────────────────────────────────────────────────────────────────

function argsOf(argv) {
  const args = { apply: false, upload: false, minScore: 45, limit: 0, maxGallery: 3, region: process.env.AWS_REGION || "us-east-1" };
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    if (arg === "--apply") args.apply = true;
    else if (arg === "--dry-run") args.apply = false;
    else if (arg === "--upload") args.upload = true;
    else if (arg === "--run") args.runId = argv[++i];
    else if (arg === "--dataset") args.datasetId = argv[++i];
    else if (arg === "--file") args.file = resolve(argv[++i]);
    else if (arg === "--limit") args.limit = Number(argv[++i]);
    else if (arg === "--min-score") args.minScore = Number(argv[++i]);
    else if (arg === "--max-gallery") args.maxGallery = Number(argv[++i]);
    else if (arg === "--bucket") args.bucket = argv[++i];
    else if (arg === "--table") args.table = argv[++i];
    else if (arg === "--out") args.out = resolve(argv[++i]);
  }
  return args;
}

async function apifyJson(path) {
  const token = process.env.APIFY_TOKEN;
  const url = `https://api.apify.com/v2/${path}${token ? `${path.includes("?") ? "&" : "?"}token=${token}` : ""}`;
  const response = await fetch(url);
  if (!response.ok) throw new Error(`Apify ${path} -> HTTP ${response.status}`);
  return response.json();
}

async function loadItems(args) {
  if (args.file) return JSON.parse(await readFile(args.file, "utf8"));
  let datasetId = args.datasetId;
  if (!datasetId && args.runId) {
    const run = (await apifyJson(`actor-runs/${args.runId}`)).data;
    if (run.status !== "SUCCEEDED") throw new Error(`Apify run ${args.runId} is ${run.status}`);
    datasetId = run.defaultDatasetId;
  }
  if (!datasetId) throw new Error("Pass --run, --dataset or --file");

  // Datasets page at 1000; loop so a 1000-post ask is not silently truncated.
  const all = [];
  for (let offset = 0; ; offset += 1000) {
    const page = await apifyJson(`datasets/${datasetId}/items?clean=true&format=json&limit=1000&offset=${offset}`);
    if (!page.length) break;
    all.push(...page);
    if (page.length < 1000) break;
  }
  return all;
}

async function uploadImages(posts, { bucket, region, datasetId }) {
  const { PutObjectCommand, S3Client } = await import("@aws-sdk/client-s3");
  const s3 = new S3Client({ region });
  let uploaded = 0;
  for (const post of posts) {
    const urls = [post.product.image, ...post.product.images];
    const archived = [];
    for (const [index, url] of urls.entries()) {
      try {
        const response = await fetch(url);
        const type = response.headers.get("content-type") || "";
        if (!response.ok || !type.startsWith("image/")) throw new Error(`HTTP ${response.status}`);
        const key = `ugc/public/inspiration/instagram/${SOURCE_USER}/${post.instagram.shortCode}/${index}.jpg`;
        await s3.send(new PutObjectCommand({
          Bucket: bucket, Key: key, Body: Buffer.from(await response.arrayBuffer()),
          ContentType: type, CacheControl: "public,max-age=31536000,immutable",
          Metadata: { "source-post": post.instagram.shortCode, "source-user": SOURCE_USER, dataset: String(datasetId || "") },
        }));
        archived.push(`${CDN}/${key}`);
        uploaded++;
      } catch (error) {
        // IG CDN URLs expire; a miss is not fatal — keep the original and let
        // the gap analysis skip what it cannot fetch.
        console.warn(`  ! ${post.postId} image ${index}: ${error.message}`);
      }
    }
    if (archived.length) {
      post.product.image = archived[0];
      post.product.images = archived.slice(1);
    }
  }
  return uploaded;
}

async function persist(posts, args) {
  const { DynamoDBClient } = await import("@aws-sdk/client-dynamodb");
  const { BatchWriteCommand, DynamoDBDocumentClient } = await import("@aws-sdk/lib-dynamodb");
  const ddb = DynamoDBDocumentClient.from(new DynamoDBClient({ region: args.region }), {
    marshallOptions: { removeUndefinedValues: true },
  });
  const table = args.table || DEFAULT_TABLE;
  for (let i = 0; i < posts.length; i += 25) {
    const batch = posts.slice(i, i + 25).map((Item) => ({ PutRequest: { Item } }));
    await ddb.send(new BatchWriteCommand({ RequestItems: { [table]: batch } }));
  }
  return table;
}

async function main() {
  const args = argsOf(process.argv.slice(2));
  const items = await loadItems(args);
  const capped = args.limit ? items.slice(0, args.limit) : items;
  console.log(`Loaded ${items.length} Apify items${args.limit ? ` (capped to ${capped.length})` : ""}`);

  const tally = { image: 0, carousel: 0, video: 0, unknown: 0 };
  const rejected = {};
  const posts = [];
  for (const item of capped) {
    const quality = scorePost(item, { minScore: args.minScore });
    tally[quality.media] = (tally[quality.media] || 0) + 1;
    if (!quality.accepted) {
      // Report why it FAILED, not the first positive signal it happened to
      // carry — a tally of "gift_intent=15" among rejects is meaningless.
      const negatives = quality.reasons.filter((r) =>
        ["no_image", "no_caption", "engagement_bait", "hashtags_only", "reel_cover"].includes(r)
      );
      const key = negatives.length ? negatives.join("+") : "low_score";
      rejected[key] = (rejected[key] || 0) + 1;
      continue;
    }
    posts.push(postFor(item, quality, { datasetId: args.datasetId, runId: args.runId }, { maxGallery: args.maxGallery }));
  }
  posts.sort((a, b) => b.qualityScore - a.qualityScore);

  console.log(`\nMedia mix: ${Object.entries(tally).map(([k, v]) => `${k}=${v}`).join("  ")}`);
  console.log(`Accepted ${posts.length} / ${capped.length}`);
  console.log(`Rejected: ${Object.entries(rejected).map(([k, v]) => `${k}=${v}`).join("  ") || "none"}`);
  const totalImages = posts.reduce((n, p) => n + 1 + p.product.images.length, 0);
  console.log(`Images to embed: ${totalImages}`);

  const out = args.out || resolve("instagram.manifest.json");
  await writeFile(out, JSON.stringify({ sourceUser: SOURCE_USER, datasetId: args.datasetId, tally, rejected, posts }, null, 2));
  console.log(`\nManifest → ${out}`);

  if (args.upload) {
    const bucket = args.bucket || process.env.MEDIA_BUCKET || "giftmaxxing-dev-media";
    console.log(`\nArchiving images to s3://${bucket}/ugc/public/inspiration/instagram/${SOURCE_USER}/ …`);
    const uploaded = await uploadImages(posts, { bucket, region: args.region, datasetId: args.datasetId });
    console.log(`Uploaded ${uploaded} images`);
    await writeFile(out, JSON.stringify({ sourceUser: SOURCE_USER, datasetId: args.datasetId, tally, rejected, posts }, null, 2));
  }

  if (!args.apply) {
    console.log("\nDry run — pass --apply to write to DynamoDB.");
    return;
  }
  const table = await persist(posts, args);
  console.log(`\nWrote ${posts.length} posts to ${table}`);
}

if (resolve(process.argv[1] || "") === fileURLToPath(import.meta.url)) {
  main().catch((error) => { console.error(error); process.exit(1); });
}
