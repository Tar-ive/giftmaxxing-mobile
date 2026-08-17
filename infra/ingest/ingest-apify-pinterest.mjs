// Apify Pinterest dataset -> quality report -> S3-backed editorial carousels.
// Dry-run by default. Pass --apply to upload accepted images and upsert DynamoDB.

import { mkdir, readFile, writeFile } from "node:fs/promises";
import { dirname, extname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const CDN = "https://d21osnvwewgoao.cloudfront.net";
const DEFAULT_TABLE = "giftmaxxing-dev-posts";
const DEFAULT_CONFIG = "giftmaxxing-dev-config";
const BLOCKED_HOSTS = /(^|\.)(instagram|facebook|tiktok|twitter|x|medium|linktr\.ee|blogspot)\.com$/i;
const GIFT = /\b(gift|present|birthday|anniversary|valentine|mother|father|mom|dad|bestie|friend|boyfriend|girlfriend|husband|wife|basket|bouquet|wrapp?ing|surprise)\b/i;
const ACTIONABLE = /\b(diy|personal|custom|photo|memory|collage|letter|keepsake|handmade|self[ -]?care|journal|basket|bouquet|wrap|experience|ritual|recipe|box)\b/i;
const LISTICLE = /(^|\b)\d{2,}\+?\s|\b(gift ideas|gift guide|ultimate guide|tap to|click to|actually wants?)\b/i;
const SALES_COPY = /\b(shop now|limited time|sale ends|free shipping|buy now)\b/i;

export const carouselSpecs = [
  {
    slug: "birthday-gifts-that-feel-personal",
    title: "6 birthday gifts that feel deeply personal",
    caption: "The best birthday gifts prove you noticed. Swipe for six ways to turn memories, favorites, and inside jokes into something they’ll keep.",
    queries: [0, 1], recipient: "friend", occasion: "birthday", category: "diy",
    vibes: ["sentimental", "personalized", "bestie"],
  },
  {
    slug: "build-a-better-gift-basket",
    title: "Build a gift basket that doesn’t feel random",
    caption: "Use one comfort, one treat, one useful item, one personal detail, and a handwritten note. Swipe for combinations that feel intentional.",
    queries: [2], recipient: "anyone", occasion: "any", category: "wellness",
    vibes: ["cozy", "curated", "thoughtful"],
  },
  {
    slug: "personalized-gifts-for-your-partner",
    title: "Personalized gifts for your partner",
    caption: "Skip generic romance. Build the gift around a shared memory, their daily ritual, or a future plan you’re excited about together.",
    queries: [3, 4], recipient: "partner", occasion: "anniversary", category: "art",
    vibes: ["romantic", "personalized", "sentimental"],
  },
  {
    slug: "meaningful-gifts-for-parents",
    title: "Meaningful gifts for Mom and Dad",
    caption: "The strongest parent gifts preserve a story, remove a small annoyance, or create time together. Swipe for ideas with a reason behind them.",
    queries: [5, 6], recipient: "parent", occasion: "any", category: "gifts",
    vibes: ["meaningful", "useful", "family"],
  },
  {
    slug: "gift-wrapping-worth-keeping",
    title: "Gift wrapping worth keeping",
    caption: "Make opening part of the gift: add texture, one personal detail, and a clear focal point. These ideas turn the reveal into a memory.",
    queries: [7], recipient: "anyone", occasion: "any", category: "diy",
    vibes: ["creative", "handmade", "aesthetic"],
  },
];

function argsOf(argv) {
  const args = { apply: false, perCarousel: 6, minScore: 54, region: process.env.AWS_REGION || "us-east-1" };
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    if (arg === "--apply") args.apply = true;
    else if (arg === "--run") args.runId = argv[++i];
    else if (arg === "--dataset") args.datasetId = argv[++i];
    else if (arg === "--file") args.file = resolve(argv[++i]);
    else if (arg === "--picks") args.picks = resolve(argv[++i]);
    else if (arg === "--report") args.report = resolve(argv[++i]);
    else if (arg === "--per-carousel") args.perCarousel = Number(argv[++i]);
    else if (arg === "--min-score") args.minScore = Number(argv[++i]);
    else if (arg === "--bucket") args.bucket = argv[++i];
    else if (arg === "--table") args.table = argv[++i];
    else if (arg === "--config-table") args.configTable = argv[++i];
  }
  if (!args.runId && !args.datasetId && !args.file) throw new Error("Pass --run, --dataset, or --file");
  return args;
}

const getJson = async (url) => {
  const response = await fetch(url);
  if (!response.ok) throw new Error(`${url} -> HTTP ${response.status}`);
  return response.json();
};

async function loadRun(args) {
  if (args.file) {
    return { items: JSON.parse(await readFile(args.file, "utf8")), datasetId: args.datasetId || "local", queries: [] };
  }
  let { runId, datasetId } = args;
  let queries = [];
  let maxPins = 0;
  if (runId) {
    const run = (await getJson(`https://api.apify.com/v2/actor-runs/${runId}`)).data;
    if (run.status !== "SUCCEEDED") throw new Error(`Apify run ${runId} is ${run.status}`);
    datasetId ||= run.defaultDatasetId;
    const input = await getJson(`https://api.apify.com/v2/key-value-stores/${run.defaultKeyValueStoreId}/records/INPUT`);
    queries = input.searchQueries || [];
    maxPins = Number(input.maxPins) || 0;
  }
  const items = await getJson(`https://api.apify.com/v2/datasets/${datasetId}/items?clean=true&format=json&limit=1000`);
  return { items, runId, datasetId, queries, maxPins };
}

const hostOf = (pin) => {
  try { return new URL(pin.link || pin.url).hostname.replace(/^www\./, ""); }
  catch { return String(pin.domain || "").replace(/^www\./, ""); }
};

export function scorePin(pin) {
  const reasons = [];
  if (!pin?.id) return { score: 0, accepted: false, reasons: ["missing_id"] };
  if (!/^https:\/\//.test(pin.imageUrl || "")) return { score: 0, accepted: false, reasons: ["missing_image"] };
  if (pin.isVideo) return { score: 0, accepted: false, reasons: ["video"] };
  const title = String(pin.title || "").replace(/\s+/g, " ").trim();
  const text = `${title} ${pin.description || ""} ${pin.altText || ""}`;
  const host = hostOf(pin);
  let score = 30;
  if (GIFT.test(text)) { score += 18; reasons.push("gift_intent"); }
  if (ACTIONABLE.test(text)) { score += 15; reasons.push("actionable"); }
  const saves = Math.max(0, Number(pin.saves) || 0);
  score += Math.min(25, Math.log10(saves + 1) * 10);
  score += Math.min(7, Math.log10(Math.max(0, Number(pin.pinnerFollowers) || 0) + 1) * 3);
  if (pin.link && !/pinterest\.com/i.test(pin.link)) { score += 5; reasons.push("outbound_link"); }
  if (!title) { score -= 12; reasons.push("blank_title"); }
  if (title.length > 170) { score -= 10; reasons.push("product_title_spam"); }
  if (LISTICLE.test(text)) { score -= 18; reasons.push("listicle"); }
  if (SALES_COPY.test(text)) { score -= 12; reasons.push("sales_copy"); }
  if (BLOCKED_HOSTS.test(host)) { score -= 25; reasons.push("blocked_host"); }
  return { score: Math.round(Math.max(0, Math.min(100, score))), accepted: score >= 54, reasons };
}

const labelFor = (pin) => {
  const raw = String(pin.title || pin.altText || pin.description || "Thoughtful gift idea").replace(/\s+/g, " ").trim();
  const clean = raw.split("|")[0].replace(/\s+#\w.*$/, "").trim();
  return clean.length <= 82 ? clean : clean.slice(0, 82).replace(/\s+\S*$/, "") + "…";
};

export function curate(items, { queries = [], maxPins = 0, perCarousel = 6, minScore = 54, picks = null } = {}) {
  const seenIds = new Set();
  const seenImages = new Set();
  const enriched = items.map((pin, index) => {
    const queryIndex = maxPins ? Math.floor(index / maxPins) : null;
    let quality = scorePin(pin);
    if (seenIds.has(pin.id) || seenImages.has(pin.imageUrl)) {
      quality = { score: 0, accepted: false, reasons: ["duplicate_result"] };
    } else {
      seenIds.add(pin.id); seenImages.add(pin.imageUrl);
    }
    return { ...pin, datasetIndex: index, queryIndex, query: queries[queryIndex] || null, quality };
  });
  const usedImages = new Set();
  const byId = new Map();
  for (const pin of enriched) if (!byId.has(String(pin.id))) byId.set(String(pin.id), pin);
  const carousels = carouselSpecs.map((spec) => {
    const manualIds = picks?.[spec.slug];
    const source = Array.isArray(manualIds)
      ? manualIds.map((id) => byId.get(String(id))).filter((pin) => pin?.quality.score > 0)
      : enriched
        .filter((pin) => spec.queries.includes(pin.queryIndex) && pin.quality.score >= minScore)
        .sort((a, b) => b.quality.score - a.quality.score || (b.saves || 0) - (a.saves || 0));
    const pinners = new Set();
    const selected = [];
    for (const pin of source) {
      const pinner = String(pin.pinnerUsername || "unknown").toLowerCase();
      if (usedImages.has(pin.imageUrl) || (!manualIds && pinners.has(pinner))) continue;
      usedImages.add(pin.imageUrl); pinners.add(pinner); selected.push(pin);
      if (selected.length === perCarousel) break;
    }
    return { ...spec, selected };
  });
  const accepted = carousels.flatMap((c) => c.selected);
  const acceptedIndexes = new Set(accepted.map((pin) => pin.datasetIndex));
  const rejected = enriched.filter((pin) => !acceptedIndexes.has(pin.datasetIndex));
  return { carousels, accepted, rejected };
}

const extFor = (type, url) => {
  if (/png/i.test(type)) return ".png";
  if (/webp/i.test(type)) return ".webp";
  const ext = extname(new URL(url).pathname).toLowerCase();
  return [".jpg", ".jpeg", ".png", ".webp"].includes(ext) ? ext : ".jpg";
};

async function uploadSelections(result, { bucket, region, datasetId }) {
  const { PutObjectCommand, S3Client } = await import("@aws-sdk/client-s3");
  const s3 = new S3Client({ region });
  for (const carousel of result.carousels) {
    for (const pin of carousel.selected) {
      const response = await fetch(pin.imageUrl);
      const type = response.headers.get("content-type") || "";
      if (!response.ok || !type.startsWith("image/")) throw new Error(`Image ${pin.id} -> HTTP ${response.status}`);
      const key = `ugc/public/editorial/pinterest/${datasetId}/${carousel.slug}/${pin.id}${extFor(type, pin.imageUrl)}`;
      await s3.send(new PutObjectCommand({
        Bucket: bucket, Key: key, Body: Buffer.from(await response.arrayBuffer()), ContentType: type,
        CacheControl: "public,max-age=31536000,immutable",
        Metadata: { "source-pin": pin.id, "source-user": String(pin.pinnerUsername || "unknown") },
      }));
      pin.originalImageUrl = pin.imageUrl;
      pin.imageUrl = `${CDN}/${key}`;
      pin.s3Key = key;
    }
  }
  const reportKey = `ingest/apify/pinterest/${datasetId}/curation.json`;
  await s3.send(new PutObjectCommand({
    Bucket: bucket, Key: reportKey, Body: JSON.stringify(result), ContentType: "application/json",
  }));
  return reportKey;
}

function postsFor(result, provenance) {
  const now = Date.now();
  return result.carousels.filter((c) => c.selected.length >= 2).map((c, index) => ({
    postId: `carousel-${c.slug}-v1`, feedPk: "all", author: "giftmaxxing",
    createdAt: now - index * 1_000, likes: 0, comments: 0, caption: c.caption,
    source: `Apify/Pinterest · dataset ${provenance.datasetId}`, rec: true,
    reason: "Curated gift-giving inspiration", recipient: c.recipient, occasion: c.occasion,
    category: c.category, vibes: c.vibes, status: "find", priceTier: "unknown", price: 0,
    contentType: "gift_guide", feedEligible: true, qualityScore: 0.9,
    carouselSlides: c.selected.map((pin, slide) => ({
      index: slide, label: labelFor(pin), imageUrl: pin.imageUrl, s3Key: pin.s3Key || null,
      sourceUrl: pin.url, sourceCreator: pin.pinnerName || pin.pinnerUsername || "Pinterest",
      sourceDomain: pin.domain || null, qualityScore: pin.quality.score,
    })),
    apify: { actor: "automation-lab/pinterest-scraper", ...provenance },
    product: {
      id: `carousel-${c.slug}-v1`, name: c.title, brand: "Giftmaxxing", price: 0,
      grad: "rose", emoji: "🎁", image: c.selected[0].imageUrl,
      images: c.selected.slice(1).map((pin) => pin.imageUrl),
    },
  }));
}

async function persist(posts, args) {
  const { DynamoDBClient } = await import("@aws-sdk/client-dynamodb");
  const { BatchWriteCommand, DynamoDBDocumentClient, GetCommand, PutCommand } = await import("@aws-sdk/lib-dynamodb");
  const ddb = DynamoDBDocumentClient.from(new DynamoDBClient({ region: args.region }));
  const table = args.table || process.env.POSTS_TABLE || DEFAULT_TABLE;
  const configTable = args.configTable || process.env.CONFIG_TABLE || DEFAULT_CONFIG;
  await ddb.send(new BatchWriteCommand({ RequestItems: { [table]: posts.map((Item) => ({ PutRequest: { Item } })) } }));
  const key = "featured#feed";
  const current = (await ddb.send(new GetCommand({ TableName: configTable, Key: { key } }))).Item || { key };
  const ids = [...posts.map((post) => post.postId), ...(current.itemIds || [])];
  await ddb.send(new PutCommand({
    TableName: configTable,
    Item: { ...current, key, itemIds: [...new Set(ids)].slice(0, 10), label: "Featured gift carousels", updatedAt: Date.now() },
  }));
}

async function main() {
  const args = argsOf(process.argv.slice(2));
  const run = await loadRun(args);
  const picks = args.picks ? JSON.parse(await readFile(args.picks, "utf8")) : null;
  const result = curate(run.items, { ...run, picks, perCarousel: args.perCarousel, minScore: args.minScore });
  const summary = {
    runId: run.runId || null, datasetId: run.datasetId, scraped: run.items.length,
    accepted: result.accepted.length, rejected: result.rejected.length,
    carousels: result.carousels.map((c) => ({ slug: c.slug, slides: c.selected.length })),
    rejectionReasons: Object.entries(result.rejected
      .flatMap((p) => p.quality.reasons)
      .filter((reason) => ["duplicate_result", "video", "missing_image", "missing_id", "listicle", "blocked_host", "sales_copy", "blank_title", "product_title_spam"].includes(reason))
      .reduce((a, reason) => ({ ...a, [reason]: (a[reason] || 0) + 1 }), {}))
      .sort((a, b) => b[1] - a[1]),
  };
  if (args.apply) {
    const bucket = args.bucket || process.env.MEDIA_BUCKET || "giftmaxxing-dev-media";
    summary.reportKey = await uploadSelections(result, { ...args, bucket, datasetId: run.datasetId });
    const posts = postsFor(result, { runId: run.runId || null, datasetId: run.datasetId, scrapedAt: new Date().toISOString() });
    await persist(posts, args);
    summary.seeded = posts.length;
  }
  if (args.report) {
    await mkdir(dirname(args.report), { recursive: true });
    await writeFile(args.report, JSON.stringify({ summary, result }, null, 2) + "\n");
  }
  console.log(JSON.stringify(summary, null, 2));
  if (!args.apply) console.log("Dry run only; pass --apply to upload and seed.");
}

if (resolve(process.argv[1] || "") === fileURLToPath(import.meta.url)) {
  main().catch((error) => { console.error(error); process.exit(1); });
}
