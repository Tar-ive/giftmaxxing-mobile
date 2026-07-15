// Vector backfill driver: find every POSTS-table item that has an image but no
// vector in the S3 Vectors index, and write an embed.mjs-compatible manifest
// for them. Closes the "21k image references, only a fraction embedded" gap so
// visual search + recommendations cover the WHOLE catalog.
//
// Why not CLIP-on-SageMaker: our index is Titan Multimodal 1024-d — CLIP lives
// in a DIFFERENT embedding space, so its vectors can't be compared/fused with
// the existing ones. Titan already accepts remote images (embed.mjs fetches
// rec.imageUrl when there's no s3Key), and at batch pricing 21.3k images is
// ≈ $0.64 one-time. Same space, same index, no new infra.
//
// Usage (needs AWS creds; in a CCR container add NODE_USE_ENV_PROXY=1):
//   set -a; source ../../.env; set +a
//   node backfill-vectors.mjs                    # report + write manifest
//   node backfill-vectors.mjs --brands top       # top-20 brands by item count first
//   node backfill-vectors.mjs --limit 500        # cap manifest size
//   node embed.mjs --manifest backfill.manifest.json   # then embed
//
// Config (env): POSTS_TABLE, VECTOR_BUCKET, VECTOR_INDEX, AWS_REGION.

import { writeFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { DynamoDBClient } from "@aws-sdk/client-dynamodb";
import { DynamoDBDocumentClient, ScanCommand } from "@aws-sdk/lib-dynamodb";
import { S3VectorsClient, ListVectorsCommand } from "@aws-sdk/client-s3vectors";

const __dirname = dirname(fileURLToPath(import.meta.url));

const REGION = process.env.AWS_REGION || "us-east-1";
const POSTS = process.env.POSTS_TABLE || "giftmaxxing-dev-posts";
const VECTOR_BUCKET = process.env.VECTOR_BUCKET || "giftmaxxing-dev-vectors";
const VECTOR_INDEX = process.env.VECTOR_INDEX || "pins";

const ddb = DynamoDBDocumentClient.from(new DynamoDBClient({ region: REGION }));
const s3v = new S3VectorsClient({ region: REGION });

function parseArgs(argv) {
  const a = { limit: 0, brands: "", out: join(__dirname, "backfill.manifest.json") };
  for (let i = 0; i < argv.length; i++) {
    const x = argv[i];
    if (x === "--limit") a.limit = Number(argv[++i]);
    else if (x === "--brands") a.brands = String(argv[++i] || "");
    else if (x === "--out") a.out = argv[++i];
  }
  return a;
}

async function allVectorKeys() {
  const keys = new Set();
  let nextToken;
  do {
    const out = await s3v.send(
      new ListVectorsCommand({
        vectorBucketName: VECTOR_BUCKET,
        indexName: VECTOR_INDEX,
        nextToken,
        maxResults: 500,
      })
    );
    for (const v of out.vectors ?? []) keys.add(v.key);
    nextToken = out.nextToken;
  } while (nextToken);
  return keys;
}

async function allPosts() {
  const items = [];
  let lastKey;
  do {
    const out = await ddb.send(
      new ScanCommand({ TableName: POSTS, ExclusiveStartKey: lastKey })
    );
    items.push(...(out.Items ?? []));
    lastKey = out.LastEvaluatedKey;
  } while (lastKey);
  return items;
}

async function main() {
  const args = parseArgs(process.argv.slice(2));

  console.log(`Listing existing vector keys (${VECTOR_BUCKET}/${VECTOR_INDEX})…`);
  const existing = await allVectorKeys();
  console.log(`  ${existing.size} vectors in the index.`);

  console.log(`Scanning ${POSTS}…`);
  const posts = await allPosts();
  console.log(`  ${posts.length} posts.`);

  // A post is backfillable when it has an id + an image URL and isn't indexed.
  let missing = posts.filter((p) => {
    const id = p.postId || p.id;
    const image = p.product?.image || p.image || p.imageUrl;
    if (!id || !image || existing.has(id)) return false;
    // Respect the quality gate — junk should never enter the index.
    if (p.feedEligible === false) return false;
    return true;
  });

  // Per-brand tally (drives the --brands top ordering and the report).
  const byBrand = {};
  for (const p of missing) {
    const brand = p.product?.brand || p.author || "unknown";
    byBrand[brand] = (byBrand[brand] || 0) + 1;
  }
  const topBrands = Object.entries(byBrand).sort((a, b) => b[1] - a[1]);
  console.log("\nMissing vectors by brand (top 20):");
  for (const [brand, n] of topBrands.slice(0, 20)) console.log(`  ${String(n).padStart(5)}  ${brand}`);

  if (args.brands === "top") {
    // Most-common brands first — the bulk of the catalog embeds earliest.
    const rank = new Map(topBrands.map(([b], i) => [b, i]));
    missing.sort((a, b) => {
      const ra = rank.get(a.product?.brand || a.author || "unknown") ?? 1e9;
      const rb = rank.get(b.product?.brand || b.author || "unknown") ?? 1e9;
      return ra - rb;
    });
  }
  if (args.limit) missing = missing.slice(0, args.limit);

  // embed.mjs manifest shape (it fetches imageUrl when there's no s3Key).
  const manifest = missing.map((p) => ({
    id: p.postId || p.id,
    title: p.caption || p.product?.name || "",
    imageUrl: p.product?.image || p.image || p.imageUrl,
    link: p.productUrl || p.url || "",
    domain: p.domain || "",
    category: p.category || p.product?.category || "",
    recipient: p.recipient || "anyone",
    occasion: p.occasion || "any",
    source: p.source || "posts-backfill",
    sourceUser: p.author || "",
    ...(typeof p.product?.price === "number" && p.product.price > 0 ? { price: p.product.price } : {}),
  }));

  await writeFile(args.out, JSON.stringify(manifest, null, 2));
  console.log(`\n${manifest.length} posts → ${args.out}`);
  console.log(`Estimated one-time Bedrock cost: ~$${(manifest.length * 0.00006).toFixed(2)} on-demand`
    + ` (~$${(manifest.length * 0.00003).toFixed(2)} batch).`);
  console.log(`Next: node embed.mjs --manifest ${args.out}`);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
