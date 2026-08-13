#!/usr/bin/env node
import { readFile, writeFile } from "node:fs/promises";
import { basename, dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { PutObjectCommand, S3Client } from "@aws-sdk/client-s3";
import { fetchGallery, providerFor } from "./enrich-images.mjs";

const here = dirname(fileURLToPath(import.meta.url));
const root = resolve(here, "../..");
const manifestPath = resolve(root, "Giftmaxxing/Resources/curated-gift-journeys.json");
const outputPath = resolve(here, "curated-product-enrichment.json");
const overridesPath = resolve(here, "curated-product-overrides.json");
const args = process.argv.slice(2);
const apply = args.includes("--apply");
const force = args.includes("--force");
const value = (flag, fallback) => args.includes(flag) ? args[args.indexOf(flag) + 1] : fallback;
const onlyIds = new Set(String(value("--ids", "")).split(",").filter(Boolean));
const limit = Number(value("--limit", 0)) || Infinity;
const concurrency = Math.max(1, Math.min(8, Number(value("--concurrency", 4)) || 4));
const region = process.env.AWS_REGION || "us-east-1";
const bucket = process.env.MEDIA_BUCKET || `${process.env.ENV_PREFIX || "giftmaxxing-dev"}-media`;
const s3 = new S3Client({ region });
const manifest = JSON.parse(await readFile(manifestPath, "utf8"));
const previous = await readFile(outputPath, "utf8").then(JSON.parse).catch(() => ({ products: [] }));
const overrides = await readFile(overridesPath, "utf8").then(JSON.parse).catch(() => ({ products: {} }));
const results = new Map(previous.products.map((item) => [item.id, item]));
const targets = manifest.products
  .filter((item) => (!onlyIds.size || onlyIds.has(item.id)) && (force || !results.has(item.id)))
  .slice(0, limit);

async function archiveImage(product, url, index) {
  const response = await fetch(url, { headers: { "user-agent": "Mozilla/5.0 GiftmaxxingGallery/1.0", accept: "image/*" } });
  if (!response.ok) throw new Error(`image HTTP ${response.status}`);
  const type = response.headers.get("content-type") || "image/jpeg";
  if (!type.startsWith("image/")) throw new Error(`not image (${type})`);
  const body = Buffer.from(await response.arrayBuffer());
  if (!body.length || body.length > 15_000_000) throw new Error("invalid image size");
  const suffix = type.includes("png") ? "png" : type.includes("webp") ? "webp" : "jpg";
  const key = `curated/${manifest.version}/products/${product.id}/${String(index + 1).padStart(2, "0")}.${suffix}`;
  await s3.send(new PutObjectCommand({ Bucket: bucket, Key: key, Body: body, ContentType: type, CacheControl: "public,max-age=31536000,immutable" }));
  return `/${key}`;
}

let cursor = 0;
async function worker() {
  while (cursor < targets.length) {
    const product = targets[cursor++];
    const override = overrides.products?.[product.id];
    const fetched = override
      ? {
          images: override.images ?? [], features: override.features,
          description: override.description, title: override.title, brand: override.brand,
          provider: "manual-official",
        }
      : await fetchGallery(product.productUrl).catch((error) => ({ error: error.message }));
    let images = fetched.images ?? [];
    let archiveError;
    if (apply && images.length) {
      const settled = await Promise.allSettled(images.map((url, index) => archiveImage(product, url, index)));
      images = settled.filter((item) => item.status === "fulfilled").map((item) => item.value);
      archiveError = settled.find((item) => item.status === "rejected")?.reason?.message;
    }
    results.set(product.id, {
      id: product.id,
      listingUrl: product.productUrl,
      provider: fetched.provider ?? providerFor(product.productUrl),
      status: images.length > 1 ? "gallery_verified" : images.length ? "single_image" : "no_gallery",
      images,
      title: fetched.title ?? product.name,
      brand: fetched.brand ?? product.brand,
      description: fetched.description,
      descriptionSource: fetched.description ? "retailer_listing" : null,
      features: fetched.features ?? product.capabilities,
      observedText: override?.observedText,
      mediaSource: images.length ? "retailer_listing" : null,
      verifiedAt: new Date().toISOString(),
      error: fetched.error ?? fetched.skipped ?? archiveError,
    });
    process.stdout.write(`${product.id}\t${images.length}\t${fetched.error ?? fetched.skipped ?? "ok"}\n`);
  }
}

await Promise.all(Array.from({ length: concurrency }, worker));
const payload = {
  schemaVersion: "1.0.0",
  catalogVersion: manifest.version,
  generatedAt: new Date().toISOString(),
  storage: apply ? `s3://${bucket}/curated/${manifest.version}/products` : "retailer-cdn",
  summary: {
    products: results.size,
    galleries: [...results.values()].filter((item) => item.images.length > 1).length,
    images: [...results.values()].reduce((sum, item) => sum + item.images.length, 0),
  },
  products: [...results.values()].sort((a, b) => a.id.localeCompare(b.id)),
};
await writeFile(outputPath, `${JSON.stringify(payload, null, 2)}\n`);
console.log(JSON.stringify({ output: basename(outputPath), ...payload.summary, storage: payload.storage }));
