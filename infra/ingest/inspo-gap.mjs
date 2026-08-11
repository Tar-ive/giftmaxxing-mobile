#!/usr/bin/env node
//
// Inspiration → product gap analysis.
//
// THE PROBLEM. Instagram inspiration is a great source of taste and a terrible
// source of commerce: a beautiful flat-lay tells you what someone WANTS and
// nothing about where to buy it. This job measures and closes that gap.
//
// HOW IT MATCHES — and the one thing that must not be got wrong.
//
//   Matching is IMAGE → IMAGE, never text → image.
//
// That is not a style preference, it is a measured property of this index (see
// CLOUD.md §8, age-packs): the vectors are image + marketing-title, so a text
// query lands loosely and short generic titles ("Villa", "Newborn", "Gift card")
// behave as hub vectors sitting near EVERY text query. Measured live:
// `over ear wireless headphones` → Wine Glass at 0.428, while the genuinely
// correct `kids art supplies` → Watercolor Kit sat FARTHER out at 0.438. No
// distance threshold can separate those, so text→image cannot be the matcher.
// Image→image is tight and is what this uses.
//
// The caption is still used — but only as a LEXICAL gate and as the seed for an
// Amazon search on the items we cannot match. kNN proposes, keywords dispose.
//
// OUTPUT. Three buckets, and the third is the real deliverable:
//   matched   → strong subject match (≥2 shared content words). Link it.
//   near      → one shared word. Show as "something similar".
//   unmatched → SOURCING GAP. This list says what to add to the catalog, and is
//               the most valuable artefact this job produces.
// See the CALIBRATION note below for why the bands are lexical, not cosine.
//
// Usage:
//   node inspo-gap.mjs --manifest instagram.manifest.json --limit 50
//   node inspo-gap.mjs --manifest instagram.manifest.json --apply

import { readFile, writeFile } from "node:fs/promises";
import { resolve } from "node:path";
import { fileURLToPath } from "node:url";

const MODEL = process.env.BEDROCK_EMBED_MODEL_ID || "amazon.titan-embed-image-v1";
const DIM = 1024;
const VECTOR_BUCKET = process.env.VECTOR_BUCKET || "giftmaxxing-dev-vectors";
const VECTOR_INDEX = process.env.VECTOR_INDEX || "pins";
const AMAZON_TAG = process.env.AMAZON_ASSOCIATES_PARTNER_TAG || "";

// CALIBRATION, measured — not assumed.
//
// The first version of this file used absolute cosine bands (0.78 / 0.62)
// picked by intuition. Run against the real corpus every single post came back
// "unmatched", because image→image similarity in THIS index actually spans
// ~0.38–0.58. The 0.78 band was empty by construction.
//
// Worse, the ordering inside that range is not relevance:
//   "gifts for the picky boyfriend" → Personalized Photo Canvas  0.467  ✓ right
//   "LMFAO my man 4life ok"         → Kylie's Oscars Look Bundle 0.486  ✗ junk
// The junk scores HIGHER. So similarity cannot be the primary decision at all —
// it is a tiebreak. Lexical overlap is the signal; cosine only orders within it.
//
// FLOOR, not threshold: anything under this is noise regardless of words.
export const SIMILARITY_FLOOR = 0.42;
// Two shared content words is a genuine subject match ("boyfriend" + "birthday"
// is not, on its own — those appear in half the corpus).
export const STRONG_OVERLAP = 2;

/**
 * Bucket a candidate. Lexical overlap decides; similarity is a floor and a
 * tiebreak. `overlapCount` is the number of shared content words.
 */
export function bucketFor(similarity, overlap = []) {
  const words = Array.isArray(overlap) ? overlap : [];
  if (similarity < SIMILARITY_FLOOR) return "unmatched";
  // A match needs at least one SPECIFIC word. "year" or "birthday" alone is a
  // coincidence — both appear in a large share of the corpus.
  const specific = specificOverlap(words);
  if (!specific.length) return "unmatched";
  if (words.length >= STRONG_OVERLAP) return "matched";
  return "near";
}

// ── Lexical gate ─────────────────────────────────────────────────────────────
// kNN proposes; this disposes. A neighbour only counts as a real match if it
// shares a content word with the inspiration's caption — the check that turned
// the age-packs build from junk into on-theme (CLOUD.md §8).
const STOP = new Set([
  "the", "and", "for", "with", "your", "you", "this", "that", "from", "have",
  "has", "are", "was", "our", "out", "get", "got", "all", "any", "new", "best",
  "gift", "gifts", "gifting", "idea", "ideas", "perfect", "love", "loved",
  "great", "good", "make", "makes", "made", "just", "one", "two", "she", "her",
  "him", "his", "they", "them", "who", "what", "when", "will", "can", "more",
]);

// Words that ARE content but are far too common in gifting to identify a
// subject on their own. Measured false positives from the first calibrated run:
//   "Birthday gifts for 10 year olds"  → "Nude Beauty Box 10 Year Anniversary"  (year)
//   "Easy snack for the beach"          → "Easy Sunkissed Nude Set"              (easy)
// Both are coincidences. A weak word only counts alongside a specific one.
const WEAK = new Set([
  "birthday", "anniversary", "christmas", "holiday", "wedding", "year", "years",
  "easy", "cute", "mini", "little", "small", "large", "box", "boxes", "set",
  "sets", "kit", "pink", "aesthetic", "custom", "personalized", "personalised",
  "cheap", "expensive", "girl", "girls", "boy", "boys", "friend", "friends",
  "boyfriend", "girlfriend", "bestie", "couple", "couples", "mom", "dad",
  // Rekognition label noise: true of the photo, useless as a subject.
  // Measured: "or like a gift or anythingg" matched a Spa Gift Box on
  // ["color", "pink"] — which says nothing about what either item IS.
  "color", "colour", "pattern", "texture", "shape", "material", "design",
  "accessory", "accessories", "symbol", "number", "paper", "publication",
  "food", "fun", "romantic", "purple", "white", "black", "green", "blue",
]);

export function isWeakWord(word) { return WEAK.has(String(word || "").toLowerCase()); }

/** Overlap that actually identifies a subject: at least one specific word. */
export function specificOverlap(overlap) {
  return (overlap || []).filter((word) => !isWeakWord(word));
}

export function contentWords(text) {
  return [...new Set(
    String(text || "")
      .toLowerCase()
      // Strip hashtags and @handles FIRST. On this corpus the top tags are
      // trend/fyp/viral/foryou — pure reach bait that would otherwise become
      // the Amazon search terms ("save bdayy giftideas foryou foryoupage").
      .replace(/[#@]\S+/g, " ")
      .replace(/[^a-z0-9\s]/g, " ")
      .split(/\s+/)
      .filter((word) => word.length >= 4 && !STOP.has(word))
  )];
}

/** Word-boundary match with an optional trailing s — never bare `includes`, which
 *  let "Easter Party" satisfy an "art" slot in the age-pack build. */
export function lexicalOverlap(captionWords, title) {
  const target = String(title || "").toLowerCase();
  return captionWords.filter((word) => new RegExp(`\\b${word}s?\\b`).test(target));
}

/** The Amazon search we'd send someone to for an item we cannot match. */
export function amazonQuery(post) {
  const words = contentWords(`${post?.product?.name || ""} ${post?.caption || ""}`).slice(0, 5);
  return words.join(" ") || String(post?.product?.name || "gift").slice(0, 60);
}

export function amazonSearchUrl(query) {
  const url = new URL("https://www.amazon.com/s");
  url.searchParams.set("k", query);
  if (AMAZON_TAG) url.searchParams.set("tag", AMAZON_TAG);
  return url.toString();
}

// ── AWS ──────────────────────────────────────────────────────────────────────

async function embedImage(bedrock, InvokeModelCommand, url) {
  const response = await fetch(url);
  if (!response.ok) throw new Error(`image HTTP ${response.status}`);
  const base64 = Buffer.from(await response.arrayBuffer()).toString("base64");
  const out = await bedrock.send(new InvokeModelCommand({
    modelId: MODEL,
    contentType: "application/json",
    accept: "application/json",
    body: JSON.stringify({ inputImage: base64, embeddingConfig: { outputEmbeddingLength: DIM } }),
  }));
  return JSON.parse(Buffer.from(out.body).toString("utf8")).embedding;
}

function argsOf(argv) {
  const args = { apply: false, limit: 0, topK: 12, region: process.env.AWS_REGION || "us-east-1" };
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    if (arg === "--apply") args.apply = true;
    else if (arg === "--manifest") args.manifest = resolve(argv[++i]);
    else if (arg === "--limit") args.limit = Number(argv[++i]);
    else if (arg === "--top-k") args.topK = Number(argv[++i]);
    else if (arg === "--out") args.out = resolve(argv[++i]);
    else if (arg === "--table") args.table = argv[++i];
    else if (arg === "--resume") args.resume = true;
    else if (arg === "--labels") args.labels = resolve(argv[++i]);
  }
  return args;
}

async function main() {
  const args = argsOf(process.argv.slice(2));
  if (!args.manifest) throw new Error("Pass --manifest instagram.manifest.json");

  const manifest = JSON.parse(await readFile(args.manifest, "utf8"));

  // Fold in Rekognition labels (label-images.mjs) when they exist. Passed as a
  // side file rather than re-read from DynamoDB so the analysis stays runnable
  // offline against a manifest.
  if (args.labels) {
    try {
      const file = JSON.parse(await readFile(args.labels, "utf8"));
      const byId = new Map((file.results || []).map((r) => [r.postId, r.words || []]));
      let applied = 0;
      for (const post of manifest.posts) {
        const words = byId.get(post.postId);
        if (words?.length) { post.labelWords = words; applied++; }
      }
      console.log(`Image labels applied to ${applied} posts.`);
    } catch (error) {
      console.warn(`Could not read labels: ${error.message}`);
    }
  }

  const posts = args.limit ? manifest.posts.slice(0, args.limit) : manifest.posts;
  console.log(`Analysing ${posts.length} inspiration posts against the catalog…\n`);

  const { BedrockRuntimeClient, InvokeModelCommand } = await import("@aws-sdk/client-bedrock-runtime");
  const { QueryVectorsCommand, S3VectorsClient } = await import("@aws-sdk/client-s3vectors");
  const bedrock = new BedrockRuntimeClient({ region: args.region });
  const s3v = new S3VectorsClient({ region: args.region });

  // CHECKPOINTING. This job embeds ~800 images one at a time and takes ~20
  // minutes. The first version wrote its report only at the very end, so an
  // interruption at 759/795 lost every result — 95% of the work and the spend.
  // Now: results append to the report file every CHECKPOINT_EVERY items, and a
  // re-run skips whatever the file already holds.
  const CHECKPOINT_EVERY = 25;
  const out = args.out || resolve("inspo-gap.report.json");

  let results = [];
  let tally = { matched: 0, near: 0, unmatched: 0, failed: 0 };
  let done = new Set();
  if (args.resume) {
    try {
      const prior = JSON.parse(await readFile(out, "utf8"));
      results = prior.results || [];
      tally = prior.tally || tally;
      done = new Set(results.map((r) => r.postId));
      console.log(`Resuming — ${done.size} already analysed.\n`);
    } catch { /* no prior report; start clean */ }
  }

  const checkpoint = async () => {
    await writeFile(out, JSON.stringify(
      { tally, similarityFloor: SIMILARITY_FLOOR, strongOverlap: STRONG_OVERLAP, results }, null, 2));
  };

  for (const [index, post] of posts.entries()) {
    const label = `${index + 1}/${posts.length} ${post.postId}`;
    if (done.has(post.postId)) continue;
    // DIY has no product to find — embedding it would spend money to conclude
    // something we already know from the caption.
    if (post.intent === "make") {
      results.push({ postId: post.postId, title: post.product?.name, bucket: "diy", intent: "make" });
      continue;
    }
    try {
      // The HERO image only. Later carousel slides are usually the same product
      // from another angle, so embedding all of them multiplies cost without
      // changing the verdict.
      const vector = await embedImage(bedrock, InvokeModelCommand, post.product.image);

      const query = await s3v.send(new QueryVectorsCommand({
        vectorBucketName: VECTOR_BUCKET,
        indexName: VECTOR_INDEX,
        queryVector: { float32: vector },
        topK: args.topK,
        returnMetadata: true,
        returnDistance: true,
      }));

      // IMAGE labels first, caption second.
      //
      // Rekognition read the picture; the caption was written by a teenager.
      // Measured on this corpus: captions like "LMFAO my man 4life ok" carry no
      // product noun at all, while the same image labels as "Headphones,
      // Cosmetics, Lipstick". The gate matches on nouns, so give it nouns.
      const labelWords = (post.labelWords || []).filter((w) => w.length >= 4);
      const captionWords = [...new Set([
        ...labelWords,
        ...contentWords(`${post.product.name} ${post.caption}`),
      ])];
      const neighbours = (query.vectors || []).map((v) => {
        const title = v.metadata?.title || "";
        const similarity = v.distance != null ? 1 - v.distance : 0;
        return {
          key: v.key,
          title,
          similarity: Number(similarity.toFixed(4)),
          imageUrl: v.metadata?.imageUrl || null,
          overlap: lexicalOverlap(captionWords, title),
        };
      });

      // Best neighbour = highest similarity that ALSO shares a content word.
      // Falling back to pure similarity would reintroduce the hub-vector
      // failure the lexical gate exists to prevent, so a no-overlap top hit is
      // demoted to "near" at best rather than promoted to "matched".
      // Rank by OVERLAP first, similarity only within the same overlap count —
      // see the calibration note at the top of this file.
      // Rank by SPECIFIC overlap first, then total overlap, then similarity.
      const ranked = [...neighbours].sort((a, b) =>
        (specificOverlap(b.overlap).length - specificOverlap(a.overlap).length) ||
        (b.overlap.length - a.overlap.length) ||
        (b.similarity - a.similarity));
      const best = ranked[0] || null;
      const similarity = best?.similarity ?? 0;
      const bucket = bucketFor(similarity, best?.overlap ?? []);

      tally[bucket]++;
      const record = {
        postId: post.postId,
        title: post.product.name,
        image: post.product.image,
        instagramUrl: post.instagram?.url,
        bucket,
        similarity,
        match: best ? { key: best.key, title: best.title, overlap: best.overlap } : null,
        neighbours: neighbours.slice(0, 5),
      };
      if (bucket === "unmatched") {
        const q = amazonQuery(post);
        record.sourcing = { query: q, amazonUrl: amazonSearchUrl(q) };
      }
      results.push(record);
      console.log(`  ${label} → ${bucket} (${similarity.toFixed(3)})${best ? ` · ${best.title.slice(0, 46)}` : ""}`);
    } catch (error) {
      tally.failed++;
      results.push({ postId: post.postId, bucket: "failed", error: error.message });
      console.warn(`  ${label} ! ${error.message}`);
    }
    if (results.length % CHECKPOINT_EVERY === 0) await checkpoint();
  }
  await checkpoint();

  const diy = results.filter((r) => r.bucket === "diy").length;
  const total = results.length - tally.failed - diy;
  const pct = (n) => (total ? ((n / total) * 100).toFixed(1) : "0.0");
  console.log(`\n${"─".repeat(58)}`);
  console.log(`matched    ${String(tally.matched).padStart(4)}  ${pct(tally.matched)}%   strong subject match — link it`);
  console.log(`near       ${String(tally.near).padStart(4)}  ${pct(tally.near)}%   we sell something like it`);
  console.log(`unmatched  ${String(tally.unmatched).padStart(4)}  ${pct(tally.unmatched)}%   SOURCING GAP`);
  if (diy) console.log(`diy        ${String(diy).padStart(4)}         skipped — the gift IS the making`);
  if (tally.failed) console.log(`failed     ${String(tally.failed).padStart(4)}`);

  // The gap list, ranked — what to add to the catalog next.
  const gaps = results.filter((r) => r.bucket === "unmatched");
  if (gaps.length) {
    console.log(`\nTop sourcing gaps:`);
    for (const gap of gaps.slice(0, 15)) {
      console.log(`  · ${gap.title.slice(0, 58)}`);
      console.log(`      search: ${gap.sourcing.query}`);
    }
  }

  await checkpoint();
  console.log(`\nReport → ${out}`);

  if (!args.apply) {
    console.log("Dry run — pass --apply to write matches back to the posts table.");
    return;
  }

  const { DynamoDBClient } = await import("@aws-sdk/client-dynamodb");
  const { DynamoDBDocumentClient, UpdateCommand } = await import("@aws-sdk/lib-dynamodb");
  const ddb = DynamoDBDocumentClient.from(new DynamoDBClient({ region: args.region }), {
    marshallOptions: { removeUndefinedValues: true },
  });
  const table = args.table || process.env.POSTS_TABLE || "giftmaxxing-dev-posts";
  let written = 0;
  for (const record of results) {
    if (record.bucket === "failed" || record.bucket === "diy") continue;
    await ddb.send(new UpdateCommand({
      TableName: table,
      // POSTS is keyed on postId ALONE — `feedPk` is a GSI attribute, not part
      // of the primary key. Passing both returned ValidationException.
      Key: { postId: record.postId },
      UpdateExpression: "SET matchState = :m, matchSimilarity = :s, matchedKey = :k, shoppable = :b, sourcing = :g",
      ExpressionAttributeValues: {
        ":m": record.bucket,
        ":s": record.similarity,
        ":k": record.match?.key || null,
        // Only a gated, high-similarity match earns a buy affordance.
        ":b": record.bucket === "matched",
        ":g": record.sourcing || null,
      },
    }));
    written++;
  }
  console.log(`Updated ${written} rows in ${table}`);
}

if (resolve(process.argv[1] || "") === fileURLToPath(import.meta.url)) {
  main().catch((error) => { console.error(error); process.exit(1); });
}
