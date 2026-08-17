# MTL value model — the SageMaker recommendation stack

> Moved out of `CLOUD.md` on 2026-08-17, verbatim. The summary lives in `CLOUD.md`;
> this is the full detail on training, features, serving and the runbook.

## 16. MTL value model — the SageMaker recommendation stack (Jul 2026)

> **Status:** code complete + trained on live data; endpoint deploy is the
> remaining AWS step (runbook §16.5). Everything lives in **`infra/ml/`**.

### 16.1 What it is

A multi-task network predicts three concrete actions per (user, item); the feed
sorts by the value model:

| Head | Meaning | Label source (analytics/interactions) |
|---|---|---|
| `P_Time` | dwells > 60 s on the item | `feed_dwell.dwellMs >= 60000` — **live today** (2.7k dwell events, 83 positives) |
| `P_Custom` | types a custom message for the gift | `custom_message` (why-note / gift-letter — iOS instrumented Jul 2026), `comment` |
| `P_Buy` | checkout / buy intent | `product_affiliate_click`, `pledge`, `queue_add`, future `checkout` |

**`Score = 2·P_Time + 5·P_Custom + 1·P_Buy`**

Architecture (small-data regime, ~2k examples / 40 users): item tower =
**1024-d Titan Multimodal embedding** (the image-understanding pipeline IS the
multi-modal augmentation — no separate vision model), user tower = leakage-free
taste centroid (events strictly before each exposure), aux = cosine + price +
activity + source one-hots → shared bottom MLP → three sigmoid heads. Heads
with zero train positives are masked (custom/buy today) and come alive as
instrumentation accrues — no retraining-code changes needed.

First train (Jul 2026): 1,838 examples (1,617/221 group-split by user),
P_Time val AUC ≈ 0.98 (1 val positive — directional, not a benchmark).

### 16.2 Files (`infra/ml/`)

- `export_training_data.py` — DynamoDB analytics+interactions ⋈ S3 Vectors →
  `train/val.npz` + `meta.json`, local + `s3://giftmaxxing-dev-ml/datasets/mtl/<stamp>/`.
- `mtl_model.py` / `train.py` / `inference.py` — model, SageMaker-compatible
  trainer (also runs locally in seconds), serverless-endpoint handlers.
- `cluster_gifts.py` — **gift grouping**: k-means over all 4.3k Titan vectors →
  coherent shelves (jewelry/handmade, personalized/wedding, tech accessories,
  beauty, apparel…); `--apply` publishes `pool#<id>` rows (config table) for
  §15.3 pool blending. Read-only by default.
- `notebooks/mtl_recommender.ipynb` — the SageMaker notebook: EDA → local train
  → Training Job (`ml.m5.large` spot) → Model Registry → **serverless endpoint**
  deploy → smoke test → clustering. Notebook instance: `ml.t3.medium`, PyTorch
  kernel, no GPU (the model is a tiny MLP; dataset is a few MB).

### 16.3 SageMaker component mapping (adopt now vs later)

| Reference component | Now (40 users) | At scale |
|---|---|---|
| Processing Jobs | `export_training_data.py` run locally/notebook | same script as a Processing Job on a schedule |
| Feature Store | **deferred** — npz + meta.json is the feature contract | online store when features need sub-ms reads |
| Training Jobs | ✅ `train.py` (local ≈ SageMaker, same file) | distributed only if data demands it |
| Model Registry | ✅ notebook cell (`giftmaxxing-mtl` group) | approval-gated CD |
| Real-time serving | ✅ **Serverless endpoint** (scales to zero, pennies) — fronted by the existing API Gateway + Lambda | provisioned endpoint + auto-scaling |
| Batch Transform | deferred (no large offline population yet) | nightly offline recs |
| Model Monitor | deferred — retrain is manual/cheap | drift-triggered retraining |

### 16.4 Serving + iOS wiring

`GET /recommendations` (handler.mjs): taste centroid → S3 Vectors kNN →
**`mtlRerank()`** fetches candidate vectors (`GetVectors`) → invokes
`MTL_ENDPOINT` (2.5 s timeout) → sorts by `Score`, attaches per-item
`mtl:{pTime,pCustom,pBuy,score}`, response `source:"vector+mtl"`. Any
error/timeout (e.g. serverless cold start ~10–30 s) soft-falls back to cosine
order — cold hits warm the endpoint without hurting users. **Zero iOS changes
needed for serving:** `FeedViewModel.fetchPersonalizedPicks()` already consumes
`/recommendations`. Client-side additions: `custom_message` analytics event
(why-notes via `trackContentAction`, letters fan out to board items) feeding
P_Custom.

### 16.5 Runbook (infra agent)

1. `cd infra/ml && python3 -m venv .venv && .venv/bin/pip install -r requirements.txt`
2. `AWS_PROFILE=… .venv/bin/python export_training_data.py --s3-bucket giftmaxxing-dev-ml`
3. Train + deploy via `notebooks/mtl_recommender.ipynb` (§4–§6) → endpoint `giftmaxxing-dev-mtl`.
4. `terraform apply -var mtl_endpoint=giftmaxxing-dev-mtl` (also ships the
   handler + IAM `sagemaker:InvokeEndpoint`; dark until the var is set).
5. Verify: `GET /recommendations?userId=…` returns `source:"vector+mtl"`.
6. Optional: `cluster_gifts.py --apply` to publish gift pools; retrain
   monthly-ish as `custom_message`/buy labels accrue (re-run 2–4).

Costs: training ≈ pennies (spot, minutes), serverless inference ≈ $ single
digits/mo at current traffic, `giftmaxxing-dev-ml` storage ≈ pennies. No idle
cost anywhere.

### 16.6 v2 — interaction model + deep MTL with context & Reddit features (Jul 2026)

**Serving = "fast front-end + intelligent back-end"** (Thinking-Machines-style
interaction model): `GET /recommendations` DEFAULTS to the fast path — cosine
order, no model invoke, instant. **`?rank=full`** is the back-end path: MTL
value-model re-rank with a 12 s deadline (`MTL_TIMEOUT_FULL_MS`) — cold starts
are fine because the iOS client calls it AFTER first paint
(`FeedViewModel.refinePersonalizedPicks()`) and swaps the refined ranking into
the below-the-fold pick slots only (slot 1 may be on screen; it stays).
A stale refine is cancelled on every reload.

**Model v2** (`infra/ml/mtl_model.py`, version=2): item/user towers (1024→96)
→ deep shared bottom **256→128→64** (3 hidden layers) → **per-task MLP heads**
(64→32→1) so what drives a custom message can be learned separately from what
drives a quick buy. New **context input (20-d, `features.py`)**: cyclical
time-of-day/day-of-week, relationship one-hot, occasion one-hot, and **Reddit
knowledge features** — the item title is matched against the r/Gifts idea
lexicon and carries that idea's global + per-recipient popularity weight
(snapshot `knowledge_snapshot.json` rides inside the model artifact; zero
runtime I/O).

**Training/inference separation without skew:** `features.py` is the single
featurizer imported by BOTH `export_training_data.py` (offline) and
`inference.py` (endpoint); the Lambda sends only RAW context
(ts/relationship/occasion/title). Relationship/occasion are historically
untracked so they train as zeros until instrumented context accrues — the
pipeline is already plumbed. Retrained Jul 2026: P_Time val AUC ≈ 0.99 (still
1 val positive — directional).
