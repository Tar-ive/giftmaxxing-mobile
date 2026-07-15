"""SageMaker inference handlers for the MTL value model.

Deployed on a SERVERLESS endpoint (scales to zero — matches CLOUD.md's cost
posture) with the PyTorch inference container; this file + mtl_model.py ride
in the model.tar.gz source bundle.

Request (application/json), sent by the /recommendations Lambda:
  {
    "user":        [1024 floats]   — taste centroid (unit-norm or raw),
    "user_events": 123,            — user's total event count (optional)
    "items": [
      {"key": "pin-1", "vector": [1024f], "price": 42.5, "source": "shopify"},
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

from mtl_model import TASKS, build_aux, load_model, value_score


def model_fn(model_dir):
    return load_model(model_dir)


def input_fn(request_body, content_type="application/json"):
    if content_type != "application/json":
        raise ValueError(f"unsupported content type {content_type}")
    return json.loads(request_body)


def predict_fn(payload, model):
    items = payload.get("items") or []
    if not items:
        return {"items": []}
    user = np.asarray(payload.get("user") or [], dtype=np.float32)
    dim = model.config["dim"]
    if user.size != dim:
        user = np.zeros(dim, dtype=np.float32)
    else:
        n = np.linalg.norm(user)
        user = user / n if n > 0 else user
    user_events = payload.get("user_events") or 0

    x_item, x_aux = [], []
    for it in items:
        v = np.asarray(it.get("vector") or [], dtype=np.float32)
        if v.size != dim:
            v = np.zeros(dim, dtype=np.float32)
        n = np.linalg.norm(v)
        vn = v / n if n > 0 else v
        cos = float(np.dot(user, vn))
        x_item.append(vn)
        x_aux.append(build_aux(cos, it.get("price"), user_events, it.get("source") or "other"))

    xi = torch.from_numpy(np.stack(x_item))
    xu = torch.from_numpy(np.tile(user, (len(items), 1)))
    xa = torch.tensor(x_aux, dtype=torch.float32)
    with torch.no_grad():
        p = model.probs(xi, xu, xa)
    score = value_score(p)

    return {"items": [
        {"key": it.get("key"),
         **{f"p_{t}": round(float(p[t][i]), 5) for t in TASKS},
         "score": round(float(score[i]), 5)}
        for i, it in enumerate(items)
    ]}


def output_fn(prediction, accept="application/json"):
    return json.dumps(prediction), accept
