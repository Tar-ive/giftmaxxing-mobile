// Enrich posts with the FULL product-page image gallery.
//
// Our scraped pins carry exactly one image, but the retailer listing behind
// them (eBay/Etsy/…) usually has 5-10 shots — the iOS detail sheet renders
// them as a swipeable carousel once `product.images` exists on the row.
//
// For each Pinterest-imported post with a shoppable productUrl, this fetches
// the product page (politely: throttled, UA'd, timeout) and extracts gallery
// image URLs from, in order of trust:
//   1. JSON-LD `Product.image` (string or array) — most retailers emit this
//   2. eBay CDN references (i.ebayimg.com/…/s-l64.jpg → upgraded to s-l1600)
//   3. Etsy CDN references (i.etsystatic.com il_75x75… → upgraded to il_1588xN)
//   4. og:image metas (often several)
// then writes the deduped list (cap 8) to `product.images` on the posts row.
// The existing single `product.image` stays the cover everywhere.
//
// Usage:
//   node enrich-images.mjs --url "https://www.ebay.com/itm/…"   # offline: print one page's gallery
//   node enrich-images.mjs --dry-run --limit 20                 # scan table, fetch, print, no writes
//   node enrich-images.mjs                                      # enrich all un-enriched posts
//   node enrich-images.mjs --force                              # re-fetch even already-enriched rows
//
// Flags: --table --region --limit N --min-interval MS --only-domain a,b
//        --dry-run --force --url <productUrl>
//
// Config (env): POSTS_TABLE, AWS_REGION + standard AWS credential chain.
// Re-running is idempotent: rows with `product.images` are skipped sans --force.

const UA =
  "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36";
const IMAGE_CAP = 8;

function parseArgs(argv) {
  const args = { dryRun: false, force: false, minInterval: 1500 };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === "--dry-run") args.dryRun = true;
    else if (a === "--force") args.force = true;
    else if (a === "--limit") args.limit = Number(argv[++i]);
    else if (a === "--min-interval") args.minInterval = Number(argv[++i]) || 1500;
    else if (a === "--table") args.table = argv[++i];
    else if (a === "--region") args.region = argv[++i];
    else if (a === "--url") args.url = argv[++i];
    else if (a === "--only-domain")
      args.onlyDomain = String(argv[++i] || "").split(",").map((s) => s.trim()).filter(Boolean);
  }
  return args;
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

function isPinterestImport(p) {
  const author = String(p.author || "");
  const source = String(p.source || "");
  return author.startsWith("pinterest_") || source.startsWith("Pinterest/");
}

// ── Extraction ────────────────────────────────────────────────────────────────

function normalizeImageUrl(u) {
  if (typeof u !== "string") return null;
  let s = u.trim().replace(/&amp;/g, "&");
  if (s.startsWith("//")) s = "https:" + s;
  if (!/^https?:\/\//i.test(s)) return null;
  // CDN upgrades: thumbnails → the largest rendition the CDN serves.
  s = s.replace(/(i\.ebayimg\.com\/[^"' ]*\/s-l)\d+(\.\w+)/i, "$11600$2");
  s = s.replace(/(i\.etsystatic\.com\/[^"' ]*\/il_)(?:\d+x\d+|fullxfull)\./i, "$11588xN.");
  return s.length <= 500 ? s : null;
}

// Real product shots only — sprites, favicons, tracking pixels add noise.
function looksLikeProductImage(u) {
  if (/\.(svg|gif)(\?|$)/i.test(u)) return false;
  if (/(sprite|favicon|logo|icon|badge|pixel|placeholder|avatar)/i.test(u)) return false;
  return true;
}

function extractJsonLdImages(html) {
  const out = [];
  const scripts = html.matchAll(
    /<script[^>]*type=["']application\/ld\+json["'][^>]*>([\s\S]*?)<\/script>/gi
  );
  for (const m of scripts) {
    let data;
    try {
      data = JSON.parse(m[1]);
    } catch {
      continue;
    }
    const nodes = Array.isArray(data) ? data : [data, ...(Array.isArray(data["@graph"]) ? data["@graph"] : [])];
    for (const node of nodes) {
      if (!node || typeof node !== "object") continue;
      const types = [].concat(node["@type"] ?? []);
      if (!types.includes("Product")) continue;
      const image = node.image;
      if (typeof image === "string") out.push(image);
      else if (Array.isArray(image)) {
        for (const i of image) {
          if (typeof i === "string") out.push(i);
          else if (i && typeof i === "object" && typeof i.url === "string") out.push(i.url);
        }
      } else if (image && typeof image === "object" && typeof image.url === "string") {
        out.push(image.url);
      }
    }
  }
  return out;
}

function extractCdnImages(html, host) {
  const out = [];
  if (/ebay\./i.test(host)) {
    for (const m of html.matchAll(/https?:\/\/i\.ebayimg\.com\/[^"'\\ )]+/gi)) out.push(m[0]);
  }
  if (/etsy\./i.test(host)) {
    for (const m of html.matchAll(/https?:\/\/i\.etsystatic\.com\/[^"'\\ )]+\/il_[^"'\\ )]+/gi)) out.push(m[0]);
  }
  return out;
}

function extractOgImages(html) {
  const out = [];
  for (const m of html.matchAll(
    /<meta[^>]+(?:property|name)=["']og:image(?::secure_url)?["'][^>]+content=["']([^"']+)["']/gi
  )) {
    out.push(m[1]);
  }
  // content-before-property attribute order
  for (const m of html.matchAll(
    /<meta[^>]+content=["']([^"']+)["'][^>]+(?:property|name)=["']og:image(?::secure_url)?["']/gi
  )) {
    out.push(m[1]);
  }
  return out;
}

export function extractGallery(html, pageUrl) {
  const host = (() => {
    try {
      return new URL(pageUrl).hostname;
    } catch {
      return "";
    }
  })();
  const raw = [
    ...extractJsonLdImages(html),
    ...extractCdnImages(html, host),
    ...extractOgImages(html),
  ];
  const seen = new Set();
  const images = [];
  for (const r of raw) {
    const u = normalizeImageUrl(r);
    if (!u || !looksLikeProductImage(u)) continue;
    // Dedup eBay renditions of the same shot (…/g/<id>/s-l1600.jpg).
    const key = u.replace(/\/s-l\d+(\.\w+)$/i, "/$1").replace(/\/il_[^/]+\./i, "/il.");
    if (seen.has(key)) continue;
    seen.add(key);
    images.push(u);
    if (images.length >= IMAGE_CAP) break;
  }
  return images;
}

async function fetchPage(url) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 15000);
  try {
    const res = await fetch(url, {
      headers: { "user-agent": UA, accept: "text/html,application/xhtml+xml" },
      redirect: "follow",
      signal: controller.signal,
    });
    if (!res.ok) return { error: `HTTP ${res.status}` };
    const type = res.headers.get("content-type") || "";
    if (!type.includes("html")) return { error: `not html (${type})` };
    return { html: await res.text() };
  } catch (e) {
    return { error: e.name === "AbortError" ? "timeout" : e.message };
  } finally {
    clearTimeout(timer);
  }
}

// ── Main ──────────────────────────────────────────────────────────────────────

async function main() {
  const args = parseArgs(process.argv.slice(2));

  // Offline single-page mode — no AWS needed; verifies extraction on a URL.
  if (args.url) {
    const { html, error } = await fetchPage(args.url);
    if (error) {
      console.error(`fetch failed: ${error}`);
      process.exit(1);
    }
    const images = extractGallery(html, args.url);
    console.log(JSON.stringify({ url: args.url, count: images.length, images }, null, 2));
    return;
  }

  const table = args.table || process.env.POSTS_TABLE || "giftmaxxing-dev-posts";
  const region = args.region || process.env.AWS_REGION || "us-east-1";
  const { DynamoDBClient } = await import("@aws-sdk/client-dynamodb");
  const { DynamoDBDocumentClient, ScanCommand, UpdateCommand } = await import("@aws-sdk/lib-dynamodb");
  const ddb = DynamoDBDocumentClient.from(new DynamoDBClient({ region }), {
    marshallOptions: { removeUndefinedValues: true },
  });

  // Scan the whole table once (10k rows ≈ a few MB); page-fetch is the real cost.
  const rows = [];
  let ExclusiveStartKey;
  do {
    const out = await ddb.send(new ScanCommand({ TableName: table, ExclusiveStartKey, Limit: 500 }));
    rows.push(...(out.Items ?? []));
    ExclusiveStartKey = out.LastEvaluatedKey;
  } while (ExclusiveStartKey);

  const candidates = rows.filter((p) => {
    if (!isPinterestImport(p)) return false;
    const link = p.productUrl || p.url || p.product?.url || "";
    if (!/^https?:\/\//i.test(link)) return false;
    if (!args.force && Array.isArray(p.product?.images) && p.product.images.length) return false;
    if (args.onlyDomain?.length) {
      const d = String(p.domain || "").replace(/^www\./, "").toLowerCase();
      if (!args.onlyDomain.some((x) => d === x || d.endsWith("." + x))) return false;
    }
    return true;
  });
  const targets = args.limit ? candidates.slice(0, args.limit) : candidates;
  console.log(`Scanned ${rows.length} posts — ${candidates.length} enrichable, processing ${targets.length}.`);

  let enriched = 0;
  let failed = 0;
  for (const [i, post] of targets.entries()) {
    const link = post.productUrl || post.url || post.product?.url;
    const { html, error } = await fetchPage(link);
    if (error) {
      failed++;
      console.log(`  [${i + 1}/${targets.length}] ${post.postId} ✗ ${error}`);
    } else {
      const images = extractGallery(html, link);
      if (images.length > 1) {
        console.log(`  [${i + 1}/${targets.length}] ${post.postId} → ${images.length} images`);
        if (!args.dryRun) {
          await ddb.send(
            new UpdateCommand({
              TableName: table,
              Key: { postId: post.postId },
              UpdateExpression: "SET #p.#imgs = :imgs",
              ExpressionAttributeNames: { "#p": "product", "#imgs": "images" },
              ExpressionAttributeValues: { ":imgs": images },
              ConditionExpression: "attribute_exists(#p)",
            })
          ).catch((e) => console.log(`    write failed: ${e.message}`));
        }
        enriched++;
      } else {
        console.log(`  [${i + 1}/${targets.length}] ${post.postId} — no gallery found`);
      }
    }
    if (i < targets.length - 1) await sleep(args.minInterval);
  }
  console.log(
    `\nDone. ${enriched} galleries ${args.dryRun ? "found (dry run, no writes)" : "written"}, ${failed} fetch failures.`
  );
}

// `--url` mode is import-safe for tests; only run main when executed directly.
if (import.meta.url === `file://${process.argv[1]}`) {
  main().catch((e) => {
    console.error(e);
    process.exit(1);
  });
}
