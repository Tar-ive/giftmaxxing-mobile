import fs from 'node:fs/promises';
import path from 'node:path';
import sharp from '../../../web/node_modules/sharp/lib/index.js';

const root = path.dirname(new URL(import.meta.url).pathname);
const source = path.join(root, 'base', '09-unopened-big-gift.png');
const output = path.join(root, 'final', '09-more-in-part-2.png');
const title = 'more in part 2- comng soon';

const overlay = Buffer.from(`
<svg width="1080" height="1920" xmlns="http://www.w3.org/2000/svg">
  <rect x="82" y="590" width="916" height="126" rx="8" fill="#2b2023" fill-opacity="0.82"/>
  <line x1="118" y1="653" x2="202" y2="653" stroke="#f2dfe2" stroke-width="2"/>
  <line x1="878" y1="653" x2="962" y2="653" stroke="#f2dfe2" stroke-width="2"/>
  <text x="540" y="675" text-anchor="middle" fill="#fff7f5"
    font-family="Georgia, Times New Roman, serif" font-size="52" font-weight="400"
    letter-spacing="0.1">${title}</text>
</svg>`);

await fs.mkdir(path.dirname(output), { recursive: true });
await sharp(source)
  .resize(1080, 1920, { fit: 'cover', position: 'centre' })
  .composite([{ input: overlay, top: 0, left: 0 }])
  .png({ compressionLevel: 9 })
  .toFile(output);

console.log(output);
