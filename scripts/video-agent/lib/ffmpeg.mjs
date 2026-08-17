// Caption-card rendering + final per-scene / composite ffmpeg assembly. Local only.
import { execFile } from "node:child_process";
import { mkdir, stat, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { promisify } from "node:util";
import { sharpModule } from "./paths.mjs";

const run = promisify(execFile);
const exists = async (p) => (await stat(p).catch(() => null))?.size > 0;
const escape = (text) => text.replaceAll("&", "&amp;").replaceAll("<", "&lt;").replaceAll(">", "&gt;");

export async function renderCaptionCards(brief, dirs) {
  await mkdir(dirs.captions, { recursive: true });
  const { default: sharp } = await sharpModule();
  for (const scene of brief.scenes) {
    if (!scene.caption) continue;
    const output = join(dirs.captions, `${scene.name}.png`);
    if (await exists(output)) continue;
    const svg = `
      <svg width="720" height="1280" xmlns="http://www.w3.org/2000/svg">
        <rect x="42" y="1015" width="636" height="176" rx="28" fill="rgba(8,8,12,.76)"/>
        <text x="360" y="1080" text-anchor="middle" fill="white" font-family="Arial, sans-serif" font-size="31" font-weight="700">${escape(scene.caption.title)}</text>
        <text x="360" y="1134" text-anchor="middle" fill="white" font-family="Arial, sans-serif" font-size="24">${escape(scene.caption.subtitle ?? "")}</text>
        <text x="360" y="1240" text-anchor="middle" fill="rgba(255,255,255,.75)" font-family="Arial, sans-serif" font-size="18" font-weight="700" letter-spacing="3">GIFTMAXXING</text>
      </svg>`;
    await sharp(Buffer.from(svg)).png().toFile(output);
  }
}

async function probeDuration(p) {
  const { stdout } = await run("ffprobe", ["-v", "error", "-show_entries", "format=duration", "-of", "default=noprint_wrappers=1:nokey=1", p]);
  return parseFloat(stdout.trim());
}

async function buildScene(scene, dirs) {
  const video = join(dirs.scenes, `${scene.name}.mp4`);
  const voice = join(dirs.audio, `${scene.name}.wav`);
  const card = join(dirs.captions, `${scene.name}.png`);
  const output = join(dirs.final, `${scene.name}.mp4`);
  const hasVoice = await exists(voice);
  const hasCaption = await exists(card);

  const targetDuration = hasVoice ? (await probeDuration(voice)) + 0.6 : 5.6;

  const inputs = ["-stream_loop", "-1", "-i", video];
  if (hasVoice) inputs.push("-i", voice);
  if (hasCaption) inputs.push("-loop", "1", "-i", card);

  const filters = [];
  let vLabel = "0:v";
  if (hasCaption) {
    filters.push(`[0:v]scale=720:1280[vbase]`);
    filters.push(`[vbase][${hasVoice ? 2 : 1}:v]overlay=0:0:shortest=0[v]`);
    vLabel = "v";
  } else {
    filters.push(`[0:v]scale=720:1280[v]`);
    vLabel = "v";
  }
  let aLabel = "0:a";
  if (hasVoice) {
    filters.push(`[0:a]volume=0.06[amb]`);
    filters.push(`[1:a]volume=1.0,adelay=200|200[voice]`);
    filters.push(`[amb][voice]amix=inputs=2:duration=first:normalize=0[a]`);
    aLabel = "a";
  }

  const args = [
    "-y", "-v", "error",
    ...inputs,
    "-filter_complex", filters.join(";"),
    "-map", `[${vLabel}]`, "-map", `[${aLabel}]`,
    "-t", targetDuration.toFixed(2),
    "-c:v", "libx264", "-preset", "medium", "-crf", "18",
    "-c:a", "aac", "-b:a", "192k", "-movflags", "+faststart",
    output,
  ];
  await mkdir(dirs.final, { recursive: true });
  await run("ffmpeg", args);
  console.log(`  [ffmpeg] ${scene.name}: built ${output} (${targetDuration.toFixed(1)}s)`);
  return { name: scene.name, output, duration: targetDuration };
}

export async function assemble(brief, dirs) {
  await renderCaptionCards(brief, dirs);
  const built = [];
  for (const scene of brief.scenes) built.push(await buildScene(scene, dirs));

  const concatList = built.map((b) => `file '${b.output}'`).join("\n") + "\n";
  const concatPath = join(dirs.output, "concat.txt");
  await writeFile(concatPath, concatList);

  const roughCut = join(dirs.output, "rough-cut.mp4");
  await run("ffmpeg", ["-y", "-v", "error", "-f", "concat", "-safe", "0", "-i", concatPath, "-c", "copy", roughCut]);

  const finalOutput = join(dirs.output, `${brief.id}.mp4`);
  await run("ffmpeg", ["-y", "-v", "error", "-i", roughCut, "-c", "copy", finalOutput]);

  const totalDuration = built.reduce((sum, b) => sum + b.duration, 0);
  console.log(`  [ffmpeg] composite: ${finalOutput} (~${totalDuration.toFixed(1)}s)`);
  return { finalOutput, scenes: built, totalDuration };
}
