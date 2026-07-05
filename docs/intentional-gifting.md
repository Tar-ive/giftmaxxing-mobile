# Intentional Gifting — the agent-first consult

> "Giftmaxxing is about making gifting *intentional*. When friends ask me for
> gift help, I don't hand them a catalog — I ask a few sharp questions about
> the person, then say *get them this*. The bar for a good gift: **when they
> move, would they pack it — or purge it?**"

This document specifies the two conversational surfaces that implement that
thesis on the web app, and the shared engine behind them, so the iOS app can
implement the identical experience.

## The two conversations

| Surface | Route | Purpose |
|---|---|---|
| **Gift Concierge** | `/gift` (public, no account) | The consult: 7 questions about a person → a ranked shortlist where every item passes the move test. The link you send someone who texts "help, what do I get my mom". |
| **Onboarding** | `/onboarding` | Meeting Maxi. Same chat engine, same register — collects the exact `UserProfile` the old 9-step wizard produced (bit-compatible: `saveProfile()` + `giftmaxxing:profile` event, ≥3 interests, deal prefs, event dates, Pinterest link). |

Both are rendered by one script engine: `web/components/app/chat-flow.tsx`.
The conversation is **deterministic** — a data script of steps (chips /
multi-select / free text), not an LLM call. Free-text answers are parsed with
small, testable parsers (budget, dates, "free Sunday" keywords). This keeps
the flow instant, offline-safe, and free, while *feeling* like an agent
(typing dots, staggered bubbles, personalized prompts, an "change my last
answer" undo). The live-LLM upgrade path slots in behind the same script
interface (see "Later" below).

## The consult script (`/gift`)

Defined in `web/lib/consult.ts` (framework-free, mirrors `lib/events.ts` style).

1. **Who are we gifting?** — relation chips → the catalog's `recipient` facet
   (`mom`, `dad`, `partner`, …; soft boost server-side).
2. **What do you call them?** — optional name; every later prompt and result
   line uses it ("Squarely Maya's thing").
3. **Occasion** — maps to the `occasion` facet.
4. **Budget** — chips or free text (`parseBudgetText`: "$80", "around 100").
   Hard ceiling at 1.15× ("a friend will stretch you 15%, no more").
5. **Their world** — multi-select of 12 "worlds" (Cooks & hosts, Jewelry &
   keepsakes, …), each mapping to real catalog categories + vibes
   (`CONSULT_WORLDS`).
6. **Free Sunday** — the sharpest discriminator a friend asks. Free text,
   parsed by keyword sweep into additional worlds (`parseSunday`).
7. **The keeper question** — "last time they moved, what came with them, no
   question?" Calibrates which durable cluster this person provably values
   (`CONSULT_KEEPERS`); "they travel light" flags a minimalist (stricter
   move-test weighting).

## The move test (`moveTest`)

Every candidate gets a 0–1 keep-probability score:

- **Category priors** (`CATEGORY_DURABILITY`): jewelry 0.9, kitchen/books 0.8,
  art 0.75 … consumables (food 0.3, beauty 0.35) at the bottom.
- **Keep signals** (title regex, additive): personalized/engraved +0.15,
  handmade +0.12, real materials (walnut, leather, ceramic, cast iron) +0.10,
  heirloom/keepsake +0.15, daily-use nouns +0.06.
- **Clutter signals** (subtractive): novelty/gag −0.35, figurine/trinket −0.20,
  plastic/single-use −0.15, keychain/sticker/magnet −0.15.
- **Price sanity**: under $12 −0.10 (trinket risk).

Verdicts: `≥0.7` **"Would pack it"** 📦 · `≥0.5` **"Keeps it"** 👍 · below
**"Clutter risk"** ⚠️ — clutter is *never shown* in consult results. Each card
wears its verdict badge and one human-readable reason.

## Ranking (`rankGifts`)

`score = wMove·moveTest + 0.35·interestMatch + wFit·budgetFit`

- `wMove` = 0.45, or **0.55 for minimalists** (the gift must earn shelf space).
- `interestMatch`: position of the item's category in the derived, keeper-
  boosted category order (unmatched items still compete at 0.25 — serendipity).
- `budgetFit`: spending real budget beats token spends; the 1.0–1.15× stretch
  zone scores 0.55; anything above is filtered out.
- Variety pass: max 3 per category in the final 9.

## Data flow

```
answers ──deriveSignals──▶ GET /feed?recipient&occasion&category&budget&vibes   (targeted)
                        └▶ GET /feed?budget&limit=50                            (broad)
        posts (now carrying `category`) ──rankGifts──▶ top pick + 8 runners-up
        outbound links ──outboundAffiliateUrl──▶ Amazon tag / Skimlinks, rel=sponsored
```

- Backend facets are **soft boosts** (`scorePost` in `infra/src/handler.mjs`),
  so thin facets can't starve results; the client-side ranker does the
  precision work.
- `Post.category` is newly mapped through `mapApiPost` (`web/lib/api.ts`) —
  the API always returned it; the client just dropped it before.
- Zero results / API down → tagged Amazon search links per world (never a
  dead end, still monetized).

## Onboarding parity notes

- Output shape unchanged: `UserProfile` from `web/lib/onboarding.ts`,
  including `dealPreferences`, `pinterestLinks`, `recipients` + `events`.
- The events chat loop (`evtName → evtRelation → evtType → evtDate → evtMore`)
  reuses recipients for repeat (name, relation) pairs, `reminderLeadDays: 7`,
  recurrence `annual` unless a one-off occasion carries an explicit future year
  (`parseEventDateText` accepts "3/14", "March 14", "14 march 1998").
- Clerk-known names skip the name question (same as the wizard's auto-skip).

## iOS implementation map

| Web | iOS |
|---|---|
| `lib/consult.ts` | `Consult.swift` — pure struct + functions, port 1:1 |
| `components/app/chat-flow.tsx` | SwiftUI chat view driven by the same step list |
| `/gift` results | Sheet with the same top-pick + grid + verdict badges |
| Feed CTA (`consult-cta.tsx`) | Feed header card → consult sheet |

The question script, world/keeper mappings, durability table, and scoring
weights above are the spec — keep the constants in sync.

## Later (explicitly out of scope now)

- **LLM mode**: swap the scripted prompts for Bedrock chat (`/maxi/chat`
  tools already exist) while keeping this script as the deterministic
  fallback and the move test as the ranking layer.
- Persist consult answers as a draft `Recipient` on the signed-in profile.
- Log `consult_completed` / verdict-click analytics events.
