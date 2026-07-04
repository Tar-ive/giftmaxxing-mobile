// Audit + prune the S3 Vectors `pins` index against the LIVE posts table.
//
// Every vector's key == a postId. A vector earns its storage only if its post
// still exists AND meets the catalog quality bar we show on the site:
//   * a real, shoppable product link (not pinterest/social/blog/landing pages)
//   * a product image
// Everything else is dead weight from old ingests (the Jun 22 experiment, the
// pruned Reddit/Pinterest trash) — it can still surface via kNN as a neighbor,
// and it costs storage + query bytes.
//
// Buckets:
//   orphan-reddit      key/metadata says Reddit, post row is gone
//   orphan-pinterest   Pinterest-shaped key, post row is gone
//   orphan-other       post row gone, source unknown
//   bad-link           post exists but link is dead / social / landing / spam
//   no-image           post exists, link OK, but no product image
//   borderline         post exists; guide-ish or missing price (REPORT ONLY)
//   good               post exists, shoppable deep link + image
//
// Default DELETE set: all orphans + bad-link + no-image. `borderline` is never
// deleted by default (those posts are still served on recipient surfaces).
//
// Usage:
//   node prune-vectors.mjs                 # DRY RUN: audit + report + backup
//   node prune-vectors.mjs --apply         # delete (backup written first)
//   node prune-vectors.mjs --include-borderline   # also delete borderline
//
// Config (env): POSTS_TABLE, VECTOR_BUCKET, VECTOR_INDEX, AWS_REGION, plus the
// standard AWS credential chain (refresh SSO before --apply).

import { writeFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { DynamoDBClient } from "@aws-sdk/client-dynamodb";
import { DynamoDBDocumentClient, ScanCommand } from "@aws-sdk/lib-dynamodb";
import {
  S3VectorsClient,
  ListVectorsCommand,
  DeleteVectorsCommand,
} from "@aws-sdk/client-s3vectors";
import { classifyPin } from "../src/quality.mjs";

const __dirname = dirname(fileURLToPath(import.meta.url));

const REGION = process.env.AWS_REGION || "us-east-1";
const POSTS_TABLE = process.env.POSTS_TABLE || "giftmaxxing-dev-posts";
const VECTOR_BUCKET = process.env.VECTOR_BUCKET || "giftmaxxing-dev-vectors";
const VECTOR_INDEX = process.env.VECTOR_INDEX || "pins";

const APPLY = process.argv.includes("--apply");
const INCLUDE_BORDERLINE = process.argv.includes("--include-borderline");

// Same non-shoppable hosts as clean-posts.mjs — a link here is a dead end.
const NON_SHOPPABLE = [
  "pinterest.com", "pin.it", "pinterest.co.uk", "instagram.com", "facebook.com",
  "fb.me", "fb.com", "tiktok.com", "twitter.com", "x.com", "t.co",
  "youtube.com", "youtu.be", "flickr.com", "reddit.com", "redd.it",
  "linktw.in", "linktr.ee", "tumblr.com", "snapchat.com",
];

function parseLink(raw) {
  if (!raw || typeof raw !== "string") return null;
  let s = raw.trim();
  if (!s) return null;
  if (!/^https?:\/\//i.test(s)) {
    if (/^[\w-]+(\.[\w-]+)+/.test(s)) s = "https://" + s;
    else return null;
  }
  try {
    return new URL(s);
  } catch {
    return null;
  }
}

function hostMatches(host, list) {
  const h = host.replace(/^www\./, "").toLowerCase();
  return list.some((d) => h === d || h.endsWith("." + d));
}

// Quality bucket for a post that still exists (mirrors clean-posts.mjs).
function postBucket(p) {
  const title = p.caption || p.product?.name || p.name || "";
  const link = p.url || p.productUrl || p.pinUrl || p.product?.url || "";
  const priceRaw = p.price ?? p.product?.price;
  const price = typeof priceRaw === "number" ? priceRaw : Number(priceRaw) || 0;
  const image = p.image || p.product?.image || p.imageUrl || "";

  const url = parseLink(link);
  if (!url) return "bad-link";
  const host = url.hostname.replace(/^www\./, "").toLowerCase();
  if (hostMatches(host, NON_SHOPPABLE)) return "bad-link";
  if (url.pathname.replace(/\/+$/, "") === "") return "bad-link";

  const q = classifyPin({ title, domain: p.domain || host, link, price });
  if (q.contentType === "spam" || q.contentType === "recipe") return "bad-link";

  if (!parseLink(image)) return "no-image";

  if (!q.feedEligible || !(price > 0)) return "borderline";
  return "good";
}

// Which bucket does an ORPHANED vector belong to? (post row already deleted)
function orphanBucket(key, metadata) {
  const src = String(metadata?.source ?? "").toLowerCase();
  const sub = String(metadata?.subreddit ?? "");
  if (src.includes("reddit") || sub || /^t3_|^reddit-/.test(key)) return "orphan-reddit";
  if (src.includes("pinterest") || /^pin-/.test(key)) return "orphan-pinterest";
  return "orphan-other";
}

async function scanPosts(ddb) {
  const byId = new Map();
  let ExclusiveStartKey;
  do {
    const out = await ddb.send(
      new ScanCommand({ TableName: POSTS_TABLE, ExclusiveStartKey, Limit: 500 })
    );
    for (const item of out.Items ?? []) byId.set(String(item.postId), item);
    ExclusiveStartKey = out.LastEvaluatedKey;
  } while (ExclusiveStartKey);
  return byId;
}

async function listAllVectors(s3v) {
  const vectors = [];
  let nextToken;
  do {
    const out = await s3v.send(
      new ListVectorsCommand({
        vectorBucketName: VECTOR_BUCKET,
        indexName: VECTOR_INDEX,
        maxResults: 500,
        returnMetadata: true,
        nextToken,
      })
    );
    vectors.push(...(out.vectors ?? []));
    nextToken = out.nextToken;
  } while (nextToken);
  return vectors;
}

const chunk = (arr, n) =>
  Array.from({ length: Math.ceil(arr.length / n) }, (_, i) => arr.slice(i * n, i * n + n));

async function main() {
  const ddb = DynamoDBDocumentClient.from(new DynamoDBClient({ region: REGION }));
  const s3v = new S3VectorsClient({ region: REGION });

  console.log(`Scanning posts table ${POSTS_TABLE}…`);
  const posts = await scanPosts(ddb);
  console.log(`  ${posts.size} posts live in the catalog`);

  console.log(`Listing vectors in ${VECTOR_BUCKET}/${VECTOR_INDEX}…`);
  const vectors = await listAllVectors(s3v);
  console.log(`  ${vectors.length} vectors stored\n`);

  const buckets = {
    "orphan-reddit": [],
    "orphan-pinterest": [],
    "orphan-other": [],
    "bad-link": [],
    "no-image": [],
    borderline: [],
    good: [],
  };

  for (const v of vectors) {
    const key = String(v.key);
    const post = posts.get(key);
    const bucket = post ? postBucket(post) : orphanBucket(key, v.metadata);
    buckets[bucket].push({ key, metadata: v.metadata ?? null });
  }

  const total = vectors.length;
  console.log("── Audit ────────────────────────────────────────────");
  for (const [name, list] of Object.entries(buckets)) {
    const pctStr = total ? ((list.length / total) * 100).toFixed(1) : "0.0";
    console.log(`  ${String(list.length).padStart(6)}  (${pctStr.padStart(5)}%)  ${name}`);
  }

  const deleteBuckets = [
    "orphan-reddit",
    "orphan-pinterest",
    "orphan-other",
    "bad-link",
    "no-image",
    ...(INCLUDE_BORDERLINE ? ["borderline"] : []),
  ];
  const toDelete = deleteBuckets.flatMap((b) => buckets[b]);
  console.log(
    `\n  → ${toDelete.length} vectors to delete (${deleteBuckets.join(", ")})` +
      `\n  → ${buckets.good.length + (INCLUDE_BORDERLINE ? 0 : buckets.borderline.length)} vectors kept`
  );

  if (!toDelete.length) {
    console.log("\nNothing to prune. ✨");
    return;
  }

  // Backup manifest before anything destructive — same convention as
  // clean-posts.mjs (timestamped JSON next to this script).
  const when = new Date().toISOString().replace(/[:.]/g, "-");
  const backupPath = join(__dirname, `prune-vectors.backup.${when}.json`);
  await writeFile(
    backupPath,
    JSON.stringify(
      { bucket: VECTOR_BUCKET, index: VECTOR_INDEX, when, count: toDelete.length, buckets: Object.fromEntries(Object.entries(buckets).map(([k, v]) => [k, v.length])), toDelete },
      null,
      1
    )
  );
  console.log(`  backup written: ${backupPath}`);

  if (!APPLY) {
    console.log("\nDRY RUN — nothing deleted. Re-run with --apply to prune.");
    return;
  }

  console.log("\nDeleting…");
  let deleted = 0;
  for (const c of chunk(toDelete.map((x) => x.key), 100)) {
    await s3v.send(
      new DeleteVectorsCommand({
        vectorBucketName: VECTOR_BUCKET,
        indexName: VECTOR_INDEX,
        keys: c,
      })
    );
    deleted += c.length;
    if (deleted % 1000 === 0 || deleted === toDelete.length) {
      console.log(`  …${deleted}/${toDelete.length}`);
    }
  }
  console.log(`\nDone: ${deleted} vectors pruned, ${buckets.good.length} good ones kept.`);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
