// Assemble the v2 gift-rules UGC video: per-scene clip (looped video + caption
// card + voiceover/ambient mix) then concat into the full cut. All local, ffmpeg only.
// Usage: node scripts/assemble-gift-rules-ugc-v2.mjs

import { execFile } from "node:child_process";
import { mkdir, writeFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { promisify } from "node:util";

const run = promisify(execFile);
const root = dirname(dirname(fileURLToPath(import.meta.url)));
const v1Dir = join(root, "marketing-assets/video/gift-rules-30s");
const v2Dir = join(root, "marketing-assets/video/gift-rules-ugc-v2");
const sceneDir = join(v2Dir, "scenes");
const finalDir = join(v2Dir, "final");

const shots = [
  { name: "01-forgettable-gifts", card: "01" },
  { name: "02-micro-friction", card: "02" },
  { name: "03-small-luxury", card: "03" },
  { name: "04-inside-callback", card: "04" },
  { name: "05-permission-gift", card: "05" },
  { name: "06-gift-notes", card: "06" },
];

async function probeDuration(path) {
  const { stdout } = await run("ffprobe", ["-v", "error", "-show_entries", "format=duration", "-of", "default=noprint_wrappers=1:nokey=1", path]);
  return parseFloat(stdout.trim());
}

async function buildScene(shot) {
  const video = join(sceneDir, `${shot.name}.mp4`);
  const voice = join(v1Dir, "audio", `v2-${shot.name}.wav`);
  const card = join(v1Dir, "caption-cards", `${shot.card}.png`);
  const output = join(finalDir, `${shot.name}.mp4`);

  const voiceDuration = await probeDuration(voice);
  const targetDuration = (voiceDuration + 0.6).toFixed(2);

  const args = [
    "-y", "-v", "error",
    "-stream_loop", "-1", "-i", video,
    "-i", voice,
    "-loop", "1", "-i", card,
    "-filter_complex",
    "[0:v]scale=720:1280[vbase];[vbase][2:v]overlay=0:0:shortest=0[v];" +
      "[0:a]volume=0.06[amb];[1:a]volume=1.0,adelay=200|200[voice];" +
      "[amb][voice]amix=inputs=2:duration=first:normalize=0[a]",
    "-map", "[v]", "-map", "[a]",
    "-t", targetDuration,
    "-c:v", "libx264", "-preset", "medium", "-crf", "18",
    "-c:a", "aac", "-b:a", "192k", "-movflags", "+faststart",
    output,
  ];
  await run("ffmpeg", args);
  console.log(`${shot.name}: built ${output} (${targetDuration}s)`);
  return { name: shot.name, output, duration: parseFloat(targetDuration) };
}

await mkdir(finalDir, { recursive: true });
const built = [];
for (const shot of shots) built.push(await buildScene(shot));

const concatList = built.map((b) => `file '${b.output}'`).join("\n") + "\n";
const concatPath = join(v2Dir, "concat.txt");
await writeFile(concatPath, concatList);

const roughCut = join(v2Dir, "rough-cut.mp4");
await run("ffmpeg", ["-y", "-v", "error", "-f", "concat", "-safe", "0", "-i", concatPath, "-c", "copy", roughCut]);

const finalOutput = join(v2Dir, "gift-rules-ugc-v2.mp4");
await run("ffmpeg", ["-y", "-v", "error", "-i", roughCut, "-c", "copy", finalOutput]);

const totalDuration = built.reduce((sum, b) => sum + b.duration, 0);
console.log(`\nAssembled ${finalOutput} (~${totalDuration.toFixed(1)}s total)`);
console.log("Standalone rule clips (the 5 storytelling videos):");
for (const b of built.slice(1)) console.log(`  ${b.output}`);
