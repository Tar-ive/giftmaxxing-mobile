import path from "node:path";
import { fileURLToPath } from "node:url";
import sharp from "../web/node_modules/sharp/lib/index.js";

const repo = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const sourceDir = path.join(repo, "output/onboarding-audit-2026-08-12");
const output = path.join(sourceDir, "onboarding-flow-map.png");
const screens = [
  ["01-about-you.png", "01 · About you"],
  ["02-contacts.png", "02 · Contacts"],
  ["03-preferences.png", "03 · Preferences"],
  ["04-invite.png", "04 · Invite five"],
  ["05-taste-calibration.png", "05 · Taste swipes"],
  ["06-value.png", "06 · Value recap"],
  ["07-first-save.png", "07 · First save"],
  ["08-sign-in.png", "08 · Sign in"],
  ["09-tour-swipe.png", "09 · Tour: Swipe"],
  ["10-tour-circles.png", "10 · Tour: Circles"],
  ["11-tour-you.png", "11 · Tour: You"],
  ["12-tour-search.png", "12 · Tour: Search"],
];

const columns = 4;
const cardWidth = 320;
const imageHeight = 694;
const labelHeight = 52;
const cardHeight = labelHeight + imageHeight;
const gap = 16;
const headerHeight = 104;
const rows = Math.ceil(screens.length / columns);
const canvasWidth = columns * cardWidth + (columns - 1) * gap;
const canvasHeight = headerHeight + rows * cardHeight + (rows - 1) * gap;
const background = { r: 247, g: 242, b: 235, alpha: 1 };

const cards = await Promise.all(screens.map(async ([file, label]) => {
  const image = await sharp(path.join(sourceDir, file))
    .resize(cardWidth, imageHeight, { fit: "cover" })
    .png()
    .toBuffer();
  return sharp({ create: { width: cardWidth, height: cardHeight, channels: 4, background } })
    .composite([
      { input: image, top: labelHeight, left: 0 },
      {
        input: {
          text: {
            text: `<span foreground="#1A1A1A"><b>${label}</b></span>`,
            font: "SF Pro",
            width: cardWidth - 24,
            height: 34,
            align: "center",
            rgba: true,
          },
        },
        top: 9,
        left: 12,
      },
    ])
    .png()
    .toBuffer();
}));

const title = await sharp({
  text: {
    text: '<span foreground="#1A1A1A"><b>Giftmaxxing onboarding · current 12-screen path</b></span>\n<span foreground="#6B6560">7 setup screens → authentication → 4 coach marks</span>',
    font: "SF Pro",
    width: canvasWidth - 48,
    height: headerHeight - 20,
    align: "left",
    rgba: true,
  },
}).png().toBuffer();

await sharp({ create: { width: canvasWidth, height: canvasHeight, channels: 4, background } })
  .composite([
    { input: title, top: 16, left: 24 },
    ...cards.map((input, index) => ({
      input,
      left: (index % columns) * (cardWidth + gap),
      top: headerHeight + Math.floor(index / columns) * (cardHeight + gap),
    })),
  ])
  .png()
  .toFile(output);

console.log(output);
