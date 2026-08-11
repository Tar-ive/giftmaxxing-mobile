// Agent graph: nodes are tool capabilities, edges are data dependencies —
// the same shape as VideoAgent's agent_graph/agent_chain (environment/utils.py),
// scaled down to what our pipeline actually needs and with the LLM planner step
// replaced by an authored content brief (see briefs/*.json).
import * as storyboard from "./agents/storyboard.mjs";
import * as image from "./agents/image.mjs";
import * as video from "./agents/video.mjs";
import * as voice from "./agents/voice.mjs";
import * as assemble from "./agents/assemble.mjs";
import { mkdir } from "node:fs/promises";
import { join } from "node:path";
import { path as rootPath } from "./lib/paths.mjs";

export const NODES = [
  { name: "storyboard", deps: [], agent: storyboard },
  { name: "image", deps: ["storyboard"], agent: image },
  { name: "voice", deps: ["storyboard"], agent: voice },
  { name: "video", deps: ["image"], agent: video },
  { name: "assemble", deps: ["video", "voice"], agent: assemble },
];

export function resolveDirs(brief) {
  const output = rootPath(brief.outputDir);
  return {
    output,
    stills: join(output, "stills"),
    scenes: join(output, "scenes"),
    audio: brief.audioDir ? rootPath(brief.audioDir) : join(output, "audio"),
    captions: brief.captionsDir ? rootPath(brief.captionsDir) : join(output, "captions"),
    final: join(output, "final"),
  };
}

// stage: run only up through this node (topological), or "all".
export async function runGraph(brief, { stage = "all" } = {}) {
  const dirs = resolveDirs(brief);
  await mkdir(dirs.output, { recursive: true });

  const order = NODES.map((n) => n.name);
  const cutoff = stage === "all" ? order.length : order.indexOf(stage) + 1;
  if (cutoff === 0) throw new Error(`unknown stage "${stage}", expected one of ${order.join(", ")} or "all"`);

  console.log(`\n▶ video-agent graph: ${brief.id}`);
  console.log(`  plan: ${order.slice(0, cutoff).join(" -> ")}\n`);

  let context = brief;
  const results = {};
  for (const node of NODES.slice(0, cutoff)) {
    console.log(`[${node.name}]`);
    results[node.name] = await node.agent.run(context, dirs);
    if (node.name === "storyboard") context = results.storyboard;
  }
  return results;
}
