import fs from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import sharp from "../../../web/node_modules/sharp/lib/index.js";

const dir = path.dirname(fileURLToPath(import.meta.url));
const specs = JSON.parse(await fs.readFile(path.join(dir, "carousel-specs.json"), "utf8"));
const analysis = JSON.parse(await fs.readFile(path.join(dir, "image-analysis.json"), "utf8"));
const index = JSON.parse(await fs.readFile(path.join(dir, "image-index.json"), "utf8"));
const known = new Set(analysis.images.map((image) => image.imageNumber));
const W = specs.format.width;
const H = specs.format.height;

const esc = (value) => value.replaceAll("&", "&amp;").replaceAll("<", "&lt;").replaceAll(">", "&gt;");

function textOverlay(slide, number, total) {
  const lineHeight = Math.round(slide.fontSize * 1.12);
  const title = slide.lines.map((line, i) => `<tspan x="540" y="${slide.y + i * lineHeight}">${esc(line)}</tspan>`).join("");
  const subY = slide.y + slide.lines.length * lineHeight + 28;
  return Buffer.from(`<svg width="${W}" height="${H}" xmlns="http://www.w3.org/2000/svg">
    <defs><linearGradient id="shade" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#000" stop-opacity=".18"/><stop offset=".72" stop-color="#000" stop-opacity="0"/><stop offset="1" stop-color="#000" stop-opacity=".16"/></linearGradient></defs>
    <rect width="${W}" height="${H}" fill="url(#shade)"/>
    <g text-anchor="middle" font-family="Arial Black,Arial,sans-serif" font-weight="900" fill="#fff" stroke="#080808" stroke-width="15" stroke-linejoin="round" paint-order="stroke fill">
      <text font-size="${slide.fontSize}">${title}</text>
      ${slide.sub ? `<text x="540" y="${subY}" font-size="42">${esc(slide.sub)}</text>` : ""}
    </g>
    <g font-family="Arial,sans-serif" font-size="27" font-weight="700" fill="#fff" stroke="#080808" stroke-width="8" paint-order="stroke fill">
      <text x="40" y="1392">@giftmaxxing</text><text x="1000" y="1392" text-anchor="end">${number}/${total}${number < total ? "  swipe →" : ""}</text>
    </g>
  </svg>`);
}

for (const carousel of specs.carousels) {
  const out = path.join(dir, "carousels", carousel.slug);
  await fs.mkdir(out, { recursive: true });
  const thumbs = [];
  for (const [i, slide] of carousel.slides.entries()) {
    if (!known.has(slide.imageNumber)) throw new Error(`Image ${slide.imageNumber} lacks analysis metadata`);
    const item = index.find((image) => image.imageNumber === slide.imageNumber);
    if (!item) throw new Error(`Image ${slide.imageNumber} lacks a local source`);
    const output = path.join(out, `${String(i + 1).padStart(2, "0")}.jpg`);
    await sharp(path.join(dir, item.localFile))
      .resize(W, H, { fit: "cover", position: "centre" })
      .composite([{ input: textOverlay(slide, i + 1, carousel.slides.length) }])
      .jpeg({ quality: 95, chromaSubsampling: "4:4:4" })
      .toFile(output);
    const thumb = await sharp(output).resize(270, 360).jpeg({ quality: 88 }).toBuffer();
    thumbs.push({ input: thumb, left: (i % 4) * 282, top: Math.floor(i / 4) * 372 });
  }
  await sharp({ create: { width: 1116, height: 732, channels: 3, background: "#111" } })
    .composite(thumbs)
    .jpeg({ quality: 92 })
    .toFile(path.join(out, "contact-sheet.jpg"));
}

console.log(`Rendered ${specs.carousels.length} carousels from analyzed metadata.`);
