// Shared kie.ai (Gemini 3.1 Flash TTS) voiceover helper.
// One call per line — a single multi-turn call truncates to ~6s regardless of
// script length, so per-scene calls are both correct and conveniently 1:1 with clips.
import { mkdir, stat, writeFile } from "node:fs/promises";
import { join } from "node:path";

const CREATE_URL = "https://api.kie.ai/api/v1/jobs/createTask";
const INFO_URL = "https://api.kie.ai/api/v1/jobs/recordInfo";
const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
const exists = async (p) => (await stat(p).catch(() => null))?.size > 0;

function apiKey() {
  const key = process.env.KIE_API_KEY;
  if (!key) throw new Error("KIE_API_KEY is required");
  return key;
}

async function request(url, init = {}) {
  const response = await fetch(url, {
    ...init,
    headers: { Authorization: `Bearer ${apiKey()}`, ...(init.body ? { "content-type": "application/json" } : {}), ...init.headers },
  });
  const body = await response.json().catch(() => ({}));
  if (!response.ok || body.code >= 400) throw new Error(`${response.status} ${body.code ?? ""} ${body.msg || "request failed"}`.trim());
  return body;
}

async function generateLine(text, voice, sceneContext) {
  const payload = {
    model: "google/gemini-3-1-flash-tts",
    input: {
      temperature: 1,
      scene: sceneContext,
      sample_context: "Casual, upbeat, trustworthy explainer voiceover. Confident and friendly, never salesy or robotic.",
      speakers: [voice],
      dialogue_turns: [{ speaker_id: voice.speaker_id, text }],
    },
  };
  const create = await request(CREATE_URL, { method: "POST", body: JSON.stringify(payload) });
  const taskId = create.data?.taskId;
  if (!taskId) throw new Error(`no taskId in response: ${JSON.stringify(create)}`);

  for (let attempt = 1; attempt <= 60; attempt++) {
    const info = await request(`${INFO_URL}?taskId=${encodeURIComponent(taskId)}`);
    const state = info.data?.state;
    if (state === "success") {
      const result = JSON.parse(info.data.resultJson || "{}");
      const resultUrl = result.resultUrls?.[0];
      if (!resultUrl) throw new Error(`no resultUrls in ${info.data.resultJson}`);
      return resultUrl;
    }
    if (state === "fail") throw new Error(`failed ${info.data.failCode} ${info.data.failMsg}`);
    await sleep(3_000);
  }
  throw new Error("timed out waiting for result");
}

export async function generateVoiceover(brief, dirs) {
  await mkdir(dirs.audio, { recursive: true });
  const voice = { speaker_id: "Speaker 1", ...brief.voice };
  const manifest = [];
  for (const scene of brief.scenes) {
    if (!scene.voiceoverLine) continue;
    const output = join(dirs.audio, `${scene.name}.wav`);
    if (await exists(output)) {
      manifest.push({ name: scene.name, output, reused: true });
      continue;
    }
    console.log(`  [kie] ${scene.name}: generating voiceover`);
    const resultUrl = await generateLine(scene.voiceoverLine, voice, brief.voiceSceneContext ?? brief.title);
    const audio = await fetch(resultUrl);
    if (!audio.ok) throw new Error(`${scene.name}: download failed (${audio.status})`);
    await writeFile(output, Buffer.from(await audio.arrayBuffer()));
    manifest.push({ name: scene.name, output });
  }
  await writeFile(join(dirs.audio, "manifest.json"), JSON.stringify({ generatedAt: new Date().toISOString(), lines: manifest }, null, 2) + "\n");
  return manifest;
}
