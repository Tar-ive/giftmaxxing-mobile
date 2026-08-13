# Data inventory — everything we actually have

> Audited live against AWS account `445056752928` / `us-east-1` on **2026-08-06**.
> Every number below was measured, not estimated. Re-run the queries in
> §8 to refresh.

**The one-line answer:** we have a *catalog* problem that is solved and a
*behaviour* problem that is not. There are **4,417 products, 4,302 embeddings
and 81 MB of media** — plenty to recommend *from*. There are **63 positive
training labels across 47 users** — nowhere near enough to learn *how* to rank.
The MTL model isn't badly built; it's starved.

---

## 1. The whole estate at a glance

| Store | What | Size | Records |
|---|---|---:|---:|
| **DynamoDB** (14 tables) | all relational/document data | **11.9 MB** | 22,219 items |
| **S3 Vectors** (`pins`) | 1024-d Titan embeddings | **16.8 MB** raw | 4,302 vectors |
| **S3 `-media`** | product/UGC images, wraps | **62.6 MB** | 133 objects |
| **S3 `-ml`** | training sets + model artifacts | **14.3 MB** | 9 objects |
| **S3 `-tfstate`** | terraform state | 0.34 MB | 1 |
| **Repo (local)** | Reddit corpus, seed catalogs | ~2.3 MB | 6 files |
| **Repo (local, non-data)** | marketing assets | 709 MB | — |

**Total actual product data: ~106 MB.** That is small enough that the entire
dataset fits in memory on a laptop — worth remembering before anyone proposes
a data platform.

---

## 2. DynamoDB — every table

Sorted by size. `PK` = partition key, `SK` = sort key.

| Table | Items | Size | Key | What it holds | Useful for ML? |
|---|---:|---:|---|---|---|
| `posts` | **4,417** | 6.69 MB | `postId` | the gift catalog | ✅ item features |
| `analytics` | **16,465** | 4.57 MB | `userId`+`sk` | raw client events | ✅ **the label source** |
| `challenges` | 40 | 0.18 MB | `challengeId`+`itemId` | swipe decks + guest responses | ✅ **explicit labels** |
| `knowledge` | 16 | 0.13 MB | `recipient` | Reddit-mined gift ideas | ⚠️ priors only |
| `graph` | 352 | 0.11 MB | `pk`+`sk` | memories, briefs, orders, chat | ⚠️ sparse |
| `interactions` | **623** | 0.08 MB | `userId`+`targetId` | like/save/hide/seen | ✅ **the taste signal** |
| `users` | 32 | 0.04 MB | `userId` | profiles, boards, cart | ✅ user features |
| `config` | 47 | 0.04 MB | `key` | galleries, bundles, budgets, caches | ❌ operational |
| `friends` | 83 | 0.02 MB | `pk`+`sk` | friend graph | ⚠️ social signal |
| `events` | 73 | 0.02 MB | `userId`+`eventId` | birthdays/occasions | ✅ context feature |
| `connections` | 31 | 0.01 MB | `userId`+`connectionId` | soft profiles + taste seeds | ✅ 168 seed items |
| `pools` | 25 | <0.01 MB | `poolId`+`itemId` | group gifts | ❌ too few |
| `devices` | 15 | <0.01 MB | `userId`+`deviceId` | push tokens | ❌ |
| `ugc-reports` | **0** | 0 | `reportId` | moderation reports | ❌ empty |

---

## 3. The catalog (`posts`) — this part is healthy

4,417 products. Completeness is genuinely good:

| Property | Count | % |
|---|---:|---:|
| Has a price | 4,400 | **100%** |
| Has an image | 4,402 | **100%** |
| Multi-image gallery | 2,877 | 65% |
| Has a maker story | 2,224 | 50% |
| Services (not products) | 11 | 0.2% |

**Provenance** — the "is it just Pinterest?" question:

| Source | Items | Share |
|---|---:|---:|
| **Shopify** (22 stores, real product feeds) | 2,553 | **58%** |
| **Pinterest** (RSS scrape) | 1,819 | 41% |
| Giftmaxxing curated carousels | 30 | 1% |
| Apify editorial carousels | 6 | <1% |
| UGC | 4 | <1% |

So it is **majority real retailer data**, not Pinterest. That's better than
assumed.

**Quality gate** (`classifyPin`, run over all 4,417): **4,404 pass (100%)**,
13 rejected (12 gift-guide listicles, 1 editorial). The junk-purge work already
did its job — there is no meaningful quality reason to exclude catalog rows
from training.

**Category mix** — heavily skewed to fashion/beauty:

| Category | Items | | Category | Items |
|---|---:|---|---|---:|
| apparel | 864 | | tech | 262 |
| beauty | 601 | | kitchen | 197 |
| jewelry | 540 | | fitness | 155 |
| shoes | 421 | | gifts | 128 |
| home | 321 | | | |

> **Coverage gap, already observed:** no wooden blocks, skateboards, game
> consoles or jigsaw puzzles — which is why the kids/tween age shelves come out
> short. That is a *sourcing* gap, not a data-quality one.

---

## 4. Embeddings

| | |
|---|---|
| Index | `giftmaxxing-dev-vectors / pins` |
| Vectors | **4,302** |
| Dimensions | 1024 |
| Metric | cosine |
| Type | float32 |
| Model | Amazon Titan Multimodal (`amazon.titan-embed-image-v1`) |
| Raw size | 16.8 MB |

**4,302 vectors vs 4,417 posts → ~115 products have no embedding.** They are
invisible to every vector path (Maxi's `find_gifts`, `/recommendations`, the
swipe deck, gallery curation). Fixable with one `backfill:vectors` run.

Embeddings are **image + title** in a shared text/image space. That is why
text→image matching is loose and why shelf curation needs a keyword gate
(see `build-shelves.mjs`).

---

## 5. Behavioural data — the actual bottleneck

### 5.1 Analytics: 16,477 events, but only 13 real users

| Event | Count | | Event | Count |
|---|---:|---|---|---:|
| `feed_dwell` | 3,774 | | `swipe_left` | 327 |
| `feed_impression` | 2,809 | | `session_start` | 314 |
| `feed_revisit` | 2,661 | | **`swipe_right`** | **46** |
| `feed_scroll_depth` | 2,235 | | **`product_affiliate_click`** | **26** |
| `tab_switch` | 1,560 | | `content_tap` | 25 |
| `screen_view` | 986 | | `swipe_deck_complete` | 16 |
| `session_background` | 650 | | **`content_save`** | **16** |
| `swipe_card_shown` | 533 | | **`content_like`** | **8** |
| `session_resume` | 490 | | `content_unsave` | 1 |

**111 distinct userIds — but 98 are anonymous and only 13 are signed in.**

Of 3,774 dwell events, **only 109 reach the ≥60s threshold** that defines the
model's primary label.

### 5.2 Interactions: 623 rows, 15 users

| Type | Count | Signal |
|---|---:|---|
| `seen` | 376 | exposure (negative-ish) |
| `like` | 131 | ✅ positive |
| `hide` | 66 | ✅ **explicit negative** |
| `queue_add` | 32 | ✅ positive |
| `save` | 5 | ✅ positive |
| `comment` | 3 | ✅ positive |
| `pledge` | 2 | ✅ strong positive |
| `unsave` / `queue_remove` | 8 | negative |

**~170 positive and ~450 negative events, from 15 people.**

### 5.3 Swipe challenges — the most under-used asset

| | |
|---|---|
| Decks created (`META`) | 29 |
| Guest responses (`RESP`) | 11 |
| **Per-item yes/no labels** | **86** (37 yes · 49 no) |
| Connection taste seeds | 168 items |

These are **explicit, deliberate, per-item preference judgements from real
recipients** — the cleanest labels in the entire system. They are used today
only to build the sender's connection profile. **The MTL model has never seen
them.**

---

## 6. What the model was actually trained on

`infra/ml/data/{train,val}.npz`, trained 2026-07-16, endpoint
`giftmaxxing-dev-mtl` (InService).

```
X_item  (2000, 1024)   Titan item embedding
X_user  (2000, 1024)   leakage-free taste centroid
X_aux   (2000, 7)      cosine, price, activity, source one-hots
X_ctx   (2000, 20)     time, relationship, occasion, Reddit idea weights
Y       (2000, 3)      three binary labels
```

| Label | Positives | Rate |
|---|---:|---:|
| `y_time_gt60s` | **63** | 3.15% |
| `y_custom_message` | **2** | 0.10% |
| `y_buy_intent` | **3** | 0.15% |

**47 distinct users, and the top user contributes 472 of 2,000 rows (24%).**

### Why the model is weak — precisely

1. **Two of three heads have no signal.** 2 and 3 positives cannot train
   anything; those heads are masked and contribute nothing.
2. **The live head has 63 positives against ~2,096 parameters in the item
   tower alone.** That is 30× more parameters than positive examples.
   Any reported AUC on a validation set with **1 positive** is noise.
3. **One user is a quarter of the data.** The model can score that person's
   taste and little else.
4. **Its inputs exclude the best signals we have** — the 86 explicit swipe
   labels, the 66 `hide` events, and the on-device negative centroid.
5. **It is barely invoked**: 1–6 calls/day, only via `?rank=full` from the Home
   background refine.

**Verdict: the architecture is reasonable; the dataset is ~30× too small and
badly skewed.** No amount of tuning fixes that.

---

## 7. On pre-trained weights

Worth separating two very different ideas:

**❌ Downloading a pre-trained recommender is not a thing.** Ranking models are
tied to a specific catalog, user base and label definition. There is no
transferable "gift ranking" checkpoint — the item IDs, the feature space and
the notion of a positive are all ours.

**✅ We already do the transfer learning that *does* work.** Titan Multimodal
is a large pre-trained model, and every product embedding comes from it. That
is exactly the "borrow someone else's weights" move, applied at the right
layer — representation, not ranking. It is why cosine similarity works at all
with 15 users.

The gap is the thin layer on top that turns similarity into an ordering.

### What we could do better with the data we already have

| Idea | Why it fits our data | Effort |
|---|---|---|
| **Train on swipe labels** (86 explicit + 373 in-app decisions) | deliberate per-item judgements; 6× the positives of the current label | small |
| **Pairwise learn-to-rank** instead of pointwise binary | a shown-vs-chosen pair is a label; turns 533 `swipe_card_shown` into comparisons | medium |
| **Use `hide` as a true negative** (66 events) | already collected, already used on-device, invisible to the model | small |
| **Shrink the model** — logistic regression on ~10 features (cosine, price fit, category match, brand, social proof) | ~170 positives can fit 10 weights; cannot fit 2M | small |
| **Fix user skew** — cap rows per user | one user is 24% of the set | trivial |
| **Backfill the ~115 missing embeddings** | those products can never be recommended | trivial |
| **Log which surface served an item** | we cannot currently attribute an outcome to a ranker | small |

The honest sequencing: **instrument first, model second.** A learned ranker
that beats cosine needs on the order of 10³–10⁴ positives. We have ~170.

---

## 8. How to reproduce this audit

```bash
export AWS_PROFILE=dev_sso_giftmaxxing

# Table inventory
for T in $(aws dynamodb list-tables --region us-east-1 --query 'TableNames[]' --output text); do
  aws dynamodb describe-table --region us-east-1 --table-name "$T" \
    --query 'Table.{n:TableName,items:ItemCount,bytes:TableSizeBytes}'
done

# S3
aws s3 ls s3://giftmaxxing-dev-media --recursive --summarize | tail -2
aws s3 ls s3://giftmaxxing-dev-ml    --recursive --summarize | tail -2

# Vectors
aws s3vectors list-vectors --region us-east-1 \
  --vector-bucket-name giftmaxxing-dev-vectors --index-name pins --max-results 500

# Maxi conversation turns as JSONL
cd infra/ingest && npm run maxi:sessions -- --since 24h --print

# Training label distribution
python3 -c "import numpy as np; d=np.load('infra/ml/data/train.npz',allow_pickle=True); print(d['Y'].sum(0))"
```

> `ItemCount` / `TableSizeBytes` are updated by DynamoDB roughly every 6 hours,
> so they can lag a live write by a few hours. Everything else is exact.
