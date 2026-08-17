# JSON → TOON Migration Analysis — Giftmaxxing

> **Purpose.** Map every JSON interaction in the giftmaxxing agent pipeline,
> evaluate where TOON (Token-Oriented Object Notation) would reduce token cost,
> and propose a concrete migration path for agentic commerce readiness.
>
> **TOON** (`@toon-format/toon` v2.3, spec v3.3) is a compact, human-readable
> encoding of the JSON data model that minimizes tokens for LLM input. It
> combines YAML-like indentation with CSV-style tabular arrays. Benchmarks show
> **~40% fewer tokens** than JSON with equal or better LLM comprehension accuracy
> (76.4% vs 75.0% across 4 models). Its sweet spot is **uniform arrays of
> objects** — exactly what Maxi's tool results are.

---

## 1. Where TOON Applies (and Where It Doesn't)

TOON is designed for **LLM input** — a translation layer between JSON (used
programmatically) and what the model reads. This means it applies to data
**flowing INTO Bedrock Converse** (tool results, context), but NOT to:

| Layer | Format | TOON applicable? |
|-------|--------|:---:|
| **Maxi tool results → Bedrock** | JSON objects fed as `toolResult.content` | **YES — primary target** |
| **Maxi system prompt context** | Text with embedded data | **YES** |
| Frontend ↔ API (HTTP) | `application/json` | No (programmatic, not LLM) |
| DynamoDB marshalling | DocumentClient JSON | No (AWS SDK, not LLM) |
| localStorage | `JSON.stringify` | No (browser-only) |
| Bedrock embed requests | `InvokeModelCommand` body | No (API contract, not LLM input) |
| Ingest scripts | JSON manifests | No (offline, not LLM) |

**The entire TOON migration is scoped to one place: the Maxi Converse loop
(search for `MAXI_TOON_ENABLED` in `handler.mjs`), specifically the
`toolResult.content` objects fed back to the model after each tool execution.**

---

## 2. Current JSON Cost in the Maxi Agent Loop

### How the loop works today

```text
POST /maxi → Lambda handler
  for step 0..4:
    ConverseCommand(system, messages, toolConfig) → Bedrock
    ← model returns tool_use blocks
    for each tool_use:
      result = runMaxiTool(name, input, ctx)       // returns JSON object
      messages.push({ toolResult: { content: [{ json: result }] } })
    → next Converse iteration with accumulated history
```

Each tool result is a **full JSON object** carried in message history for ALL
subsequent Converse turns. By step 3–4 the context window carries every prior
tool result in full JSON verbosity.

### The 7 tool results that benefit most from TOON

These tools return **uniform arrays of objects** — TOON's sweet spot:

#### 2.1 `find_gifts` — catalog search results

**JSON today (~480 tokens for 6 items):**
```json
{
  "items": [
    { "postId": "pin-155303888285817876", "title": "Handmade Ceramic Coffee Mug", "price": 24.99, "brand": "CeramicCo", "image": "https://i.pinimg.com/...", "category": "kitchen" },
    { "postId": "pin-155303888285817877", "title": "Minimalist Plant Pot Set", "price": 34.50, "brand": "GreenHome", "image": "https://i.pinimg.com/...", "category": "plants" },
    { "postId": "pin-155303888285817878", "title": "Cozy Knit Throw Blanket", "price": 42.00, "brand": "NestWell", "image": "https://i.pinimg.com/...", "category": "home" },
    { "postId": "pin-155303888285817879", "title": "Vintage Camera Keychain", "price": 12.99, "brand": null, "image": "https://i.pinimg.com/...", "category": "vintage" },
    { "postId": "pin-155303888285817880", "title": "Essential Oil Diffuser", "price": 29.99, "brand": "AromaZen", "image": "https://i.pinimg.com/...", "category": "wellness" },
    { "postId": "pin-155303888285817881", "title": "Watercolor Paint Set", "price": 18.50, "brand": null, "image": "https://i.pinimg.com/...", "category": "art" }
  ],
  "count": 6
}
```

**TOON equivalent (~290 tokens, ~40% savings):**
```text
count: 6
items[6]{postId,title,price,brand,image,category}:
  pin-155303888285817876,Handmade Ceramic Coffee Mug,24.99,CeramicCo,https://i.pinimg.com/...,kitchen
  pin-155303888285817877,Minimalist Plant Pot Set,34.5,GreenHome,https://i.pinimg.com/...,plants
  pin-155303888285817878,Cozy Knit Throw Blanket,42,NestWell,https://i.pinimg.com/...,home
  pin-155303888285817879,Vintage Camera Keychain,12.99,null,https://i.pinimg.com/...,vintage
  pin-155303888285817880,Essential Oil Diffuser,29.99,AromaZen,https://i.pinimg.com/...,wellness
  pin-155303888285817881,Watercolor Paint Set,18.5,null,https://i.pinimg.com/...,art
```

The field names (`postId`, `title`, `price`, `brand`, `image`, `category`) are
declared **once** in the header instead of repeated 6× in JSON.

#### 2.2 `find_deals` — deal products with commerce metadata

**JSON today (~900 tokens for 8 items):**
Each product has 13 fields: `postId, title, brand, image, category, price,
listPrice, discountPct, rating, reviews, boughtPastMonth, delivery, onDeal`.
Repeating 13 keys × 8 rows = 104 key repetitions eliminated by TOON.

**TOON equivalent (~500 tokens, ~44% savings):**
```text
count: 8
groups[2]:
  - category: kitchen
    label: Kitchen
    items[3]{postId,title,brand,price,listPrice,discountPct,rating,reviews,boughtPastMonth,delivery}:
      pin-001,Ceramic Mug Set,CeramicCo,24.99,39.99,38,4.5,2340,200+,2026-07-03
      pin-002,Chef Knife,SharpEdge,49.99,79.99,37,4.7,5120,500+,2026-07-02
      pin-003,Bamboo Cutting Board,GreenKit,18.5,29.99,38,4.3,890,100+,2026-07-04
  - category: wellness
    label: Wellness & Self-Care
    items[2]{postId,title,brand,price,listPrice,discountPct,rating,reviews,boughtPastMonth,delivery}:
      pin-004,Essential Oil Set,AromaZen,22.99,34.99,34,4.6,3200,500+,2026-07-02
      pin-005,Yoga Mat,FlexCore,29.99,44.99,33,4.4,1800,200+,2026-07-03
products[5]{postId,title,brand,price,listPrice,discountPct,rating,reviews,boughtPastMonth,delivery,category,onDeal}:
  pin-001,Ceramic Mug Set,CeramicCo,24.99,39.99,38,4.5,2340,200+,2026-07-03,kitchen,true
  pin-002,Chef Knife,SharpEdge,49.99,79.99,37,4.7,5120,500+,2026-07-02,kitchen,true
  pin-003,Bamboo Cutting Board,GreenKit,18.5,29.99,38,4.3,890,100+,2026-07-04,kitchen,true
  pin-004,Essential Oil Set,AromaZen,22.99,34.99,34,4.6,3200,500+,2026-07-02,wellness,true
  pin-005,Yoga Mat,FlexCore,29.99,44.99,33,4.4,1800,200+,2026-07-03,wellness,true
```

#### 2.3 `order_history` — past orders + restockables

**JSON today (~350 tokens):**
```json
{
  "orderCount": 4,
  "seeded": false,
  "topCategories": [
    { "category": "kitchen", "label": "Kitchen", "count": 7 },
    { "category": "wellness", "label": "Wellness & Self-Care", "count": 5 },
    { "category": "home", "label": "Home & Cozy", "count": 3 }
  ],
  "restockables": [
    { "postId": "pin-001", "title": "Ceramic Mug Set", "category": "kitchen", "timesOrdered": 4, "lastOrdered": "2026-06-15" },
    { "postId": "pin-004", "title": "Essential Oil Set", "category": "wellness", "timesOrdered": 3, "lastOrdered": "2026-06-20" }
  ]
}
```

**TOON equivalent (~200 tokens, ~43% savings):**
```text
orderCount: 4
seeded: false
topCategories[3]{category,label,count}:
  kitchen,Kitchen,7
  wellness,Wellness & Self-Care,5
  home,Home & Cozy,3
restockables[2]{postId,title,category,timesOrdered,lastOrdered}:
  pin-001,Ceramic Mug Set,kitchen,4,2026-06-15
  pin-004,Essential Oil Set,wellness,3,2026-06-20
```

#### 2.4 `list_connections` — friend profiles

**JSON today (~320 tokens for 5 items):**
```json
{
  "items": [
    { "friendName": "Maya", "birthday": "1998-03-15", "interests": ["matcha", "yoga"], "vibes": ["cozy", "minimal"], "connectionId": "conn_abc" }
  ],
  "note": "These are the user's FRIENDS/CONNECTIONS..."
}
```

**TOON equivalent (~200 tokens, ~38% savings):**
```text
note: These are the user's FRIENDS/CONNECTIONS (other people), not the user. friendName is the friend's name.
items[5]:
  - friendName: Maya
    birthday: 1998-03-15
    interests[2]: matcha,yoga
    vibes[2]: cozy,minimal
    connectionId: conn_abc
```

(Note: `list_connections` has nested arrays in each item, so TOON uses expanded
list-item form rather than pure tabular — still saves ~38% from key deduplication
and removing braces/quotes.)

#### 2.5 `upcoming_events`

**TOON tabular form is a perfect fit:**
```text
items[4]{type,date,daysUntil,recipient}:
  birthday,2026-07-15,16,Maya
  anniversary,2026-08-03,35,null
  graduation,2026-09-01,64,Alex
  holiday,2026-12-25,179,null
```

#### 2.6 `gift_ideas`

```text
ideas[4]{item,count}:
  matcha tea set,47
  yoga mat,38
  essential oils,29
  plant pot,22
bundles[2]:
  - items[3]: matcha tea set,bamboo whisk,ceramic cup
  - items[3]: yoga mat,resistance bands,water bottle
```

#### 2.7 `list_recipients`

```text
items[8]{recipient,label,postCount}:
  mom,Mom,42
  dad,Dad,38
  friend,Friend,35
  partner,Partner,31
  sister,Sister,28
  brother,Brother,24
  grandparent,Grandparent,18
  coworker,Coworker,15
```

### Tools where TOON doesn't help much

| Tool | Shape | Why TOON isn't ideal |
|------|-------|---------------------|
| `get_profile` | Single nested object | Not a uniform array — TOON's savings are minimal (~10%) |
| `relationship_graph` | Mixed counts + small list | Non-tabular — minimal savings |
| `save_event`, `remember_fact` | Small `{ ok: true }` | Too small to matter |
| `add_to_cart`, `checkout` | Action confirmation | Too small to matter |

---

## 3. Total Token Savings Estimate

### Per-interaction model (typical 3-tool Maxi flow)

| Step | Tool | JSON tokens (est.) | TOON tokens (est.) | Savings |
|------|------|---:|---:|---:|
| 1 | `order_history` | 350 | 200 | 150 (43%) |
| 2 | `find_deals` (8 items) | 900 | 500 | 400 (44%) |
| 3 | `get_profile` | 200 | 180 | 20 (10%) |
| — | Tool schemas (13 tools) | 2,500 | 2,500 | 0 (N/A) |
| — | Accumulated in history | ×2.5 avg | ×2.5 avg | — |
| **Total tool-result tokens** | | **~3,625** | **~2,200** | **~1,425 (39%)** |
| **With history multiplier** | | **~9,060** | **~5,500** | **~3,560 (39%)** |

### Monthly cost impact

- Current Maxi budget: **$25/month**
- Haiku 4.5 input: $0.80/1M tokens, output: $4.00/1M tokens
- If 60% of input tokens are tool results + schemas, and tool results shrink by
  39%, the overall input token reduction is ~23%
- **Estimated monthly savings: ~$3.50–5.00** (14–20% of total spend)
- More importantly: **~23% more interactions per dollar** before hitting the
  budget cap

### Compounding effect

The savings compound on multi-step flows because tool results accumulate in
message history. A 5-step flow (order_history → find_deals → add_to_cart →
checkout → confirmation) carries ALL prior results on every subsequent turn.
TOON shrinks the carried context, so steps 3–5 see disproportionately lower
input token counts.

---

## 4. Implementation Plan

### Phase 1: Add TOON encoding to tool results (handler.mjs)

**Scope:** Change how `runMaxiTool` results are serialized into
`toolResult.content` before feeding back to Bedrock.

**Approach:**

```js
// Add to handler.mjs dependencies
import { encode as toonEncode } from '@toon-format/toon';

// In the Maxi tool-use loop (handler.mjs ~line 2854–2861):
// BEFORE:
results.push({
  toolResult: {
    toolUseId: tu.toolUseId,
    content: [{ json: scrubPII(out) }],
    status: out && out.error ? "error" : "success",
  },
});

// AFTER:
const toolOut = scrubPII(out);
results.push({
  toolResult: {
    toolUseId: tu.toolUseId,
    content: [{ text: toonEncode(toolOut) }],  // TOON-encoded text
    status: toolOut && toolOut.error ? "error" : "success",
  },
});
```

**Key change:** Instead of `content: [{ json: result }]`, use
`content: [{ text: toonEncode(result) }]`. Bedrock Converse accepts both
`json` and `text` content blocks in tool results. Using `text` with
TOON-encoded data gives the model the same information in fewer tokens.

**System prompt addition:**
```
Tool results are formatted in TOON (Token-Oriented Object Notation) — a compact
tabular encoding. Read the headers (e.g., items[6]{id,name,price}:) to
understand field names, then read rows as comma-separated values.
```

### Phase 2: Selective encoding (only for array-heavy tools)

Encode with TOON only for tools whose results contain uniform arrays:

```js
const MAXI_TOON_ENABLED = process.env.MAXI_TOON_ENABLED !== "0";
const MAXI_TOON_TOOLS = new Set([
  'find_gifts', 'find_deals', 'order_history',
  'list_connections', 'upcoming_events', 'gift_ideas',
  'list_recipients',
]);

// In the loop:
const scrubbed = scrubPII(out);
const useToon = MAXI_TOON_ENABLED && MAXI_TOON_TOOLS.has(tu.name) && !scrubbed?.error;
const content = useToon
  ? [{ text: toonEncode(scrubbed) }]
  : [{ json: scrubbed }];
```

This keeps small/non-uniform results (get_profile, save_event, checkout) as
native JSON where TOON wouldn't save tokens.

### Phase 3: Encode memory context as TOON

The `memBlock` injected into the system prompt is currently a bullet list of
strings. If memory entries grow to structured data (preference objects, tagged
facts), encode them as TOON:

```text
memories[5]{kind,text}:
  preference,usually spends $30-50 on gifts
  preference,dislikes scented candles
  semantic,sister Maya loves matcha
  semantic,anniversary May 3
  summary,Helped pick a birthday gift for dad under $40
```

### Phase 4: TOON for the `/maxi` response body (agentic commerce)

For agent-to-agent scenarios where another LLM agent is calling `/maxi`, the
response body itself could optionally be TOON-encoded:

```text
Accept: text/toon
```

```text
say: Here are some deals in your top restock categories!
pins[5]{postId,title,price,listPrice,discountPct,category}:
  pin-001,Ceramic Mug Set,24.99,39.99,38,kitchen
  pin-002,Chef Knife,49.99,79.99,37,kitchen
  pin-003,Bamboo Cutting Board,18.5,29.99,38,kitchen
  pin-004,Essential Oil Set,22.99,34.99,34,wellness
  pin-005,Yoga Mat,29.99,44.99,33,wellness
steps[2]{tool,label,detail}:
  order_history,Scanned your past orders,Top categories you restock: Kitchen & Wellness
  find_deals,Found 5 active deals,in Kitchen & Wellness
source: agent
usage:
  inputTokens: 8420
  outputTokens: 312
  costUsd: 0.00799
```

This makes Maxi's responses consumable by other agents at lower token cost —
foundational for agentic commerce where agents chain tool calls across services.

---

## 5. Dependencies & Risks

### Dependencies

| Item | Detail |
|------|--------|
| `@toon-format/toon` | v2.3.0, MIT, 24.7K stars, TypeScript SDK |
| npm install | Add to `infra/src/package.json` (Lambda bundle) |
| Bundle size | The SDK is lightweight (~15KB minified) |
| Bedrock Converse | Must accept `text` content blocks in tool results (confirmed: Converse API supports both `json` and `text`) |

### Risks & mitigations

| Risk | Mitigation |
|------|-----------|
| Model misparses TOON | Benchmarks show Claude Haiku 4.5 has **highest accuracy with TOON** (59.8%) vs JSON (57.4%). Add a one-line system prompt hint. |
| Commas in product titles break tabular rows | TOON spec handles this: values containing the delimiter are auto-quoted. The SDK handles escaping. |
| Deeply nested tool results (e.g., `find_deals` groups) | Use expanded list-item form for nested objects; tabular for the leaf arrays. SDK handles this automatically. |
| Tool schemas still sent as JSON | Bedrock Converse `toolConfig` requires JSON Schema — can't change this. TOON only applies to tool **results**. |
| Rollback | Keep the `{ json: ... }` path behind a flag: `MAXI_TOON_ENABLED` env var. |

---

## 6. Agentic Commerce Implications

### Why this matters for scaling

1. **More conversations per dollar.** 23% fewer input tokens means 23% more
   Maxi interactions before hitting the $25/month budget. At scale, this is the
   difference between 1,000 and 1,300 agent conversations/month.

2. **Faster agent responses.** Fewer input tokens = faster time-to-first-token
   from Bedrock. In a 5-step tool loop, the cumulative speedup is meaningful.

3. **Agent-to-agent readiness.** When another agent calls Maxi (Phase 4), TOON
   responses are immediately parseable by that agent's LLM at lower cost. The
   `@toon-format/toon` SDK provides `decode()` for programmatic consumption
   and `encode()` for further forwarding — lossless round-trip.

4. **MCP tool server compatibility.** The TOON ecosystem includes
   [Tooner](https://github.com/chaindead/tooner), an MCP proxy that auto-converts
   JSON tool responses to TOON. If/when Maxi's tools are exposed via MCP
   (as recommended in the AgentCore design doc), TOON encoding slots in
   naturally.

### What TOON doesn't solve (need separate work)

- **Tool discoverability:** Still need MCP/A2A/OpenAPI for external agents to
  find Maxi's tools.
- **Real commerce transactions:** Cart/checkout are still simulated. TOON
  optimizes the data format but doesn't add payment processing.
- **Structured commerce schemas:** TOON is a format, not a schema. Still need
  to define product/order/transaction types that agents agree on.

---

## 7. Summary

| Aspect | Current (JSON) | With TOON |
|--------|:---:|:---:|
| Tool result tokens (3-tool flow) | ~3,625 | ~2,200 (−39%) |
| With history accumulation | ~9,060 | ~5,500 (−39%) |
| Monthly budget utilization | $25 → ~1,000 interactions | $25 → ~1,300 interactions |
| Claude Haiku 4.5 accuracy | 57.4% | 59.8% (+2.4pp) |
| Implementation scope | — | 1 file (`handler.mjs`), 1 dependency (`@toon-format/toon`) |
| Rollback risk | — | Feature flag (`MAXI_TOON_ENABLED`) |
| Agent-to-agent readiness | JSON only | TOON + JSON (content negotiation) |
