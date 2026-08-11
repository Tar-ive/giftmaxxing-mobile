#!/usr/bin/env node
//
// Rekognition labels for inspiration images.
//
// WHY. The lexical gate in inspo-gap.mjs is what actually decides a match —
// cosine ordering proved unreliable (a wrong neighbour at 0.486 beat the
// correct one at 0.467), so shared CONTENT WORDS make the call. Those words
// currently come from Instagram captions, and the captions on this corpus are
//
//     "LMFAO my man 4life ok😍"
//     "i fr have the best gf Post Credit: @lyft0gt"
//     "how is this even real"
//
// which contain no product noun at all. The gate is being asked to match on
// text that never describes the thing in the picture.
//
// Rekognition reads the PICTURE. `Jar`, `Candle`, `Bouquet`, `Notebook` are
// exactly the words the gate needs, and they are independent of how the poster
// captioned it. DetectLabels is already in this stack — ugc-ingest.mjs uses it
// for safety review — so this adds no new service, no new IAM and no new key.
//
// Usage:
//   node label-images.mjs --limit 20            # dry run
//   node label-images.mjs --apply               # write labels to POSTS
//   node label-images.mjs --apply --resume      # continue an interrupted run

import { readFile, writeFile } from "node:fs/promises";
import { resolve } from "node:path";
import { fileURLToPath } from "node:url";

const DEFAULT_TABLE = process.env.POSTS_TABLE || "giftmaxxing-dev-posts";
const MIN_CONFIDENCE = 75;
const MAX_LABELS = 25;

// Labels that are true of almost every photo and therefore identify nothing.
// Leaving them in would make the gate match on "Person" and call it a subject
// match — the same coincidence problem the weak-word list already solved for
// captions.
const USELESS = new Set([
  "person", "human", "people", "adult", "female", "male", "man", "woman", "boy", "girl",
  "face", "head", "hand", "finger", "arm", "body part", "portrait", "photography",
  "indoors", "outdoors", "room", "interior design", "home decor", "furniture",
  "text", "handwriting", "art", "advertisement", "poster", "collage", "screen",
  "electronics", "computer hardware", "accessories", "clothing", "apparel",
  "plant", "table", "wall", "floor", "light", "lighting", "still life photography",
]);

/** Keep only labels that could plausibly name a gift. */
export function usefulLabels(labels) {
  const seen = new Set();
  return (labels || [])
    .filter((l) => (l.Confidence ?? 0) >= MIN_CONFIDENCE)
    .map((l) => String(l.Name || "").trim())
    .filter((name) => {
      const key = name.toLowerCase();
      if (!key || USELESS.has(key)) return false;
      // Multi-word labels are usually more specific ("Coffee Cup" > "Cup"), so
      // keep both — the gate matches on single words anyway.
      return seen.add(key) !== undefined && seen.has(key);
    })
    .slice(0, 12);
}

/** The words the lexical gate will actually see. */
export function labelWords(labels) {
  const words = new Set();
  for (const label of usefulLabels(labels)) {
    for (const word of label.toLowerCase().split(/\s+/)) {
      if (word.length >= 4) words.add(word);
    }
  }
  return [...words];
}

function argsOf(argv) {
  const args = { apply: false, resume: false, limit: 0, region: process.env.AWS_REGION || "us-east-1" };
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    if (arg === "--apply") args.apply = true;
    else if (arg === "--resume") args.resume = true;
    else if (arg === "--limit") args.limit = Number(argv[++i]);
    else if (arg === "--manifest") args.manifest = resolve(argv[++i]);
    else if (arg === "--out") args.out = resolve(argv[++i]);
    else if (arg === "--table") args.table = argv[++i];
  }
  return args;
}

async function main() {
  const args = argsOf(process.argv.slice(2));
  const manifestPath = args.manifest || "/tmp/instagram.manifest.json";
  const manifest = JSON.parse(await readFile(manifestPath, "utf8"));
  const posts = args.limit ? manifest.posts.slice(0, args.limit) : manifest.posts;

  const out = args.out || resolve("image-labels.json");
  // Checkpointed for the same reason inspo-gap.mjs is: this is an ~800-call
  // job and losing it at 95% once was enough.
  let results = [];
  let done = new Set();
  if (args.resume) {
    try {
      results = JSON.parse(await readFile(out, "utf8")).results || [];
      done = new Set(results.map((r) => r.postId));
      console.log(`Resuming — ${done.size} already labelled.`);
    } catch { /* start clean */ }
  }

  const { DetectLabelsCommand, RekognitionClient } = await import("@aws-sdk/client-rekognition");
  const rekognition = new RekognitionClient({ region: args.region });

  const checkpoint = () => writeFile(out, JSON.stringify({ results }, null, 2));
  let failed = 0;

  for (const [index, post] of posts.entries()) {
    if (done.has(post.postId)) continue;
    const label = `${index + 1}/${posts.length} ${post.postId}`;
    try {
      const url = post.product?.image;
      if (!url) throw new Error("no image");
      const response = await fetch(url);
      if (!response.ok) throw new Error(`image HTTP ${response.status}`);
      const bytes = Buffer.from(await response.arrayBuffer());

      const detected = await rekognition.send(new DetectLabelsCommand({
        Image: { Bytes: bytes },
        MaxLabels: MAX_LABELS,
        MinConfidence: MIN_CONFIDENCE,
      }));

      const labels = usefulLabels(detected.Labels);
      const words = labelWords(detected.Labels);
      results.push({ postId: post.postId, labels, words });
      console.log(`  ${label} → ${labels.slice(0, 6).join(", ") || "(nothing usable)"}`);
    } catch (error) {
      failed++;
      results.push({ postId: post.postId, labels: [], words: [], error: error.message });
      console.warn(`  ${label} ! ${error.message}`);
    }
    if (results.length % 25 === 0) await checkpoint();
  }
  await checkpoint();

  const labelled = results.filter((r) => r.labels.length).length;
  console.log(`\n${"─".repeat(52)}`);
  console.log(`labelled ${labelled} / ${results.length}   failed ${failed}`);
  const freq = {};
  for (const r of results) for (const l of r.labels) freq[l] = (freq[l] || 0) + 1;
  const top = Object.entries(freq).sort((a, b) => b[1] - a[1]).slice(0, 20);
  console.log(`top labels: ${top.map(([k, v]) => `${k}(${v})`).join(", ")}`);
  console.log(`\nLabels → ${out}`);

  if (!args.apply) {
    console.log("Dry run — pass --apply to write to DynamoDB.");
    return;
  }

  const { DynamoDBClient } = await import("@aws-sdk/client-dynamodb");
  const { DynamoDBDocumentClient, UpdateCommand } = await import("@aws-sdk/lib-dynamodb");
  const ddb = DynamoDBDocumentClient.from(new DynamoDBClient({ region: args.region }), {
    marshallOptions: { removeUndefinedValues: true },
  });
  const table = args.table || DEFAULT_TABLE;

  let written = 0;
  for (const r of results) {
    if (!r.labels.length) continue;
    await ddb.send(new UpdateCommand({
      TableName: table,
      Key: { postId: r.postId },
      UpdateExpression: "SET imageLabels = :l, labelWords = :w",
      ExpressionAttributeValues: { ":l": r.labels, ":w": r.words },
      ConditionExpression: "attribute_exists(postId)",
    }));
    written++;
  }
  console.log(`Updated ${written} rows in ${table}`);
}

if (resolve(process.argv[1] || "") === fileURLToPath(import.meta.url)) {
  main().catch((error) => { console.error(error); process.exit(1); });
}
