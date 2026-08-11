"""Export swipe labels -> a training set for the 10-feature model.

Two label sources, both explicit per-item preference judgements:

  1. CHALLENGES  RESP rows -> `swipes: [{id, dir: yes|no, dwellMs}]`
     A friend swiping a deck the sender built for them. The cleanest signal in
     the product: deliberate, per-item, and from the person the gift is FOR.

  2. ANALYTICS   swipe_right / swipe_left events (postId + decisionTimeMs)
     The owner swiping their own deck. Same shape, larger volume.

Both beat the MTL model's "dwelled >= 60s" proxy, which yielded 63 positives
across the entire history.

Chronology matters: each example's features are built from a UserProfile
containing ONLY that user's earlier labels. Building profiles from all of a
user's history leaks the answer and produces an offline score that means
nothing.

Usage:
    export AWS_PROFILE=dev_sso_giftmaxxing
    python3 export_swipe_data.py --out data/swipes.npz
"""
from __future__ import annotations

import argparse
import json
import os
from collections import defaultdict

import boto3
import numpy as np

from swipe_model import UserProfile, build_features, FEATURE_NAMES

REGION = os.environ.get("AWS_REGION", "us-east-1")
PREFIX = os.environ.get("ENV_PREFIX", "giftmaxxing-dev")
VECTOR_BUCKET = os.environ.get("VECTOR_BUCKET", f"{PREFIX}-vectors")
VECTOR_INDEX = os.environ.get("VECTOR_INDEX", "pins")

ddb = boto3.client("dynamodb", region_name=REGION)
s3v = boto3.client("s3vectors", region_name=REGION)


def scan_all(table, **kw):
    out, start = [], None
    while True:
        args = dict(TableName=table, **kw)
        if start:
            args["ExclusiveStartKey"] = start
        page = ddb.scan(**args)
        out.extend(page.get("Items", []))
        start = page.get("LastEvaluatedKey")
        if not start:
            return out


def S(item, key, default=None):
    return item.get(key, {}).get("S", default)


def N(item, key, default=None):
    v = item.get(key, {}).get("N")
    return float(v) if v is not None else default


def collect_labels():
    """-> [(user_id, post_id, y, ts, origin)] sorted by time."""
    rows = []

    # 1. Guest swipes on shared decks.
    for it in scan_all(f"{PREFIX}-challenges"):
        if not S(it, "itemId", "").startswith("RESP"):
            continue
        # Attribute the label to the GUEST, not the sender — it is the guest's
        # taste being expressed.
        uid = f"guest:{S(it, 'challengeId', '?')}:{S(it, 'guestName', 'anon')}"
        ts = N(it, "createdAt", 0) or 0
        for i, s in enumerate(it.get("swipes", {}).get("L", [])):
            m = s.get("M", {})
            pid = S(m, "id")
            d = S(m, "dir", "")
            if not pid or d not in ("yes", "no"):
                continue
            rows.append((uid, pid, 1 if d == "yes" else 0, ts + i, "challenge"))

    # 2. In-app swipes by the account owner.
    for it in scan_all(f"{PREFIX}-analytics"):
        t = S(it, "type", "")
        if t not in ("swipe_right", "swipe_left"):
            continue
        pid = S(it, "postId")
        if not pid:
            continue
        rows.append((S(it, "userId", "?"), pid, 1 if t == "swipe_right" else 0,
                     N(it, "timestamp", 0) or 0, "app"))

    rows.sort(key=lambda r: r[3])
    return rows


def fetch_item_meta(post_ids):
    """Catalog metadata for the features. BatchGetItem in chunks of 100."""
    metas = {}
    ids = list(post_ids)
    for i in range(0, len(ids), 100):
        chunk = ids[i : i + 100]
        resp = ddb.batch_get_item(RequestItems={
            f"{PREFIX}-posts": {"Keys": [{"postId": {"S": p}} for p in chunk]}
        })
        for it in resp.get("Responses", {}).get(f"{PREFIX}-posts", []):
            pm = it.get("product", {}).get("M", {})
            source = S(it, "source", "") or ""
            imgs = pm.get("images", {}).get("L", [])
            metas[S(it, "postId")] = {
                "price": N(it, "price") or N(pm, "price") or 0.0,
                "category": S(it, "category", ""),
                "domain": S(it, "domain", ""),
                "merchant": S(pm, "brand", "") or S(it, "domain", ""),
                "likes": N(it, "likes", 0) or 0,
                "has_gallery": len(imgs) > 1,
                "has_story": bool(S(it, "story")),
                # A real storefront feed rather than a scraped pin.
                "is_retailer": source.startswith("Shopify") or source.startswith("Giftmaxxing"),
            }
    return metas


def fetch_vectors(keys):
    vecs = {}
    keys = [k for k in keys if k]
    for i in range(0, len(keys), 100):
        try:
            resp = s3v.get_vectors(
                vectorBucketName=VECTOR_BUCKET, indexName=VECTOR_INDEX,
                keys=keys[i : i + 100], returnData=True,
            )
        except Exception as e:  # a missing key 404s the whole batch on some paths
            print(f"  vector batch {i} failed: {e}")
            continue
        for v in resp.get("vectors", []):
            vecs[v["key"]] = np.asarray(v["data"]["float32"], dtype=np.float32)
    return vecs


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default="data/swipes.npz")
    args = ap.parse_args()

    print("collecting swipe labels…")
    rows = collect_labels()
    if not rows:
        print("no swipe labels found")
        return
    by_origin = defaultdict(int)
    for _, _, _, _, o in rows:
        by_origin[o] += 1
    pos = sum(r[2] for r in rows)
    print(f"  {len(rows)} labels ({pos} yes / {len(rows)-pos} no) from {dict(by_origin)}")
    print(f"  {len(set(r[0] for r in rows))} distinct swipers")

    post_ids = {r[1] for r in rows}
    print(f"fetching metadata + vectors for {len(post_ids)} products…")
    metas = fetch_item_meta(post_ids)
    vectors = fetch_vectors(post_ids)
    print(f"  {len(metas)} metas, {len(vectors)} vectors")

    # Walk forward in time per user so each profile sees only the past.
    history = defaultdict(list)
    X, Y, groups, origins, timestamps = [], [], [], [], []
    skipped = 0
    for uid, pid, y, ts, origin in rows:
        vec = vectors.get(pid)
        meta = metas.get(pid)
        if vec is None or meta is None:
            skipped += 1
            history[uid].append((pid, y))
            continue
        profile = UserProfile.from_labels(history[uid], vectors, metas)
        X.append(build_features(vec, meta, profile))
        Y.append(y)
        groups.append(uid)
        origins.append(origin)
        timestamps.append(ts)
        history[uid].append((pid, y))

    X = np.stack(X) if X else np.zeros((0, len(FEATURE_NAMES)), dtype=np.float32)
    Y = np.asarray(Y, dtype=np.float32)
    print(f"\nbuilt {len(Y)} examples ({int(Y.sum())} positive), skipped {skipped} "
          f"(no vector or no catalog row)")

    os.makedirs(os.path.dirname(args.out) or ".", exist_ok=True)
    np.savez(args.out, X=X, Y=Y, groups=np.array(groups), origins=np.array(origins),
             timestamps=np.asarray(timestamps, dtype=np.float64), features=np.array(FEATURE_NAMES))
    print(f"wrote {args.out}")

    meta_path = os.path.splitext(args.out)[0] + "_meta.json"
    with open(meta_path, "w") as f:
        json.dump({
            "n": int(len(Y)), "positives": int(Y.sum()),
            "users": int(len(set(groups))), "features": FEATURE_NAMES,
            "by_origin": dict(by_origin), "skipped": skipped,
        }, f, indent=2)
    print(f"wrote {meta_path}")


if __name__ == "__main__":
    main()
