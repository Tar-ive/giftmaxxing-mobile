#!/usr/bin/env node
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { resolve } from "node:path";

const args = process.argv.slice(2);
const value = (flag, fallback) => args.includes(flag) ? args[args.indexOf(flag) + 1] : fallback;
const carouselId = value("--carousel", "practical-gifts-for-him");
const api = value("--api", process.env.MIXER_API_URL || "https://d21osnvwewgoao.cloudfront.net").replace(/\/$/, "");
const manifest = JSON.parse(await readFile(resolve("Giftmaxxing/Resources/curated-gift-journeys.json"), "utf8"));
const journey = manifest.journeys.find((item) => item.id === carouselId);
if (!journey) throw new Error(`unknown carousel ${carouselId}`);

async function item(productId) {
  const response = await fetch(`${api}/v2/items/curated-product-${productId}`);
  if (!response.ok) throw new Error(`${productId}: HTTP ${response.status}`);
  return (await response.json()).item;
}

const products = await Promise.all(journey.productIds.map(async (productId) => {
  const current = await item(productId);
  const verified = current.quality?.mediaVerified === true && current.quality?.mediaSource === "retailer_listing";
  return {
    productId, title: current.title, summary: current.summary,
    mediaCount: current.media?.length ?? 0, verified,
    swipeEligible: verified && current.commerce?.shoppability === "direct",
    mediaSource: current.quality?.mediaSource ?? null,
    offerUrl: current.commerce?.offers?.[0]?.url ?? null,
    media: current.media ?? [],
  };
}));

const report = {
  runAt: new Date().toISOString(), api, carousel: {
    id: journey.id, sourcePostId: journey.sourcePostId, title: journey.title,
    sourceSlides: journey.imageCount, productCount: products.length,
  },
  result: {
    verifiedProducts: products.filter((item) => item.verified).length,
    swipeEligible: products.filter((item) => item.swipeEligible).length,
    heldOutsideSwipe: products.filter((item) => !item.swipeEligible).length,
  },
  products,
};
const outDir = resolve("infra/eval/runs/carousel-pipeline");
await mkdir(outDir, { recursive: true });
const path = resolve(outDir, `${carouselId}.json`);
await writeFile(path, `${JSON.stringify(report, null, 2)}\n`);
console.log(JSON.stringify({ path, ...report.result }, null, 2));
