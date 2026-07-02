// Catalog enrichment: pins -> structured PRODUCTS (AWS Bedrock Nova Lite).
//
// The scraped pins are links + images, not products. This backfill turns each
// feed-eligible pin into a catalog entry with structured, FILTERABLE attributes
// extracted from its image + title by a cheap multimodal model:
//   • productType   — canonical noun ("tote bag", "ceramic mug", "hoop earrings")
//   • color/colors  — primary + up to 4 palette color names
//   • materials     — up to 3 ("ceramic", "sterling silver", …)
//   • styles        — up to 4 taste tags ("minimal", "cottagecore", …)
//   • audience      — women | men | kids | any
//
// Written to BOTH stores so every surface benefits:
//   1. DynamoDB posts   — attrs map + top-level productType/color (feed, Maxi)
//   2. S3 Vectors       — re-put with merged metadata; productType/color are
//      FILTERABLE, enabling kNN like {productType $eq "tote bag", color $ne
//      "black"} = "same product, different colorway" (challenge deck twins).
//
// Idempotent + resumable: vectors already carrying productType are skipped
// (unless --force) and progress is checkpointed to .catalog-enrich.state.json.
//
// Usage:
//   set -a; source ../../.env; set +a     # AWS creds (SSO)
//   node catalog-enrich.mjs --limit 20 --dry-run   # preview, no writes
//   node catalog-enrich.mjs --limit 500            # enrich 500 pins
//   node catalog-enrich.mjs                        # everything eligible
//
// Config (env): VECTOR_BUCKET, VECTOR_INDEX, MEDIA_BUCKET, POSTS_TABLE,
// BEDROCK_ATTR_MODEL_ID (default us.amazon.nova-lite-v1:0), AWS_REGION.

import { readFile, writeFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { S3Client, GetObjectCommand } from "@aws-sdk/client-s3";
import { BedrockRuntimeClient, ConverseCommand } from "@aws-sdk/client-bedrock-runtime";
import {
  S3VectorsClient,
  ListVectorsCommand,
  GetVectorsCommand,
  PutVectorsCommand,
} from "@aws-sdk/client-s3vectors";
import { DynamoDBClient } from "@aws-sdk/client-dynamodb";
import { DynamoDBDocumentClient, UpdateCommand } from "@aws-sdk/lib-dynamodb";
import { classifyPin } from "../src/quality.mjs";

const __dirname = dirname(fileURLToPath(import.meta.url));

const REGION = process.env.AWS_REGION || "us-east-1";
const VECTOR_BUCKET = process.env.VECTOR_BUCKET || "giftmaxxing-dev-vectors";
const VECTOR_INDEX = process.env.VECTOR_INDEX || "pins";
const MEDIA_BUCKET = process.env.MEDIA_BUCKET || "giftmaxxing-dev-media";
const POSTS_TABLE = process.env.POSTS_TABLE || "giftmaxxing-dev-posts";
const MODEL = process.env.BEDROCK_ATTR_MODEL_ID || "us.amazon.nova-lite-v1:0";
const STATE_FILE = join(__dirname, ".catalog-enrich.state.json");

const s3 = new S3Client({ region: REGION });
const bedrock = new BedrockRuntimeClient({ region: REGION });
const s3v = new S3VectorsClient({ region: REGION });
const ddb = DynamoDBDocumentClient.from(new DynamoDBClient({ region: REGION }), {
  marshallOptions: { removeUndefinedValues: true },
});

const PROMPT = `You are a product cataloger. Look at the product image (and title) and return ONLY a JSON object, no prose, with these keys:
{
  "isProduct": boolean,            // false for collages, listicle covers, text graphics
  "productType": string,           // canonical noun phrase, lowercase, e.g. "tote bag", "ceramic mug", "hoop earrings"
  "primaryColor": string,          // single lowercase color word, e.g. "sage green" -> "green"
  "colors": [string],              // up to 4 palette color names, lowercase, dominant first
  "materials": [string],           // up to 3, lowercase, e.g. "ceramic", "leather"; [] if unclear
  "styles": [string],              // up to 4 aesthetic tags, lowercase, e.g. "minimal", "boho", "cottagecore", "luxe"
  "audience": "women"|"men"|"kids"|"any"
}`;

function parseArgs(argv) {
  const a = { limit: 0, dryRun: false, force: false, concurrency: 4, batch: 25 };
  for (let i = 0; i < argv.length; i++) {
    const x = argv[i];
    if (x === "--dry-run") a.dryRun = true;
    else if (x === "--force") a.force = true;
    else if (x === "--limit") a.limit = Number(argv[++i]);
    else if (x === "--concurrency") a.concurrency = Number(argv[++i]);
    else if (x === "--batch") a.batch = Number(argv[++i]);
  }
  return a;
}

async function streamToBuffer(stream) {
  const chunks = [];
  for await (const c of stream) chunks.push(c);
  return Buffer.concat(chunks);
}

// The CDN lies (webp behind .jpg URLs) — sniff the real format from magic bytes.
function sniffFormat(buf) {
  if (buf.length > 11 && buf.toString("ascii", 0, 4) === "RIFF" && buf.toString("ascii", 8, 12) === "WEBP") return "webp";
  if (buf[0] === 0x89 && buf[1] === 0x50) return "png";
  if (buf[0] === 0x47 && buf[1] === 0x49) return "gif";
  return "jpeg";
}

// Image bytes for a vector record: prefer our media-bucket copy, else the CDN.
async function imageBytes(meta) {
  if (meta.s3Key) {
    try {
      const out = await s3.send(new GetObjectCommand({ Bucket: MEDIA_BUCKET, Key: meta.s3Key }));
      const bytes = await streamToBuffer(out.Body);
      return { bytes, format: sniffFormat(bytes) };
    } catch {
      /* fall through to URL fetch */
    }
  }
  if (!meta.imageUrl) throw new Error("no image source");
  const res = await fetch(meta.imageUrl);
  if (!res.ok) throw new Error(`image HTTP ${res.status}`);
  const bytes = Buffer.from(await res.arrayBuffer());
  return { bytes, format: sniffFormat(bytes) };
}

// One Converse call -> parsed attrs object (throws on refusal/garbage).
async function extractAttrs(meta) {
  const { bytes, format } = await imageBytes(meta);
  const out = await bedrock.send(
    new ConverseCommand({
      modelId: MODEL,
      messages: [
        {
          role: "user",
          content: [
            { image: { format, source: { bytes } } },
            { text: `${PROMPT}\n\nTitle: ${(meta.title || "").slice(0, 200)}` },
          ],
        },
      ],
      inferenceConfig: { maxTokens: 300, temperature: 0 },
    })
  );
  const text = out.output?.message?.content?.map((c) => c.text ?? "").join("") ?? "";
  const jsonStr = text.slice(text.indexOf("{"), text.lastIndexOf("}") + 1);
  const raw = JSON.parse(jsonStr);
  const str = (v, n = 40) => String(v ?? "").toLowerCase().trim().slice(0, n);
  const list = (v, n) => (Array.isArray(v) ? v.map((x) => str(x)).filter(Boolean).slice(0, n) : []);
  return {
    isProduct: raw.isProduct !== false,
    productType: str(raw.productType, 60),
    primaryColor: str(raw.primaryColor, 24),
    colors: list(raw.colors, 4),
    materials: list(raw.materials, 3),
    styles: list(raw.styles, 4),
    audience: ["women", "men", "kids"].includes(str(raw.audience)) ? str(raw.audience) : "any",
  };
}

async function listAllVectors() {
  const all = [];
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
    all.push(...(out.vectors ?? []));
    nextToken = out.nextToken;
  } while (nextToken);
  return all;
}

async function loadState() {
  try {
    return JSON.parse(await readFile(STATE_FILE, "utf8"));
  } catch {
    return { done: {} };
  }
}

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

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const state = await loadState();

  console.log(`Listing vectors in ${VECTOR_BUCKET}/${VECTOR_INDEX}…`);
  const vectors = await listAllVectors();

  // Enrich only feed-eligible single products that aren't already attributed.
  let targets = vectors.filter((v) => {
    const m = v.metadata ?? {};
    if (!args.force && (m.productType || state.done[v.key])) return false;
    const q = classifyPin({ title: m.title, domain: m.domain, link: m.link || m.pinUrl, price: Number(m.price) || 0 });
    return q.feedEligible && (m.imageUrl || m.s3Key);
  });
  if (args.limit) targets = targets.slice(0, args.limit);
  console.log(`${vectors.length} vectors, ${targets.length} to enrich (model=${MODEL}).`);
  if (!targets.length) return;

  const enriched = [];
  let failed = 0,
    skippedNonProduct = 0;
  await pool(targets, args.concurrency, async (v) => {
    try {
      const attrs = await extractAttrs(v.metadata ?? {});
      if (!attrs.isProduct) {
        skippedNonProduct++;
        state.done[v.key] = "non-product";
        return;
      }
      enriched.push({ key: v.key, metadata: v.metadata ?? {}, attrs });
      if (enriched.length % 20 === 0) console.log(`  …extracted ${enriched.length}`);
    } catch (e) {
      failed++;
      console.warn(`  ! ${v.key}: ${e.message}`);
    }
  });
  console.log(`Extracted ${enriched.length} (failed ${failed}, non-product ${skippedNonProduct}).`);

  if (args.dryRun) {
    console.log("[dry-run] no writes. Sample:");
    for (const s of enriched.slice(0, 5)) {
      console.log(`  ${s.key}  ${JSON.stringify(s.attrs)}`);
    }
    return;
  }

  // 1) DynamoDB posts: attrs map + top-level filterable fields.
  let ddbWrites = 0;
  for (const e of enriched) {
    try {
      await ddb.send(
        new UpdateCommand({
          TableName: POSTS_TABLE,
          Key: { postId: e.key },
          UpdateExpression:
            "SET attrs = :a, productType = :t, color = :c, enrichedAt = :ts",
          ConditionExpression: "attribute_exists(postId)",
          ExpressionAttributeValues: {
            ":a": e.attrs,
            ":t": e.attrs.productType,
            ":c": e.attrs.primaryColor,
            ":ts": Date.now(),
          },
        })
      );
      ddbWrites++;
    } catch (err) {
      if (err?.name !== "ConditionalCheckFailedException") {
        console.warn(`  ! ddb ${e.key}: ${err.message}`);
      }
    }
  }
  console.log(`DynamoDB: updated ${ddbWrites}/${enriched.length} posts.`);

  // 2) S3 Vectors: re-put each vector (same key + data) with merged metadata.
  //    productType/color/styles land as FILTERABLE keys for variant queries.
  let vecWrites = 0;
  for (let i = 0; i < enriched.length; i += 20) {
    const chunk = enriched.slice(i, i + 20);
    const got = await s3v.send(
      new GetVectorsCommand({
        vectorBucketName: VECTOR_BUCKET,
        indexName: VECTOR_INDEX,
        keys: chunk.map((c) => c.key),
        returnData: true,
        returnMetadata: true,
      })
    );
    const byKey = new Map((got.vectors ?? []).map((v) => [v.key, v]));
    const puts = [];
    for (const e of chunk) {
      const v = byKey.get(e.key);
      if (!v?.data?.float32) continue;
      puts.push({
        key: e.key,
        data: { float32: v.data.float32 },
        metadata: {
          ...(v.metadata ?? {}),
          productType: e.attrs.productType,
          color: e.attrs.primaryColor,
          styles: e.attrs.styles.join(","),
        },
      });
    }
    if (puts.length) {
      await s3v.send(
        new PutVectorsCommand({
          vectorBucketName: VECTOR_BUCKET,
          indexName: VECTOR_INDEX,
          vectors: puts,
        })
      );
      vecWrites += puts.length;
      console.log(`  …re-put ${vecWrites}/${enriched.length} vectors`);
    }
    for (const e of chunk) state.done[e.key] = "ok";
    await writeFile(STATE_FILE, JSON.stringify(state) + "\n");
  }

  console.log(
    `\n✓ catalog enrichment: ${enriched.length} products attributed ` +
      `(${ddbWrites} posts, ${vecWrites} vectors). Re-run to continue where it left off.`
  );
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
