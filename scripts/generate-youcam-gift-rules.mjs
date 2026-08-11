// Generate six vertical scenes for the 30-second gift-rules video.
// Usage: YOUCAM_API_KEY=... node scripts/generate-youcam-gift-rules.mjs

import { mkdir, stat, writeFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const apiKey = process.env.YOUCAM_API_KEY;
if (!apiKey) throw new Error("YOUCAM_API_KEY is required");

const root = dirname(dirname(fileURLToPath(import.meta.url)));
const outputDir = join(root, "marketing-assets/video/gift-rules-30s/scenes");
const endpoint = "https://yce-api-01.makeupar.com/s2s/v2.0/task/text-to-video/youcam";
const negative = "text, captions, logos, watermark, distorted hands, extra fingers, warped objects, duplicated items, flicker, shaky camera, low resolution, oversaturated skin, plastic skin";

const scenes = [
  {
    name: "01-forgettable-gifts",
    prompt: "Vertical cinematic social video. A stylish young adult opens a hallway closet and finds an untouched generic candle, bath gift set, and plain gift card among forgotten clutter, then closes the door with disappointment. Warm realistic apartment lighting, subtle handheld push-in, relatable premium TikTok lifestyle aesthetic, no readable text.",
  },
  {
    name: "02-micro-friction",
    prompt: "Vertical cinematic close-up in a beautiful home kitchen. A thoughtful hand replaces a messy leaking olive oil bottle with an elegant no-drip glass dispenser, wipes the counter clean, then pours perfectly into a pan. Satisfying precise motion, natural morning light, realistic hands, premium lifestyle commercial.",
  },
  {
    name: "03-small-luxury",
    prompt: "Vertical premium food-film close-up. A beautifully packaged bottle of artisanal maple syrup is opened and poured slowly over a warm breakfast, rich amber highlights and steam, a recipient smiles with genuine delight in the soft background. Small everyday luxury, natural skin, editorial gift campaign, smooth camera arc.",
  },
  {
    name: "04-inside-callback",
    prompt: "Vertical intimate gift moment between two close friends at a coffee table. One unwraps a handcrafted wooden chess set and immediately laughs with recognition of a shared memory; the other smiles. Authentic emotion, tasteful modern apartment, warm afternoon light, realistic natural skin, gentle push-in, no readable text.",
  },
  {
    name: "05-permission-gift",
    prompt: "Vertical luxury beauty experience video. A woman relaxes during a personalized professional facial she has wanted for months, a skincare expert gently applies a hydrating treatment, luminous healthy natural skin with realistic texture, peaceful expression, refined clean studio, soft diffused light, slow cinematic movement, clearly an experience gift rather than a generic product.",
  },
  {
    name: "06-gift-notes",
    prompt: "Vertical over-the-shoulder lifestyle video. After a friend casually mentions something they love, a thoughtful person discreetly opens the notes app on their phone and adds an idea to a neatly organized gift list, then smiles. Screen content remains abstract and unreadable for later graphic overlay. Cozy cafe light, realistic hands, smooth subtle camera motion.",
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

async function start(scene) {
  const response = await request(endpoint, {
    method: "POST",
    body: JSON.stringify({
      model: "youcam-video-v2",
      prompt: scene.prompt,
      negative_prompt: negative,
      resolution: "720P",
      ratio: "9:16",
      dst_duration: 5,
      prompt_extend: true,
    }),
  });
  const taskId = response.data?.task_id;
  if (!taskId) throw new Error(`${scene.name}: API returned no task_id`);
  console.log(`${scene.name}: started ${taskId}`);
  return { ...scene, taskId };
}

async function finish(scene) {
  for (let attempt = 1; attempt <= 120; attempt++) {
    const status = await request(`${endpoint}/${encodeURIComponent(scene.taskId)}`);
    const resultUrl = status.data?.results?.url ?? status.data?.url ?? status.url;
    if (resultUrl) {
      const video = await fetch(resultUrl);
      if (!video.ok) throw new Error(`${scene.name}: download failed (${video.status})`);
      const output = join(outputDir, `${scene.name}.mp4`);
      await writeFile(output, Buffer.from(await video.arrayBuffer()));
      console.log(`${scene.name}: saved ${output}`);
      return { ...scene, output };
    }
    const error = status.data?.error ?? status.error;
    if (error || status.error_code) throw new Error(`${scene.name}: ${status.error_code || error}`);
    await sleep(5_000);
  }
  throw new Error(`${scene.name}: timed out waiting for result`);
}

await mkdir(outputDir, { recursive: true });
const completed = [];
for (const scene of scenes) {
  const output = join(outputDir, `${scene.name}.mp4`);
  const existing = await stat(output).catch(() => null);
  if (existing?.size) {
    console.log(`${scene.name}: keeping existing ${output}`);
    completed.push({ ...scene, output, reused: true });
    continue;
  }
  completed.push(await finish(await start(scene)));
}
await writeFile(join(outputDir, "manifest.json"), JSON.stringify({ generatedAt: new Date().toISOString(), scenes: completed }, null, 2) + "\n");
console.log(`Generated ${completed.length} scenes.`);
