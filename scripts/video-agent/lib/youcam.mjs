// Shared PerfectCorp YouCam Enterprise (YCE) helpers: file upload + async task run/poll.
import { basename, join } from "node:path";
import { mkdir, readFile, stat, writeFile } from "node:fs/promises";
import { path, sharpModule } from "./paths.mjs";

const BASE = "https://yce-api-01.makeupar.com/s2s/v2.0";
const IMAGE_NEGATIVE =
  "AI-generated look, glossy commercial, studio lighting, plastic skin, beauty retouching, deformed hands, extra fingers, distorted objects, duplicate objects, readable text, captions, logos, watermark";
const VIDEO_NEGATIVE =
  "identity drift, face morphing, warped hands, extra fingers, object morphing, duplicated objects, distorted text, flicker, camera shake, plastic skin, captions, logos, watermark";

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
const exists = async (p) => (await stat(p).catch(() => null))?.size > 0;

function apiKey() {
  const key = process.env.YOUCAM_API_KEY;
  if (!key) throw new Error("YOUCAM_API_KEY is required");
  return key;
}

async function request(url, init = {}) {
  const response = await fetch(url, {
    ...init,
    headers: { Authorization: `Bearer ${apiKey()}`, ...(init.body ? { "content-type": "application/json" } : {}), ...init.headers },
  });
  const body = await response.json().catch(() => ({}));
  if (!response.ok) throw new Error(`${response.status} ${body.error_code || ""} ${body.error || "request failed"}`.trim());
  return body;
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
  const response = await fetch(uploadRequest.url, { method: uploadRequest.method ?? "PUT", headers: uploadRequest.headers, body: file });
  if (!response.ok) throw new Error(`upload failed for ${filePath} (${response.status})`);
  return item.file_id;
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
  console.log(`  [youcam] ${label}: started ${taskId}`);
  return { taskId, resultUrl: await waitFor(taskEndpoint, taskId, label) };
}

async function saveNormalized(url, output) {
  const { default: sharp } = await sharpModule();
  const response = await fetch(url);
  if (!response.ok) throw new Error(`download failed (${response.status})`);
  await sharp(Buffer.from(await response.arrayBuffer())).resize(720, 1280, { fit: "cover", position: "centre" }).png().toFile(output);
}

// Generates one still per scene: the first scene is text-to-image (or reuses an
// existing identityAnchor image); every later scene is image-to-image against that
// same reference, so the recurring creator stays visually consistent.
export async function generateStills(brief, dirs) {
  await mkdir(dirs.stills, { recursive: true });
  const manifest = [];
  const scenes = brief.scenes;

  let referencePath;
  if (brief.identityAnchor?.mode === "reuse") {
    referencePath = path(brief.identityAnchor.path);
    if (!(await exists(referencePath))) throw new Error(`identityAnchor.path does not exist: ${referencePath}`);
    console.log(`  [youcam] identity anchor: reusing ${referencePath}`);
  } else {
    const lead = scenes[0];
    referencePath = join(dirs.stills, `${lead.name}.png`);
    if (!(await exists(referencePath))) {
      const task = await runTask(`${BASE}/task/text-to-image/youcam`, {
        model: "youcam-image-v2",
        prompt: lead.imagePrompt,
        negative_prompt: IMAGE_NEGATIVE,
        size: "928*1664",
        prompt_extend: false,
      }, lead.name);
      await saveNormalized(task.resultUrl, referencePath);
      manifest.push({ name: lead.name, taskId: task.taskId, output: referencePath });
    } else {
      manifest.push({ name: lead.name, output: referencePath, reused: true });
    }
  }

  const rest = brief.identityAnchor?.mode === "reuse" ? scenes : scenes.slice(1);
  const pending = [];
  for (const scene of rest) {
    const output = join(dirs.stills, `${scene.name}.png`);
    if (await exists(output)) manifest.push({ name: scene.name, output, reused: true });
    else pending.push(scene);
  }
  const referenceId = pending.length ? await upload(`${BASE}/file/image-to-image/youcam`, referencePath) : null;
  for (const scene of pending) {
    const output = join(dirs.stills, `${scene.name}.png`);
    const task = await runTask(`${BASE}/task/image-to-image/youcam`, {
      src_file_ids: [referenceId],
      model: "youcam-image-v2",
      prompt: scene.imagePrompt,
      negative_prompt: IMAGE_NEGATIVE,
      size: "720*1280",
      prompt_extend: false,
    }, scene.name);
    await saveNormalized(task.resultUrl, output);
    manifest.push({ name: scene.name, taskId: task.taskId, output });
  }
  await writeFile(join(dirs.stills, "manifest.json"), JSON.stringify({ generatedAt: new Date().toISOString(), shots: manifest }, null, 2) + "\n");
  return manifest;
}

export async function generateVideos(brief, dirs) {
  await mkdir(dirs.scenes, { recursive: true });
  const manifest = [];
  for (const scene of brief.scenes) {
    const input = join(dirs.stills, `${scene.name}.png`);
    if (!(await exists(input))) throw new Error(`missing still: ${input}`);
    const output = join(dirs.scenes, `${scene.name}.mp4`);
    if (await exists(output)) {
      manifest.push({ name: scene.name, input, output, reused: true });
      continue;
    }
    try {
      const srcFileId = await upload(`${BASE}/file/image-to-video/youcam`, input);
      const task = await runTask(`${BASE}/task/image-to-video/youcam`, {
        src_file_id: srcFileId,
        resolution: "720",
        dst_duration: 5,
        prompt: scene.motionPrompt,
        negative_prompt: VIDEO_NEGATIVE,
        model: "youcam-video-v2",
      }, scene.name);
      const response = await fetch(task.resultUrl);
      if (!response.ok) throw new Error(`${scene.name}: video download failed (${response.status})`);
      await writeFile(output, Buffer.from(await response.arrayBuffer()));
      manifest.push({ name: scene.name, taskId: task.taskId, input, output });
    } catch (error) {
      console.error(`  [youcam] ${scene.name}: FAILED — ${error.message}`);
      manifest.push({ name: scene.name, input, failed: true, error: error.message });
    }
  }
  await writeFile(join(dirs.scenes, "manifest.json"), JSON.stringify({ generatedAt: new Date().toISOString(), shots: manifest }, null, 2) + "\n");
  return manifest;
}
