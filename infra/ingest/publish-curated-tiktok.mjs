#!/usr/bin/env node
import { readFile, readdir } from "node:fs/promises";
import { basename, dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { DynamoDBClient } from "@aws-sdk/client-dynamodb";
import { BatchWriteCommand, DynamoDBDocumentClient, PutCommand } from "@aws-sdk/lib-dynamodb";
import { PutObjectCommand, S3Client } from "@aws-sdk/client-s3";
import { normalizeLegacyPost } from "../src/catalog-v2.mjs";

const here = dirname(fileURLToPath(import.meta.url));
const root = resolve(here, "../..");
const apply = process.argv.includes("--apply");
const prefix = process.env.ENV_PREFIX || "giftmaxxing-dev";
const tables = {
  posts: process.env.POSTS_TABLE || `${prefix}-posts`,
  entities: process.env.CATALOG_ENTITIES_TABLE || `${prefix}-catalog-entities`,
  edges: process.env.CATALOG_EDGES_TABLE || `${prefix}-catalog-edges`,
};
const bucket = process.env.MEDIA_BUCKET || `${prefix}-media`;
const manifestPath = resolve(root, "Giftmaxxing/Resources/curated-gift-journeys.json");
const themeMapPath = resolve(root, "docs/audits/carousel-theme-audit-2026-08-13/carousel-theme-map.json");
const enrichmentPath = resolve(here, "curated-product-enrichment.json");
const imagesDir = resolve(root, "Giftmaxxing/Resources/Curated");
const region = process.env.AWS_REGION || "us-east-1";
const collectionId = "giftmaxxing-reviewed";
const ddb = DynamoDBDocumentClient.from(new DynamoDBClient({ region }), { marshallOptions: { removeUndefinedValues: true } });
const s3 = new S3Client({ region });

const publicPath = (version, asset) => `/curated/${version}/${basename(asset)}`;
const labelsFor = (journey) => [...new Set(journey.labels.map((value) => value.toLowerCase()))];

async function batch(table, items) {
  if (!apply) return;
  const key = table === tables.posts ? (item) => item.postId
    : table === tables.entities ? (item) => item.entityId
      : (item) => `${item.fromId}\0${item.edgeKey}`;
  const unique = [...new Map(items.map((item) => [key(item), item])).values()];
  for (let offset = 0; offset < unique.length; offset += 25) {
    let requests = unique.slice(offset, offset + 25).map((Item) => ({ PutRequest: { Item } }));
    for (let attempt = 0; requests.length && attempt < 8; attempt++) {
      const output = await ddb.send(new BatchWriteCommand({ RequestItems: { [table]: requests } }));
      requests = output.UnprocessedItems?.[table] ?? [];
    }
    if (requests.length) throw new Error(`${requests.length} writes remained for ${table}`);
  }
}

const manifest = JSON.parse(await readFile(manifestPath, "utf8"));
const themeMap = JSON.parse(await readFile(themeMapPath, "utf8"));
const enrichment = await readFile(enrichmentPath, "utf8").then(JSON.parse).catch(() => ({ products: [] }));
const themeByCarousel = new Map(themeMap.carousels.map((item) => [item.id, item]));
const galleryByProduct = new Map(enrichment.products.map((item) => [item.id, item.images ?? []]));
const products = new Map(manifest.products.map((product) => [product.id, product]));
const productTaxonomy = new Map();
for (const journey of manifest.journeys) {
  const theme = themeByCarousel.get(journey.id);
  const themeLabels = theme ? [theme.themeId, theme.filterLabel, ...theme.recipients, ...theme.occasions, ...theme.interests]
    .map((value) => value.toLowerCase()) : [];
  for (const productId of journey.productIds) {
    const current = productTaxonomy.get(productId) ?? { category: labelsFor(journey)[0] || "curated", labels: [] };
    current.labels = [...new Set([...current.labels, ...labelsFor(journey), ...themeLabels])];
    productTaxonomy.set(productId, current);
  }
}
const posts = [], entities = [], edges = [];

for (const journey of manifest.journeys) {
  const theme = themeByCarousel.get(journey.id);
  const curatedLabels = [...new Set([
    ...labelsFor(journey), theme?.themeId, theme?.filterLabel,
    ...(theme?.recipients ?? []), ...(theme?.occasions ?? []), ...(theme?.interests ?? []),
  ].filter(Boolean).map((value) => value.toLowerCase()))];
  const postId = `curated-source-${journey.sourcePostId}`;
  const mediaUrls = Array.from({ length: Math.max(1, journey.imageCount) }, (_, index) =>
    publicPath(manifest.version, `${journey.sourcePostId}-${String(index + 1).padStart(2, "0")}.jpg`));
  const shoppable = journey.productIds.map((id) => products.get(id)).filter(Boolean).map((product) => ({
    postId: `curated-product-${product.id}`, name: product.name, image: galleryByProduct.get(product.id)?.[0] ?? publicPath(manifest.version, product.image),
    price: product.price, productUrl: product.productUrl, merchant: product.merchant,
  }));
  const row = {
    postId, author: "giftmaxxing", authorName: "giftmaxxing", caption: journey.subtitle,
    story: journey.whySelected, source: "ugc", contentType: "ugc_carousel", mediaType: "carousel",
    mediaUrl: mediaUrls[0], mediaUrls, posterUrl: mediaUrls[0], url: journey.sourceUrl,
    product: { id: `curated-guide-${journey.id}`, name: journey.title, brand: "Gift guide", price: 0, image: mediaUrls[0], images: mediaUrls },
    category: theme?.themeId ?? labelsFor(journey)[0] ?? "curated", vibes: curatedLabels, shoppable,
    curationStatus: "approved", moderationStatus: "APPROVED", processingStatus: "READY",
    curationCollectionId: collectionId, curationCollectionVersion: manifest.version,
    status: "made", feedEligible: true, feedPk: "all", qualityScore: 1,
    likes: 0, comments: 0, createdAt: Date.parse(manifest.reviewedAt), updatedAt: Date.now(),
  };
  posts.push(row);
  const entity = normalizeLegacyPost(row);
  entity.provenance.provider = "giftmaxxing-curation";
  entities.push(entity);
  for (const product of shoppable) {
    edges.push({
      fromId: postId, edgeKey: `FEATURES#${product.postId}`,
      toId: product.postId, relation: "FEATURES", evidence: { reviewStatus: "approved" },
    });
  }
}

for (const product of [...manifest.products, ...manifest.wrapKit]) {
  const postId = `curated-product-${product.id}`;
  const taxonomy = productTaxonomy.get(product.id) ?? { category: "wrapping", labels: ["wrapping", "presentation"] };
  const gallery = galleryByProduct.get(product.id) ?? [];
  const cover = gallery[0] ?? publicPath(manifest.version, product.image);
  const row = {
    postId, author: "giftmaxxing", source: "curated-product", kind: "product",
    product: { id: product.id, name: product.name, brand: product.brand, price: product.price, image: cover, images: gallery },
    productUrl: product.productUrl, merchant: product.merchant, caption: product.matchEvidence,
    capabilities: product.capabilities,
    story: product.matchEvidence, category: taxonomy.category, vibes: [...new Set([...taxonomy.labels, ...product.capabilities])],
    curationStatus: "approved", moderationStatus: "APPROVED", status: "made",
    curationCollectionId: collectionId, curationCollectionVersion: manifest.version,
    feedEligible: true, feedPk: "all", qualityScore: 1, likes: 0, comments: 0,
    createdAt: Date.parse(manifest.reviewedAt), updatedAt: Date.now(),
  };
  posts.push(row);
  const entity = normalizeLegacyPost(row);
  entity.provenance = { ...entity.provenance, type: "retailer", provider: "giftmaxxing-curation" };
  entities.push(entity);
}

for (const entity of [...entities]) {
  for (const assertion of entity.taxonomy.assertions) {
    const labelId = `label:${assertion.labelId}`;
    entities.push({ entityId: labelId, entityType: "label", schemaVersion: 2, title: assertion.labelId, status: "active", updatedAt: Date.now() });
    edges.push({ fromId: entity.entityId, edgeKey: `HAS_LABEL#${labelId}`, toId: labelId, relation: "HAS_LABEL", evidence: { ...assertion, reviewStatus: "approved" } });
  }
  for (const offer of entity.commerce?.offers ?? []) {
    entities.push({ entityId: offer.offerId, entityType: "offer", schemaVersion: 2, ...offer, status: "active", updatedAt: Date.now() });
    edges.push({ fromId: entity.entityId, edgeKey: `AVAILABLE_AS#${offer.offerId}`, toId: offer.offerId, relation: "AVAILABLE_AS" });
  }
}

const files = (await readdir(imagesDir)).filter((name) => /\.(jpe?g|png)$/i.test(name));
if (apply) await Promise.all(files.map(async (name) => s3.send(new PutObjectCommand({
  Bucket: bucket, Key: `curated/${manifest.version}/${name}`, Body: await readFile(join(imagesDir, name)),
  ContentType: name.endsWith(".png") ? "image/png" : "image/jpeg", CacheControl: "public,max-age=31536000,immutable",
}))));
await batch(tables.posts, posts);
await batch(tables.entities, entities);
await batch(tables.edges, edges);
if (apply) await ddb.send(new PutCommand({
  TableName: tables.entities,
  Item: {
    entityId: `curation_collection:${collectionId}`,
    entityType: "curation_collection",
    collectionId,
    activeVersion: manifest.version,
    itemIds: entities.filter((entity) => entity.entityType === "item").map((entity) => entity.entityId),
    status: "active",
    activatedAt: Date.now(),
  },
}));
console.log(JSON.stringify({ mode: apply ? "apply" : "dry-run", version: manifest.version, assets: files.length, posts: posts.length, entities: entities.length, edges: edges.length }));
