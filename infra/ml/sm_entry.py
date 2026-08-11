"""SageMaker script-mode entry point for the swipe model.

SageMaker's contract:
  input   $SM_CHANNEL_TRAINING   (S3 channel mounted read-only)
  output  $SM_MODEL_DIR          (tarred to S3 as model.tar.gz)

Everything of substance lives in swipe_model.py / train_swipe.py so the job and
the local run produce identical numbers — a training job that diverges from
what you validated locally is worse than no training job.

Launched by launch_training_job.sh (AWS CLI, no SDK).
"""
from __future__ import annotations

import json
import os
import numpy as np

from swipe_model import LogisticSwipeModel, LinearSwipeModel, PairwiseSwipeModel, FEATURE_NAMES, auc
from train_swipe import loocv

TRAIN_DIR = os.environ.get("SM_CHANNEL_TRAINING", "data")
MODEL_DIR = os.environ.get("SM_MODEL_DIR", "model")
OUTPUT_DIR = os.environ.get("SM_OUTPUT_DATA_DIR", MODEL_DIR)


def main():
    path = os.path.join(TRAIN_DIR, "swipes.npz")
    d = np.load(path, allow_pickle=True)
    X, Y, groups = d["X"], d["Y"], d["groups"]
    timestamps = d["timestamps"] if "timestamps" in d.files else np.zeros(len(Y))

    n, pos, users = len(Y), int(Y.sum()), len(set(groups))
    print(f"[data] {n} examples · {pos} positive ({pos/max(n, 1)*100:.1f}%) · {users} swipers")
    if n < 2 or pos == 0 or pos == n or users < 2:
        report = {
            "status": "completed_without_viable_candidate", "viable": False,
            "n": n, "positives": pos, "users": users,
            "excluded_heads": [{"head": "swipe_preference", "reason": "needs two classes and two users"}],
            "ship": False, "features": FEATURE_NAMES,
        }
        for target in {MODEL_DIR, OUTPUT_DIR}:
            os.makedirs(target, exist_ok=True)
            with open(os.path.join(target, "report.json"), "w") as f:
                json.dump(report, f, indent=2)
        print("[verdict] completed without a viable candidate; production unchanged")
        return

    latest = float(np.max(timestamps)) if np.any(timestamps) else 0.0
    age_days = np.maximum(0.0, latest - timestamps) / 86_400_000.0 if latest > 1e11 else np.maximum(0.0, latest - timestamps) / 86_400.0
    time_weight = np.power(0.5, age_days / 90.0)

    # --- Baseline: what production already serves, for free ------------------
    i_cos = FEATURE_NAMES.index("cos_user_item")
    base = auc(Y, X[:, i_cos])

    # --- Held-out evaluation, grouped by user --------------------------------
    oof = loocv(X, Y, groups)
    ok = ~np.isnan(oof)
    model_auc = auc(Y[ok], oof[ok])
    lift = model_auc - base

    def _ndcg10(scores):
        values = {}
        for user in sorted(set(groups)):
            mask = groups == user
            truth, ranked = Y[mask], np.asarray(scores)[mask]
            if truth.sum() == 0 or not np.all(np.isfinite(ranked)):
                continue
            order = np.argsort(-ranked)[:10]
            dcg = sum(float(truth[i]) / np.log2(rank + 2) for rank, i in enumerate(order))
            ideal = sum(1.0 / np.log2(rank + 2) for rank in range(min(10, int(truth.sum()))))
            values[str(user)] = dcg / ideal if ideal else 0.0
        return values

    # --- Class-weighted pointwise: with 16.5% positives the L2 penalty drags
    # coefficients toward the majority class; weighting lets positives push back.
    def _cw_loocv():
        oo = np.full(len(Y), np.nan)
        for u in sorted(set(groups)):
            te = groups == u; tr = ~te
            if Y[tr].sum() == 0 or Y[tr].sum() == tr.sum():
                continue
            yt = Y[tr]; p_ = yt.mean()
            sw = np.where(yt == 1, 1 / max(p_, 1e-6), 1 / max(1 - p_, 1e-6))
            oo[te] = LogisticSwipeModel(l2=1.0).fit(X[tr], yt, sample_weight=sw).predict_proba(X[te])
        return oo
    oof_cw = _cw_loocv(); ok_cw = ~np.isnan(oof_cw)
    cw_auc = auc(Y[ok_cw], oof_cw[ok_cw])
    print(f"auc_classweight={cw_auc:.4f};")

    # --- Pairwise learning-to-rank: the objective the deck actually poses.
    def _pw_loocv():
        oo = np.full(len(Y), np.nan)
        for u in sorted(set(groups)):
            te = groups == u; tr = ~te
            if Y[tr].sum() == 0 or Y[tr].sum() == tr.sum():
                continue
            oo[te] = PairwiseSwipeModel(l2=1.0).fit(X[tr], Y[tr], groups=groups[tr]).predict_proba(X[te])
        return oo
    oof_pw = _pw_loocv(); ok_pw = ~np.isnan(oof_pw)
    pw_auc = auc(Y[ok_pw], oof_pw[ok_pw])
    print(f"auc_pairwise={pw_auc:.4f};")

    # The best variant becomes the shipped artifact.
    oof, ok, model_auc = (oof_pw, ok_pw, pw_auc) if pw_auc >= max(cw_auc, model_auc) else (
        (oof_cw, ok_cw, cw_auc) if cw_auc >= model_auc else (oof, ok, model_auc))
    lift = model_auc - base
    model_by_user, base_by_user = _ndcg10(oof), _ndcg10(X[:, i_cos])
    common_users = sorted(set(model_by_user) & set(base_by_user))
    ndcg_model = np.asarray([model_by_user[user] for user in common_users])
    ndcg_base = np.asarray([base_by_user[user] for user in common_users])
    ndcg_lift_by_user = ndcg_model - ndcg_base
    ndcg10_model = float(ndcg_model.mean()) if len(ndcg_model) else float("nan")
    ndcg10_base = float(ndcg_base.mean()) if len(ndcg_base) else float("nan")
    ndcg10_lift = ndcg10_model - ndcg10_base

    # --- Control: ordinary least squares on the same features ----------------
    # Wrong tool for a 0/1 target, but for RANKING only the order matters. If
    # OLS matches logistic, the model family is not the constraint - the labels
    # are - and nobody should reach for a bigger model.
    oof_lin = loocv(X, Y, groups, model_cls=LinearSwipeModel)
    ok_lin = ~np.isnan(oof_lin)
    lin_auc = auc(Y[ok_lin], oof_lin[ok_lin])
    print(f"auc_linear={lin_auc:.4f};")

    # --- Is the lift distinguishable from zero at this sample size? ----------
    rng = np.random.default_rng(0)
    idx = np.where(ok)[0]
    deltas = []
    for _ in range(2000):
        b = rng.choice(idx, size=len(idx), replace=True)
        a1, a0 = auc(Y[b], oof[b]), auc(Y[b], X[b, i_cos])
        if not (np.isnan(a1) or np.isnan(a0)):
            deltas.append(a1 - a0)
    deltas = np.array(deltas)
    lo, hi = (np.percentile(deltas, [2.5, 97.5]) if len(deltas) else (float("nan"),) * 2)
    p_better = float((deltas > 0).mean()) if len(deltas) else float("nan")
    ndcg_boot = np.asarray([rng.choice(ndcg_lift_by_user, size=len(ndcg_lift_by_user), replace=True).mean() for _ in range(2000)]) if len(ndcg_lift_by_user) else np.asarray([])
    ndcg_lo, ndcg_hi = (np.percentile(ndcg_boot, [2.5, 97.5]) if len(ndcg_boot) else (float("nan"),) * 2)

    # SageMaker scrapes these from stdout into training-job metrics.
    print(f"auc_cosine={base:.4f};")
    print(f"auc_model={model_auc:.4f};")
    print(f"lift={lift:.4f};")
    print(f"ci_low={lo:.4f};")
    print(f"ci_high={hi:.4f};")
    print(f"p_better={p_better:.4f};")
    print(f"ndcg10_cosine={ndcg10_base:.4f};")
    print(f"ndcg10_model={ndcg10_model:.4f};")
    print(f"ndcg10_lift={ndcg10_lift:.4f};")
    print(f"ndcg10_ci_low={ndcg_lo:.4f};")
    print(f"ndcg10_ci_high={ndcg_hi:.4f};")

    ships = bool(ndcg_lo > 0)
    print(f"[control] linear regression AUC {lin_auc:.4f} "
          f"(vs logistic {model_auc:.4f}) - a match means the model family is not the constraint")
    print(f"[verdict] {'SHIP — CI excludes zero' if ships else 'DO NOT SHIP over cosine — CI includes zero'}")

    # --- Fit on everything and persist ---------------------------------------
    best = "pairwise" if model_auc == pw_auc else ("classweight" if model_auc == cw_auc else "pointwise")
    print(f"[best] {best}")
    if best == "pairwise":
        final = PairwiseSwipeModel(l2=1.0).fit(X, Y, groups=groups, sample_weight=time_weight)
    elif best == "classweight":
        p_ = Y.mean()
        final = LogisticSwipeModel(l2=1.0).fit(X, Y, sample_weight=time_weight * np.where(
            Y == 1, 1 / max(p_, 1e-6), 1 / max(1 - p_, 1e-6)))
    else:
        final = LogisticSwipeModel(l2=1.0).fit(X, Y, sample_weight=time_weight)
    os.makedirs(MODEL_DIR, exist_ok=True)
    with open(os.path.join(MODEL_DIR, "swipe_lr.json"), "w") as f:
        f.write(final.to_json())

    weights = final.weights()
    print("[weights]")
    for k, v in sorted(weights.items(), key=lambda kv: -abs(kv[1])):
        print(f"  {k:20} {v:+.4f}")

    report = {
        "status": "candidate_created", "viable": True,
        "n": n, "positives": pos, "users": users, "time_decay_half_life_days": 90,
        "auc_cosine_baseline": None if np.isnan(base) else round(float(base), 4),
        "auc_model_loucv": None if np.isnan(model_auc) else round(float(model_auc), 4),
        "lift": None if np.isnan(lift) else round(float(lift), 4),
        "auc_classweight": None if np.isnan(cw_auc) else round(float(cw_auc), 4),
        "auc_pairwise": None if np.isnan(pw_auc) else round(float(pw_auc), 4),
        "objective": best,
        "auc_linear_regression": None if np.isnan(lin_auc) else round(float(lin_auc), 4),
        "ci95": [None if np.isnan(lo) else round(float(lo), 4),
                 None if np.isnan(hi) else round(float(hi), 4)],
        "ndcg10_cosine_baseline": None if np.isnan(ndcg10_base) else round(ndcg10_base, 4),
        "ndcg10_model_loocv": None if np.isnan(ndcg10_model) else round(ndcg10_model, 4),
        "ndcg10_lift": None if np.isnan(ndcg10_lift) else round(ndcg10_lift, 4),
        "ndcg10_ci95": [None if np.isnan(ndcg_lo) else round(float(ndcg_lo), 4), None if np.isnan(ndcg_hi) else round(float(ndcg_hi), 4)],
        "p_lift_gt_0": None if np.isnan(p_better) else round(p_better, 4),
        "ship": ships,
        "weights": weights,
        "features": FEATURE_NAMES,
    }
    for target in {MODEL_DIR, OUTPUT_DIR}:
        os.makedirs(target, exist_ok=True)
        with open(os.path.join(target, "report.json"), "w") as f:
            json.dump(report, f, indent=2)
    print(f"[done] wrote swipe_lr.json + report.json")


if __name__ == "__main__":
    main()
