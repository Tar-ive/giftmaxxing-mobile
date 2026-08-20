#!/usr/bin/env node
import fs from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, "../../..");
const output = path.join(here, "output");
const catalogPath = path.join(root, "Giftmaxxing/Resources/curated-gift-journeys.json");
const assetsDir = path.join(root, "Giftmaxxing/Resources/Curated");
const labelMap = {
  "coffee-gifts": ["foodie", "coffee", "morning", "practical"],
  "anniversary-boyfriend": ["men", "partner", "anniversary", "romantic"],
  "housewarming-gifts": ["home", "housewarming", "practical", "cozy"],
  "beer-lover-gifts": ["men", "beer", "foodie", "hosting"],
  "graduation-daughter": ["women", "graduation", "student", "travel"],
  "nurse-gifts": ["women", "nurse", "wellness", "practical"],
  "artist-gifts": ["artist", "creative", "stationery", "hobby"],
  "runner-gifts": ["fitness", "runner", "wellness", "tech"],
  "dog-lover-gifts": ["pets", "dog", "outdoors", "sentimental"],
  "small-brand-home-gifts": ["home", "housewarming", "small-brand", "foodie"],
  "birdwatcher-gifts": ["outdoors", "birdwatching", "nature", "hobby"],
  "hiker-gifts": ["outdoors", "hiking", "fitness", "practical"],
  "teacher-gifts": ["teacher", "stationery", "wellness", "thank-you"],
  "sustainable-gifts-under-50": ["sustainable", "budget", "under-50", "small-brand"],
};

const slugify = value => value.toLowerCase().normalize("NFKD").replace(/[^a-z0-9]+/g, "-").replace(/(^-|-$)/g, "");
const price = value => Number(String(value).replace(/[^0-9.]/g, "")) || 0;
const subtitle = value => value.split(/(?<=[.!?])\s/)[0].replace(/\s#[^ ]+/g, "").trim();

const catalog = JSON.parse(await fs.readFile(catalogPath, "utf8"));
catalog.journeys = catalog.journeys.filter(journey => !journey.id.startsWith("editorial-"));
catalog.products = catalog.products.filter(product => !product.id.startsWith("editorial-"));

for (const entry of await fs.readdir(output, { withFileTypes: true })) {
  if (!entry.isDirectory()) continue;
  const dir = path.join(output, entry.name);
  const manifest = JSON.parse(await fs.readFile(path.join(dir, "app-manifest.json"), "utf8"));
  const sourcePostId = `editorial-${entry.name}`;
  const products = manifest.products.map(product => ({
    id: `editorial-${entry.name}-${slugify(product.name)}`,
    name: product.name,
    brand: product.merchant,
    price: price(product.price),
    merchant: product.merchant,
    productUrl: product.url,
    image: product.imageUrl,
    purchaseMode: product.price.startsWith("from") ? "chooseVariant" : "productPage",
    capabilities: ["merchant product page", "online purchase"],
    matchEvidence: product.reason,
  }));
  catalog.products.push(...products);
  catalog.journeys.push({
    id: sourcePostId,
    sourcePostId,
    sourceUrl: manifest.sourceGuide,
    title: manifest.title,
    subtitle: subtitle(manifest.caption),
    whySelected: "A manually reviewed gift genre with original editorial copy, current merchant links, and five independently verified products.",
    labels: labelMap[entry.name] ?? ["curated", "gift-guide"],
    imageCount: manifest.slides.length,
    productIds: products.map(product => product.id),
  });
  await Promise.all(manifest.slides.map(async (slide, index) => {
    const destination = path.join(assetsDir, `${sourcePostId}-${String(index + 1).padStart(2, "0")}.jpg`);
    await fs.copyFile(path.join(dir, slide.file), destination);
  }));
}

catalog.version = "2026-08-11.3";
catalog.sourceFile = "human-reviewed editorial discovery: supplied TikTok export, Wishwave, and GiftOffList";
catalog.reviewedAt = new Date().toISOString();
await fs.writeFile(catalogPath, `${JSON.stringify(catalog, null, 2)}\n`);
console.log(JSON.stringify({ version: catalog.version, journeys: catalog.journeys.length, products: catalog.products.length, synced: Object.keys(labelMap).length }));
