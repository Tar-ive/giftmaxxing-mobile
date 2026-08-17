# The swipe model, explained

> Written because the training job printed a lot of numbers and explained
> nothing. This is what the model *is*, what it *sees*, and what it *does*.

---

## 1. What problem it solves

You send a birthday swipe challenge to Sarah. She opens a deck of ~14 gift
cards and swipes each one left or right.

**The question the model answers:** *given everything we know about Sarah, which
of these candidate gifts should be card #1?*

That is all it does. It does not choose *which* products exist — that is
retrieval (S3 Vectors kNN). It takes a pool of candidates and puts them in an
order.

```
                 candidate pool (~60 gifts)
                            │
                            ▼
                  ┌───────────────────┐
   Sarah's state ─►   THE SWIPE MODEL  ├─► ranked deck: card 1, 2, 3 …
                  └───────────────────┘
                            │
                            ▼
                  Sarah swipes ← or →
                            │
                            └──► becomes a new label, feeds the next deck
```

---

## 2. The algorithm — genuinely simple

**Logistic regression.** Ten numbers in, one number out.

```
score = sigmoid( w₁·f₁ + w₂·f₂ + … + w₁₀·f₁₀ + b )
```

- `f₁…f₁₀` are the ten features (§3)
- `w₁…w₁₀` are ten learned weights
- `sigmoid` squashes the result into 0–1, read as "probability of a right-swipe"
- rank the deck by that score, highest first

That is the whole model. **Ten weights and one bias — 11 numbers.** You can
read them all (§4). It is stored as a 1 KB JSON file:

```json
{ "features": ["cos_user_item", ...], "w": [0.1577, -0.516, ...], "b": ... }
```

### Why so small — deliberately

The other model in the repo (`mtl_model.py`) is a 3-layer neural net with
**~2,096 parameters in its item tower alone**, trained on **63 positive
examples**. That is 30× more knobs than evidence. It cannot learn; it can only
memorise.

Eleven numbers can be fit from a few hundred labels. And every one is legible —
a wrong sign is a bug you can *see*, instead of a number buried in a tensor.

---

## 3. The ten features — what the model actually sees

For each **(person, candidate gift)** pair:

| # | Feature | What it measures | Where it comes from |
|---|---|---|---|
| 1 | `cos_user_item` | how similar this gift is to things they've swiped **right** | cosine of Titan embeddings |
| 2 | `cos_user_item_neg` | how similar to things they've swiped **left** | cosine against the dislike centroid |
| 3 | `log1p_price` | how expensive it is | catalog `price` |
| 4 | `price_fit` | how close to *their* usual price band | vs. median price of their right-swipes |
| 5 | `category_match` | is it a category they've said yes to | 0 / 1 |
| 6 | `brand_match` | is it a merchant they've said yes to | 0 / 1 |
| 7 | `log1p_social` | how popular catalog-wide | `likes` |
| 8 | `has_gallery` | multi-image listing | a committed retailer page |
| 9 | `has_story` | maker/provenance text present | 0 / 1 |
| 10 | `is_retailer` | real store feed vs. scraped Pinterest pin | 0 / 1 |

**Features 1, 2, 4, 5, 6 are personal** — they differ per recipient.
**Features 3, 7, 8, 9, 10 are properties of the gift** — identical for everyone.

That split matters, and §4 shows why.

### The taste centroid (features 1 & 2)

Every product has a **1024-number Titan embedding** — a coordinate in a space
where visually and semantically similar things sit near each other.

- Average the embeddings of everything Sarah swiped **right** → her **taste centroid**
- Average everything she swiped **left** → her **dislike centroid**
- Feature 1 = closeness to the first. Feature 2 = closeness to the second.

This is why the deck improves *as she swipes*: after five cards both centroids
exist and sharpen with every decision.

### Guarding against cheating

Each training example's profile is built **only from that person's earlier
swipes**. Using their whole history would leak the answer into the features and
produce an offline score that means nothing in production.

---

## 4. What it learned — the actual weights

From the SageMaker job (`report.json`). Standardized, so they're comparable:

| Feature | Weight | Reading |
|---|---:|---|
| `is_retailer` | **+0.59** | real retailer listings get swiped right far more |
| `cos_user_item_neg` | **−0.52** | resembling past left-swipes strongly predicts a left-swipe |
| `log1p_social` | **+0.44** | popular things do better |
| `has_gallery` | **+0.35** | multi-image listings do better |
| `price_fit` | +0.29 | matching their price band helps |
| `has_story` | −0.27 | maker stories slightly *hurt* — worth investigating |
| `log1p_price` | +0.21 | mildly prefers pricier |
| `category_match` | −0.16 | category history barely matters, slightly negative |
| **`cos_user_item`** | **+0.16** | **personal taste is the second-weakest signal** |
| `brand_match` | +0.14 | brand history barely matters |

### The finding that matters

**The two strongest signals — `is_retailer` and `log1p_social` — are not about
the person at all.** They're catalog quality and popularity.

Right now the model is mostly learning *"show good products"*, not *"show
products **this** person likes."* With 70 positive labels from 19 people, there
isn't enough evidence to learn individual taste, so it falls back on what's
generally good.

Two things follow:

1. **Better catalog may beat a better ranker.** `is_retailer` being the top
   weight says sourcing more real retailer products moves the metric more than
   any model change.
2. **The dislike signal is real and under-used.** `cos_user_item_neg` at −0.52
   is the strongest *personal* feature — and it's currently computed only
   on-device. The server never sees it.

---

## 5. Is it any good? No — and that's measured

| Ranker | AUC | What it is |
|---|---:|---|
| random | 0.42 | coin flip |
| **cosine only** | **0.535** | what production serves today, free |
| logistic regression | 0.569 | this model |
| linear regression | 0.5685 | control (§6) |

**AUC** = pick one gift they liked and one they didn't; how often does the model
score the liked one higher? 0.5 is chance, 1.0 is perfect.

The lift over cosine is **+0.034**. But:

```
bootstrap 95% CI:  [-0.073, +0.147]
P(model is better): 0.76
```

**The interval includes zero.** At this sample size the model and plain cosine
are indistinguishable, and there's a ~24% chance the model is *worse*.

`report.json` records `"ship": false`.

---

## 6. The linear-regression control

Ordinary least squares on the identical ten features:

```
logistic regression   AUC 0.5690
linear regression     AUC 0.5685      ← 0.0005 apart
```

Linear regression is the *wrong* tool for a 0/1 target — it predicts unbounded
values. It was run as a control, and the result is informative:

**Swapping the algorithm changes nothing.** The bottleneck is not the model
family, the architecture, or the optimiser. It is **labels**. Nobody should
reach for a bigger model until there are far more of them.

---

## 7. Where it runs

| Thing | Where |
|---|---|
| Training code | `infra/ml/swipe_model.py`, `train_swipe.py`, `sm_entry.py` |
| Launch a run | `infra/ml/launch_training_job.sh` (AWS CLI, ~$0.005, ~2 min) |
| Training job | `giftmaxxing-swipe-<stamp>` |
| Model artifact | `s3://giftmaxxing-dev-ml/models/swipe-lr/model.tar.gz` |
| Inference code | `infra/ml/swipe_inference.py` |
| **Endpoint** | **`giftmaxxing-swipe-lr`** — serverless, scales to **zero** |

Serverless matters: an idle endpoint costs **nothing**. Right for a model that
isn't yet load-bearing.

### Calling it

```json
POST /endpoints/giftmaxxing-swipe-lr/invocations
{
  "user":  {"pos_vector": [...1024], "neg_vector": [...1024],
            "median_price": 45, "categories": ["home"], "brands": ["etsy.com"]},
  "items": [{"postId": "p1", "vector": [...1024], "price": 48,
             "category": "home", "merchant": "etsy.com", "likes": 40,
             "has_gallery": true, "has_story": true, "is_retailer": true}]
}
→ {"ranked": [{"postId": "p1", "score": 0.78, "rank": 0}], "model": "swipe-lr-v1"}
```

**Features are computed inside the endpoint**, not by the caller. The container
carries `swipe_model.py`, so serving uses the exact function training used —
the standard way a model silently rots is the caller reimplementing the
features slightly differently.

---

## 8. Not yet wired: favourite colour

The endpoint **accepts** `favorite_color` and ignores it. The app doesn't
collect it yet.

Making it real needs three things:

1. capture it — onboarding and the swipe-challenge intro
2. a colour-match feature — the catalog has `grad`/dominant colour, and Titan
   embeddings already encode colour implicitly
3. retrain

Accepting the field now keeps the wire format stable, so adding it later is a
model change rather than an API change.

---

## 9. Honest summary

- The algorithm is **logistic regression**: 10 features, 11 numbers, 1 KB.
- It is **trained, versioned and deployed** on SageMaker.
- It is **not better than cosine** yet, and that is measured, not assumed.
- The blocker is **labels, not the model** — proven by the linear-regression
  control landing within 0.0005.
- Every completed swipe deck adds ~14 labels. We have ~70 positives; the rough
  bar for a learned ranker to beat cosine is 10³.
- The most actionable finding isn't about ML at all: **`is_retailer` is the
  strongest weight**, so improving the catalog likely beats improving the
  ranker.
