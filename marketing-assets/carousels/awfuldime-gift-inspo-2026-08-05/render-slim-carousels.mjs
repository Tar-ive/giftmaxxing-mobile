import fs from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import sharp from "../../../web/node_modules/sharp/lib/index.js";

const dir = path.dirname(fileURLToPath(import.meta.url));
const specs = JSON.parse(await fs.readFile(path.join(dir, "carousel-specs.json"), "utf8"));
const index = JSON.parse(await fs.readFile(path.join(dir, "image-index.json"), "utf8"));
const root = path.join(dir, "tiktok-ready-slim-text");
const W = 1080;
const H = 1440;

for (const carousel of specs.carousels) {
  for (const slide of carousel.slides) {
    const copy = [...slide.lines, slide.sub ?? ""].join(" ");
    if (/\b[A-Z]{2,}\b/.test(copy)) throw new Error(`all-caps copy is not allowed: ${copy}`);
    if (slide.lines.some((line) => line.length > 36)) throw new Error(`carousel copy is too long: ${copy}`);
  }
}

const esc = (value) => value.replaceAll("&", "&amp;").replaceAll("<", "&lt;").replaceAll(">", "&gt;");

function overlay(slide) {
  const size = Math.max(48, Math.round(slide.fontSize * 0.84));
  const lineHeight = Math.round(size * 1.13);
  const lines = slide.lines.map((line, i) => `<tspan x="540" y="${slide.y + i * lineHeight}">${esc(line)}</tspan>`).join("");
  const subY = slide.y + slide.lines.length * lineHeight + 24;
  return Buffer.from(`<svg width="${W}" height="${H}" xmlns="http://www.w3.org/2000/svg">
    <defs><filter id="shadow"><feDropShadow dx="0" dy="3" stdDeviation="3" flood-color="#000" flood-opacity=".7"/></filter></defs>
    <g text-anchor="middle" font-family="Helvetica Neue,Helvetica,Arial,sans-serif" font-weight="700" fill="#fff" stroke="#111" stroke-width="6" stroke-linejoin="round" paint-order="stroke fill" filter="url(#shadow)">
      <text font-size="${size}">${lines}</text>
      ${slide.sub ? `<text x="540" y="${subY}" font-size="36" font-weight="600">${esc(slide.sub)}</text>` : ""}
    </g>
  </svg>`);
}

for (const [carouselIndex, carousel] of specs.carousels.entries()) {
  const folder = path.join(root, `${String(carouselIndex + 1).padStart(2, "0")}-${carousel.slug}`);
  await fs.mkdir(folder, { recursive: true });
  const thumbs = [];
  for (const [slideIndex, slide] of carousel.slides.entries()) {
    const source = index.find((image) => image.imageNumber === slide.imageNumber);
    if (!source) throw new Error(`Missing source image ${slide.imageNumber}`);
    const output = path.join(folder, `${String(slideIndex + 1).padStart(2, "0")}.jpg`);
    await sharp(path.join(dir, source.localFile))
      .resize(W, H, { fit: "cover", position: "centre" })
      .composite([{ input: overlay(slide) }])
      .jpeg({ quality: 95, chromaSubsampling: "4:4:4" })
      .toFile(output);
    thumbs.push({ input: await sharp(output).resize(270, 360).jpeg({ quality: 88 }).toBuffer(), left: (slideIndex % 4) * 282, top: Math.floor(slideIndex / 4) * 372 });
  }
  await sharp({ create: { width: 1116, height: 732, channels: 3, background: "#111" } })
    .composite(thumbs)
    .jpeg({ quality: 92 })
    .toFile(path.join(folder, "contact-sheet.jpg"));
}

const uploadPlan = specs.carousels.map((carousel, i) => ({
  folder: `${String(i + 1).padStart(2, "0")}-${carousel.slug}`,
  title: carousel.heading,
  caption: carousel.caption,
  slides: carousel.slides.map((slide, j) => ({ file: `${String(j + 1).padStart(2, "0")}.jpg`, textOverlay: [slide.lines.join("\n"), slide.sub].filter(Boolean).join("\n") })),
}));
await fs.writeFile(path.join(root, "tiktok-upload-plan.json"), JSON.stringify(uploadPlan, null, 2));
console.log(`Rendered ${specs.carousels.length} slim-text carousels to ${root}`);
