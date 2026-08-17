# CLAUDE.md

@AGENTS.md

`AGENTS.md` (imported above) is the canonical instruction file — it's the cross-tool standard, so
Codex and Cursor read the same rules rather than a drifting copy. Everything about building, testing,
releasing, and the module and design-token boundaries lives there.

Claude-specific notes:

- **Architecture reference is not loaded by default.** `CLOUD.md` (backend), `DESIGN.md` (iOS design
  system) and `docs/` are read on demand. Open them when the work touches that surface — `DESIGN.md`
  before any UI change, `CLOUD.md` before any backend change.
- **Skills live in `.claude/skills/`.** Put a repeatable workflow there rather than in `AGENTS.md`;
  it loads only when relevant instead of costing context every session.
