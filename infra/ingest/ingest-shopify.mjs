// Shopify storefront catalog ingester — the free product firehose.
//
// Every Shopify store publishes /products.json (title, price, availability,
// and the FULL image gallery) publicly — no API key, no approval. This pulls
// the curated stores in shopify-stores.json, quality-gates each product with
// classifyPin, and produces:
//
//   1. shopify.manifest.json — embed.mjs-compatible records (id/title/imageUrl/
//      link/domain/price/…), so `node embed.mjs --manifest shopify.manifest.json`
//      adds them to the S3 Vectors index (visual search + recs kNN). AWS-gated.
//   2. with --seed: DynamoDB posts via the admin /seed endpoint (same item
//      shape as ingest-pins.mjs, PLUS product.images — the carousel gallery).
//      Needs ADMIN_API_SECRET; no AWS credentials required.
//
// Data comes from each store's INTERNAL *.myshopify.com host (config `feed`):
// headless storefronts (Gymshark, Fashion Nova) block /products.json on their
// custom domain, but the internal address serves it. Outbound product links
// use the PUBLIC storefront (config `store`) so users land on the real site.
//
// Usage:
//   node ingest-shopify.mjs --discover https://brand.com   # find a brand's myshopify host
//   node ingest-shopify.mjs --dry-run                 # fetch + gate + report, write manifest only
//   node ingest-shopify.mjs --dry-run --store skims --limit 10
//   set -a; source ../../.env; set +a                 # ADMIN_API_SECRET (+ API_BASE optional)
//   node ingest-shopify.mjs --seed                    # manifest + POST /seed
//
// Flags: --discover <url> --dry-run --seed --limit N (per store)
//        --store <host substring> --out <path> --min-interval MS
//
// Politeness: one page per request (250 products), throttled, 429-aware;
// stores whose feed still fails are skipped with a tally.

import { readFile, writeFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { classifyPin } from "../src/quality.mjs";

const __dirname = dirname(fileURLToPath(import.meta.url));

const UA = "giftmaxxing-catalog-bot/1.0 (+https://giftmaxxing-web.vercel.app)";
const IMAGE_CAP = 8;
const PAGE_SIZE = 250;
const API_BASE = process.env.API_BASE || "https://tvyu8gqmki.execute-api.us-east-1.amazonaws.com";

function parseArgs(argv) {
  const a = { dryRun: false, seed: false, minInterval: 1200 };
  for (let i = 0; i < argv.length; i++) {
    const x = argv[i];
    if (x === "--dry-run") a.dryRun = true;
    else if (x === "--seed") a.seed = true;
    else if (x === "--limit") a.limit = Number(argv[++i]);
    else if (x === "--store") a.store = String(argv[++i] || "").toLowerCase();
    else if (x === "--out") a.out = argv[++i];
    else if (x === "--min-interval") a.minInterval = Number(argv[++i]) || 1200;
    else if (x === "--discover") a.discover = argv[++i];
  }
  return a;
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

const stripHtml = (s) =>
  String(s || "").replace(/<[^>]*>/g, " ").replace(/\s+/g, " ").trim();

const shortCaption = (title) => {
  const t = String(title || "").trim();
  return t.length <= 120 ? t : t.slice(0, 120).replace(/\s+\S*$/, "") + "...";
};

function priceTier(price) {
  if (typeof price !== "number" || price <= 0) return "unknown";
  if (price < 25) return "budget";
  if (price < 75) return "mid";
  if (price < 150) return "premium";
  return "luxury";
}

// Stable gradient per brand so cards look consistent.
const GRADS = ["peach", "rose", "butter", "lilac", "sky", "sage", "coral"];
function gradFor(s) {
  let h = 0;
  for (const c of String(s)) h = (h * 31 + c.charCodeAt(0)) >>> 0;
  return GRADS[h % GRADS.length];
}

// Shopify CDN images accept a width suffix — request a sane size, keep quality.
export function shopifyImage(src, width = 1200) {
  if (typeof src !== "string" || !/^https?:\/\//.test(src)) return null;
  const clean = src.split("?")[0];
  return `${clean}?width=${width}`;
}

// One Shopify product -> a quality-gated catalog record, or null.
export function mapProduct(product, storeCfg, host) {
  const variants = product.variants ?? [];
  const available = variants.some((v) => v?.available !== false);
  const price = Math.round(Number(variants[0]?.price) || 0);
  const images = (product.images ?? [])
    .map((i) => shopifyImage(i?.src))
    .filter(Boolean)
    .slice(0, IMAGE_CAP);
  if (!available || price <= 0 || !images.length) return null;

  const title = String(product.title || "").trim();
  const link = `${storeCfg.store.replace(/\/$/, "")}/products/${product.handle}`;
  const q = classifyPin({ title, domain: host, link, price });
  if (!q.feedEligible) return null;

  return {
    id: `shopify-${storeCfg.brand.toLowerCase().replace(/[^a-z0-9]+/g, "")}-${product.id}`,
    title,
    caption: shortCaption(title),
    blurb: stripHtml(product.body_html).slice(0, 200),
    brand: storeCfg.brand,
    price,
    category: storeCfg.category || String(product.product_type || "misc").toLowerCase(),
    vibes: storeCfg.vibes ?? [],
    link,
    domain: host,
    imageUrl: images[0],
    images,
    recipient: "anyone",
    occasion: "any",
    sourceUser: storeCfg.brand.toLowerCase(),
    source: "shopify",
    qualityScore: q.qualityScore,
  };
}

// Record -> DynamoDB post item (ingest-pins.mjs shape + product.images gallery).
export function recordToPostItem(rec, i = 0) {
  const grad = gradFor(rec.brand);
  // Spread synthetic timestamps (~12h apart) so the feed isn't one flat block
  // of same-brand cards (same trick as ingest-catalog.mjs).
  const createdAt = Date.now() - i * 12 * 3600 * 1000;
  return {
    postId: rec.id,
    feedPk: "all",
    author: `shopify_${rec.sourceUser}`,
    createdAt,
    likes: 0,
    comments: 0,
    caption: rec.caption,
    source: `Shopify/${rec.brand}`,
    url: rec.link,
    rec: true,
    reason: `${rec.brand} official store`,
    recipient: rec.recipient,
    occasion: rec.occasion,
    category: rec.category,
    vibes: rec.vibes,
    status: "find",
    priceTier: priceTier(rec.price),
    price: rec.price,
    priceDisplay: `$${rec.price}`,
    inStock: true,
    giftType: "product",
    merchant: rec.domain,
    domain: rec.domain,
    productUrl: rec.link,
    product: {
      id: rec.id,
      name: rec.caption,
      brand: rec.brand,
      price: rec.price,
      grad,
      emoji: "🛍️",
      image: rec.imageUrl,
      images: rec.images,
      url: rec.link,
    },
  };
}

// The user-taught discovery trick: a brand's page source references its
// internal *.myshopify.com host even when the storefront is headless.
async function discoverMyshopifyHost(brandUrl) {
  const res = await fetch(brandUrl, {
    headers: { "user-agent": UA, accept: "text/html" },
    redirect: "follow",
  });
  const html = await res.text();
  const counts = {};
  for (const m of html.matchAll(/([a-z0-9-]+\.myshopify\.com)/gi)) {
    counts[m[1].toLowerCase()] = (counts[m[1].toLowerCase()] ?? 0) + 1;
  }
  const best = Object.entries(counts).sort((a, b) => b[1] - a[1])[0];
  return best ? best[0] : null;
}

async function fetchStorePage(store, page) {
  const url = `${store.replace(/\/$/, "")}/products.json?limit=${PAGE_SIZE}&page=${page}`;
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 20000);
  try {
    let res = await fetch(url, {
      headers: { "user-agent": UA, accept: "application/json" },
      redirect: "follow",
      signal: controller.signal,
    });
    if (res.status === 429) {
      // Transient rate limit — one polite retry after the advertised delay.
      const wait = Math.min(Number(res.headers.get("retry-after")) || 5, 30);
      await sleep(wait * 1000);
      res = await fetch(url, {
        headers: { "user-agent": UA, accept: "application/json" },
        redirect: "follow",
      });
    }
    if (!res.ok) return { error: `HTTP ${res.status}` };
    const type = res.headers.get("content-type") || "";
    if (!type.includes("json")) return { error: `not json (${type.split(";")[0]})` };
    const json = await res.json();
    return { products: Array.isArray(json.products) ? json.products : [] };
  } catch (e) {
    return { error: e.name === "AbortError" ? "timeout" : e.message };
  } finally {
    clearTimeout(timer);
  }
}

async function main() {
  const args = parseArgs(process.argv.slice(2));

  if (args.discover) {
    const host = await discoverMyshopifyHost(args.discover);
    if (!host) {
      console.log(`${args.discover}: no myshopify.com reference found — probably not a Shopify store.`);
      process.exit(1);
    }
    console.log(`${args.discover} → feed host: https://${host}`);
    console.log(`Verify: curl -s "https://${host}/products.json?limit=2" | head -c 300`);
    return;
  }

  const cfg = JSON.parse(await readFile(join(__dirname, "shopify-stores.json"), "utf8"));
  let stores = cfg.stores ?? [];
  if (args.store) stores = stores.filter((s) => s.store.toLowerCase().includes(args.store));
  if (!stores.length) {
    console.error("No stores matched.");
    process.exit(1);
  }

  const records = [];
  const skipped = [];
  for (const storeCfg of stores) {
    const host = new URL(storeCfg.store).hostname.replace(/^www\./, "");
    const feedOrigin = storeCfg.feed || storeCfg.store; // internal myshopify host when set
    const cap = Math.min(args.limit || storeCfg.maxProducts || 150, 1000);
    let kept = 0;
    let dropped = 0;
    let page = 1;
    while (kept < cap) {
      const { products, error } = await fetchStorePage(feedOrigin, page);
      if (error) {
        if (page === 1) skipped.push({ host, error });
        else console.log(`  ${host} page ${page}: ${error} (stopping)`);
        break;
      }
      if (!products.length) break;
      for (const product of products) {
        if (kept >= cap) break;
        const rec = mapProduct(product, storeCfg, host);
        if (rec) {
          records.push(rec);
          kept++;
        } else {
          dropped++;
        }
      }
      page++;
      await sleep(args.minInterval);
    }
    if (kept) console.log(`${host}: kept ${kept}, gated out ${dropped}`);
  }

  if (skipped.length) {
    console.log("\nSkipped stores (no public products.json — headless/non-Shopify):");
    for (const s of skipped) console.log(`  ${s.host}: ${s.error}`);
  }

  const outPath = args.out || join(__dirname, "shopify.manifest.json");
  await writeFile(outPath, JSON.stringify(records, null, 2));
  console.log(`\n${records.length} products → ${outPath}`);
  console.log("Next: node embed.mjs --manifest shopify.manifest.json   (vectors; needs AWS creds)");

  if (records.length && args.seed && !args.dryRun) {
    const posts = records.map(recordToPostItem);
    console.log(`Seeding ${posts.length} posts via ${API_BASE}/seed …`);
    let seeded = 0;
    for (let i = 0; i < posts.length; i += 25) {
      const batch = posts.slice(i, i + 25);
      const res = await fetch(`${API_BASE}/seed`, {
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
  } else if (args.seed && args.dryRun) {
    console.log("[dry-run] skipping /seed. Sample post item:");
    console.log(JSON.stringify(recordToPostItem(records[0] ?? {}, 0), null, 2).slice(0, 800));
  }
}

if (import.meta.url === `file://${process.argv[1]}`) {
  main().catch((e) => {
    console.error(e);
    process.exit(1);
  });
}
