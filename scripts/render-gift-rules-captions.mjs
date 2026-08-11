import { mkdir } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import sharp from "../web/node_modules/sharp/lib/index.js";

const root = dirname(dirname(fileURLToPath(import.meta.url)));
const outputDir = join(root, "marketing-assets/video/gift-rules-30s/caption-cards");
const cards = [
  ["01", "STOP BUYING FORGETTABLE GIFTS", "Five rules for gifts people remember."],
  ["02", "1. SOLVE A MICRO-FRICTION", "Replace the thing they tolerate every day."],
  ["03", "2. UPGRADE THE EVERYDAY", "Buy the best version of something inexpensive."],
  ["04", "3. USE AN INSIDE CALLBACK", "Turn your shared memory into something physical."],
  ["05", "4. GIVE GUILT-FREE PERMISSION", "Support the experience they keep postponing."],
  ["06", "5. KEEP THE NOTES", "What friction or desire can I solve?"],
];

const escape = (text) => text.replaceAll("&", "&amp;").replaceAll("<", "&lt;").replaceAll(">", "&gt;");

await mkdir(outputDir, { recursive: true });
for (const [id, title, subtitle] of cards) {
  const svg = `
    <svg width="720" height="1280" xmlns="http://www.w3.org/2000/svg">
      <rect x="42" y="1015" width="636" height="176" rx="28" fill="rgba(8,8,12,.76)"/>
      <text x="360" y="1080" text-anchor="middle" fill="white" font-family="Arial, sans-serif" font-size="31" font-weight="700">${escape(title)}</text>
      <text x="360" y="1134" text-anchor="middle" fill="white" font-family="Arial, sans-serif" font-size="24">${escape(subtitle)}</text>
      <text x="360" y="1240" text-anchor="middle" fill="rgba(255,255,255,.75)" font-family="Arial, sans-serif" font-size="18" font-weight="700" letter-spacing="3">GIFTMAXXING</text>
    </svg>`;
  await sharp(Buffer.from(svg)).png().toFile(join(outputDir, `${id}.png`));
}
