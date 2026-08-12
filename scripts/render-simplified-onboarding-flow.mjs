import path from "node:path";
import { fileURLToPath } from "node:url";
import sharp from "../web/node_modules/sharp/lib/index.js";

const repo = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const dir = path.join(repo, "output/onboarding-simplified-2026-08-12");
const output = path.join(dir, "simplified-onboarding-flow.png");
const screens = [
  ["01-recipient.png", "01 · Recipient + budget"],
  ["02-leaderboard.png", "02 · Community proof"],
  ["03-swipe.png", "Ongoing · Taste learning"],
];
const width = 360, imageHeight = 780, labelHeight = 54, gap = 18, header = 104;
const background = { r: 247, g: 242, b: 235, alpha: 1 };
const cards = await Promise.all(screens.map(async ([file, label]) => {
  const image = await sharp(path.join(dir, file)).resize(width, imageHeight, { fit: "cover" }).png().toBuffer();
  const text = await sharp({ text: { text: `<b>${label}</b>`, font: "SF Pro", width: width - 20, height: 36, align: "center", rgba: true } }).png().toBuffer();
  return sharp({ create: { width, height: imageHeight + labelHeight, channels: 4, background } })
    .composite([{ input: text, top: 9, left: 10 }, { input: image, top: labelHeight, left: 0 }]).png().toBuffer();
}));
const canvasWidth = screens.length * width + (screens.length - 1) * gap;
const title = await sharp({ text: {
  text: '<b>Giftmaxxing · simplified onboarding</b>\n<span foreground="#6B6560">2 setup screens → continuous, optional taste learning</span>',
  font: "SF Pro", width: canvasWidth - 40, height: 80, align: "left", rgba: true,
} }).png().toBuffer();
await sharp({ create: { width: canvasWidth, height: header + imageHeight + labelHeight, channels: 4, background } })
  .composite([{ input: title, left: 20, top: 14 }, ...cards.map((input, i) => ({ input, left: i * (width + gap), top: header }))])
  .png().toFile(output);
console.log(output);
