import fs from 'node:fs/promises';
import path from 'node:path';
import sharp from '../../../web/node_modules/sharp/lib/index.js';

const root = path.dirname(new URL(import.meta.url).pathname);
const files = (await fs.readdir(root)).filter((file) => /^image-\d+\.jpeg$/.test(file)).sort();
const thumbWidth = 248;
const thumbHeight = 441;
const gap = 18;
const labelHeight = 42;

for (let page = 0; page < 2; page += 1) {
  const group = files.slice(page * 5, page * 5 + 5);
  const composites = [];
  for (const [index, file] of group.entries()) {
    const left = gap + index * (thumbWidth + gap);
    composites.push({
      input: await sharp(path.join(root, file)).rotate().resize(thumbWidth, thumbHeight, { fit: 'cover' }).toBuffer(),
      left,
      top: gap + labelHeight
    });
    composites.push({
      input: Buffer.from(`<svg width="${thumbWidth}" height="${labelHeight}" xmlns="http://www.w3.org/2000/svg"><text x="${thumbWidth / 2}" y="30" text-anchor="middle" font-family="Helvetica" font-size="24" fill="#171717">slide ${page * 5 + index + 1}</text></svg>`),
      left,
      top: gap
    });
  }

  await sharp({
    create: {
      width: gap + group.length * (thumbWidth + gap),
      height: thumbHeight + labelHeight + gap * 2,
      channels: 3,
      background: '#f3efe9'
    }
  }).composite(composites).jpeg({ quality: 94 }).toFile(path.join(root, `contact-sheet-${page + 1}.jpg`));
}

console.log('Created two reference contact sheets.');
