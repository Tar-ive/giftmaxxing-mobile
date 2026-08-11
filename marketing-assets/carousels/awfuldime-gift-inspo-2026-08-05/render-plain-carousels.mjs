import fs from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import sharp from "../../../web/node_modules/sharp/lib/index.js";

const dir = path.dirname(fileURLToPath(import.meta.url));
const specs = JSON.parse(await fs.readFile(path.join(dir, "carousel-specs.json"), "utf8"));
const index = JSON.parse(await fs.readFile(path.join(dir, "image-index.json"), "utf8"));
const out = path.join(dir, "tiktok-ready-plain");

for (const [carouselIndex, carousel] of specs.carousels.entries()) {
  const folder = path.join(out, `${String(carouselIndex + 1).padStart(2, "0")}-${carousel.slug}`);
  await fs.mkdir(folder, { recursive: true });
  for (const [slideIndex, slide] of carousel.slides.entries()) {
    const source = index.find((image) => image.imageNumber === slide.imageNumber);
    if (!source) throw new Error(`Missing source image ${slide.imageNumber}`);
    await sharp(path.join(dir, source.localFile))
      .resize(1080, 1440, { fit: "cover", position: "centre" })
      .jpeg({ quality: 95, chromaSubsampling: "4:4:4" })
      .toFile(path.join(folder, `${String(slideIndex + 1).padStart(2, "0")}.jpg`));
  }
}

const uploadPlan = specs.carousels.map((carousel, i) => ({
  folder: `${String(i + 1).padStart(2, "0")}-${carousel.slug}`,
  caption: carousel.caption,
  slides: carousel.slides.map((slide, j) => ({
    file: `${String(j + 1).padStart(2, "0")}.jpg`,
    textOverlay: [slide.lines.join("\n"), slide.sub].filter(Boolean).join("\n"),
  })),
}));

await fs.writeFile(path.join(out, "tiktok-upload-plan.json"), JSON.stringify(uploadPlan, null, 2));
console.log(`Created ${specs.carousels.length} unbranded carousel folders in ${out}`);
