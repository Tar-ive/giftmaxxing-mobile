#!/usr/bin/env node

// Manual-first TikTok curation audit.
//
// The approved source IDs and merchant matches live in the app manifest. This
// script never selects content and never writes DynamoDB: it verifies that the
// reviewed IDs exist in the supplied JSONL, then asks Rekognition for object
// labels and readable text as supporting evidence.

import { mkdir, readFile, writeFile } from "node:fs/promises";
import { basename, dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import {
  DetectLabelsCommand,
  DetectTextCommand,
  RekognitionClient,
} from "@aws-sdk/client-rekognition";

const here = dirname(fileURLToPath(import.meta.url));
const root = resolve(here, "../..");

export function parseJsonl(text) {
  return text.split(/\r?\n/).filter(Boolean).map((line, index) => {
    try { return JSON.parse(line); }
    catch (error) { throw new Error(`Invalid JSONL line ${index + 1}: ${error.message}`); }
  });
}

export function verifySelection(rows, manifest) {
  const byId = new Map(rows.map((row) => [String(row.id), row]));
  const approved = manifest.journeys.map((journey) => {
    const row = byId.get(journey.sourcePostId);
    if (!row) throw new Error(`Approved source ${journey.sourcePostId} is missing from JSONL`);
    return {
      sourcePostId: journey.sourcePostId,
      title: journey.title,
      sourceUrl: journey.sourceUrl,
      plays: Number(row.playCount || 0),
      likes: Number(row.diggCount || 0),
      saves: Number(row.collectCount || 0),
      photos: Array.from({ length: Math.max(journey.imageCount || 1, 1) }, (_, index) =>
        `bundle:///${journey.sourcePostId}-${String(index + 1).padStart(2, "0")}.jpg`),
      productIds: journey.productIds,
    };
  });
  return {
    approved,
    rejectedSourceIds: rows.map((row) => String(row.id)).filter((id) => !approved.some((item) => item.sourcePostId === id)),
  };
}

export function sourceImages(row) {
  const slides = (row.slideshowImageLinks || [])
    .map((image) => image.downloadLink || image.tiktokLink)
    .filter(Boolean);
  if (slides.length) return slides;
  return [row.videoMeta?.coverUrl].filter(Boolean);
}

async function syncAssets(rows, imagesDir) {
  await mkdir(imagesDir, { recursive: true });
  let downloaded = 0;
  for (const row of rows) {
    const images = sourceImages(row);
    for (const [index, url] of images.entries()) {
      const response = await fetch(url);
      if (!response.ok) throw new Error(`Image download failed (${response.status}): ${row.id}`);
      const path = join(imagesDir, `${row.id}-${String(index + 1).padStart(2, "0")}.jpg`);
      await writeFile(path, Buffer.from(await response.arrayBuffer()));
      downloaded += 1;
    }
  }
  return downloaded;
}

function localImage(asset, imagesDir) {
  if (!asset.startsWith("bundle:///")) throw new Error(`Unsupported image reference: ${asset}`);
  return join(imagesDir, basename(asset));
}

async function inspectImage(client, path) {
  const bytes = await readFile(path);
  const [labels, text] = await Promise.all([
    client.send(new DetectLabelsCommand({
      Image: { Bytes: bytes },
      MaxLabels: 20,
      MinConfidence: 70,
      Features: ["GENERAL_LABELS", "IMAGE_PROPERTIES"],
    })),
    client.send(new DetectTextCommand({ Image: { Bytes: bytes } })),
  ]);

  return {
    file: basename(path),
    modelVersion: labels.LabelModelVersion,
    labels: (labels.Labels || []).map((label) => ({
      name: label.Name,
      confidence: Number((label.Confidence || 0).toFixed(2)),
      categories: (label.Categories || []).map((category) => category.Name),
    })),
    text: (text.TextDetections || [])
      .filter((item) => item.Type === "LINE" && (item.Confidence || 0) >= 80)
      .map((item) => ({ value: item.DetectedText, confidence: Number(item.Confidence.toFixed(2)) })),
  };
}

function argsOf(argv) {
  const args = {
    file: null,
    manifest: join(root, "Giftmaxxing/Resources/curated-gift-journeys.json"),
    imagesDir: join(root, "Giftmaxxing/Resources/Curated"),
    out: join(here, "reports/tiktok-curation-pilot.json"),
    region: process.env.AWS_REGION || "us-east-1",
    syncAssets: false,
  };
  for (let index = 0; index < argv.length; index++) {
    const arg = argv[index];
    if (arg === "--file") args.file = resolve(argv[++index]);
    else if (arg === "--manifest") args.manifest = resolve(argv[++index]);
    else if (arg === "--images-dir") args.imagesDir = resolve(argv[++index]);
    else if (arg === "--out") args.out = resolve(argv[++index]);
    else if (arg === "--region") args.region = argv[++index];
    else if (arg === "--sync-assets") args.syncAssets = true;
  }
  if (!args.file) throw new Error("--file <TikTok JSONL> is required");
  return args;
}

async function main() {
  const args = argsOf(process.argv.slice(2));
  const [sourceText, manifestText] = await Promise.all([
    readFile(args.file, "utf8"),
    readFile(args.manifest, "utf8"),
  ]);
  const rows = parseJsonl(sourceText);
  const downloadedAssets = args.syncAssets ? await syncAssets(rows, args.imagesDir) : 0;
  const manifest = JSON.parse(manifestText);
  const selection = verifySelection(rows, manifest);
  const client = new RekognitionClient({ region: args.region });

  const evidence = [];
  for (const journey of selection.approved) {
    const images = [];
    for (const asset of journey.photos) {
      images.push(await inspectImage(client, localImage(asset, args.imagesDir)));
    }
    evidence.push({ sourcePostId: journey.sourcePostId, images });
  }

  const report = {
    schemaVersion: 1,
    generatedAt: new Date().toISOString(),
    sourceFile: basename(args.file),
    manifestVersion: manifest.version,
    region: args.region,
    selection,
    evidence,
  };
  await writeFile(args.out, `${JSON.stringify(report, null, 2)}\n`);
  console.log(JSON.stringify({
    report: args.out,
    sourcePosts: rows.length,
    approvedPosts: selection.approved.length,
    rejectedPosts: selection.rejectedSourceIds.length,
    inspectedPhotos: evidence.reduce((sum, item) => sum + item.images.length, 0),
    downloadedAssets,
  }, null, 2));
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main().catch((error) => {
    console.error(error.message);
    process.exitCode = 1;
  });
}
