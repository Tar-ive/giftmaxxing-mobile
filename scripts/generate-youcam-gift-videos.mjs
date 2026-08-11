// Generate short gift-content clips from approved Pinterest references.
// Usage: YOUCAM_API_KEY=... node scripts/generate-youcam-gift-videos.mjs

import { mkdir, stat, writeFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const apiKey = process.env.YOUCAM_API_KEY;
if (!apiKey) throw new Error("YOUCAM_API_KEY is required");

const root = dirname(dirname(fileURLToPath(import.meta.url)));
const outputDir = join(root, "marketing-assets/video/pinterest-giftgiving/youcam-2026-08-04/outputs");
const endpoint = "https://yce-api-01.makeupar.com/s2s/v2.0/task/image-to-video/youcam";
const negative = "warped objects, melting, duplicated items, distorted text, misspelled labels, extra fingers, deformed hands, flicker, camera shake, blur, low resolution, watermark";

const jobs = [
  {
    name: "mini-photo-album",
    source: "https://d21osnvwewgoao.cloudfront.net/ugc/public/editorial/pinterest/ukK6yxJmbvEyK5aNV/birthday-gifts-that-feel-personal/4996249584015834.png",
    prompt: "A gentle handheld push-in. The hand slowly fans the tiny camera-shaped photo album so the glossy snapshots catch warm light; the twine sways slightly. Preserve the handmade album, fingers, printed photos, and handwritten Barcelona 2023 label exactly. Authentic cozy phone-video look.",
  },
  {
    name: "self-care-gift-basket",
    source: "https://d21osnvwewgoao.cloudfront.net/ugc/public/editorial/pinterest/ukK6yxJmbvEyK5aNV/build-a-better-gift-basket/5911043262770659.jpg",
    prompt: "A slow smooth product-camera arc around the pink self-care gift basket. Clear wrapping catches soft highlights and narrow ribbons flutter subtly. Warm afternoon window light, shallow depth of field, realistic premium product video. Preserve every product, brand label, color, and the exact basket arrangement.",
  },
  {
    name: "pink-gift-wrapping",
    source: "https://d21osnvwewgoao.cloudfront.net/ugc/public/editorial/pinterest/ukK6yxJmbvEyK5aNV/gift-wrapping-worth-keeping/82612974398668191.jpg",
    prompt: "A slow overhead camera drift across the handmade pink wrapped present. Curled ribbons lift and settle gently, the pearl strand glints, and soft natural light moves across the paper. Preserve the exact gift, colors, bow, floral ribbon, pearls, and card. Premium DIY TikTok aesthetic.",
  },
];

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

async function request(url, init = {}) {
  const response = await fetch(url, {
    ...init,
    headers: { Authorization: `Bearer ${apiKey}`, ...(init.body ? { "content-type": "application/json" } : {}), ...init.headers },
  });
  const body = await response.json().catch(() => ({}));
  if (!response.ok) throw new Error(`${response.status} ${body.error_code || ""} ${body.error || "request failed"}`.trim());
  return body;
}

async function start(job) {
  const response = await request(endpoint, {
    method: "POST",
    body: JSON.stringify({
      src_file_url: job.source,
      resolution: "720",
      dst_duration: 5,
      prompt: job.prompt,
      negative_prompt: negative,
      model: "youcam-video-v2",
    }),
  });
  const taskId = response.data?.task_id;
  if (!taskId) throw new Error(`${job.name}: API returned no task_id`);
  console.log(`${job.name}: started ${taskId}`);
  return { ...job, taskId };
}

async function finish(job) {
  const statusUrl = `${endpoint}/${encodeURIComponent(job.taskId)}`;
  for (let attempt = 1; attempt <= 120; attempt++) {
    const status = await request(statusUrl);
    const resultUrl = status.data?.results?.url ?? status.data?.url ?? status.url;
    if (resultUrl) {
      const video = await fetch(resultUrl);
      if (!video.ok) throw new Error(`${job.name}: download failed (${video.status})`);
      const output = join(outputDir, `${job.name}.mp4`);
      await writeFile(output, Buffer.from(await video.arrayBuffer()));
      console.log(`${job.name}: saved ${output}`);
      return { ...job, output };
    }
    const error = status.data?.error ?? status.error;
    if (error || status.error_code) throw new Error(`${job.name}: ${status.error_code || error}`);
    await sleep(5_000);
  }
  throw new Error(`${job.name}: timed out waiting for result`);
}

await mkdir(outputDir, { recursive: true });
const completed = [];
for (const job of jobs) {
  const output = join(outputDir, `${job.name}.mp4`);
  const existing = await stat(output).catch(() => null);
  if (existing?.size) {
    console.log(`${job.name}: keeping existing ${output}`);
    completed.push({ ...job, output, reused: true });
    continue;
  }
  completed.push(await finish(await start(job)));
}
await writeFile(join(outputDir, "manifest.json"), JSON.stringify({ generatedAt: new Date().toISOString(), jobs: completed }, null, 2) + "\n");
console.log(`Generated ${completed.length} videos.`);
