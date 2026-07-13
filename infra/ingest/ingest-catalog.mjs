// Curated "basics" catalog (products + gift-able services) -> the full pipeline:
//   catalog-basics.json -> [optional image -> S3 media] -> Titan Multimodal embed
//   (image+text, or TEXT-ONLY for items without an image — same shared space)
//   -> S3 Vectors put-vectors (metadata carries giftType) -> DynamoDB posts via
//   the /seed API endpoint (same item shape as ingest-pins.mjs).
//
// Services (giftType "service", category "services") power the product-vs-service
// taste split: the challenge deck mixes them in (handler.mjs buildChallengeDeck)
// and swipes on them feed verdict.giftTypeSplit + the iOS giftTypeAffinity.
//
// Usage:
//   set -a; source ../../.env; set +a         # AWS creds + ADMIN_API_SECRET
//   node ingest-catalog.mjs --dry-run          # print vectors + posts, no writes
//   node ingest-catalog.mjs --limit 5          # first 5 items only
//   node ingest-catalog.mjs --skip-existing    # don't re-embed keys already indexed
//   node ingest-catalog.mjs --no-posts         # vectors only (skip /seed)
//   node ingest-catalog.mjs --no-vectors       # posts only (skip Bedrock/S3 Vectors)
//   node ingest-catalog.mjs --images-dir ./img # use ./img/<id>.jpg|png when present
//
// Config (env): MEDIA_BUCKET, VECTOR_BUCKET, VECTOR_INDEX, VECTOR_DIM,
// BEDROCK_EMBED_MODEL_ID, AWS_REGION, API_BASE or NEXT_PUBLIC_API_URL,
// ADMIN_API_SECRET (when API auth is enforced).

import { readFile, readdir } from "node:fs/promises";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { S3Client, PutObjectCommand } from "@aws-sdk/client-s3";
import { BedrockRuntimeClient, InvokeModelCommand } from "@aws-sdk/client-bedrock-runtime";
import { S3VectorsClient, PutVectorsCommand, GetVectorsCommand } from "@aws-sdk/client-s3vectors";

const __dirname = dirname(fileURLToPath(import.meta.url));

const REGION = process.env.AWS_REGION || "us-east-1";
const MEDIA_BUCKET = process.env.MEDIA_BUCKET || "giftmaxxing-dev-media";
const VECTOR_BUCKET = process.env.VECTOR_BUCKET || "giftmaxxing-dev-vectors";
const VECTOR_INDEX = process.env.VECTOR_INDEX || "pins";
const DIM = Number(process.env.VECTOR_DIM || 1024);
const MODEL = process.env.BEDROCK_EMBED_MODEL_ID || "amazon.titan-embed-image-v1";

const s3 = new S3Client({ region: REGION });
const bedrock = new BedrockRuntimeClient({ region: REGION });
const s3v = new S3VectorsClient({ region: REGION });

function parseArgs(argv) {
  const a = {
    dryRun: false,
    limit: 0,
    skipExisting: false,
    noVectors: false,
    noPosts: false,
    batch: 25,
    concurrency: 4,
  };
  for (let i = 0; i < argv.length; i++) {
    const x = argv[i];
    if (x === "--dry-run") a.dryRun = true;
    else if (x === "--limit") a.limit = Number(argv[++i]);
    else if (x === "--skip-existing") a.skipExisting = true;
    else if (x === "--no-vectors") a.noVectors = true;
    else if (x === "--no-posts") a.noPosts = true;
    else if (x === "--file") a.file = argv[++i];
    else if (x === "--images-dir") a.imagesDir = argv[++i];
    else if (x === "--api") a.api = argv[++i];
  }
  return a;
}

const chunk = (arr, n) =>
  Array.from({ length: Math.ceil(arr.length / n) }, (_, i) => arr.slice(i * n, i * n + n));

async function pool(items, size, worker) {
  let i = 0;
  await Promise.all(
    Array.from({ length: Math.min(size, items.length) }, async () => {
      while (i < items.length) {
        const idx = i++;
        await worker(items[idx], idx);
      }
    })
  );
}

// ── Images (optional): local file or remote URL -> S3 media bucket ──────────
// Items without an image embed TEXT-ONLY (same Titan shared space) and render
// as branded gradient cards client-side, so nothing here is required.
async function resolveImage(item, imagesDir, dryRun) {
  let buf = null;
  let ext = "jpg";
  if (imagesDir) {
    try {
      const files = await readdir(imagesDir);
      const hit = files.find((f) => f.replace(/\.(jpe?g|png)$/i, "") === item.id);
      if (hit) {
        buf = await readFile(join(imagesDir, hit));
        ext = /\.png$/i.test(hit) ? "png" : "jpg";
      }
    } catch {
      // images dir missing/unreadable -> fall through
    }
  }
  if (!buf && item.imageUrl && /^https?:\/\//.test(item.imageUrl)) {
    const res = await fetch(item.imageUrl);
    if (!res.ok) throw new Error(`image ${item.imageUrl} -> HTTP ${res.status}`);
    buf = Buffer.from(await res.arrayBuffer());
    ext = /\.png(\?|$)/i.test(item.imageUrl) ? "png" : "jpg";
  }
  if (!buf) return { b64: null, s3Key: "", imageUrl: item.imageUrl || "" };

  const s3Key = `catalog/${item.id}.${ext}`;
  if (!dryRun) {
    await s3.send(
      new PutObjectCommand({
        Bucket: MEDIA_BUCKET,
        Key: s3Key,
        Body: buf,
        ContentType: ext === "png" ? "image/png" : "image/jpeg",
      })
    );
  }
  return { b64: buf.toString("base64"), s3Key, imageUrl: item.imageUrl || "" };
}

// One shared-space vector. Image+text when an image exists, else text-only —
// Titan Multimodal accepts either input alone (embed.mjs uses image+title).
async function embed(item, imageB64) {
  const text = [item.name, item.serviceDuration, item.caption]
    .filter(Boolean)
    .join(". ")
    .slice(0, 200); // Titan MM text cap
  const body = { embeddingConfig: { outputEmbeddingLength: DIM } };
  if (imageB64) body.inputImage = imageB64;
  if (text) body.inputText = text;
  const out = await bedrock.send(
    new InvokeModelCommand({
      modelId: MODEL,
      contentType: "application/json",
      accept: "application/json",
      body: JSON.stringify(body),
    })
  );
  const { embedding } = JSON.parse(Buffer.from(out.body).toString("utf8"));
  return embedding;
}

// Which of these keys are already in the index (for --skip-existing).
async function existingKeys(keys) {
  const found = new Set();
  for (const c of chunk(keys, 20)) {
    try {
      const res = await s3v.send(
        new GetVectorsCommand({
          vectorBucketName: VECTOR_BUCKET,
          indexName: VECTOR_INDEX,
          keys: c,
          returnData: false,
          returnMetadata: false,
        })
      );
      for (const v of res.vectors ?? []) found.add(v.key);
    } catch (e) {
      console.warn(`  ! existing-key check failed (${e.message}) — treating batch as new`);
    }
  }
  return found;
}

// ── DynamoDB post item (same shape ingest-pins.mjs writes; /seed adds feedPk) ─
function priceTier(price) {
  if (typeof price !== "number" || price <= 0) return "unknown";
  if (price < 25) return "budget";
  if (price < 75) return "mid";
  if (price < 150) return "premium";
  return "luxury";
}

function catalogPostItem(item, media, i) {
  const isService = item.giftType === "service";
  // Spread createdAt over ~7 weeks (36h apart). The first seeding used minutes,
  // which made every catalog item the NEWEST post — the recency-ordered byFeed
  // GSI then served an unbroken wall of same-author catalog cards before any
  // real pin. Catalog basics are evergreen; they should blend into the feed's
  // window, not own its head. Re-running ingest overwrites the same postIds,
  // so this also repairs an already-seeded table.
  const createdAt = Date.now() - (i + 1) * 36 * 3600 * 1000;
  return {
    postId: item.id,
    author: "giftmaxxing_catalog",
    createdAt,
    likes: 30 + ((i * 17) % 60),
    comments: 0,
    caption: item.caption || item.name,
    source: "Giftmaxxing/catalog",
    url: item.link,
    rec: true,
    reason: isService ? "A year of something they love" : "A classic they'd never buy themselves",
    recipient: item.recipient || "anyone",
    occasion: item.occasion || "any",
    category: item.category,
    vibes: Array.isArray(item.vibes) ? item.vibes : [],
    status: "find",
    priceTier: priceTier(item.price),
    price: item.price,
    priceDisplay: item.price > 0 ? `$${item.price}` : null,
    merchant: item.brand,
    domain: item.domain || null,
    productUrl: item.link,
    giftType: item.giftType || "product",
    ...(item.serviceDuration ? { serviceDuration: item.serviceDuration } : {}),
    product: {
      id: item.id,
      name: item.name,
      brand: item.brand,
      price: item.price,
      grad: item.grad || "peach",
      emoji: item.emoji || (isService ? "🎟️" : "🎁"),
      image: media.imageUrl || null,
      url: item.link,
    },
  };
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const file = args.file ? resolve(process.cwd(), args.file) : join(__dirname, "catalog-basics.json");
  const parsed = JSON.parse(await readFile(file, "utf8"));
  let items = Array.isArray(parsed) ? parsed : parsed.items;
  if (!Array.isArray(items)) throw new Error(`${file}: expected { items: [...] }`);
  if (args.limit) items = items.slice(0, args.limit);

  const services = items.filter((it) => it.giftType === "service").length;
  console.log(
    `Catalog: ${items.length} items (${items.length - services} products, ${services} services)`
  );

  let skip = new Set();
  if (args.skipExisting && !args.noVectors) {
    skip = await existingKeys(items.map((it) => it.id));
    if (skip.size) console.log(`--skip-existing: ${skip.size} already indexed`);
  }

  // ── Embed + collect (vectors) and transform (posts) ───────────────────────
  const vectors = [];
  const mediaById = new Map();
  let embedded = 0;
  let textOnly = 0;
  let failed = 0;

  if (!args.noVectors) {
    const todo = items.filter((it) => !skip.has(it.id));
    console.log(`Embedding ${todo.length} items (model=${MODEL}, dim=${DIM})…`);
    await pool(todo, args.concurrency, async (item) => {
      try {
        const media = await resolveImage(item, args.imagesDir, args.dryRun);
        mediaById.set(item.id, media);
        if (!media.b64) textOnly++;
        const embedding = await embed(item, media.b64);
        vectors.push({
          key: item.id,
          data: { float32: embedding },
          metadata: {
            title: item.name,
            imageUrl: media.imageUrl,
            s3Key: media.s3Key,
            sourceUser: "giftmaxxing",
            source: "catalog",
            link: item.link ?? "",
            domain: item.domain ?? "",
            category: item.category ?? "",
            recipient: item.recipient ?? "anyone",
            occasion: item.occasion ?? "any",
            giftType: item.giftType || "product",
            ...(item.serviceDuration ? { serviceDuration: item.serviceDuration } : {}),
            ...(typeof item.price === "number" && item.price > 0 ? { price: item.price } : {}),
          },
        });
        if (++embedded % 10 === 0) console.log(`  …embedded ${embedded}`);
      } catch (e) {
        failed++;
        console.warn(`  ! ${item.id}: ${e.message}`);
      }
    });
    console.log(`Embedded ${vectors.length} (${textOnly} text-only, failed ${failed}).`);
  }

  const posts = items.map((it, i) => catalogPostItem(it, mediaById.get(it.id) ?? { imageUrl: it.imageUrl || "" }, i));

  if (args.dryRun) {
    console.log("\n[dry-run] no writes. Sample vector metadata + post item:");
    const v = vectors[0];
    if (v) console.log(JSON.stringify({ key: v.key, dims: v.data.float32.length, metadata: v.metadata }, null, 2));
    console.log(JSON.stringify(posts.find((p) => p.giftType === "service") ?? posts[0], null, 2));
    return;
  }

  // ── PutVectors ─────────────────────────────────────────────────────────────
  if (!args.noVectors && vectors.length) {
    let put = 0;
    for (const c of chunk(vectors, args.batch)) {
      await s3v.send(
        new PutVectorsCommand({ vectorBucketName: VECTOR_BUCKET, indexName: VECTOR_INDEX, vectors: c })
      );
      put += c.length;
      console.log(`  …put ${put}/${vectors.length} vectors`);
    }
    console.log(`✓ upserted ${put} vectors into ${VECTOR_BUCKET}/${VECTOR_INDEX}`);
  }

  // ── Seed posts via the API (admin-gated when AUTH_ENFORCE=1) ───────────────
  if (!args.noPosts) {
    const apiBase =
      args.api ||
      process.env.API_BASE ||
      process.env.NEXT_PUBLIC_API_URL ||
      "https://tvyu8gqmki.execute-api.us-east-1.amazonaws.com";
    console.log(`Seeding ${posts.length} catalog posts via ${apiBase}/seed …`);
    let seeded = 0;
    for (const batch of chunk(posts, 25)) {
      const res = await fetch(`${apiBase}/seed`, {
        method: "POST",
        headers: {
          "content-type": "application/json",
          ...(process.env.ADMIN_API_SECRET ? { "x-admin-token": process.env.ADMIN_API_SECRET } : {}),
        },
        body: JSON.stringify({ posts: batch }),
      });
      if (!res.ok) throw new Error(`/seed -> HTTP ${res.status}: ${await res.text()}`);
      seeded += batch.length;
      console.log(`  …seeded ${seeded}/${posts.length}`);
    }
    console.log(`✓ ingested ${seeded} catalog items into the feed.`);
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
