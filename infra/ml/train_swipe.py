"""Train the 10-feature swipe model and check it against honest baselines.

The question is never "does it train" — logistic regression always trains. It is
"does it beat cosine similarity, which is what production already does for free?"
If it does not, we ship cosine and say so.

Evaluation is GROUP-SPLIT BY USER. A random split would put the same swiper on
both sides and score the model on memorising one person's taste. With 19
swipers, leave-one-user-out is both the most honest option and cheap.

Usage:
    python3 train_swipe.py --data data/swipes.npz --out model/swipe_lr.json
"""
from __future__ import annotations

import argparse
import json
import numpy as np

from swipe_model import LogisticSwipeModel, FEATURE_NAMES, auc


def loocv(X, Y, groups, l2=1.0):
    """Leave-one-USER-out. Returns pooled out-of-fold predictions so a single
    AUC can be computed over every held-out decision."""
    users = sorted(set(groups))
    oof = np.full(len(Y), np.nan)
    for u in users:
        te = groups == u
        tr = ~te
        # A fold is only informative if training saw both classes.
        if Y[tr].sum() == 0 or Y[tr].sum() == tr.sum():
            continue
        m = LogisticSwipeModel(l2=l2).fit(X[tr], Y[tr])
        oof[te] = m.predict_proba(X[te])
    return oof


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--data", default="data/swipes.npz")
    ap.add_argument("--out", default="model/swipe_lr.json")
    args = ap.parse_args()

    d = np.load(args.data, allow_pickle=True)
    X, Y, groups = d["X"], d["Y"], d["groups"]
    print(f"{len(Y)} examples · {int(Y.sum())} positive ({Y.mean()*100:.1f}%) "
          f"· {len(set(groups))} users\n")

    # ---- Baselines the model has to beat -------------------------------------
    # cos_user_item alone IS production today: rank by similarity to the taste
    # centroid. If the model cannot beat this, it is not worth deploying.
    i_cos = FEATURE_NAMES.index("cos_user_item")
    base_cos = auc(Y, X[:, i_cos])
    rng = np.random.default_rng(0)
    base_rand = auc(Y, rng.random(len(Y)))

    oof = loocv(X, Y, groups)
    ok = ~np.isnan(oof)
    model_auc = auc(Y[ok], oof[ok])

    print("AUC (higher is better; 0.5 = coin flip)")
    print(f"  random                      {base_rand:.3f}")
    print(f"  cosine only  (production)   {base_cos:.3f}")
    print(f"  logistic, leave-one-user-out {model_auc:.3f}   "
          f"[{int(ok.sum())} held-out decisions]")
    delta = model_auc - base_cos
    print(f"\n  lift over production: {delta:+.3f}")
    if not (delta > 0.02):
        print("  -> NOT a clear win. Do not ship this over cosine yet.")
    else:
        print("  -> beats cosine on held-out users.")

    # ---- Fit on everything for inspection + export ---------------------------
    final = LogisticSwipeModel(l2=1.0).fit(X, Y)
    w = final.weights()
    print("\nstandardized weights (sign = direction, magnitude = influence)")
    for k, v in sorted(w.items(), key=lambda kv: -abs(kv[1])):
        bar = "#" * int(min(abs(v), 2.0) * 15)
        print(f"  {k:20} {v:+.3f}  {bar}")

    import os
    os.makedirs(os.path.dirname(args.out) or ".", exist_ok=True)
    with open(args.out, "w") as f:
        f.write(final.to_json())
    print(f"\nwrote {args.out}")

    report = {
        "n": int(len(Y)), "positives": int(Y.sum()), "users": int(len(set(groups))),
        "auc_random": None if np.isnan(base_rand) else round(base_rand, 4),
        "auc_cosine_baseline": None if np.isnan(base_cos) else round(base_cos, 4),
        "auc_model_loucv": None if np.isnan(model_auc) else round(model_auc, 4),
        "lift_over_cosine": None if np.isnan(delta) else round(delta, 4),
        "weights": w,
    }
    with open(os.path.splitext(args.out)[0] + "_report.json", "w") as f:
        json.dump(report, f, indent=2)
    return report


if __name__ == "__main__":
    main()
