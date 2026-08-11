// video-agent: lightweight multi-agent graph harness for generating storytelling
// UGC content with YouCam (image/video) + kie.ai (voiceover) + ffmpeg (assembly).
// Usage: YOUCAM_API_KEY=... KIE_API_KEY=... node scripts/video-agent/run.mjs \
//          --brief scripts/video-agent/briefs/<name>.json [--stage storyboard|image|voice|video|assemble|all]
import { readFile } from "node:fs/promises";
import { runGraph } from "./graph.mjs";

const args = process.argv.slice(2);
const flag = (name, fallback) => {
  const i = args.indexOf(`--${name}`);
  return i === -1 ? fallback : args[i + 1];
};

const briefPath = flag("brief");
if (!briefPath) throw new Error("--brief <path-to-json> is required");
const stage = flag("stage", "all");

const brief = JSON.parse(await readFile(briefPath, "utf8"));
await runGraph(brief, { stage });
