// Curated Pinterest/Apify slides -> S3 source archive + DynamoDB feed posts.
//
// Usage:
//   node ingest-carousel.mjs --dry-run
//   node ingest-carousel.mjs --upload --api https://d21osnvwewgoao.cloudfront.net
//
// Config (env): MEDIA_BUCKET, AWS_REGION, ADMIN_API_SECRET.

import { readFile, writeFile } from "node:fs/promises";
import { dirname, extname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const defaultFile = join(here, "carousels/bestie-birthday.json");

function argsOf(argv) {
  const args = { dryRun: false, upload: false, file: defaultFile };
  for (let i = 0; i < argv.length; i++) {
    if (argv[i] === "--dry-run") args.dryRun = true;
    else if (argv[i] === "--upload") args.upload = true;
    else if (argv[i] === "--file") args.file = resolve(argv[++i]);
    else if (argv[i] === "--api") args.api = argv[++i];
    else if (argv[i] === "--out") args.out = resolve(argv[++i]);
  }
  return args;
}

function validate(config) {
  if (!config.id || !config.title || !Array.isArray(config.slides) || config.slides.length < 2) {
    throw new Error("Carousel requires id, title, and at least two slides");
  }
  const urls = config.slides.map((slide) => slide.imageUrl);
  if (urls.some((url) => !/^https:\/\//.test(url))) throw new Error("Every slide needs an https imageUrl");
  if (new Set(urls).size !== urls.length) throw new Error("Carousel imageUrl values must be unique");
}

const creator = (slide) => slide.pinnerUsername || "unknown";
const createdAt = (value, fallback) => Number.isFinite(Date.parse(value)) ? Date.parse(value) : fallback;

function pinPost(slide, index) {
  const title = slide.label || slide.title || slide.altText || "Pinterest gift idea";
  return {
    postId: `pin-${slide.id}`,
    author: `pinterest_${creator(slide).toLowerCase()}`,
    createdAt: createdAt(slide.createdAt, Date.now() - (index + 1) * 1_000),
    likes: Number(slide.saves) || 0,
    comments: 0,
    caption: title,
    source: `Pinterest/${creator(slide)}`,
    url: slide.sourceUrl,
    productUrl: slide.link || slide.sourceUrl,
    pinUrl: slide.sourceUrl,
    rec: true,
    reason: "Best-friend birthday inspiration",
    recipient: "friend",
    occasion: "birthday",
    category: slide.category || "diy",
    vibes: ["sentimental", "handmade", "aesthetic"],
    status: "find",
    priceTier: "unknown",
    price: 0,
    merchant: slide.domain || "Pinterest",
    domain: slide.domain || null,
    dominantColor: slide.dominantColor || null,
    s3Key: slide.s3Key || null,
    product: {
      id: `pin-${slide.id}`,
      name: title,
      brand: slide.pinnerName || "Pinterest",
      price: 0,
      grad: "rose",
      emoji: "💝",
      image: slide.imageUrl,
      url: slide.link || slide.sourceUrl,
    },
  };
}

function carouselPost(config) {
  const [cover, ...rest] = config.slides;
  return {
    postId: config.id,
    author: "giftmaxxing",
    createdAt: Date.now(),
    likes: 0,
    comments: 0,
    caption: config.caption || config.title,
    source: `Apify/Pinterest · dataset ${config.apify.datasetId}`,
    rec: true,
    reason: "Curated best-friend birthday ideas",
    recipient: "friend",
    occasion: "birthday",
    category: "diy",
    vibes: ["sentimental", "handmade", "aesthetic", "bestie"],
    status: "find",
    priceTier: "unknown",
    price: 0,
    merchant: "Giftmaxxing",
    carouselSlides: config.slides.map((slide, index) => ({
      index,
      label: slide.label,
      imageUrl: slide.imageUrl,
      sourceUrl: slide.sourceUrl,
      sourceCreator: slide.pinnerName || creator(slide),
      s3Key: slide.s3Key || null,
    })),
    product: {
      id: config.id,
      name: config.title,
      brand: "Giftmaxxing",
      price: 0,
      grad: "rose",
      emoji: "💝",
      image: cover.imageUrl,
      images: rest.map((slide) => slide.imageUrl),
    },
  };
}

const extFor = (contentType, url) => {
  if (contentType.includes("png")) return ".png";
  if (contentType.includes("webp")) return ".webp";
  const ext = extname(new URL(url).pathname).toLowerCase();
  return [".jpg", ".jpeg", ".png", ".webp"].includes(ext) ? ext : ".jpg";
};

async function archiveSlides(config) {
  const bucket = process.env.MEDIA_BUCKET || "giftmaxxing-dev-media";
  const region = process.env.AWS_REGION || "us-east-1";
  const { PutObjectCommand, S3Client } = await import("@aws-sdk/client-s3");
  const s3 = new S3Client({ region });
  for (let i = 0; i < config.slides.length; i++) {
    const slide = config.slides[i];
    const response = await fetch(slide.imageUrl);
    const contentType = response.headers.get("content-type") || "";
    if (!response.ok || !contentType.startsWith("image/")) {
      throw new Error(`Slide ${i + 1} image failed: HTTP ${response.status}`);
    }
    const body = Buffer.from(await response.arrayBuffer());
    const key = `carousels/${config.id}/${String(i + 1).padStart(2, "0")}${extFor(contentType, slide.imageUrl)}`;
    await s3.send(new PutObjectCommand({
      Bucket: bucket,
      Key: key,
      Body: body,
      ContentType: contentType,
      Metadata: { "source-pin": slide.id, "source-user": creator(slide) },
    }));
    slide.s3Key = key;
  }
  console.log(`Archived ${config.slides.length} slides to s3://${bucket}/carousels/${config.id}/`);
}

async function seed(posts, api) {
  const response = await fetch(`${api}/seed`, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      ...(process.env.ADMIN_API_SECRET ? { "x-admin-token": process.env.ADMIN_API_SECRET } : {}),
    },
    body: JSON.stringify({ posts }),
  });
  if (!response.ok) throw new Error(`/seed -> HTTP ${response.status}: ${await response.text()}`);
}

async function main() {
  const args = argsOf(process.argv.slice(2));
  const config = JSON.parse(await readFile(args.file, "utf8"));
  validate(config);
  if (args.upload) await archiveSlides(config);

  const posts = [...config.slides.map(pinPost), carouselPost(config)];
  const out = args.out || join(dirname(args.file), `${config.id}.posts.json`);
  await writeFile(out, JSON.stringify(posts, null, 2) + "\n");
  console.log(`Prepared ${posts.length} posts (${config.slides.length} pins + 1 carousel) -> ${out}`);
  if (args.dryRun) return;

  const api = args.api || process.env.API_BASE || "https://d21osnvwewgoao.cloudfront.net";
  await seed(posts, api.replace(/\/$/, ""));
  console.log(`Seeded ${posts.length} posts via ${api}/seed`);
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
