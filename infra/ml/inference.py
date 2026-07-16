"""SageMaker inference handlers for the MTL value model (v2).

Deployed on a SERVERLESS endpoint (scales to zero — matches CLOUD.md's cost
posture) with the PyTorch inference container; this file + mtl_model.py +
features.py + knowledge_snapshot.json ride in the model.tar.gz bundle.

Training/inference separation: the request carries RAW context; all
featurization happens in features.py — the same module the training export
used — so features can never skew between the two sides.

Request (application/json), sent by the /recommendations Lambda:
  {
    "user":        [1024 floats],   — taste centroid (unit-norm or raw)
    "user_events": 123,             — user's total event count (optional)
    "context": {                    — all optional
      "ts": 1760000000000,          — epoch ms of the request
      "relationship": "wife",       — giver's relationship to the recipient
      "occasion": "birthday",
      "recipient": "mom"            — knowledge-recipient key for Reddit weights
    },
    "items": [
      {"key": "pin-1", "vector": [1024f], "price": 42.5,
       "source": "shopify", "title": "Espresso maker"},
      ...
    ]
  }

Response:
  {"items": [{"key", "p_time", "p_custom", "p_buy", "score"}, ...]}
  where score = 2·p_time + 5·p_custom + 1·p_buy (VALUE_WEIGHTS).
"""
import json

import numpy as np
import torch

from features import KnowledgeFeatures, build_context
from mtl_model import TASKS, build_aux, load_model, value_score


def model_fn(model_dir):
    model = load_model(model_dir)
    model.knowledge = KnowledgeFeatures.load(model_dir)
    return model


def input_fn(request_body, content_type="application/json"):
    if content_type != "application/json":
        raise ValueError(f"unsupported content type {content_type}")
    return json.loads(request_body)


def predict_fn(payload, model):
    items = payload.get("items") or []
    if not items:
        return {"items": []}
    dim = model.config["dim"]
    user = np.asarray(payload.get("user") or [], dtype=np.float32)
    if user.size != dim:
        user = np.zeros(dim, dtype=np.float32)
    else:
        n = np.linalg.norm(user)
        user = user / n if n > 0 else user
    user_events = payload.get("user_events") or 0
    ctx = payload.get("context") or {}
    knowledge = getattr(model, "knowledge", None)

    x_item, x_aux, x_ctx = [], [], []
    for it in items:
        v = np.asarray(it.get("vector") or [], dtype=np.float32)
        if v.size != dim:
            v = np.zeros(dim, dtype=np.float32)
        n = np.linalg.norm(v)
        vn = v / n if n > 0 else v
        cos = float(np.dot(user, vn))
        x_item.append(vn)
        x_aux.append(build_aux(cos, it.get("price"), user_events, it.get("source") or "other"))
        x_ctx.append(build_context(
            ts_ms=ctx.get("ts"), relationship=ctx.get("relationship"),
            occasion=ctx.get("occasion"), title=it.get("title"),
            recipient=ctx.get("recipient"), knowledge=knowledge,
        ))

    xi = torch.from_numpy(np.stack(x_item))
    xu = torch.from_numpy(np.tile(user, (len(items), 1)))
    xa = torch.tensor(x_aux, dtype=torch.float32)
    xc = torch.tensor(x_ctx, dtype=torch.float32)
    with torch.no_grad():
        p = model.probs(xi, xu, xa, xc)
    score = value_score(p)

    return {"items": [
        {"key": it.get("key"),
         **{f"p_{t}": round(float(p[t][i]), 5) for t in TASKS},
         "score": round(float(score[i]), 5)}
        for i, it in enumerate(items)
    ]}


def output_fn(prediction, accept="application/json"):
    return json.dumps(prediction), accept
