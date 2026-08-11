// YouCam UGC pipeline: text-to-image -> reference image-to-image -> image-to-video.
// Usage: YOUCAM_API_KEY=... node scripts/generate-youcam-gift-rules-ugc.mjs --stage images|videos|all

import { basename, dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { mkdir, readFile, stat, writeFile } from "node:fs/promises";
import sharp from "../web/node_modules/sharp/lib/index.js";

const apiKey = process.env.YOUCAM_API_KEY;
if (!apiKey) throw new Error("YOUCAM_API_KEY is required");

const stage = process.argv.includes("--stage") ? process.argv[process.argv.indexOf("--stage") + 1] : "all";
if (!["images", "videos", "all"].includes(stage)) throw new Error("--stage must be images, videos, or all");

const root = dirname(dirname(fileURLToPath(import.meta.url)));
const assetDir = join(root, "marketing-assets/video/gift-rules-ugc-v2");
const stillDir = join(assetDir, "stills");
const sceneDir = join(assetDir, "scenes");
const base = "https://yce-api-01.makeupar.com/s2s/v2.0";
const imageNegative = "AI-generated look, glossy commercial, studio lighting, plastic skin, beauty retouching, deformed hands, extra fingers, distorted objects, duplicate objects, readable text, captions, logos, watermark";
const videoNegative = "identity drift, face morphing, warped hands, extra fingers, object morphing, duplicated objects, distorted text, flicker, camera shake, plastic skin, captions, logos, watermark";

const shots = [
  {
    name: "01-forgettable-gifts",
    imagePrompt: "Authentic vertical iPhone UGC photo. A woman in her late 20s with warm olive skin, shoulder-length loose dark brown hair, cream knit sweater, minimal makeup, and small gold hoops stands at a cluttered apartment gift closet. She holds an untouched generic candle and plain gift card and gives the phone camera a mildly unimpressed look. Natural window light, realistic skin, slightly imperfect handheld framing, safe caption space, no readable text or branding.",
    motionPrompt: "Subtle handheld phone drift. She glances from the generic candle and gift card toward the cluttered closet, gives a small unimpressed expression, then lowers the items. Preserve her exact face, hands, clothing, and every object. Natural UGC motion, no speaking.",
  },
  {
    name: "02-micro-friction",
    imagePrompt: "Retain ONLY the woman's exact identity, hair, sweater, earrings, and realistic UGC style from Image 1. Remove the candle, card, closet, and original pose completely. In a warm apartment kitchen, she replaces a messy olive oil bottle with an elegant no-drip glass dispenser beside a frying pan. One hand holds the dispenser; the other moves the old bottle aside. Natural morning light, realistic hands, safe caption space, no labels.",
    motionPrompt: "She sets aside the leaky bottle, lifts the no-drip dispenser, and pours a small clean stream into the pan. Gentle handheld phone movement. Preserve her exact identity, outfit, dispenser, bottle, counter, and realistic hands. No speaking.",
  },
  {
    name: "03-small-luxury",
    imagePrompt: "Use Image 1 as the exact identity and wardrobe reference. The same woman sits at a casual breakfast table, pouring beautiful amber artisanal maple syrup from an unbranded glass bottle over pancakes. Her expression shows delighted surprise at an elevated everyday luxury. Vertical iPhone UGC photo, warm window light, authentic home texture, realistic face and hands, safe caption space, no text or logos.",
    motionPrompt: "She slowly pours amber syrup over the pancakes, watches it settle, and smiles with genuine delight. Small natural handheld push-in. Preserve her exact identity, hands, bottle, food, and table. Realistic UGC motion, no speaking.",
  },
  {
    name: "04-inside-callback",
    imagePrompt: "Use Image 1 as the exact identity and wardrobe reference. The same woman gives a handcrafted wooden chess set to a close female friend at a coffee table. The friend has just opened it, and both share an immediate knowing laugh from an old inside joke. Vertical candid iPhone UGC photo, cozy apartment, natural afternoon light, believable emotion and hands, safe caption space, no readable text.",
    motionPrompt: "The friend opens the wooden chess set and reacts with recognition; both women share a warm laugh. Gentle phone-camera drift. Preserve both faces, all chess pieces, hands, clothing, and room. Natural restrained motion, no speaking.",
  },
  {
    name: "05-permission-gift",
    baseImagePrompt: "Use Image 1 as the exact identity and wardrobe reference. The same fully clothed woman sits in her cream sweater at a bright professional skincare studio for a personalized consultation she has wanted for months. An esthetician beside her holds a small mirror and gestures toward a simple unbranded routine card while the woman smiles with interest. Natural visible skin texture, vertical candid phone photo, soft daylight, safe caption space, no treatment or product labels.",
    imagePrompt: "Edit Image 1 only: remove every letter, word, mark, and glyph from the routine card. Replace the card surface with three simple muted color swatches and no text. Preserve both women's exact faces, skin texture, expressions, hands, clothing, mirror, room, framing, and lighting unchanged.",
    motionPrompt: "The fully clothed woman turns slightly toward the small mirror while the skincare professional gestures to an unbranded routine card; both share a warm smile. Slow natural phone-camera drift. Preserve her exact face, sweater, natural skin texture, mirror, card, hands, and room. No treatment, face touching, speaking, text, or exaggerated beauty effect.",
  },
  {
    name: "06-gift-notes",
    imagePrompt: "Keep the woman's exact identity, hair, sweater, earrings, and realistic UGC style from Image 1. Move her to a cozy cafe while a friend chats across the table. Camera is behind her right shoulder and shows ONLY the matte back of the phone; the screen is completely hidden from camera as she discreetly types with her thumb. No gifts, packages, cards, candles, screens, letters, words, or glyphs. Vertical candid iPhone photo, warm light, realistic hands, safe caption space.",
    motionPrompt: "She types one quick note on the phone, glances warmly toward her friend, and gives a subtle satisfied smile. The friend gestures casually in soft focus. Preserve both identities, phone, hands, cups, and cafe. Keep the screen unreadable, no speaking.",
  },
];

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
const exists = async (path) => (await stat(path).catch(() => null))?.size > 0;

async function request(url, init = {}) {
  const response = await fetch(url, {
    ...init,
    headers: { Authorization: `Bearer ${apiKey}`, ...(init.body ? { "content-type": "application/json" } : {}), ...init.headers },
  });
  const body = await response.json().catch(() => ({}));
  if (!response.ok) throw new Error(`${response.status} ${body.error_code || ""} ${body.error || "request failed"}`.trim());
  return body;
}

async function waitFor(taskEndpoint, taskId, label) {
  for (let attempt = 1; attempt <= 120; attempt++) {
    const status = await request(`${taskEndpoint}/${encodeURIComponent(taskId)}`);
    const resultUrl = status.data?.results?.url ?? status.data?.url ?? status.url;
    if (resultUrl) return resultUrl;
    const error = status.data?.error ?? status.error;
    if (error || status.error_code) throw new Error(`${label}: ${status.error_code || JSON.stringify(error)}`);
    await sleep(5_000);
  }
  throw new Error(`${label}: timed out`);
}

async function runTask(taskEndpoint, body, label) {
  const response = await request(taskEndpoint, { method: "POST", body: JSON.stringify(body) });
  const taskId = response.data?.task_id;
  if (!taskId) throw new Error(`${label}: API returned no task_id`);
  console.log(`${label}: started ${taskId}`);
  return { taskId, resultUrl: await waitFor(taskEndpoint, taskId, label) };
}

async function saveNormalized(url, output) {
  const response = await fetch(url);
  if (!response.ok) throw new Error(`download failed (${response.status})`);
  await sharp(Buffer.from(await response.arrayBuffer())).resize(720, 1280, { fit: "cover", position: "centre" }).png().toFile(output);
}

async function upload(fileEndpoint, filePath) {
  const file = await readFile(filePath);
  const metadata = await request(fileEndpoint, {
    method: "POST",
    body: JSON.stringify({ files: [{ content_type: "image/png", file_name: basename(filePath), file_size: file.length }] }),
  });
  const item = metadata.data?.files?.[0] ?? metadata.files?.[0];
  const uploadRequest = item?.requests?.[0];
  if (!item?.file_id || !uploadRequest?.url) throw new Error(`upload metadata missing for ${filePath}`);
  const response = await fetch(uploadRequest.url, {
    method: uploadRequest.method ?? "PUT",
    headers: uploadRequest.headers,
    body: file,
  });
  if (!response.ok) throw new Error(`upload failed for ${filePath} (${response.status})`);
  return item.file_id;
}

async function generateImages() {
  const manifest = [];
  const leadPath = join(stillDir, `${shots[0].name}.png`);
  if (!(await exists(leadPath))) {
    const task = await runTask(`${base}/task/text-to-image/youcam`, {
      model: "youcam-image-v2",
      prompt: shots[0].imagePrompt,
      negative_prompt: imageNegative,
      size: "928*1664",
      prompt_extend: false,
    }, shots[0].name);
    await saveNormalized(task.resultUrl, leadPath);
    manifest.push({ name: shots[0].name, taskId: task.taskId, output: leadPath });
    console.log(`${shots[0].name}: saved ${leadPath}`);
  } else {
    manifest.push({ name: shots[0].name, output: leadPath, reused: true });
  }

  const referenceId = await upload(`${base}/file/image-to-image/youcam`, leadPath);
  for (const shot of shots.slice(1)) {
    const output = join(stillDir, `${shot.name}.png`);
    if (await exists(output)) {
      manifest.push({ name: shot.name, output, reused: true });
      continue;
    }
    let sourceId = referenceId;
    if (shot.baseImagePrompt) {
      const basePath = join(stillDir, `${shot.name}-base.png`);
      if (!(await exists(basePath))) {
        const baseTask = await runTask(`${base}/task/image-to-image/youcam`, {
          src_file_ids: [referenceId], model: "youcam-image-v2", prompt: shot.baseImagePrompt,
          negative_prompt: imageNegative, size: "720*1280", prompt_extend: false,
        }, `${shot.name}-base`);
        await saveNormalized(baseTask.resultUrl, basePath);
      }
      sourceId = await upload(`${base}/file/image-to-image/youcam`, basePath);
    } else if (shot.name === "06-gift-notes") {
      sourceId = await upload(`${base}/file/image-to-image/youcam`, join(stillDir, "03-small-luxury.png"));
    }
    const task = await runTask(`${base}/task/image-to-image/youcam`, {
      src_file_ids: [sourceId],
      model: "youcam-image-v2",
      prompt: shot.imagePrompt,
      negative_prompt: imageNegative,
      size: "720*1280",
      prompt_extend: false,
    }, shot.name);
    await saveNormalized(task.resultUrl, output);
    manifest.push({ name: shot.name, taskId: task.taskId, output });
    console.log(`${shot.name}: saved ${output}`);
  }
  await writeFile(join(stillDir, "manifest.json"), JSON.stringify({ generatedAt: new Date().toISOString(), shots: manifest }, null, 2) + "\n");
}

async function generateVideos() {
  const manifest = [];
  for (const shot of shots) {
    const input = join(stillDir, `${shot.name}.png`);
    if (!(await exists(input))) throw new Error(`missing still: ${input}`);
    const output = join(sceneDir, `${shot.name}.mp4`);
    if (await exists(output)) {
      manifest.push({ name: shot.name, input, output, reused: true });
      continue;
    }
    const srcFileId = await upload(`${base}/file/image-to-video/youcam`, input);
    const task = await runTask(`${base}/task/image-to-video/youcam`, {
      src_file_id: srcFileId,
      resolution: "720",
      dst_duration: 5,
      prompt: shot.motionPrompt,
      negative_prompt: videoNegative,
      model: "youcam-video-v2",
    }, shot.name);
    const response = await fetch(task.resultUrl);
    if (!response.ok) throw new Error(`${shot.name}: video download failed (${response.status})`);
    await writeFile(output, Buffer.from(await response.arrayBuffer()));
    manifest.push({ name: shot.name, taskId: task.taskId, input, output });
    console.log(`${shot.name}: saved ${output}`);
  }
  await writeFile(join(sceneDir, "manifest.json"), JSON.stringify({ generatedAt: new Date().toISOString(), shots: manifest }, null, 2) + "\n");
}

await mkdir(stillDir, { recursive: true });
await mkdir(sceneDir, { recursive: true });
if (stage === "images" || stage === "all") await generateImages();
if (stage === "videos" || stage === "all") await generateVideos();
