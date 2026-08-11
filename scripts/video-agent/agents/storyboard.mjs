// Storyboard Agent: validates/normalizes a content brief. No API calls — the
// brief itself is the planner's output (the "Agentic Graph Router" step is done
// by whoever authors the brief; this agent just enforces the contract downstream
// agents rely on).
export function run(brief) {
  if (!brief.id) throw new Error("brief.id is required");
  if (!brief.outputDir) throw new Error("brief.outputDir is required");
  if (!Array.isArray(brief.scenes) || brief.scenes.length === 0) throw new Error("brief.scenes must be a non-empty array");
  for (const scene of brief.scenes) {
    if (!scene.name) throw new Error("every scene needs a name");
    if (!scene.imagePrompt) throw new Error(`${scene.name}: imagePrompt is required`);
    if (!scene.motionPrompt) throw new Error(`${scene.name}: motionPrompt is required`);
  }
  if (!brief.identityAnchor) throw new Error("brief.identityAnchor is required ({mode:'generate'} or {mode:'reuse', path})");
  console.log(`  [storyboard] ${brief.id}: ${brief.scenes.length} scenes, identity anchor mode=${brief.identityAnchor.mode}`);
  return brief;
}
