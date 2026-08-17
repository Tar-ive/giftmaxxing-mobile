"""SageMaker inference for the swipe-deck ranker.

WHAT THIS SERVES
----------------
Given a recipient and a pool of candidate gifts, return them ranked by how
likely that person is to swipe RIGHT.

The deck is the product surface where this matters most: a challenge deck is a
short, finite list shown to ONE person, and every card they swipe is immediate
feedback. So the endpoint is built to be called repeatedly within a session —
pass back the swipes so far and the ranking of the remaining cards improves as
the deck is worked through.

FEATURES ARE COMPUTED HERE, NOT BY THE CALLER
---------------------------------------------
The caller sends the recipient's state and raw item metadata; this container
builds the feature vector using the same swipe_model.build_features() the
training job used. Computing features in the caller would let training and
serving drift apart silently, which is the classic way a model that looked good
offline does nothing in production.

REQUEST
{
  "user": {
    "pos_vector": [1024 floats]   | null,   # taste centroid (right-swipes)
    "neg_vector": [1024 floats]   | null,   # what they swiped away from
    "median_price": 45.0          | null,
    "categories": ["home", ...],
    "brands": ["etsy.com", ...],
    "favorite_color": "sage"      | null    # reserved; see note below
  },
  "items": [
    {"postId": "...", "vector": [1024 floats], "price": 42, "category": "home",
     "merchant": "etsy.com", "likes": 12, "has_gallery": true,
     "has_story": false, "is_retailer": true}
  ]
}

RESPONSE
{"ranked": [{"postId": "...", "score": 0.63, "rank": 0}, ...],
 "model": "swipe-lr-v1", "n": 14}

NOTE ON favorite_color: accepted and echoed back but NOT yet a model feature —
the app does not collect it. Adding it means (a) capturing it in onboarding and
the challenge intro, (b) a colour-match feature, (c) retraining. Accepting the
field now keeps the wire format stable so that is a model change, not an API
change.
"""
from __future__ import annotations

import json
import os
import numpy as np

from swipe_model import LogisticSwipeModel, UserProfile, build_features, FEATURE_NAMES

CONTENT_TYPE = "application/json"


def model_fn(model_dir):
    with open(os.path.join(model_dir, "swipe_lr.json")) as f:
        return LogisticSwipeModel.from_json(f.read())


def input_fn(body, content_type=CONTENT_TYPE):
    if content_type != CONTENT_TYPE:
        raise ValueError(f"unsupported content type {content_type}")
    return json.loads(body)


def _profile(u):
    p = UserProfile()
    pv, nv = u.get("pos_vector"), u.get("neg_vector")
    p.pos_centroid = np.asarray(pv, dtype=np.float32) if pv else None
    p.neg_centroid = np.asarray(nv, dtype=np.float32) if nv else None
    p.median_price = u.get("median_price")
    p.liked_categories = {str(c).lower() for c in (u.get("categories") or [])}
    p.liked_brands = {str(b).lower() for b in (u.get("brands") or [])}
    return p


def predict_fn(payload, model):
    user = _profile(payload.get("user") or {})
    items = payload.get("items") or []
    scored = []
    for it in items:
        vec = it.get("vector")
        vec = np.asarray(vec, dtype=np.float32) if vec else None
        # A candidate with no embedding still gets ranked — on the non-vector
        # features alone — rather than being dropped. Dropping it would make
        # the deck silently shorter than the caller asked for.
        feats = build_features(vec, it, user)
        score = float(model.predict_proba(feats.reshape(1, -1))[0])
        scored.append((score, it.get("postId")))

    scored.sort(key=lambda t: -t[0])
    return {
        "ranked": [{"postId": pid, "score": round(s, 4), "rank": i}
                   for i, (s, pid) in enumerate(scored)],
        "model": "swipe-lr-v1",
        "features": FEATURE_NAMES,
        "n": len(scored),
    }


def output_fn(prediction, accept=CONTENT_TYPE):
    return json.dumps(prediction), CONTENT_TYPE
