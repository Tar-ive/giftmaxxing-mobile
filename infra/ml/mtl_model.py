"""Shared-bottom multi-task network for the gift feed value model (v2).

Three heads predict concrete user actions on a (user, item) pair:
  P_Time   — user dwells > 60 s on the item
  P_Custom — user types a custom message for the gift (letter / why-note / comment)
  P_Buy    — buy intent (affiliate click / pledge / add to gift pool / checkout)

Feed sort order uses the value model:
  Score = 2·P_Time + 5·P_Custom + 1·P_Buy

v2 architecture (deep shared bottom + task-specific towers):

  item tower:  1024-d Titan Multimodal embedding -> Linear -> 96
  user tower:  1024-d taste centroid             -> Linear -> 96
  context:     CTX_DIM raw floats (time-of-day/day-of-week cyclical,
               relationship one-hot, occasion one-hot, Reddit idea weights —
               see features.py, the train/serve-shared featurizer)
  aux:         cosine, price, activity, source one-hots

  shared bottom: [item96 | user96 | ctx | aux] -> 256 -> 128 -> 64
                 (3 hidden layers; common structure every task benefits from)
  heads: one small MLP PER TASK (64 -> 32 -> 1) — what drives typing a custom
         message differs from what drives a quick checkout, so each task gets
         its own tower to specialize in instead of a single linear readout.

The Titan embedding IS the multi-modal augmentation: it already fuses the
item's image + title into one vector, so the image-understanding pipeline
feeds the recommender through the item tower with no extra vision model.
"""
import json
import os

import numpy as np
import torch
import torch.nn as nn

TASKS = ["time", "custom", "buy"]
VALUE_WEIGHTS = {"time": 2.0, "custom": 5.0, "buy": 1.0}
SRC_ONEHOT = ["pinterest", "shopify", "catalog", "other"]
MODEL_VERSION = 2


class MTLNet(nn.Module):
    def __init__(self, dim=1024, aux_dim=7, ctx_dim=20, tower=96,
                 shared=(256, 128, 64), head_hidden=32, dropout=0.3, version=MODEL_VERSION):
        super().__init__()
        self.item_tower = nn.Sequential(nn.Linear(dim, tower), nn.ReLU())
        self.user_tower = nn.Sequential(nn.Linear(dim, tower), nn.ReLU())

        layers, width = [], tower * 2 + aux_dim + ctx_dim
        for h in shared:
            layers += [nn.Linear(width, h), nn.ReLU(), nn.Dropout(dropout)]
            width = h
        self.shared = nn.Sequential(*layers)

        self.heads = nn.ModuleDict({
            t: nn.Sequential(
                nn.Linear(width, head_hidden), nn.ReLU(), nn.Dropout(dropout),
                nn.Linear(head_hidden, 1),
            )
            for t in TASKS
        })
        self.config = {"dim": dim, "aux_dim": aux_dim, "ctx_dim": ctx_dim, "tower": tower,
                       "shared": list(shared), "head_hidden": head_hidden,
                       "dropout": dropout, "version": MODEL_VERSION}

    def forward(self, x_item, x_user, x_aux, x_ctx):
        z = self.shared(torch.cat(
            [self.item_tower(x_item), self.user_tower(x_user), x_aux, x_ctx], dim=-1))
        return {t: self.heads[t](z).squeeze(-1) for t in TASKS}  # logits

    def probs(self, x_item, x_user, x_aux, x_ctx):
        logits = self.forward(x_item, x_user, x_aux, x_ctx)
        return {t: torch.sigmoid(v) for t, v in logits.items()}


def value_score(p):
    """p: {task: tensor/array} -> Score = 2·P_Time + 5·P_Custom + 1·P_Buy."""
    return sum(VALUE_WEIGHTS[t] * p[t] for t in TASKS)


def build_aux(cos, price, user_events, source):
    """Mirror of export_training_data.py's aux features — keep in lockstep."""
    onehot = [1.0 if source == s else 0.0 for s in SRC_ONEHOT]
    return [float(cos), float(np.log1p(price or 0.0)), float(np.log1p(user_events or 0)), *onehot]


def save_model(model, out_dir):
    os.makedirs(out_dir, exist_ok=True)
    torch.save(model.state_dict(), os.path.join(out_dir, "model.pt"))
    with open(os.path.join(out_dir, "config.json"), "w") as f:
        json.dump(model.config, f)


def load_model(model_dir):
    with open(os.path.join(model_dir, "config.json")) as f:
        cfg = json.load(f)
    cfg.pop("version", None)
    model = MTLNet(**cfg)
    model.load_state_dict(torch.load(os.path.join(model_dir, "model.pt"),
                                     map_location="cpu", weights_only=True))
    model.eval()
    return model
