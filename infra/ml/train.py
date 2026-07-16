#!/usr/bin/env python3
"""Train the MTL value model. Runs identically three ways:

  local:      .venv/bin/python train.py --data data --out model
  notebook:   %run train.py --data data --out model
  SageMaker:  PyTorch Estimator entry_point (reads SM_CHANNEL_TRAIN/SM_MODEL_DIR)

Small-data regime notes:
  - Per-head BCEWithLogits with pos_weight = neg/pos (clamped at 50) so the
    ~3%-positive dwell head learns; heads whose TRAIN split has zero positives
    are masked out of the loss entirely (they output an uninformative prior
    until instrumentation accrues labels — expected for custom/buy today).
  - Early stopping on mean validation AUC over heads that have val positives.
"""
import argparse
import json
import os

import numpy as np
import torch
import torch.nn as nn
from sklearn.metrics import roc_auc_score

from mtl_model import MTLNet, TASKS, save_model


def load_split(path):
    d = np.load(path, allow_pickle=True)
    n = len(d["Y"])
    # v1 datasets predate context features -> zero ctx keeps them loadable.
    ctx = d["X_ctx"] if "X_ctx" in d else np.zeros((n, 20), dtype=np.float32)
    return (torch.from_numpy(d["X_item"]), torch.from_numpy(d["X_user"]),
            torch.from_numpy(d["X_aux"]), torch.from_numpy(ctx), torch.from_numpy(d["Y"]))


def aucs(model, xi, xu, xa, xc, y):
    with torch.no_grad():
        p = model.probs(xi, xu, xa, xc)
    out = {}
    for k, t in enumerate(TASKS):
        yt = y[:, k].numpy()
        if 0 < yt.sum() < len(yt):
            out[t] = float(roc_auc_score(yt, p[t].numpy()))
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--data", default=os.environ.get("SM_CHANNEL_TRAIN", "data"))
    ap.add_argument("--out", default=os.environ.get("SM_MODEL_DIR", "model"))
    ap.add_argument("--epochs", type=int, default=200)
    ap.add_argument("--lr", type=float, default=1e-3)
    ap.add_argument("--weight-decay", type=float, default=1e-4)
    ap.add_argument("--batch", type=int, default=256)
    ap.add_argument("--dropout", type=float, default=0.3)
    ap.add_argument("--patience", type=int, default=20)
    ap.add_argument("--seed", type=int, default=7)
    args = ap.parse_args()
    torch.manual_seed(args.seed)

    xi, xu, xa, xc, y = load_split(os.path.join(args.data, "train.npz"))
    vxi, vxu, vxa, vxc, vy = load_split(os.path.join(args.data, "val.npz"))
    model = MTLNet(dim=xi.shape[1], aux_dim=xa.shape[1], ctx_dim=xc.shape[1], dropout=args.dropout)

    # per-head pos_weight; mask heads with no train positives
    losses, active = {}, []
    for k, t in enumerate(TASKS):
        pos = float(y[:, k].sum())
        if pos == 0:
            print(f"head '{t}': 0 train positives — masked out of the loss")
            continue
        w = min((len(y) - pos) / pos, 50.0)
        losses[t] = nn.BCEWithLogitsLoss(pos_weight=torch.tensor(w))
        active.append((k, t))
        print(f"head '{t}': {int(pos)} positives, pos_weight={w:.1f}")

    opt = torch.optim.Adam(model.parameters(), lr=args.lr, weight_decay=args.weight_decay)
    best, best_state, stale = -1.0, None, 0
    n = len(y)
    for epoch in range(args.epochs):
        model.train()
        perm = torch.randperm(n)
        total = 0.0
        for i in range(0, n, args.batch):
            idx = perm[i : i + args.batch]
            logits = model(xi[idx], xu[idx], xa[idx], xc[idx])
            loss = sum(losses[t](logits[t], y[idx, k]) for k, t in active) / len(active)
            opt.zero_grad(); loss.backward(); opt.step()
            total += float(loss) * len(idx)
        model.eval()
        va = aucs(model, vxi, vxu, vxa, vxc, vy)
        # Early-stop only on heads that are actually being trained — an
        # unmasked-but-untrained head's val AUC is noise and must not steer.
        steer = [v for t, v in va.items() if t in {t2 for _, t2 in active}]
        mean_auc = float(np.mean(steer)) if steer else -total  # no val positives: fall back to train loss
        if mean_auc > best:
            best, stale = mean_auc, 0
            best_state = {k: v.clone() for k, v in model.state_dict().items()}
        else:
            stale += 1
        if epoch % 10 == 0 or stale == 0:
            print(f"epoch {epoch:3d} loss {total / n:.4f} val_auc {va} mean {mean_auc:.4f}")
        if stale >= args.patience:
            print(f"early stop at epoch {epoch} (best mean val AUC {best:.4f})")
            break

    if best_state:
        model.load_state_dict(best_state)
    save_model(model, args.out)
    snap = os.path.join(args.data, "knowledge_snapshot.json")
    if os.path.exists(snap):
        import shutil
        shutil.copy(snap, os.path.join(args.out, "knowledge_snapshot.json"))
    final = {"val_auc": aucs(model, vxi, vxu, vxa, vxc, vy), "train_auc": aucs(model, xi, xu, xa, xc, y),
             "active_heads": [t for _, t in active]}
    with open(os.path.join(args.out, "metrics.json"), "w") as f:
        json.dump(final, f, indent=2)
    print("final:", json.dumps(final))


if __name__ == "__main__":
    main()
