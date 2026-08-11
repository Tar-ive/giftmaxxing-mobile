// Generate an improved gift-rules-30s voiceover via kie.ai (Gemini 3.1 Flash TTS).
// One clip per scene line (a single multi-turn call truncates to ~6s), which also
// gives 1:1 per-scene audio for syncing against the 5s video clips.
// Usage: KIE_API_KEY=... node scripts/generate-voiceover-kie.mjs

import { mkdir, writeFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const apiKey = process.env.KIE_API_KEY;
if (!apiKey) throw new Error("KIE_API_KEY is required");

const root = dirname(dirname(fileURLToPath(import.meta.url)));
const outputDir = join(root, "marketing-assets/video/gift-rules-30s/audio");
const createUrl = "https://api.kie.ai/api/v1/jobs/createTask";
const infoUrl = "https://api.kie.ai/api/v1/jobs/recordInfo";

// Mirrors captions.srt's / scenes' six 5-second segments for 1:1 scene sync.
const lines = [
  { name: "01-forgettable-gifts", text: "Stop buying forgettable gifts. Great gift givers follow five rules." },
  { name: "02-micro-friction", text: "One: solve a micro-friction. Replace the leaky bottle, frayed charger, or cold coffee mug." },
  { name: "03-small-luxury", text: "Two: buy the best version of something inexpensive, not the cheapest version of something expensive." },
  { name: "04-inside-callback", text: "Three: turn an inside joke into a physical callback." },
  { name: "05-permission-gift", text: "Four: give guilt-free permission for the hobby, facial, or experience they never buy themselves." },
  { name: "06-gift-notes", text: "Five: keep notes whenever someone mentions a want or annoyance. Don't ask, what should I buy. Ask, what friction or desire can I solve." },
];

const speaker = {
  speaker_id: "Speaker 1",
  voice_name: "Aoede",
  audio_profile: "A warm, confident young woman giving practical gift-giving advice to a friend",
  accent: "American (Gen)",
  style: "Empathetic",
  pace: "Natural",
};

async function request(url, init = {}) {
  const response = await fetch(url, {
    ...init,
    headers: { Authorization: `Bearer ${apiKey}`, ...(init.body ? { "content-type": "application/json" } : {}), ...init.headers },
  });
  const body = await response.json().catch(() => ({}));
  if (!response.ok || body.code >= 400) throw new Error(`${response.status} ${body.code ?? ""} ${body.msg || "request failed"}`.trim());
  return body;
}

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

async function generateLine(line) {
  const payload = {
    model: "google/gemini-3-1-flash-tts",
    input: {
      temperature: 1,
      scene: "A confident, warm creator speaking directly to a phone camera, giving one quick practical gift-giving tip in a TikTok voiceover.",
      sample_context: "Casual, upbeat, trustworthy explainer voiceover. Confident and friendly, never salesy or robotic.",
      speakers: [speaker],
      dialogue_turns: [{ speaker_id: "Speaker 1", text: line.text }],
    },
  };
  const create = await request(createUrl, { method: "POST", body: JSON.stringify(payload) });
  const taskId = create.data?.taskId;
  if (!taskId) throw new Error(`${line.name}: no taskId in response: ${JSON.stringify(create)}`);
  console.log(`${line.name}: started ${taskId}`);

  for (let attempt = 1; attempt <= 60; attempt++) {
    const info = await request(`${infoUrl}?taskId=${encodeURIComponent(taskId)}`);
    const state = info.data?.state;
    if (state === "success") {
      const result = JSON.parse(info.data.resultJson || "{}");
      const resultUrl = result.resultUrls?.[0];
      if (!resultUrl) throw new Error(`${line.name}: no resultUrls in ${info.data.resultJson}`);
      return resultUrl;
    }
    if (state === "fail") throw new Error(`${line.name}: failed ${info.data.failCode} ${info.data.failMsg}`);
    await sleep(3_000);
  }
  throw new Error(`${line.name}: timed out waiting for result`);
}

await mkdir(outputDir, { recursive: true });
const manifest = [];
for (const line of lines) {
  const resultUrl = await generateLine(line);
  const audio = await fetch(resultUrl);
  if (!audio.ok) throw new Error(`${line.name}: download failed (${audio.status})`);
  const output = join(outputDir, `v2-${line.name}.wav`);
  await writeFile(output, Buffer.from(await audio.arrayBuffer()));
  console.log(`${line.name}: saved ${output}`);
  manifest.push({ name: line.name, text: line.text, output });
}
await writeFile(join(outputDir, "v2-manifest.json"), JSON.stringify({ generatedAt: new Date().toISOString(), lines: manifest }, null, 2) + "\n");
console.log(`Generated ${manifest.length} voiceover lines.`);
