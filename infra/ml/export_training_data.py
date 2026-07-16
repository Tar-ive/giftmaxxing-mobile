#!/usr/bin/env python3
"""Export MTL training data: (user, post) examples with three binary labels.

Joins three live sources (read-only):
  - DynamoDB giftmaxxing-dev-analytics  — exposure (feed_impression) + dwell
    (feed_dwell.dwellMs) + buy/custom proxy events, per (userId, postId)
  - DynamoDB giftmaxxing-dev-interactions — like/save/comment/pledge/queue_add
  - S3 Vectors giftmaxxing-dev-vectors/pins — 1024-d Titan Multimodal item
    embeddings (the image-understanding features)

Labels per (user, post):
  y_time   — any dwell event with dwellMs >= 60_000
  y_custom — user typed words for it: comment / custom_message (gift letter,
             why-note; see AnalyticsEngine "custom_message")
  y_buy    — buy intent: product_affiliate_click / pledge / queue_add / checkout

Features per example:
  item_vec (1024f)  — Titan MM embedding of the item
  user_vec (1024f)  — taste centroid: mean item_vec over the user's positive
                      engagements (like/save/swipe_right/dwell>=8s), computed
                      from events STRICTLY BEFORE this example's first exposure
                      (no label leakage)
  aux (float)       — cos(user_vec, item_vec), log1p(price), user event count,
                      item source one-hots (pinterest/shopify/catalog/other)

Output (local dir and/or s3://<ml-bucket>/datasets/mtl/<stamp>/):
  train.npz / val.npz — X_item, X_user, X_aux, Y (n,3), plus keys
  meta.json           — feature/label spec + class balance (read by train.py)

Usage:
  python export_training_data.py [--out DIR] [--s3-bucket giftmaxxing-dev-ml]
                                 [--val-frac 0.2] [--profile dev_sso_giftmaxxing]
"""
import argparse
import json
import os
import time

import boto3
import numpy as np

from features import CTX_DIM, KnowledgeFeatures, build_context

ENV = "giftmaxxing-dev"
ANALYTICS = f"{ENV}-analytics"
INTERACTIONS = f"{ENV}-interactions"
KNOWLEDGE = f"{ENV}-knowledge"
POSTS = f"{ENV}-posts"
VECTOR_BUCKET = f"{ENV}-vectors"
VECTOR_INDEX = "pins"
DIM = 1024

DWELL_LABEL_MS = 60_000  # P_Time: "more than 60 seconds looking at the item"
DWELL_TASTE_MS = 8_000   # dwell long enough to count as positive taste signal
BUY_EVENTS = {"product_affiliate_click", "pledge", "queue_add", "checkout"}
CUSTOM_EVENTS = {"comment", "custom_message", "content_comment"}
TASTE_EVENTS = {"like", "save", "content_like", "content_save", "swipe_right"}


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


def attr(item, key, kind="S", default=None):
    v = item.get(key, {}).get(kind)
    if v is None:
        return default
    return float(v) if kind == "N" else v


def fetch_vectors(keys):
    """S3 Vectors GetVectors in chunks -> {key: np.array(1024)}."""
    vecs = {}
    keys = [k for k in keys if k]
    for i in range(0, len(keys), 100):
        resp = s3v.get_vectors(
            vectorBucketName=VECTOR_BUCKET, indexName=VECTOR_INDEX,
            keys=keys[i : i + 100], returnData=True, returnMetadata=True,
        )
        for v in resp.get("vectors", []):
            vecs[v["key"]] = (
                np.asarray(v["data"]["float32"], dtype=np.float32),
                v.get("metadata") or {},
            )
    return vecs


def build_knowledge_snapshot():
    """KNOWLEDGE table -> the compact idea-weight snapshot consumed by
    features.KnowledgeFeatures. Ships inside the dataset + model artifact so
    training and the endpoint featurize identically with zero runtime I/O."""
    rows = scan_all(KNOWLEDGE)
    ideas = {}
    max_count = 1.0
    for row in rows:
        recipient = attr(row, "recipient")
        for entry in row.get("ideas", {}).get("L", []):
            m = entry.get("M", {})
            key, label = attr(m, "key"), attr(m, "label")
            count = attr(m, "count", "N") or 0.0
            if not key:
                continue
            idea = ideas.setdefault(key, {"label": label or key, "count": 0.0, "recipients": {}})
            idea["count"] += count
            if recipient:
                idea["recipients"][recipient] = max(idea["recipients"].get(recipient, 0.0), count)
            max_count = max(max_count, idea["count"])
    for idea in ideas.values():
        idea["global"] = round(idea.pop("count") / max_count, 4)
        rmax = max(idea["recipients"].values(), default=1.0) or 1.0
        idea["recipients"] = {r: round(c / rmax, 4) for r, c in idea["recipients"].items()}
    return {"ideas": ideas}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=os.path.join(os.path.dirname(__file__), "data"))
    ap.add_argument("--s3-bucket", default=None, help="also upload to s3://BUCKET/datasets/mtl/<stamp>/")
    ap.add_argument("--val-frac", type=float, default=0.2)
    ap.add_argument("--profile", default=os.environ.get("AWS_PROFILE"))
    ap.add_argument("--seed", type=int, default=7)
    args = ap.parse_args()

    global ddb, s3v
    session = boto3.Session(profile_name=args.profile) if args.profile else boto3.Session()
    ddb = session.client("dynamodb", region_name="us-east-1")
    s3v = session.client("s3vectors", region_name="us-east-1")

    # ---- 1. Collect raw events -------------------------------------------
    analytics = scan_all(ANALYTICS)
    inter = scan_all(INTERACTIONS)
    print(f"analytics rows: {len(analytics)}  interaction rows: {len(inter)}")

    # events[(user, post)] = list of (ts_ms, type, dwellMs)
    events = {}

    def add(user, post, ts, typ, dwell=None):
        if not user or not post:
            return
        events.setdefault((user, post), []).append((ts or 0, typ, dwell))

    for it in analytics:
        add(attr(it, "userId"), attr(it, "postId"), attr(it, "timestamp", "N"),
            attr(it, "type"), attr(it, "dwellMs", "N"))
    for it in inter:
        add(attr(it, "userId"), attr(it, "target"), attr(it, "createdAt", "N"),
            attr(it, "type"))

    # ---- 2. Label each exposed (user, post) pair -------------------------
    EXPOSURE = {"feed_impression", "feed_dwell", "seen", "swipe_card_shown", "content_tap"}
    rows = []  # (user, post, first_exposure_ts, y_time, y_custom, y_buy)
    for (user, post), evs in events.items():
        exposed = [ts for ts, typ, _ in evs if typ in EXPOSURE]
        if not exposed:
            continue  # never shown -> not a training example
        y_time = any(typ == "feed_dwell" and (dw or 0) >= DWELL_LABEL_MS for _, typ, dw in evs)
        y_custom = any(typ in CUSTOM_EVENTS for _, typ, _ in evs)
        y_buy = any(typ in BUY_EVENTS for _, typ, _ in evs)
        rows.append((user, post, min(exposed), y_time, y_custom, y_buy))
    print(f"labeled (user,post) examples: {len(rows)}")

    # ---- 3. Item vectors + metadata --------------------------------------
    post_keys = sorted({post for _, post, *_ in rows})
    vec_map = fetch_vectors(post_keys)
    print(f"item vectors found: {len(vec_map)}/{len(post_keys)} "
          f"(items missing from the index are dropped — run backfill-vectors)")

    # price lookup from POSTS (single scan, projected)
    price, source = {}, {}
    for it in scan_all(POSTS, ProjectionExpression="postId, price, product, feedPk"):
        pid = attr(it, "postId")
        p = attr(it, "price", "N") or attr(it.get("product", {}).get("M", {}), "price", "N")
        if pid:
            if p:
                price[pid] = p
            src = "other"
            if pid.startswith("pin-"):
                src = "pinterest"
            elif pid.startswith(("shopify-", "sp-")):
                src = "shopify"
            elif pid.startswith(("cat-", "svc-", "asin-")):
                src = "catalog"
            source[pid] = src

    # ---- 4. Per-user taste centroids as of each exposure (no leakage) ----
    # Positive taste events per user, time-ordered: (ts, post)
    taste = {}
    for (user, post), evs in events.items():
        if post not in vec_map:
            continue
        for ts, typ, dw in evs:
            if typ in TASTE_EVENTS or (typ == "feed_dwell" and (dw or 0) >= DWELL_TASTE_MS):
                taste.setdefault(user, []).append((ts, post))
    for u in taste:
        taste[u].sort()

    user_event_count = {}
    for (user, _), evs in events.items():
        user_event_count[user] = user_event_count.get(user, 0) + len(evs)

    def centroid_before(user, ts):
        past = [p for t, p in taste.get(user, []) if t < ts]
        if not past:
            return None
        m = np.mean([vec_map[p][0] for p in past[-50:]], axis=0)
        n = np.linalg.norm(m)
        return (m / n).astype(np.float32) if n > 0 else None

    # ---- 5. Assemble tensors ----------------------------------------------
    # Context features (features.py, shared with inference): time of exposure
    # is real per example; relationship/occasion are historically untracked so
    # they encode as zeros ("unknown") until instrumented interaction context
    # accrues — the pipeline is already plumbed for them. Reddit idea weights
    # come from the knowledge snapshot matched against the item title.
    snapshot = build_knowledge_snapshot()
    kf = KnowledgeFeatures(snapshot)
    print(f"knowledge snapshot: {len(snapshot['ideas'])} ideas")

    SRC_ONEHOT = ["pinterest", "shopify", "catalog", "other"]
    X_item, X_user, X_aux, X_ctx, Y, keys = [], [], [], [], [], []
    zero = np.zeros(DIM, dtype=np.float32)
    for user, post, ts, yt, yc, yb in rows:
        if post not in vec_map:
            continue
        iv, imeta = vec_map[post]
        ivn = iv / (np.linalg.norm(iv) or 1.0)
        uv = centroid_before(user, ts)
        cos = float(np.dot(uv, ivn)) if uv is not None else 0.0
        onehot = [1.0 if source.get(post, "other") == s else 0.0 for s in SRC_ONEHOT]
        X_item.append(ivn)
        X_user.append(uv if uv is not None else zero)
        X_aux.append([cos, np.log1p(price.get(post, 0.0)),
                      np.log1p(user_event_count.get(user, 0)), *onehot])
        X_ctx.append(build_context(ts_ms=ts, title=imeta.get("title"), knowledge=kf))
        Y.append([yt, yc, yb])
        keys.append(f"{user}|{post}")

    X_item = np.stack(X_item); X_user = np.stack(X_user)
    X_aux = np.asarray(X_aux, dtype=np.float32); X_ctx = np.asarray(X_ctx, dtype=np.float32)
    Y = np.asarray(Y, dtype=np.float32)
    pos = Y.sum(axis=0).astype(int)
    print(f"final examples: {len(Y)}  positives — time: {pos[0]}, custom: {pos[1]}, buy: {pos[2]}")

    # ---- 6. Group split by user (honest generalization at 40 users) ------
    rng = np.random.default_rng(args.seed)
    users = np.array([k.split("|")[0] for k in keys])
    uniq = rng.permutation(np.unique(users))
    n_val = max(1, int(len(uniq) * args.val_frac))
    val_users = set(uniq[:n_val])
    is_val = np.array([u in val_users for u in users])

    os.makedirs(args.out, exist_ok=True)
    stamp = time.strftime("%Y-%m-%dT%H-%M-%S")
    meta = {
        "created": stamp, "dim": DIM, "aux_dim": X_aux.shape[1], "ctx_dim": X_ctx.shape[1],
        "features_version": 2,
        "aux_features": ["cos_user_item", "log1p_price", "log1p_user_events", *[f"src_{s}" for s in SRC_ONEHOT]],
        "labels": ["y_time_gt60s", "y_custom_message", "y_buy_intent"],
        "n_train": int((~is_val).sum()), "n_val": int(is_val.sum()),
        "pos_train": Y[~is_val].sum(axis=0).tolist(), "pos_val": Y[is_val].sum(axis=0).tolist(),
        "val_users": sorted(val_users),
    }
    for name, mask in [("train", ~is_val), ("val", is_val)]:
        np.savez_compressed(
            os.path.join(args.out, f"{name}.npz"),
            X_item=X_item[mask], X_user=X_user[mask], X_aux=X_aux[mask], X_ctx=X_ctx[mask],
            Y=Y[mask], keys=np.array(keys, dtype=object)[mask],
        )
    with open(os.path.join(args.out, "meta.json"), "w") as f:
        json.dump(meta, f, indent=2)
    with open(os.path.join(args.out, "knowledge_snapshot.json"), "w") as f:
        json.dump(snapshot, f)
    print(f"wrote {args.out}/train.npz ({meta['n_train']}), val.npz ({meta['n_val']}), meta.json, knowledge_snapshot.json")

    if args.s3_bucket:
        s3 = session.client("s3", region_name="us-east-1")
        prefix = f"datasets/mtl/{stamp}"
        for fn in ["train.npz", "val.npz", "meta.json", "knowledge_snapshot.json"]:
            s3.upload_file(os.path.join(args.out, fn), args.s3_bucket, f"{prefix}/{fn}")
        print(f"uploaded to s3://{args.s3_bucket}/{prefix}/")


if __name__ == "__main__":
    main()
