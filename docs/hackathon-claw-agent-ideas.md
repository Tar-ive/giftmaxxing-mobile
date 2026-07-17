# AITX Community × NVIDIA Claw Agent Hackathon — Project Ideas Brief

> Austin, Antler VC · July 17–19, 2026 · in-person · code freeze Sun 11 AM CST.
> Deliverable for the team: 6 project ideas mapped to tracks + bounties, how we
> stand out, and comparable winning projects from major 2025–2026 hackathons.
> Research basis: winner galleries from TreeHacks 2026, UC Berkeley AI Hackathon
> 2025/2026, Cal Hacks 12, HackMIT/HackHarvard/HackPrinceton/YHack 2025-26, plus
> pro/agent hackathons (NVIDIA NemoClaw/NeMo, Microsoft AI Agents, Anthropic,
> Google ADK, Circle OpenClaw, ElevenLabs, Berkeley RDI LLM-Agents).

---

## 0. What actually wins this event (read first)

**A "Claw Agent" is defined by three properties** — every idea below must visibly show all three or it loses points:
1. **Proactively autonomous** — initiates work, recovers from interruptions, coordinates multi-step workflows with limited supervision.
2. **Heartbeat-driven** — wakes on a timer/state change, checks its task list, acts or waits. The trigger is time/state, **not** a human message. *(This is the single most common thing weekend teams fake — make the loop real and visible in the demo.)*
3. **Persistent** — its own workspace, memory, files, config, session history across runs.

**Judging = 100 pts:** Technical Execution 30 · **Sponsor Tech 30** · Value/Impact 20 · Frontier (creativity+performance) 20.

**The single biggest lever: sponsor tech is 30% of the score, and the four bounties are all cross-track and stackable.** The winning move is to pick **one track** and stack **as many bounties as the build naturally supports**. A realistic flagship build can hit all four at once:
- serve a **Nemotron** model on **vLLM** → Nemotron bounty **+ vLLM $500 cash**;
- contain the agent in **NemoClaw + OpenShell** with a real YAML policy → that bounty;
- instrument every prompt/tool-call through **HiddenLayer** → security track *or* extra credit;
- pitch it as a business → **Antler "Most Commercializable."**

**Three patterns that win disproportionately (from the research), ranked by leverage:**
- **Agent-security projects win way above their frequency** — the field is thin and judges reward it (ClawShield, AgentGuard, Sentinel, ShadowGuard, MonkeyClaw, OpenCodeReview all placed). Our event literally has a security track *and* a containment bounty. This is the highest-EV lane.
- **"Self-improvement" that wins = verifier/adversarial sub-agents + self-correction loops**, not vague "it learns" (Tekton, Apollo, Inspector, SSEAL). Show a measurable delta between run 1 and run N.
- **Live-data agents win when the feed is exotic and genuinely real** (GDELT world-events graph, hydroponic sensors, fleet telemetry, ATC audio) — never a static CSV dressed up as "live."

**Bounties & prizes:** Best Use of vLLM = **$500 cash** (favors "small open model punches above its size"); NemoClaw + OpenShell = $100 Brev credits/member; Nemotron = $100 Brev credits/member; Most Commercializable (Antler) = dinner with Antler ATX team.

**Submission bar:** 2–5 min Loom (must be Loom) showing the core loop live; public repo w/ README + architecture diagram + reproduce steps + `.env` sample; 150–300 word write-up (problem → who it helps → solution → impact). Free credits available: Featherless AI $25, Supabase $25, Apify $50 (coupon `AITX_NVIDIA_CLAW_HACK`).

---

## 1. The six ideas

Each idea lists: what it is · tracks it qualifies for · bounties it can stack · how we stand out · comparable *winning* projects.

### Idea 1 — "Sentinel Skill": a runtime security layer for tool-using agents ⭐ TOP PICK
A drop-in **HiddenLayer-instrumented proxy** that sits between any autonomous agent and its tools/LLM: every prompt, model response, tool call, tool result, and ingested document is routed through HiddenLayer's Runtime Security API, and the agent applies a policy (refuse / redact / escalate-to-human / quarantine) the instant prompt-injection or data-exfiltration is detected. Ships as a reusable wrapper + a live "attack theater" dashboard so judges can *try* to poison it on stage.

- **Tracks:** HiddenLayer Runtime Security (primary). Also plausibly Recursive Intelligence if the policy engine learns new attack signatures across runs.
- **Bounties:** NemoClaw + OpenShell (the agent it protects runs contained, so a defense-in-depth story: HiddenLayer catches the intent, OpenShell blocks the action) · Nemotron + vLLM (self-host the classifier/policy model) · Most Commercializable (agent security is a real, growing B2B market).
- **How we stand out:** most teams will bolt HiddenLayer onto one prompt. We instrument the **whole runtime** (tool calls + ingested content, the deepest tier judges explicitly reward) and pair it with OpenShell so detection *and* enforcement both hold under adversarial testing — then invite judges to break it live. Depth of instrumentation + a boundary that survives contact with an adversary is exactly the stated rubric for both the track and the bounty.
- **Comparable winners:** ShadowGuard (TreeHacks 2026, real-time PHI-redaction network proxy) · ClawShield (Circle USDC OpenClaw 2026, protects OpenClaw agents from exfiltration) · Sentinel (Berkeley 2026, security engineer that *proves* vulns in sandboxes) · AgentGuard / Team Hoosiers (Berkeley RDI, agent-hardening frameworks).

### Idea 2 — Recursive gift-scout that gets measurably better each run
A heartbeat agent that, given a recipient (name + a few signals), autonomously researches gift ideas across the web on a loop and **compounds what it learns into a per-recipient knowledge graph** — each cycle it scrapes, evaluates its own past picks against feedback, prunes dead ends, and sharpens. Demo shows the delta: run 1 returns generic junk in 4 min; run 5 returns sharp, on-taste, well-priced picks in 40 sec. *(Leverages our existing Giftmaxxing taste-vector + gift-graph infra as a head start — see `CLOUD.md` §14/§16.)*

- **Tracks:** Recursive Intelligence (primary — this is the textbook "dumb at first, sharp by the end without retraining" arc).
- **Bounties:** Nemotron + vLLM (self-host the reasoning model; the "small model + strong scaffolding" story is directly rewarded) · Most Commercializable (Antler — it's literally our product's core).
- **How we stand out:** a **quantified first-run-vs-last-run delta** on a defined task (completion time + pick relevance) plus an explicit learning mechanism (self-RAG over an episodic memory / knowledge graph) — the two things the track says earn bonus credit. Most "self-improving" entries can't show a number; we can.
- **Comparable winners:** SSEAL (Berkeley RDI, "Self-Supervised Explorative Agent Learning," Fundamentals 1st, $25K) · HackOverflow (TreeHacks 2026, shared self-improving memory so agents stop re-solving problems) · Mobius (TreeHacks 2026 YC-track winner, 3,000-turn autonomous self-improving loop) · Apollo (Microsoft AI Agents, vector memory + knowledge-gap self-checks).

### Idea 3 — Live-data deal & restock hunter on real streaming feeds
A heartbeat agent watching **genuinely live commerce feeds** (price-drop APIs, retailer restock/inventory endpoints, RSS deal feeds via Apify) that maintains a watchlist, detects a real drop/restock the moment it happens, verifies it's not a stale/fake sale, and pushes a ranked, taste-matched alert. The "freshness earns its keep" story is strong: a deal is only useful *at the moment it fires*. *(Our `CLOUD.md` deal-monitoring scaffold already specs the price-history + watchlist data model.)*

- **Tracks:** Red Hat Live Data (primary).
- **Bounties:** Nemotron + vLLM (rank/summarize deals with a self-hosted small model at high throughput under the heartbeat) · Most Commercializable · HiddenLayer (scraped retailer pages are untrusted content → route through HiddenLayer, a natural cross-eligible add).
- **How we stand out:** judges explicitly penalize "a static download dressed up as live." We prove true streaming by showing the agent react on-stage to a price we change in real time, and by **fusing multiple live feeds** (price + inventory + shipping/seasonal signals). Exotic-but-real feeds beat stock-ticker demos.
- **Comparable winners:** GDELT Open Intelligence Agent (ArangoDB × NVIDIA GTC 2025, 1st — agent over a live global-events graph) · Congestion Desk & XChange (YHack/HackPrinceton — real-time shipping/social feeds → decisions) · Circa (YHack, live sensor loop) · GreenOps (Google ADK, continuous cloud-cost auditing loop).

### Idea 4 — Contained autonomous ops agent ("give it real power, then hold the line")
An agent with **genuine credentials and real access** (a GitHub repo, a cloud account, a data store) that does useful autonomous ops work inside an **OpenShell sandbox**, governed by a declarative YAML policy that blocks the lines it must never cross — exfiltrating data, hitting an un-approved endpoint, touching a protected path, firing an irreversible action — even under adversarial prompting. The demo is the policy holding while judges try to jailbreak it.

- **Tracks:** any (bounty-centric) — pairs cleanly with Recursive Intelligence (a self-improving ops agent) or Red Hat (ops on live telemetry).
- **Bounties:** **NemoClaw + OpenShell (primary target)** · Nemotron + vLLM (route inference to a self-hosted Nemotron per the NemoClaw blueprint) · HiddenLayer (detection layer in front of the enforcement layer) · Most Commercializable.
- **How we stand out:** the bounty rewards **"genuine capability underneath"** + **non-trivial policy** (allow-with-escalation, conditional permissions, human-in-the-loop) over a blunt global block. We build a genuinely powerful agent *and* a nuanced policy judges can stress-test — and narrate exactly how it maps to the NemoClaw blueprint (they reward architectural clarity).
- **Comparable winners:** ClawShRouter/ClawShield (Circle OpenClaw 2026) · MonkeyClaw (NVIDIA NemoClaw @ UCSC — "probing, patching, protecting the NemoClaw ecosystem") · ARIA (Anthropic Opus 4.7 — 5 agents + 17 tools, persistent ops loop) · HiveOps (YHack, agentic incident resolution).

### Idea 5 — Nemotron-Nano-on-vLLM: the small-model-that-punches-up flagship
Take a **small open Nemotron** model, serve it yourself on **vLLM** (your own OpenAI-compatible endpoint, continuous batching / PagedAttention), and build a long-running agent whose heartbeat fires **many concurrent inferences** — so throughput actually matters and the small model, wrapped in good scaffolding (tools, verification, retrieval), matches a hosted frontier model on a real task. Pick a domain with tight latency needs (edge monitoring, real-time triage, live routing).

- **Tracks:** any — best paired with Red Hat Live Data (heartbeat + concurrent inference = throughput story) or Recursive Intelligence.
- **Bounties:** **vLLM $500 cash (primary) + Nemotron (primary)** — this idea is engineered to win both · NemoClaw + OpenShell (NemoClaw routes inference to exactly this kind of self-hosted open model) · Most Commercializable.
- **How we stand out:** the vLLM bounty explicitly weights **efficiency** (in-flight batching, concurrent requests, most capability per unit compute) and the **small-model punch**. We show a benchmark: our Nemotron-Nano-on-vLLM agent vs. a big hosted API on the same task, at a fraction of the cost/latency, under a real concurrent heartbeat load. That's a graph judges can't argue with.
- **Comparable winners:** Skyrchitect (AWS × NVIDIA 2025, 2nd — Llama-3.1-Nemotron-Nano-8B as NIM autonomously designing infra) · GridVeda (TreeHacks 2026, Nemotron on Jetson edge, real-time transformer failure prediction) · Neural Courier (Berkeley 2025, Groq-hosted LLM as a <400 ms drone brain) · Route Optimization Agent (NVIDIA NeMo Toolkit, 1st).

### Idea 6 — Real-time Texas civic/emergency response agent
A heartbeat agent fusing **Texas open streaming datasets** (transit, NOAA weather, wildfire/air-quality, 511 traffic) that continuously watches for an emerging situation, reasons over the combined live picture, and pushes prioritized, actionable guidance to a target user (a commuter, a dispatcher, a facilities manager). Emergency/civic response is the domain that dominates top prizes at every hackathon we surveyed.

- **Tracks:** Red Hat Live Data (primary).
- **Bounties:** Nemotron + vLLM (fast local reasoning under the heartbeat) · HiddenLayer (ingested feeds are untrusted) · Most Commercializable (gov/enterprise ops).
- **How we stand out:** the track author *nudges* toward Texas real-time datasets — leaning in signals we read the brief, and **fusing several live feeds** into one decision is explicitly called out as what "good" looks like. Pick a narrow, real, demoable scenario (e.g. "route field crews around a fire + storm in real time") rather than a broad dashboard.
- **Comparable winners:** ContainOS (TreeHacks 2026, OpenAI Track 1st — physics-grounded multi-agent wildfire containment on live data) · MayDay (Berkeley 2025 — live ATC audio anomaly detection) · FirstResponder-Relay & Orion (Berkeley 2026 / Cal Hacks 12 — 911 overflow triage / wildfire ops on streaming data) · Baymax (Cal Hacks 12 — hospital agents on live weather/disease/inventory).

---

## 2. Recommendation & stacking strategy

**If we want the highest expected value, build Idea 1 (Sentinel Skill) or Idea 4 (Contained ops agent)** and instrument it so it stacks all four bounties. Reasoning:
- Agent-security is the **thinnest, best-rewarded field** — we compete against fewer strong entries and hit both a track (HiddenLayer) and a bounty (NemoClaw+OpenShell) with the same core build.
- Both ideas naturally serve a **Nemotron model on vLLM** (the $500-cash bounty + Nemotron bounty) and both have a clean **Antler commercial** pitch.
- A defense-in-depth demo — HiddenLayer *detects* the malicious intent, OpenShell *blocks* the action — is a memorable, on-stage, adversarial-proof story that maps 1:1 to two separate rubrics.

**If we want to lean on our existing Giftmaxxing infrastructure** (taste vectors, gift graph, deal-monitoring scaffold, AWS pipeline), **Idea 2 (recursive gift-scout)** or **Idea 3 (live deal hunter)** are the fastest to a working demo and the strongest Antler-commercializable pitch, since they extend a product we already understand.

**Universal checklist to maximize the 30 sponsor-tech points regardless of idea:**
1. Serve **Nemotron via vLLM** for at least the agent's core reasoning (2 bounties, 1 build).
2. Wrap the agent in **NemoClaw + OpenShell** with a real, testable YAML policy (bounty + containment story).
3. Route prompts/tool-calls through **HiddenLayer** (track or cross-eligible credit).
4. Make the **heartbeat visible and real** in the Loom — a timer/state trigger, persistent memory across runs, autonomous recovery.
5. Prepare the **"why this sponsor tech" answer** for each tool — 15 of the 30 sponsor points are for articulating *why* it was the right choice, not just that you used it.
6. Pitch the **commercial wedge** in the write-up for the Antler prize.

---

## 3. Appendix — comparable winning projects (full reference table)

| Project | Event (year) | Prize | Why it's relevant |
|---|---|---|---|
| ShadowGuard | TreeHacks 2026 | Healthcare Grand Prize | Real-time L7 proxy redacting PHI before it leaves the network — security instrumentation |
| ClawShield | Circle USDC OpenClaw 2026 | Best OpenClaw Skill | Protects OpenClaw agents from exfiltration at runtime |
| Sentinel | UC Berkeley AI 2026 | Finalist | Security agent that *proves* vulns in sandboxes + patches |
| AgentGuard / Team Hoosiers | Berkeley RDI LLM-Agents | Safety 2nd ($6.5K ea) | Agents that harden/scan other agent systems |
| Holistic AI | OpenAI gpt-oss-20b Red-Team | Top-10 ($50K pool) | Open-model + security crossover |
| Mobius | TreeHacks 2026 | YC Track + Modal | 3,000-turn autonomous self-improving company-builder loop |
| HackOverflow | TreeHacks 2026 | fetch.ai + Runpod | Shared self-improving memory across agents |
| SSEAL | Berkeley RDI | Fundamentals 1st ($25K) | Self-supervised explorative *self-improving* agent |
| Apollo | Microsoft AI Agents 2025 | Best C# ($5K) | Vector memory + knowledge-gap self-checks |
| Inspector | UC Berkeley AI 2026 | Hacker's Choice | Autonomous build→test→fix self-improving loop |
| Tekton | Anthropic Opus 4.8 Build Day | 1st | Independent verifier sub-agents + self-correction |
| GDELT Open Intelligence Agent | ArangoDB × NVIDIA GTC 2025 | 1st | Agent over a live global-events knowledge graph |
| ContainOS | TreeHacks 2026 | OpenAI Track 1st | Multi-agent wildfire containment on live data |
| MayDay | UC Berkeley AI 2025 | Vapi/Fetch/Unify | Live ATC audio anomaly detection |
| FirstResponder-Relay | UC Berkeley AI 2026 | Winner | 911 overflow triage, real-time voice/streaming |
| Orion | Cal Hacks 12 | Warp + Vapi | Wildfire ops on live incident/video streams |
| Skyrchitect | AWS × NVIDIA 2025 | 2nd | Nemotron-Nano-8B (as NIM) autonomously designing infra |
| GridVeda | TreeHacks 2026 | NVIDIA Edge AI | Nemotron on Jetson edge, real-time failure prediction |
| Neural Courier | UC Berkeley AI 2025 | Groq Creative | Fast-inference LLM as a <400 ms drone brain |
| Route Optimization Agent | NVIDIA NeMo Toolkit 2025 | 1st | Multi-agent routing on NeMo + cuOpt |
| MonkeyClaw | NVIDIA NemoClaw @ UCSC 2026 | Winner | Probing/patching/protecting the NemoClaw ecosystem |
| ClawRouter (BlockRunAI) | Circle USDC OpenClaw 2026 | Agentic Commerce | Agents autonomously routing + paying for inference |
| ARIA | Anthropic Opus 4.7 | Best Managed Agents | 5 agents + 17 tools, persistent ops loop |
| HiveOps | YHack 2026 | Winner | Agentic incident triage + root-cause loop |
| RiskWise | Microsoft AI Agents 2025 | Best Overall ($20K) | Supply-chain risk agent on near-real-time signals |
| Second Self | YHack 2026 | Winner | Always-on autonomous desktop agent |
| FaceTimeOS | Cal Hacks 12 | Grand Prize | Voice-commanded autonomous Mac agent |
| Alto | LA Hacks 2025 | 1st Overall | End-to-end autonomous mobile bug-fix pipeline |
| Cameron | UC Berkeley AI 2025 | Grand Prize | Always-on ambient camera agent (heartbeat exemplar) |

**Two near-identical upcoming events worth scouting for format/judges:** Ruya AI "Self-Improving Agents" Hackathon 2026; "Self Improving Agents Hack" (self-improving agents on real-time data). The Circle **USDC OpenClaw Hackathon** (Feb 2026) is the closest precedent to *this* event's "Claw Agent" framing — it was literally run by agents on a heartbeat loop.
