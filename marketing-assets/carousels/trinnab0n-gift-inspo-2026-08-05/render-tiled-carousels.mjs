import fs from 'node:fs/promises';
import path from 'node:path';
import sharp from '../../../web/node_modules/sharp/lib/index.js';

const root = path.dirname(new URL(import.meta.url).pathname);
const sourceDir = path.join(root, 'source-images');
const outputDir = path.join(root, 'tiled-slim-text');
const plan = JSON.parse(await fs.readFile(path.join(root, 'carousel-plan.json'), 'utf8'));
const { width, height } = plan.format.canvas;

const escapeXml = (value) => value
  .replaceAll('&', '&amp;')
  .replaceAll('<', '&lt;')
  .replaceAll('>', '&gt;')
  .replaceAll('"', '&quot;')
  .replaceAll("'", '&apos;');

const textOverlay = (title, subtitle) => Buffer.from(`
<svg width="${width}" height="${height}" xmlns="http://www.w3.org/2000/svg">
  <rect x="72" y="804" width="936" height="148" rx="8" fill="#24191b" fill-opacity="0.88"/>
  <line x1="116" y1="878" x2="218" y2="878" stroke="#efdadd" stroke-width="2"/>
  <line x1="862" y1="878" x2="964" y2="878" stroke="#efdadd" stroke-width="2"/>
  <text x="540" y="900" text-anchor="middle" fill="#f6e7e9"
    font-family="Georgia, Times New Roman, serif" font-size="58" font-weight="400"
    letter-spacing="0.2">${escapeXml(title)}</text>
  <rect x="198" y="952" width="684" height="82" rx="5" fill="#b96f79" fill-opacity="0.94"/>
  <text x="540" y="1006" text-anchor="middle" fill="#fff9f7"
    font-family="Helvetica Neue, Helvetica, Arial, sans-serif" font-size="31" font-weight="300"
    letter-spacing="0.4">${escapeXml(subtitle)}</text>
</svg>`);

async function renderCard(card, destination) {
  const tileHeight = height / card.tiles.length;
  const tiles = await Promise.all(card.tiles.map(async (file) => ({
    input: await sharp(path.join(sourceDir, file))
      .rotate()
      .resize(width, tileHeight, { fit: 'cover', position: 'attention' })
      .jpeg({ quality: 94, chromaSubsampling: '4:4:4' })
      .toBuffer()
  })));

  await sharp({
    create: { width, height, channels: 3, background: '#efe8e1' }
  })
    .composite([
      ...tiles.map((tile, index) => ({ ...tile, top: index * tileHeight, left: 0 })),
      { input: textOverlay(card.title, card.subtitle), top: 0, left: 0 }
    ])
    .jpeg({ quality: 94, chromaSubsampling: '4:4:4' })
    .toFile(destination);
}

for (const carousel of plan.carousels) {
  const carouselDir = path.join(outputDir, carousel.id);
  await fs.rm(carouselDir, { recursive: true, force: true });
  await fs.mkdir(carouselDir, { recursive: true });
  for (const [index, card] of carousel.cards.entries()) {
    await renderCard(card, path.join(carouselDir, `${String(index + 1).padStart(2, '0')}.jpg`));
  }

  const thumbs = await Promise.all(carousel.cards.map(async (_, index) => ({
    input: await sharp(path.join(carouselDir, `${String(index + 1).padStart(2, '0')}.jpg`))
      .resize(216, 384, { fit: 'cover' })
      .toBuffer(),
    left: index * 228,
    top: 12
  })));

  await sharp({
    create: { width: carousel.cards.length * 228 + 12, height: 408, channels: 3, background: '#f3eee9' }
  })
    .composite(thumbs)
    .jpeg({ quality: 92 })
    .toFile(path.join(carouselDir, 'contact-sheet.jpg'));
}

await fs.copyFile(path.join(root, 'carousel-plan.json'), path.join(outputDir, 'carousel-plan.json'));
console.log(`Rendered ${plan.carousels.reduce((sum, item) => sum + item.cards.length, 0)} cards to ${outputDir}`);
