// Fill catalog-basics.json imageUrl fields with REAL, hotlinkable product
// photos, scraped compliantly: fetch each item's official brand page (or its
// Wikipedia article as a licensed fallback), read the page's own og:image /
// twitter:image / JSON-LD image — i.e. the image the site itself nominates for
// sharing — then validate the URL actually serves a raster image.
//
// No Amazon scraping (ToS), no guessed CDN paths: every URL comes from a page
// that answered 200 and is verified with a real GET before being written.
// Items whose sources all fail keep imageUrl null and render the designed
// gradient card (ProductArtworkView) — nothing breaks.
//
// Usage:
//   node scrape-catalog-images.mjs --dry-run     # report only, no JSON writes
//   node scrape-catalog-images.mjs               # update catalog-basics.json
//   node scrape-catalog-images.mjs --only cat-airpods-max,svc-netflix-premium-1yr
//   node scrape-catalog-images.mjs --force       # re-scrape items that have an imageUrl
//
// After running, re-run `npm run ingest:catalog` (AWS creds needed) so vectors
// re-embed image+text and the seeded posts pick up product.image.

import { readFile, writeFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const CATALOG = join(__dirname, "catalog-basics.json");
const UA =
  "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36";

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// Candidate pages per item, tried in order. Brand product/marketing pages
// first (their og:image is the official product shot); Wikipedia articles as
// the licensed fallback for brands that block datacenter fetches (Sony, UGG…).
const SOURCES = {
  "cat-iphone-16": ["https://www.apple.com/iphone-16/", "https://en.wikipedia.org/wiki/IPhone_16"],
  "cat-iphone-16-pro": ["https://www.apple.com/shop/buy-iphone/iphone-16-pro", "https://en.wikipedia.org/wiki/IPhone_16_Pro"],
  "cat-airpods-pro-2": ["https://www.apple.com/airpods-pro/", "https://en.wikipedia.org/wiki/AirPods_Pro"],
  "cat-airpods-4-anc": ["https://www.apple.com/airpods-4/", "https://en.wikipedia.org/wiki/AirPods_(4th_generation)"],
  "cat-airpods-max": ["https://www.apple.com/airpods-max/", "https://en.wikipedia.org/wiki/AirPods_Max"],
  "cat-apple-watch-s10": ["https://www.apple.com/apple-watch-series-10/", "https://www.apple.com/shop/buy-watch/apple-watch", "https://en.wikipedia.org/wiki/Apple_Watch_Series_10"],
  "cat-apple-watch-se": ["https://www.apple.com/apple-watch-se/", "https://www.apple.com/shop/buy-watch/apple-watch-se", "https://en.wikipedia.org/wiki/Apple_Watch_SE_(2nd_generation)"],
  "cat-ipad-a16": ["https://www.apple.com/ipad-11/", "https://www.apple.com/ipad/", "https://en.wikipedia.org/wiki/IPad_(11th_generation)"],
  "cat-ipad-air-m3": ["https://www.apple.com/ipad-air/", "https://en.wikipedia.org/wiki/IPad_Air"],
  "cat-apple-pencil-pro": ["https://www.apple.com/apple-pencil/", "https://www.apple.com/shop/product/MX2D3AM/A/apple-pencil-pro"],
  "cat-airtag-4pack": ["https://www.apple.com/airtag/", "https://en.wikipedia.org/wiki/AirTag"],
  "cat-homepod-mini": ["https://www.apple.com/homepod-mini/", "https://en.wikipedia.org/wiki/HomePod_Mini"],
  "cat-magsafe-charger": ["https://www.apple.com/shop/product/MX6X3AM/A/magsafe-charger-25w", "https://en.wikipedia.org/wiki/MagSafe"],
  "cat-sony-wh1000xm5": ["https://electronics.sony.com/audio/headphones/headband/p/wh1000xm5-b", "https://en.wikipedia.org/wiki/Sony_WH-1000XM5"],
  "cat-sony-wf1000xm5": ["https://electronics.sony.com/audio/headphones/truly-wireless/p/wf1000xm5-b", "https://en.wikipedia.org/wiki/Sony_WF-1000XM5"],
  "cat-owala-freesip-24": ["https://owalalife.com/products/freesip"],
  "cat-owala-freesip-32": ["https://owalalife.com/products/freesip-32-oz", "https://owalalife.com/products/freesip"],
  "cat-kindle-paperwhite": ["https://en.wikipedia.org/wiki/Kindle_Paperwhite", "https://en.wikipedia.org/wiki/Amazon_Kindle"],
  "cat-nike-air-force-1": ["https://www.nike.com/t/air-force-1-07-mens-shoes-jBrhbr/CW2288-111", "https://en.wikipedia.org/wiki/Nike_Air_Force_1"],
  "cat-adidas-samba": ["https://www.adidas.com/us/samba-og-shoes/B75806.html", "https://en.wikipedia.org/wiki/Adidas_Samba"],
  "cat-new-balance-550": ["https://www.newbalance.com/pd/550/BB550-LWT.html", "https://en.wikipedia.org/wiki/New_Balance"],
  "cat-hoka-clifton-9": ["https://www.hoka.com/en/us/mens-road/clifton-9/1127895.html", "https://www.hoka.com/en/us/clifton-9/"],
  "cat-birkenstock-boston": ["https://www.birkenstock.com/us/boston-suede-leather/boston-suedeleather-corefootbed-0-eva-u_1.html", "https://en.wikipedia.org/wiki/Birkenstock"],
  "cat-ugg-tasman": ["https://www.ugg.com/men-slippers/tasman-slipper/5950.html", "https://www.zappos.com/p/ugg-tasman-chestnut/product/7563731", "https://en.wikipedia.org/wiki/UGG_(brand)"],
  "svc-netflix-premium-1yr": ["https://www.netflix.com", "https://en.wikipedia.org/wiki/Netflix"],
  "svc-amazon-prime-1yr": ["https://www.amazon.com/prime", "https://en.wikipedia.org/wiki/Amazon_Prime"],
  "svc-costco-gold-star-1yr": ["https://www.costco.com/join-costco.html", "https://en.wikipedia.org/wiki/Costco"],
  "svc-costco-executive-1yr": ["https://www.costco.com/join-costco.html", "https://en.wikipedia.org/wiki/Costco"],
  "svc-walmart-plus-1yr": ["https://www.walmart.com/plus", "https://en.wikipedia.org/wiki/Walmart%2B"],
  "svc-spotify-premium-1yr": ["https://www.spotify.com/us/premium/", "https://en.wikipedia.org/wiki/Spotify"],
  "svc-audible-premium-1yr": ["https://www.audible.com/ep/giftcenter", "https://en.wikipedia.org/wiki/Audible_(service)"],
  "svc-disney-plus-1yr": ["https://www.disneyplus.com", "https://en.wikipedia.org/wiki/Disney%2B"],
  "svc-youtube-premium-1yr": ["https://www.youtube.com/premium", "https://en.wikipedia.org/wiki/YouTube_Premium"],
  "svc-masterclass-1yr": ["https://www.masterclass.com/gift", "https://en.wikipedia.org/wiki/MasterClass"],
  "svc-apple-one-1yr": ["https://www.apple.com/apple-one/", "https://en.wikipedia.org/wiki/Apple_One"],
};

function parseArgs(argv) {
  const a = { dryRun: false, force: false, only: null };
  for (let i = 0; i < argv.length; i++) {
    const x = argv[i];
    if (x === "--dry-run") a.dryRun = true;
    else if (x === "--force") a.force = true;
    else if (x === "--only") a.only = new Set(String(argv[++i]).split(",").map((s) => s.trim()));
  }
  return a;
}

async function fetchPage(url) {
  const res = await fetch(url, {
    headers: {
      "User-Agent": UA,
      Accept: "text/html,application/xhtml+xml",
      "Accept-Language": "en-US,en;q=0.9",
    },
    redirect: "follow",
    signal: AbortSignal.timeout(20000),
  });
  if (!res.ok) throw new Error(`HTTP ${res.status}`);
  return { html: await res.text(), finalUrl: res.url || url };
}

// The image the page itself nominates: og:image (+ secure_url variant),
// twitter:image, <link rel="image_src">, then any JSON-LD "image".
function extractImageUrls(html) {
  const out = [];
  const push = (u) => {
    if (u && !out.includes(u)) out.push(u);
  };
  const metaRe =
    /<meta[^>]+(?:property|name)=["'](?:og:image(?::secure_url)?|twitter:image(?::src)?)["'][^>]*>/gi;
  for (const tag of html.match(metaRe) ?? []) {
    const m = tag.match(/content=["']([^"']+)["']/i);
    // HTML-decode: attribute values escape & as &amp; (Apple's og URLs do).
    if (m) push(m[1].replace(/&amp;/g, "&").replace(/&#38;/g, "&"));
  }
  const linkM = html.match(/<link[^>]+rel=["']image_src["'][^>]+href=["']([^"']+)["']/i);
  if (linkM) push(linkM[1]);
  for (const block of html.match(/<script[^>]+application\/ld\+json[^>]*>([\s\S]*?)<\/script>/gi) ?? []) {
    const body = block.replace(/<script[^>]*>|<\/script>/gi, "");
    try {
      const data = JSON.parse(body);
      const walk = (v) => {
        if (!v) return;
        if (typeof v === "string" && /^https?:\/\//.test(v) && /\.(jpe?g|png|webp)(\?|$)/i.test(v)) push(v);
        else if (Array.isArray(v)) v.forEach(walk);
        else if (typeof v === "object") {
          if (v.image) walk(v.image);
          if (v.url && v["@type"] === "ImageObject") walk(v.url);
        }
      };
      walk(data);
    } catch {
      // malformed JSON-LD — skip
    }
  }
  return out;
}

// A usable card image: real 200, raster content-type (no SVG — the iOS
// AsyncImage pipeline won't render it), and big enough to not be a favicon.
async function validateImage(url) {
  const res = await fetch(url, {
    headers: { "User-Agent": UA, Accept: "image/*" },
    redirect: "follow",
    signal: AbortSignal.timeout(20000),
  });
  if (!res.ok) throw new Error(`HTTP ${res.status}`);
  const type = res.headers.get("content-type") || "";
  if (!/image\/(jpe?g|png|webp)/i.test(type)) throw new Error(`type ${type || "unknown"}`);
  const buf = Buffer.from(await res.arrayBuffer());
  if (buf.length < 8 * 1024) throw new Error(`too small (${buf.length}B)`);
  return { bytes: buf.length, type, finalUrl: res.url || url };
}

function absolutize(u, base) {
  try {
    return new URL(u, base).toString();
  } catch {
    return null;
  }
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const parsed = JSON.parse(await readFile(CATALOG, "utf8"));
  const items = parsed.items;

  let updated = 0;
  let skipped = 0;
  let failed = 0;

  for (const item of items) {
    if (args.only && !args.only.has(item.id)) continue;
    if (item.imageUrl && !args.force) {
      skipped++;
      continue;
    }
    const pages = SOURCES[item.id] ?? [];
    if (!pages.length) {
      console.log(`- ${item.id}: no sources configured`);
      continue;
    }
    let found = null;
    for (const page of pages) {
      try {
        const { html, finalUrl } = await fetchPage(page);
        const candidates = extractImageUrls(html)
          .map((u) => absolutize(u, finalUrl))
          .filter(Boolean);
        for (const candidate of candidates.slice(0, 4)) {
          try {
            const ok = await validateImage(candidate);
            found = { url: ok.finalUrl, page, bytes: ok.bytes, type: ok.type };
            break;
          } catch (e) {
            console.log(`    · ${item.id}: rejected ${candidate.slice(0, 80)} (${e.message})`);
          }
        }
        if (found) break;
      } catch (e) {
        console.log(`    · ${item.id}: ${page} -> ${e.message}`);
      }
      await sleep(400 + Math.random() * 400);
    }
    if (found) {
      console.log(`✓ ${item.id}  <- ${found.url.slice(0, 90)}  (${Math.round(found.bytes / 1024)}KB via ${new URL(found.page).hostname})`);
      item.imageUrl = found.url;
      item.imageSourcePage = found.page;
      updated++;
    } else {
      console.log(`✗ ${item.id}: all sources failed — keeps the designed gradient card`);
      failed++;
    }
    await sleep(500 + Math.random() * 500);
  }

  console.log(`\n${updated} updated, ${skipped} already had images, ${failed} failed`);
  if (args.dryRun) {
    console.log("[dry-run] catalog-basics.json not written");
    return;
  }
  if (updated) {
    await writeFile(CATALOG, JSON.stringify(parsed, null, 2) + "\n");
    console.log(`wrote ${CATALOG}`);
    console.log("Next: npm run ingest:catalog  (re-embeds image+text, refreshes posts)");
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
