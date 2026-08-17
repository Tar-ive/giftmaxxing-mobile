// Generate the 30-second UGC narration with Kie Gemini TTS.
// Usage: KIE_API_KEY=... node scripts/generate-kie-gift-rules-voiceover.mjs

import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { mkdir, writeFile } from "node:fs/promises";

const apiKey = process.env.KIE_API_KEY;
if (!apiKey) throw new Error("KIE_API_KEY is required");

const root = dirname(dirname(fileURLToPath(import.meta.url)));
const outputDir = join(root, "marketing-assets/video/gift-rules-ugc-v2/audio");
const output = join(outputDir, "voiceover-kie.wav");
const endpoint = "https://api.kie.ai/api/v1/jobs";
const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

const response = await fetch(`${endpoint}/createTask`, {
  method: "POST",
  headers: { Authorization: `Bearer ${apiKey}`, "content-type": "application/json" },
  body: JSON.stringify({
    model: "google/gemini-3-1-flash-tts",
    input: {
      temperature: 0.5,
      scene: "One woman records a brisk, practical TikTok voiceover over six gift-giving shots. Deliver the complete script in 28 to 29 seconds.",
      sample_context: "Clean dry voice only. Smart friend energy, crisp continuous phrasing, short natural breaths, no dramatic pauses, no music, no sound effects, no announcer voice.",
      speakers: [{
        speaker_id: "Speaker 1",
        voice_name: "Kore",
        audio_profile: "A warm, confident female creator in her late 20s who sounds like a trusted friend sharing a genuinely useful idea.",
        accent: "American (Gen)",
        style: "Empathetic",
        pace: "Natural",
      }],
      dialogue_turns: [{
        speaker_id: "Speaker 1",
        text: "Stop buying forgettable gifts. Use five rules. One: solve a tiny daily annoyance—the leaky bottle, frayed charger, or cold coffee. Two: buy the best version of something inexpensive. Three: turn an inside joke into something they can keep. Four: fund the hobby, facial, or experience they keep postponing. Five: write down every want they casually mention. Don’t ask, ‘What should I buy?’ Ask, ‘What friction can I solve?’",
      }],
    },
  }),
});

const created = await response.json().catch(() => ({}));
if (!response.ok || !created.data?.taskId) throw new Error(`${response.status} ${created.msg || "task creation failed"}`);
const taskId = created.data.taskId;
console.log(`voiceover: started ${taskId}`);

let resultUrl;
for (let attempt = 1; attempt <= 180; attempt++) {
  const statusResponse = await fetch(`${endpoint}/recordInfo?taskId=${encodeURIComponent(taskId)}`, {
    headers: { Authorization: `Bearer ${apiKey}` },
  });
  const status = await statusResponse.json().catch(() => ({}));
  if (!statusResponse.ok) throw new Error(`${statusResponse.status} ${status.msg || "status failed"}`);
  if (status.data?.state === "fail") throw new Error(`${status.data.failCode || "failed"}: ${status.data.failMsg || "generation failed"}`);
  if (status.data?.state === "success") {
    const result = JSON.parse(status.data.resultJson || "{}");
    resultUrl = result.resultUrls?.[0];
    break;
  }
  await sleep(Math.min(3_000 + attempt * 250, 10_000));
}
if (!resultUrl) throw new Error("voiceover: timed out or returned no audio URL");

const audio = await fetch(resultUrl);
if (!audio.ok) throw new Error(`voiceover download failed (${audio.status})`);
await mkdir(outputDir, { recursive: true });
await writeFile(output, Buffer.from(await audio.arrayBuffer()));
await writeFile(join(outputDir, "manifest.json"), JSON.stringify({ generatedAt: new Date().toISOString(), taskId, model: "google/gemini-3-1-flash-tts", output }, null, 2) + "\n");
console.log(`voiceover: saved ${output}`);
