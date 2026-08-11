"""Swipe-preference model: 10 interpretable features, logistic regression.

WHY THIS EXISTS
---------------
The MTL net (mtl_model.py) has ~2,096 parameters in its item tower alone and
63 positive training examples — roughly 30x more parameters than signal. Two of
its three heads have 2 and 3 positives and are masked. It cannot learn.

Meanwhile the cleanest labels in the product go unused: people swiping decks
make *deliberate, per-item* yes/no judgements. Challenge responses and in-app
swipes together give an order of magnitude better label density than the
"dwelled 60 seconds" proxy the MTL model was built around.

So this module does the opposite of the MTL model on purpose:
  • ONE task (will this person swipe right?) instead of three
  • TEN hand-checkable features instead of a 2,068-d input
  • logistic regression instead of a 3-layer net

Ten weights can be fit from a few hundred labels. Two million cannot. And every
weight is readable, so a wrong one is visible rather than buried.

Reuses the same Titan vectors and the same taste-centroid maths as the serving
path, so a feature computed here means what it means in production.
"""
from __future__ import annotations

import json
import numpy as np

# Order is the contract: serving code must build the vector the same way.
FEATURE_NAMES = [
    "cos_user_item",      # cosine(taste centroid, item) — the core relevance signal
    "cos_user_item_neg",  # cosine(DISLIKE centroid, item) — what they swiped away from
    "log1p_price",        # absolute price, damped
    "price_fit",          # closeness to what this user actually engages with
    "category_match",     # item category is one the user has said yes to
    "brand_match",        # same for merchant/brand
    "log1p_social",       # catalog-wide likes, damped
    "has_gallery",        # multi-image listing (a committed retailer page)
    "has_story",          # maker/provenance text present
    "is_retailer",        # real store feed vs a scraped pin
]
N_FEATURES = len(FEATURE_NAMES)


def _cos(a, b):
    if a is None or b is None:
        return 0.0
    na, nb = np.linalg.norm(a), np.linalg.norm(b)
    if na == 0 or nb == 0:
        return 0.0
    return float(np.dot(a, b) / (na * nb))


def build_features(item_vec, meta, user):
    """One (user, item) pair -> a 10-d float32 row.

    `user` carries the centroids and preference tallies built by
    `UserProfile.from_labels` — never the label itself, so this is safe to call
    at serving time with exactly the same code path.
    """
    price = float(meta.get("price") or 0.0)
    cat = (meta.get("category") or "").lower()
    brand = (meta.get("merchant") or meta.get("domain") or "").lower()

    # Price fit: how close is this to the price band the user actually engages
    # with? Falls back to neutral (0.5) before we know their band.
    if user.median_price and price > 0:
        ratio = price / user.median_price
        price_fit = float(np.exp(-abs(np.log(ratio))))  # 1.0 at parity, decays both ways
    else:
        price_fit = 0.5

    return np.array([
        _cos(item_vec, user.pos_centroid),
        _cos(item_vec, user.neg_centroid),
        np.log1p(price),
        price_fit,
        1.0 if cat and cat in user.liked_categories else 0.0,
        1.0 if brand and brand in user.liked_brands else 0.0,
        np.log1p(float(meta.get("likes") or 0.0)),
        1.0 if meta.get("has_gallery") else 0.0,
        1.0 if meta.get("has_story") else 0.0,
        1.0 if meta.get("is_retailer") else 0.0,
    ], dtype=np.float32)


class UserProfile:
    """Taste state for one user, built ONLY from labels strictly before the
    example being scored. Building it from all of a user's history would leak
    the answer into the features and produce a model that looks excellent
    offline and does nothing in production.
    """

    def __init__(self):
        self.pos_centroid = None
        self.neg_centroid = None
        self.liked_categories = set()
        self.liked_brands = set()
        self.median_price = None

    @classmethod
    def from_labels(cls, labels, vectors, metas):
        """labels: [(post_id, y)] in chronological order, already truncated to
        what happened BEFORE the target example."""
        p = cls()
        pos, neg, prices = [], [], []
        for post_id, y in labels:
            entry = vectors.get(post_id)
            meta = metas.get(post_id, {})
            if entry is not None:
                (pos if y else neg).append(entry)
            if y:
                if meta.get("category"):
                    p.liked_categories.add(str(meta["category"]).lower())
                b = meta.get("merchant") or meta.get("domain")
                if b:
                    p.liked_brands.add(str(b).lower())
                if meta.get("price"):
                    prices.append(float(meta["price"]))
        if pos:
            p.pos_centroid = np.mean(np.stack(pos), axis=0)
        if neg:
            p.neg_centroid = np.mean(np.stack(neg), axis=0)
        if prices:
            p.median_price = float(np.median(prices))
        return p


class LogisticSwipeModel:
    """Plain logistic regression, gradient descent, L2. No sklearn so the
    notebook, the exporter and any future Lambda share one implementation with
    no dependency to install."""

    def __init__(self, l2=1.0, lr=0.1, epochs=2000, seed=0):
        self.l2, self.lr, self.epochs, self.seed = l2, lr, epochs, seed
        self.w = None
        self.b = 0.0
        self.mu = None
        self.sd = None

    def _standardize(self, X, fit=False):
        if fit:
            self.mu = X.mean(axis=0)
            self.sd = X.std(axis=0)
            self.sd[self.sd < 1e-6] = 1.0
        return (X - self.mu) / self.sd

    def fit(self, X, y, sample_weight=None):
        rng = np.random.default_rng(self.seed)
        Xs = self._standardize(np.asarray(X, dtype=np.float64), fit=True)
        y = np.asarray(y, dtype=np.float64)
        n, d = Xs.shape
        sw = np.ones(n) if sample_weight is None else np.asarray(sample_weight, dtype=np.float64)
        sw = sw / sw.mean()
        self.w = rng.normal(0, 0.01, d)
        self.b = 0.0
        for _ in range(self.epochs):
            z = Xs @ self.w + self.b
            p = 1.0 / (1.0 + np.exp(-np.clip(z, -30, 30)))
            err = (p - y) * sw
            self.w -= self.lr * ((Xs.T @ err) / n + self.l2 * self.w / n)
            self.b -= self.lr * err.mean()
        return self

    def predict_proba(self, X):
        Xs = self._standardize(np.asarray(X, dtype=np.float64))
        z = Xs @ self.w + self.b
        return 1.0 / (1.0 + np.exp(-np.clip(z, -30, 30)))

    def weights(self):
        """Standardized coefficients — directly comparable across features."""
        return dict(zip(FEATURE_NAMES, np.round(self.w, 4).tolist()))

    def to_json(self):
        return json.dumps({
            "features": FEATURE_NAMES,
            "w": self.w.tolist(),
            "b": float(self.b),
            "mu": self.mu.tolist(),
            "sd": self.sd.tolist(),
        }, indent=2)

    @classmethod
    def from_json(cls, text):
        d = json.loads(text)
        m = cls()
        m.w = np.array(d["w"])
        m.b = d["b"]
        m.mu = np.array(d["mu"])
        m.sd = np.array(d["sd"])
        return m


class PairwiseSwipeModel:
    """Learning-to-rank on WITHIN-DECK pairs (RankNet-style).

    The pointwise model asks "will they swipe right on this?". That is not the
    question the deck poses — the question is "should this be card 1 or card 9?".
    Optimising the wrong objective is why 70 labels bought so little.

    Within one person's deck, every right-swipe should rank above every
    left-swipe. That yields ~3,400 ordering constraints from the same 425
    swipes — roughly 48x the pointwise label count, with no new data.

    The trick is that a pairwise logistic model is just ordinary logistic
    regression on FEATURE DIFFERENCES with an all-positive target:

        P(i beats j) = sigmoid(w · (x_i - x_j))

    so the learned w is directly comparable to the pointwise weights, and the
    same predict_proba() ranks a deck at serving time. No new serving code.

    Pairs are CAPPED PER USER. One swiper currently generates 2,224 of the
    3,398 available pairs; uncapped, the model would simply learn that person.
    """

    def __init__(self, l2=1.0, lr=0.5, epochs=3000, max_pairs_per_user=50, seed=0):
        # 50 is measured, not guessed. Sweeping the cap: 50 -> AUC 0.5965,
        # 300 -> 0.5765, uncapped (3,398 pairs) -> 0.5742. MORE pairs is WORSE,
        # because one swiper owns 2,224 of them and the model just learns that
        # person. What helps is per-user BALANCE, not pair volume — the same
        # lesson as the MTL set, where one user was 24% of the rows.
        self.l2, self.lr, self.epochs = l2, lr, epochs
        self.max_pairs_per_user, self.seed = max_pairs_per_user, seed
        self.w = None
        self.b = 0.0          # kept at 0: a constant cannot change an ordering
        self.mu = None
        self.sd = None

    def _standardize(self, X, fit=False):
        if fit:
            self.mu = X.mean(axis=0)
            self.sd = X.std(axis=0)
            self.sd[self.sd < 1e-6] = 1.0
        return (X - self.mu) / self.sd

    def _pairs(self, Xs, y, groups, sample_weight=None):
        rng = np.random.default_rng(self.seed)
        diffs, weights = [], []
        sample_weight = np.ones(len(y)) if sample_weight is None else np.asarray(sample_weight)
        for u in np.unique(groups):
            m = groups == u
            pos = np.where(m & (y == 1))[0]
            neg = np.where(m & (y == 0))[0]
            if not len(pos) or not len(neg):
                continue
            grid = [(i, j) for i in pos for j in neg]
            if len(grid) > self.max_pairs_per_user:
                sel = rng.choice(len(grid), self.max_pairs_per_user, replace=False)
                grid = [grid[k] for k in sel]
            for i, j in grid:
                diffs.append(Xs[i] - Xs[j])
                weights.append(np.sqrt(sample_weight[i] * sample_weight[j]))
        return np.asarray(diffs, dtype=np.float64), np.asarray(weights, dtype=np.float64)

    def fit(self, X, y, groups=None, sample_weight=None):
        if groups is None:
            raise ValueError("pairwise training needs `groups` (one deck/user per group)")
        Xs = self._standardize(np.asarray(X, dtype=np.float64), fit=True)
        D, pair_weight = self._pairs(Xs, np.asarray(y), np.asarray(groups), sample_weight)
        self.n_pairs = len(D)
        if not len(D):
            self.w = np.zeros(Xs.shape[1])
            return self
        rng = np.random.default_rng(self.seed)
        self.w = rng.normal(0, 0.01, Xs.shape[1])
        # Target is 1 for every pair by construction, so the loss reduces to
        # -log sigmoid(w·d) — gradient is simply (p-1)·d.
        for _ in range(self.epochs):
            z = D @ self.w
            p = 1.0 / (1.0 + np.exp(-np.clip(z, -30, 30)))
            pair_weight = pair_weight / max(pair_weight.mean(), 1e-9)
            self.w -= self.lr * ((D.T @ ((p - 1.0) * pair_weight)) / len(D) + self.l2 * self.w / len(D))
        return self

    def predict_proba(self, X):
        Xs = self._standardize(np.asarray(X, dtype=np.float64))
        z = Xs @ self.w
        return 1.0 / (1.0 + np.exp(-np.clip(z, -30, 30)))

    def weights(self):
        return dict(zip(FEATURE_NAMES, np.round(self.w, 4).tolist()))

    def to_json(self):
        return json.dumps({
            "features": FEATURE_NAMES, "w": self.w.tolist(), "b": 0.0,
            "mu": self.mu.tolist(), "sd": self.sd.tolist(), "objective": "pairwise",
        }, indent=2)


class LinearSwipeModel:
    """Ordinary least squares on the same ten features.

    Included as a control, not a candidate. Linear regression is the wrong tool
    for a 0/1 target — it predicts unbounded values where only [0,1] is
    meaningful, and it optimises squared error when we care about ranking. But
    for RANKING, only the order of the scores matters, and OLS and logistic
    regression often produce near-identical orderings. If they do here, that is
    evidence the choice of model is not what is holding us back — the labels
    are. That is worth knowing before anyone reaches for a bigger model.

    Closed-form solve, so there is nothing to tune and no chance of blaming a
    bad result on optimisation.
    """

    def __init__(self, l2=1.0):
        self.l2 = l2
        self.w = None
        self.b = 0.0
        self.mu = None
        self.sd = None

    def _standardize(self, X, fit=False):
        if fit:
            self.mu = X.mean(axis=0)
            self.sd = X.std(axis=0)
            self.sd[self.sd < 1e-6] = 1.0
        return (X - self.mu) / self.sd

    def fit(self, X, y):
        Xs = self._standardize(np.asarray(X, dtype=np.float64), fit=True)
        y = np.asarray(y, dtype=np.float64)
        n, d = Xs.shape
        # Ridge closed form; the intercept is the mean since features are centred.
        A = Xs.T @ Xs + self.l2 * np.eye(d)
        self.w = np.linalg.solve(A, Xs.T @ (y - y.mean()))
        self.b = float(y.mean())
        return self

    def predict_proba(self, X):
        """Not a probability — an unbounded score. Named to match
        LogisticSwipeModel so evaluation code can treat them interchangeably,
        which is exactly the point of the comparison."""
        Xs = self._standardize(np.asarray(X, dtype=np.float64))
        return Xs @ self.w + self.b

    def weights(self):
        return dict(zip(FEATURE_NAMES, np.round(self.w, 4).tolist()))


def auc(y_true, scores):
    """Rank-based AUC. Returns nan when a class is absent — which is honest,
    and happens often at our data volume."""
    y = np.asarray(y_true)
    s = np.asarray(scores)
    pos, neg = s[y == 1], s[y == 0]
    if len(pos) == 0 or len(neg) == 0:
        return float("nan")
    order = np.argsort(s)
    ranks = np.empty_like(order, dtype=float)
    ranks[order] = np.arange(1, len(s) + 1)
    return float((ranks[y == 1].sum() - len(pos) * (len(pos) + 1) / 2) / (len(pos) * len(neg)))
