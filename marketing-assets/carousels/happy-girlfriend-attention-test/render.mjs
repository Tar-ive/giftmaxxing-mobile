import fs from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import sharp from "../../../web/node_modules/sharp/lib/index.js";

const dir = path.dirname(fileURLToPath(import.meta.url));
const out = path.join(dir, "slides");
const W = 1080;
const H = 1440;

const slides = [
  {
    source: "938296903635661572.jpg",
    lines: ["Tutorial on how to make a", "happy girlfriend!"],
    sub: "Thoughtful Edition • Under $20",
    y: 355,
    size: 72,
  },
  {
    source: "1098878377855285863.webp",
    lines: ["Step 1: Learn her oddly", "specific favorites—snack, drink,", "flower and color"],
    y: 455,
    size: 60,
  },
  {
    source: "4996249584015834.png",
    lines: ["Step 2: Turn one shared", "memory into something", "she can hold"],
    y: 420,
    size: 66,
  },
  {
    source: "192317846581291745.jpg",
    lines: ["Step 3: Buy the luxury version", "of one tiny thing", "she already loves"],
    y: 420,
    size: 58,
  },
  {
    source: "1266706142219574.jpg",
    lines: ["Step 4: Add one sappy note", "that could only be for her"],
    y: 410,
    size: 66,
  },
  {
    source: "3799980931637449.jpg",
    lines: ["Step 5: Wrap it in her colors", "(inside joke = bonus points)"],
    y: 410,
    size: 66,
  },
  {
    source: "1105704146043517015.png",
    lines: ["Congratulations!", "She feels known—", "not just “gifted”"],
    y: 250,
    size: 72,
  },
];

const esc = (value) => value.replaceAll("&", "&amp;").replaceAll("<", "&lt;").replaceAll(">", "&gt;");

function overlay(slide, index) {
  const lineHeight = Math.round(slide.size * 1.12);
  const title = slide.lines
    .map((line, i) => `<tspan x="540" y="${slide.y + i * lineHeight}">${esc(line)}</tspan>`)
    .join("");
  const subY = slide.y + slide.lines.length * lineHeight + 28;

  return Buffer.from(`
    <svg width="${W}" height="${H}" xmlns="http://www.w3.org/2000/svg">
      <rect width="${W}" height="${H}" fill="#000" opacity="0.06"/>
      <g font-family="Arial Black, Arial, sans-serif" text-anchor="middle" fill="#fff"
         stroke="#080808" stroke-width="15" stroke-linejoin="round" paint-order="stroke fill">
        <text font-size="${slide.size}" font-weight="900">${title}</text>
        ${slide.sub ? `<text x="540" y="${subY}" font-size="43" font-weight="900">${esc(slide.sub)}</text>` : ""}
      </g>
      <g font-family="Arial, sans-serif" font-size="28" font-weight="700" fill="#fff"
         stroke="#080808" stroke-width="8" paint-order="stroke fill">
        <text x="42" y="1388">@giftmaxxing</text>
        ${index < slides.length - 1 ? `<text x="920" y="1388">swipe →</text>` : ""}
      </g>
    </svg>`);
}

await fs.mkdir(out, { recursive: true });

for (const [index, slide] of slides.entries()) {
  const input = path.join(dir, "sources", slide.source);
  const output = path.join(out, `${String(index + 1).padStart(2, "0")}.jpg`);
  await sharp(input)
    .resize(W, H, { fit: "cover", position: "centre" })
    .composite([{ input: overlay(slide, index) }])
    .jpeg({ quality: 95, chromaSubsampling: "4:4:4" })
    .toFile(output);
}

console.log(`Rendered ${slides.length} slides to ${out}`);
