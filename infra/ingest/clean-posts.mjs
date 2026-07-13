// Clean trash posts from the DynamoDB `posts` table (the /feed data store).
//
// Scans the posts table, classifies each PINTEREST-IMPORTED post as trash or
// keep, writes a full JSON backup of everything it would delete, and (only with
// --apply) BatchWrite-deletes them. Reddit posts and any user-generated content
// are NEVER touched — only items that look like Pinterest imports are even
// considered (author "pinterest_*" / source "Pinterest/*").
//
// Trash buckets (first match wins):
//   dead-link      no usable http(s) product link at all
//   non-shoppable  link points at pinterest/instagram/facebook/tiktok/x/…
//   landing        link is a bare homepage / root path (no product page)
//   content        blog / recipe / spam domain (classifyPin: spam|recipe)
//   non-gift       replacement auto/plumbing parts, digital pattern files
//   guide          listicle / gift-guide / editorial / seasonal (opt-in)
//   no-price       real shoppable deep link but missing a price (opt-in)
//
// Default DELETE set: dead-link, non-shoppable, landing, content, non-gift.
// `guide` and `no-price` are reported but only deleted with the opt-in flags.
//
// Usage:
//   node clean-posts.mjs                       # DRY RUN: scan + report + backup
//   node clean-posts.mjs --include-no-price    # also count missing-price as trash
//   node clean-posts.mjs --include-guides      # also count listicles/editorial
//   node clean-posts.mjs --keep content        # exclude a bucket from deletion
//   node clean-posts.mjs --only non-shoppable  # delete ONLY these buckets
//   node clean-posts.mjs --apply               # actually delete (backup first)
//
// Safety: dry-run by default; a timestamped backup of every to-delete item is
// written before any deletion; the posts table has point-in-time recovery on.
//
// Config (env): POSTS_TABLE, AWS_REGION, plus the standard AWS credential chain
// (env vars / shared config / SSO). Refresh expired SSO creds before --apply.

import { readFile, writeFile } from "node:fs/promises";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { classifyPin } from "../src/quality.mjs";

const __dirname = dirname(fileURLToPath(import.meta.url));

// Non-shoppable link hosts: a link here is a dead end, not a buyable product.
const NON_SHOPPABLE = [
  "pinterest.com", "pin.it", "pinterest.co.uk", "instagram.com", "facebook.com",
  "fb.me", "fb.com", "tiktok.com", "twitter.com", "x.com", "t.co",
  "youtube.com", "youtu.be", "flickr.com", "reddit.com", "redd.it",
  "linktw.in", "linktr.ee", "tumblr.com", "snapchat.com",
];

const ALL_BUCKETS = ["dead-link", "non-shoppable", "landing", "content", "non-gift", "guide", "no-price"];
const DEFAULT_DELETE = ["dead-link", "non-shoppable", "landing", "content", "non-gift"];

function parseArgs(argv) {
  const args = { apply: false, includeGuides: false, includeNoPrice: false, verbose: false };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === "--apply") args.apply = true;
    else if (a === "--include-guides") args.includeGuides = true;
    else if (a === "--include-no-price") args.includeNoPrice = true;
    else if (a === "--verbose") args.verbose = true;
    else if (a === "--limit") args.limit = Number(argv[++i]);
    else if (a === "--table") args.table = argv[++i];
    else if (a === "--region") args.region = argv[++i];
    else if (a === "--file") args.file = argv[++i];
    else if (a === "--out") args.out = argv[++i];
    else if (a === "--keep") args.keep = String(argv[++i] || "").split(",").map((s) => s.trim()).filter(Boolean);
    else if (a === "--only") args.only = String(argv[++i] || "").split(",").map((s) => s.trim()).filter(Boolean);
  }
  return args;
}

// Only Pinterest-imported posts are candidates. Reddit ("reddit_*") and any
// user-generated post fall through untouched.
function isPinterestImport(p) {
  const author = String(p.author || "");
  const source = String(p.source || "");
  return author.startsWith("pinterest_") || source.startsWith("Pinterest/");
}

// Pull the classify-relevant fields out of a post item (Pinterest shape).
function postFields(p) {
  const title = p.caption || p.product?.name || p.name || "";
  const link = p.url || p.productUrl || p.pinUrl || p.product?.url || "";
  const priceRaw = p.price ?? p.product?.price;
  const price = typeof priceRaw === "number" ? priceRaw : Number(priceRaw) || 0;
  const domain = p.domain || "";
  return { title, link, price, domain };
}

// Parse a raw link into a URL, tolerating bare-domain strings ("etsy.com/...").
function parseLink(raw) {
  if (!raw || typeof raw !== "string") return null;
  let s = raw.trim();
  if (!s) return null;
  if (!/^https?:\/\//i.test(s)) {
    if (/^[\w-]+(\.[\w-]+)+/.test(s)) s = "https://" + s; // looks like a domain
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

// Classify one Pinterest post into a trash bucket or "keep".
function bucketFor(post) {
  const { title, domain, link, price } = postFields(post);
  const url = parseLink(link);

  if (!url) return { bucket: "dead-link", title, link, price, reason: "no http(s) product link" };

  const host = url.hostname.replace(/^www\./, "").toLowerCase();
  if (hostMatches(host, NON_SHOPPABLE))
    return { bucket: "non-shoppable", title, link, price, reason: `non-shoppable host (${host})` };

  const path = url.pathname.replace(/\/+$/, "");
  if (path === "")
    return { bucket: "landing", title, link, price, reason: `landing page (${host}, no product path)` };

  const q = classifyPin({ title, domain: domain || host, link, price });
  if (q.contentType === "spam" || q.contentType === "recipe")
    return { bucket: "content", title, link, price, reason: q.reasons.join(",") || q.contentType };
  if (q.contentType === "non_gift")
    return { bucket: "non-gift", title, link, price, reason: q.reasons.join(",") || q.contentType };
  if (!q.feedEligible)
    return { bucket: "guide", title, link, price, reason: `${q.contentType} (${q.reasons.join(",")})` };
  if (!(price > 0))
    return { bucket: "no-price", title, link, price, reason: "missing price" };

  return { bucket: "keep", title, link, price };
}

// Resolve which buckets actually get deleted, from defaults + flags.
function resolveDeleteSet(args) {
  let set;
  if (args.only && args.only.length) {
    set = new Set(args.only.filter((b) => ALL_BUCKETS.includes(b)));
  } else {
    set = new Set(DEFAULT_DELETE);
    if (args.includeGuides) set.add("guide");
    if (args.includeNoPrice) set.add("no-price");
  }
  if (args.keep) for (const b of args.keep) set.delete(b);
  return set;
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const chunk = (arr, n) =>
  Array.from({ length: Math.ceil(arr.length / n) }, (_, i) => arr.slice(i * n, i * n + n));

// Scan the entire table (paginated), capped by --limit if given.
async function scanAll(ddb, ScanCommand, table, limit) {
  const items = [];
  let ExclusiveStartKey;
  do {
    const out = await ddb.send(
      new ScanCommand({ TableName: table, ExclusiveStartKey, Limit: 500 })
    );
    items.push(...(out.Items ?? []));
    ExclusiveStartKey = out.LastEvaluatedKey;
    if (limit && items.length >= limit) return items.slice(0, limit);
  } while (ExclusiveStartKey);
  return items;
}

// BatchWrite-delete by postId (25/req) with exponential-backoff retry.
async function deleteAll(ddb, BatchWriteCommand, table, postIds) {
  let deleted = 0;
  for (const c of chunk(postIds, 25)) {
    let request = { [table]: c.map((postId) => ({ DeleteRequest: { Key: { postId } } })) };
    for (let attempt = 0; attempt < 6; attempt++) {
      const out = await ddb.send(new BatchWriteCommand({ RequestItems: request }));
      const unprocessed = out.UnprocessedItems?.[table] ?? [];
      deleted += request[table].length - unprocessed.length;
      if (unprocessed.length === 0) break;
      request = { [table]: unprocessed };
      await sleep(2 ** attempt * 100);
    }
    console.log(`  …deleted ${deleted}/${postIds.length}`);
  }
  return deleted;
}

function pct(n, total) {
  return total ? `${((n / total) * 100).toFixed(1)}%` : "0%";
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const table = args.table || process.env.POSTS_TABLE || "giftmaxxing-dev-posts";
  const region = process.env.AWS_REGION || "us-east-1";
  const deleteSet = resolveDeleteSet(args);

  console.log(`Clean trash posts — table "${table}" (${region})`);
  console.log(`Mode: ${args.apply ? "APPLY (will delete)" : "DRY RUN (no deletes)"}`);
  console.log(`Delete buckets: ${[...deleteSet].join(", ") || "(none)"}`);
  console.log("");

  const { DynamoDBClient } = await import("@aws-sdk/client-dynamodb");
  const { DynamoDBDocumentClient, ScanCommand, BatchWriteCommand } = await import("@aws-sdk/lib-dynamodb");
  const ddb = DynamoDBDocumentClient.from(new DynamoDBClient({ region }), {
    marshallOptions: { removeUndefinedValues: true },
  });

  console.log("Scanning posts table…");
  let all;
  try {
    all = await scanAll(ddb, ScanCommand, table, args.limit);
  } catch (err) {
    console.error(`\n✗ Scan failed: ${err.name}: ${err.message}`);
    if (/security token|credential|ExpiredToken|InvalidClientTokenId|UnrecognizedClient/i.test(`${err.name} ${err.message}`)) {
      console.error("\nAWS credentials look expired/invalid. Refresh them, then retry:");
      console.error("  set -a; source ../../.env; set +a    # or: aws sso login");
    }
    process.exit(1);
  }

  const pins = all.filter(isPinterestImport);
  const skipped = all.length - pins.length;

  // Tally every post into a bucket.
  const byBucket = Object.fromEntries([...ALL_BUCKETS, "keep"].map((b) => [b, []]));
  for (const post of pins) {
    const res = bucketFor(post);
    byBucket[res.bucket].push({ post, ...res });
  }

  // Report.
  console.log(`\nScanned ${all.length} posts — ${pins.length} Pinterest imports, ${skipped} skipped (Reddit/user, never touched).`);
  console.log("\nBreakdown of Pinterest imports:");
  for (const b of [...ALL_BUCKETS, "keep"]) {
    const n = byBucket[b].length;
    if (!n) continue;
    const mark = b === "keep" ? "keep " : deleteSet.has(b) ? "DELETE" : "skip  ";
    console.log(`  [${mark}] ${b.padEnd(14)} ${String(n).padStart(5)}  (${pct(n, pins.length)})`);
  }

  // Sample a few from each delete bucket so the user can eyeball them.
  for (const b of ALL_BUCKETS) {
    if (!deleteSet.has(b) || !byBucket[b].length) continue;
    console.log(`\n  sample "${b}" (first 5):`);
    for (const x of byBucket[b].slice(0, 5)) {
      const t = (x.title || "(no title)").slice(0, 60);
      console.log(`    · ${t}  ←  ${x.link || "(no link)"}  [${x.reason}]`);
    }
  }

  // Assemble the delete list (full items for the backup).
  const toDelete = [];
  for (const b of deleteSet) for (const x of byBucket[b]) toDelete.push(x);

  if (args.verbose) {
    console.log("\nAll postIds to delete:");
    for (const x of toDelete) console.log(`  ${x.post.postId}\t${x.bucket}\t${(x.title || "").slice(0, 50)}`);
  }

  console.log(`\nTotal to delete: ${toDelete.length} / ${pins.length} Pinterest imports.`);

  if (!toDelete.length) {
    console.log("\nNothing to delete. Done.");
    return;
  }

  // Always write a backup of the exact items targeted (restorable via BatchWrite Put).
  const ts = new Date().toISOString().replace(/[:.]/g, "-");
  const backupPath = args.out
    ? resolve(process.cwd(), args.out)
    : join(__dirname, `clean-posts.backup.${ts}.json`);
  await writeFile(
    backupPath,
    JSON.stringify(
      { table, region, when: ts, count: toDelete.length, buckets: [...deleteSet], items: toDelete.map((x) => x.post) },
      null,
      2
    ) + "\n"
  );
  console.log(`Backup of targeted items → ${backupPath}`);

  if (!args.apply) {
    console.log("\n[dry-run] No posts deleted. Re-run with --apply to delete the above.");
    return;
  }

  console.log(`\nDeleting ${toDelete.length} posts from "${table}"…`);
  let deleted;
  try {
    deleted = await deleteAll(ddb, BatchWriteCommand, table, toDelete.map((x) => x.post.postId));
  } catch (err) {
    console.error(`\n✗ Delete failed: ${err.name}: ${err.message}`);
    console.error(`Backup is safe at ${backupPath}.`);
    process.exit(1);
  }
  console.log(`\n✓ Deleted ${deleted}/${toDelete.length} trash posts from ${table}.`);
  console.log(`Restore (if needed) from ${backupPath} via a BatchWrite Put.`);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
