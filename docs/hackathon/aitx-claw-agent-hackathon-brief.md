# AITX Community x NVIDIA Claw Agent Hackathon — Project Brief

> Research compiled 2026-07-17 from the official hacker guide (Notion) plus winning
> projects at TreeHacks 2026, UC Berkeley AI Hackathon 2025/2026, Cal Hacks 12,
> LA Hacks 2025, HackHarvard 2025, HackPrinceton Fall 2025, YHack 2026, HackMIT 2025,
> and professional hackathons (NVIDIA NemoClaw/NeMo, Microsoft AI Agents, Anthropic,
> Circle USDC OpenClaw, Google ADK, Berkeley RDI LLM Agents, ElevenLabs, AWS+NVIDIA).

## 1. The event at a glance

- **What:** AITX Community x NVIDIA Claw Agent Hackathon, Antler VC (800 Brazos St #340, Austin), **July 17–19, 2026**. Code freeze **Sunday 11:00 AM**, judging 12–3 PM, Hack Fair + public voting 2–4 PM.
- **Theme — a "Claw Agent" must be:**
  1. **Proactively autonomous** — initiates work, monitors conditions, schedules subtasks, recovers from interruptions.
  2. **Heartbeat-driven** — wakes on a timer/state loop, not on a human prompt.
  3. **Persistent** — its own workspace, memory, files, and session history across runs.
- **Credits:** Featherless AI $25 hosting · Supabase $25 · Apify $50 (coupon `AITX_NVIDIA_CLAW_HACK`).

### Tracks

| Track | Challenge | Judged on |
|---|---|---|
| **Recursive Intelligence** | Agent measurably gets smarter over successive runs (knowledge graph / self-RAG / episodic memory), no retraining | **Performance delta first-run → last-run** (time, accuracy, decision quality); bonus for a clear learning mechanism |
| **Red Hat Live Data** | Agent powered by real-time streaming open data (TX transit, NOAA weather, fire feeds suggested — any live source OK) | Genuine streaming (not a static download dressed up); does freshness meaningfully change what the agent can do |
| **HiddenLayer Runtime Security** | Route every prompt / response / tool call / ingested doc through HiddenLayer's Runtime Security API; treat all model I/O as untrusted. Key vendor: event code `AITX-2026` | **Depth of instrumentation** + thoughtfulness of the response policy (refuse / escalate / log / creative) |

### Bounties (all cross-track, stackable on top of a track placement)

| Bounty | Bar | What wins | Prize |
|---|---|---|---|
| **Best Use of vLLM** | Agent inference actually served from your own vLLM endpoint (any open model) | Continuous batching / PagedAttention used meaningfully; **small-model-outperforms-its-size** story; heartbeat = repeated concurrent inference where throughput matters | **$500 cash** (only cash bounty) |
| **Best Use of NemoClaw + OpenShell** | Agent stood up via NemoClaw AND a real OpenShell YAML policy that judges can pressure-test | Genuine capability underneath (live credentials/real access), policy robustness under adversarial prompting, nuanced boundaries (allow-with-escalation, human-in-the-loop), architectural clarity | $100 Brev credits / member |
| **Best Use of Nemotron** | Nemotron powering the agent, with a written "why" | Model central to the value, output-quality work (grounding, evals, feedback loops), real problem | $100 Brev credits / member |
| **Most Commercializable (Antler)** | Something people would pay for in a big growing market | Customer↔problem fit, immediate value, superiority vs existing solutions | Dinner with Antler ATX |

### Judging (100 pts) — read this as strategy

- **30 pts Technical execution** (15 completeness — no crashes; 15 depth — pipeline, not a wrapper)
- **30 pts Sponsor tech** (15 meaningful use; 15 articulating *why* it was the right choice) ← **the biggest lever; most teams ignore it. Stack sponsors deliberately.**
- **20 pts Value/impact** (10 non-obvious insight; 10 could a user act on it tomorrow)
- **20 pts Frontier factor** (10 creative combination; 10 speed/scale optimization)

### Submission checklist
Project title + team name · track selected · **2–5 min Loom (must be Loom), show the core loop live** · public repo with README (quick start, stack + architecture diagram, repro steps + sample .env, data provenance, limitations) · deployed URL or screen capture · team roster · 150–300-word write-up (problem → who → solution → impact).

---

## 2. What wins at agent hackathons (patterns from ~60 winners)

1. **Security-of-agents wins disproportionately.** The field is thin and judges reward it: ClawShield (Circle OpenClaw), AgentGuard + PrivAgent (Berkeley RDI, $10K+ each), Sentinel (Berkeley '26 finalist), ShadowGuard (TreeHacks '26 track grand prize), MonkeyClaw (NVIDIA NemoClaw hackathon), HaloAudit (HackHarvard).
2. **"Observe → act → verify → improve" closed loops** are the winning flavor of autonomy: Mobius (TreeHacks — 11-hour, 3,000-turn autonomous company builder, YC track), Inspector (Berkeley '26 Hacker's Choice), Alto (LA Hacks 1st overall), Tekton (Anthropic Build Day 1st — independent verifier sub-agents + self-correction).
3. **Live-data agents win when the source is exotic and real** — GDELT global events graph (GTC 1st), live ATC audio (MayDay), wildfire ops (Orion, ContainOS), hydroponic sensors (HydroClawNics) — not a stock-ticker demo.
4. **Small open models doing real agentic work** is exactly what NVIDIA-sponsored judges reward: Skyrchitect (Nemotron-Nano-8B, AWS+NVIDIA 2nd), GridVeda (Nemotron on Jetson, TreeHacks NVIDIA track), Neural Courier (sub-400 ms LLM drone brain), Re:Compress (1.5B distilled model).
5. **A live, measurable demo beats a story**: performance-delta dashboards, judges invited to attack the system, real-time feeds on screen.

---

## 3. Project ideas (ranked)

### ⭐ 1. "Gauntlet" — the self-hardening agent firewall
An always-on sentinel that sits between any agent and the world: every prompt, tool call, tool result, and ingested document routes through HiddenLayer Runtime Security, and **every detected attack is compounded into a persistent threat knowledge graph** (attack family, payload embedding, source) so the firewall provably catches on run N what it missed on run 1. Ship it as a drop-in proxy any agent framework can point at.

- **Tracks:** HiddenLayer (primary — maximum-depth instrumentation is literally the rubric) + Recursive Intelligence (detection-rate delta over runs).
- **Bounties:** Nemotron (triage/classification model), vLLM (self-host the triage model; concurrent scan calls = throughput story), NemoClaw+OpenShell (run the *protected* agent sandboxed → all four).
- **Standout:** hand judges a "poison kit" (malicious docs, injection prompts) and let them attack it live; show the run-1 vs run-N detection curve on a dashboard. Security + measurable self-improvement is a combination none of the ~60 winners we surveyed fully hit.
- **Similar winners:** [ClawShield](https://www.circle.com/blog/meet-the-winners-of-our-first-usdc-openclaw-hackathon----and-what-we-learned) (Circle OpenClaw '26 — OpenClaw skill-supply-chain guard), [AgentGuard](https://rdi.berkeley.edu/llm-agents-hackathon/) (Berkeley RDI Safety 2nd), [Sentinel](https://devpost.com/software/sentinel-poyh3v) (Berkeley '26), [ShadowGuard](https://devpost.com/software/shadowguard-l6yv7p) (TreeHacks '26 track grand prize).

### ⭐ 2. "Leash" — a dangerously capable agent, provably contained
Flip the security track: build an agent with **real credentials and real power** (a live repo, a database, an email account) that does genuinely useful autonomous ops work on a heartbeat — then contain it with a nuanced OpenShell YAML policy (allow-with-escalation, operator approval on edge cases) and HiddenLayer on every I/O. The demo *is* the jailbreak attempt: judges try to make it exfiltrate, and the boundary holds.

- **Tracks:** HiddenLayer.
- **Bounties:** **NemoClaw+OpenShell is the centerpiece** (their rubric — "an agent worth containing" — describes this project verbatim), + Nemotron + vLLM.
- **Standout:** the NemoClaw bounty explicitly says "a weak agent behind a strong policy isn't a story" — give it real credentials and invite adversarial testing. Almost no team will dare to do this; the ones that do win security prizes (see pattern #1).
- **Similar winners:** [MonkeyClaw](https://nemoclaw.devpost.com/) (NVIDIA NemoClaw hackathon — probing/patching the Nemo