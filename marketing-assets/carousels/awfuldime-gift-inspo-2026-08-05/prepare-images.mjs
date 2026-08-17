import fs from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import sharp from "../../../web/node_modules/sharp/lib/index.js";

const dir = path.dirname(fileURLToPath(import.meta.url));
const pins = JSON.parse(await fs.readFile(path.join(dir, "apify-raw.json"), "utf8"));
const sources = path.join(dir, "sources");
const sheets = path.join(dir, "contact-sheets");
await Promise.all([fs.mkdir(sources, { recursive: true }), fs.mkdir(sheets, { recursive: true })]);

const records = [];
for (const [i, pin] of pins.entries()) {
  const number = i + 1;
  const heic = /\.heic(?:$|\?)/i.test(pin.imageUrl ?? "");
  const sourceUrl = heic ? pin.thumbnailUrl.replace("/236x/", "/736x/") : pin.imageUrl;
  const response = await fetch(sourceUrl);
  if (!response.ok) throw new Error(`Image ${number} failed: HTTP ${response.status}`);
  const bytes = Buffer.from(await response.arrayBuffer());
  const type = response.headers.get("content-type") ?? "image/jpeg";
  const ext = type.includes("png") ? "png" : type.includes("webp") ? "webp" : "jpg";
  const filename = `${String(number).padStart(2, "0")}-${pin.id}.${ext}`;
  await fs.writeFile(path.join(sources, filename), bytes);
  records.push({ ...pin, imageNumber: number, localFile: `sources/${filename}`, downloadedFrom: sourceUrl });
}

const tileW = 300;
const tileH = 400;
const gap = 14;
for (let page = 0; page < Math.ceil(records.length / 12); page++) {
  const subset = records.slice(page * 12, page * 12 + 12);
  const tiles = [];
  for (const [slot, item] of subset.entries()) {
    const image = await sharp(path.join(dir, item.localFile)).resize(tileW, tileH, { fit: "cover" }).jpeg().toBuffer();
    const label = Buffer.from(`<svg width="${tileW}" height="${tileH}" xmlns="http://www.w3.org/2000/svg">
      <rect width="84" height="58" rx="0" fill="#000" opacity=".82"/>
      <text x="42" y="42" text-anchor="middle" font-family="Arial Black,Arial" font-size="34" font-weight="900" fill="#fff">${item.imageNumber}</text>
    </svg>`);
    const tile = await sharp(image).composite([{ input: label }]).jpeg({ quality: 90 }).toBuffer();
    tiles.push({ input: tile, left: (slot % 4) * (tileW + gap), top: Math.floor(slot / 4) * (tileH + gap) });
  }
  await sharp({ create: { width: tileW * 4 + gap * 3, height: tileH * 3 + gap * 2, channels: 3, background: "#111" } })
    .composite(tiles)
    .jpeg({ quality: 92 })
    .toFile(path.join(sheets, `contact-${page + 1}.jpg`));
}

await fs.writeFile(path.join(dir, "image-index.json"), JSON.stringify(records, null, 2));
console.log(`Prepared ${records.length} images and ${Math.ceil(records.length / 12)} contact sheets.`);
