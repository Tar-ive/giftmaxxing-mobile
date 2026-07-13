# CLAUDE.md — Giftmaxxing (repo root memory)

@CLOUD.md

## Active initiative: image → vector → feed pipeline

`CLOUD.md` (imported above) is the canonical spec **and** backlog for the Pinterest →
multimodal-embedding → vector-index → recommendation work, the Pinterest-style native-ad
simulation, and the future visual-search feature. **Treat `CLOUD.md` §8 (Roadmap) as the
working backlog** for this initiative; keep `CLOUD.md` updated as decisions land.

## iOS design system

- **`DESIGN.md` (repo root) is the canonical design system for the SwiftUI iOS app.**
  Any agent touching UI in `Giftmaxxing/` MUST read it first and follow its Agent
  contract: all colors/fonts/spacing/radii/shadows resolve through tokens in
  `Giftmaxxing/Extensions/Theme.swift`; shared ButtonStyles/components only; springs +
  `sensoryFeedback` per its motion catalog. If a needed token is missing, extend
  `Theme.swift` **and** `DESIGN.md` in the same PR.
- Current-state audit + prioritized migration plan: `docs/design-gap-analysis.md`.
- The `/screenshots` folder is **outdated web material** — never use it as a design
  reference for the iOS app.

## Deploy rules (do not violate)

- `web/` (Next.js) deploys to **Vercel** via **GitHub** auto-deploy on push to `main`
  (NOT the Vercel CLI). Monorepo → Vercel Root Directory = `web`.
- `infra/` (Terraform) deploys to **AWS** `us-east-1`, account `445056752928`.
  API base: `https://tvyu8gqmki.execute-api.us-east-1.amazonaws.com` (web reads it via
  `NEXT_PUBLIC_API_URL`).
- Before any AWS spend on the pipeline, re-verify list prices and enable Bedrock model
  access for Titan Multimodal Embeddings (see `CLOUD.md` §10).
