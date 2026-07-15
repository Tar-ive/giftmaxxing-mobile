#!/usr/bin/env python3
"""Group gifts by visual+semantic similarity: k-means over the Titan
Multimodal vectors in S3 Vectors (the image-understanding pipeline's output).

These clusters are the learned "gift pools" of CLOUD.md §15.3: each cluster is
a themed shelf ("Tech Enthusiast", "Cozy Kitchen", …) discovered from the
embeddings instead of hand-curated. Output:

  clusters.json — per cluster: size, auto-label (top title terms), sample
                  items (key/title/url), centroid (for kNN serving)

  --apply       — additionally writes one pool#<clusterId> row per cluster to
                  the DynamoDB config table (item type "pool") so the
                  /recommendations Lambda can blend pool items per §15.3.
                  Without --apply this script is strictly read-only.

Usage:
  python cluster_gifts.py [--k 24] [--out clusters.json] [--apply]
                          [--profile dev_sso_giftmaxxing]
"""
import argparse
import collections
import json
import os
import re
import time

import boto3
import numpy as np
from sklearn.cluster import MiniBatchKMeans
from sklearn.metrics import silhouette_score

ENV = "giftmaxxing-dev"
VECTOR_BUCKET = f"{ENV}-vectors"
VECTOR_INDEX = "pins"
CONFIG_TABLE = f"{ENV}-config"

STOP = set("""a an and are as at be but by for from gift gifts idea ideas in is it of on or
set that the this to under with you your best top diy how make perfect cute""".split())


def list_all_vectors(s3v):
    keys, titles, vecs, token = [], [], [], None
    while True:
        kw = dict(vectorBucketName=VECTOR_BUCKET, indexName=VECTOR_INDEX,
                  maxResults=500, returnData=True, returnMetadata=True)
        if token:
            kw["nextToken"] = token
        page = s3v.list_vectors(**kw)
        for v in page.get("vectors", []):
            keys.append(v["key"])
            vecs.append(v["data"]["float32"])
            titles.append((v.get("metadata") or {}).get("title") or "")
        token = page.get("nextToken")
        if not token:
            break
    X = np.asarray(vecs, dtype=np.float32)
    X /= np.linalg.norm(X, axis=1, keepdims=True).clip(min=1e-8)
    return keys, titles, X


def label_cluster(titles):
    words = collections.Counter()
    for t in titles:
        for w in re.findall(r"[a-z]{3,}", t.lower()):
            if w not in STOP:
                words[w] += 1
    return " / ".join(w for w, _ in words.most_common(4)) or "misc"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--k", type=int, default=24)
    ap.add_argument("--pick-k", action="store_true", help="scan k in {12..40} by silhouette instead")
    ap.add_argument("--out", default=os.path.join(os.path.dirname(__file__), "clusters.json"))
    ap.add_argument("--apply", action="store_true", help="write pool#<id> rows to the config table")
    ap.add_argument("--profile", default=os.environ.get("AWS_PROFILE"))
    ap.add_argument("--seed", type=int, default=7)
    args = ap.parse_args()

    session = boto3.Session(profile_name=args.profile) if args.profile else boto3.Session()
    s3v = session.client("s3vectors", region_name="us-east-1")
    keys, titles, X = list_all_vectors(s3v)
    print(f"vectors: {len(keys)}  dim: {X.shape[1]}")

    if args.pick_k:
        best = None
        sample = np.random.default_rng(args.seed).choice(len(X), min(2000, len(X)), replace=False)
        for k in range(12, 41, 4):
            km = MiniBatchKMeans(n_clusters=k, random_state=args.seed, n_init=5).fit(X)
            s = silhouette_score(X[sample], km.labels_[sample], metric="cosine")
            print(f"k={k} silhouette={s:.4f}")
            if best is None or s > best[1]:
                best = (k, s)
        args.k = best[0]
        print(f"picked k={args.k}")

    km = MiniBatchKMeans(n_clusters=args.k, random_state=args.seed, n_init=10).fit(X)
    labels = km.labels_

    clusters = []
    for c in range(args.k):
        idx = np.where(labels == c)[0]
        # items nearest the centroid represent the cluster best
        centroid = km.cluster_centers_[c]
        centroid = centroid / (np.linalg.norm(centroid) or 1.0)
        order = idx[np.argsort(-X[idx] @ centroid)]
        clusters.append({
            "clusterId": c,
            "size": int(len(idx)),
            "label": label_cluster([titles[i] for i in idx]),
            "itemKeys": [keys[i] for i in order[:50]],
            "samples": [{"key": keys[i], "title": titles[i][:120]} for i in order[:8]],
            "centroid": [round(float(v), 6) for v in centroid],
        })
    clusters.sort(key=lambda c: -c["size"])
    with open(args.out, "w") as f:
        json.dump({"created": time.strftime("%Y-%m-%dT%H-%M-%S"), "k": args.k,
                   "n": len(keys), "clusters": clusters}, f, indent=1)
    for c in clusters[:12]:
        print(f"  #{c['clusterId']:>2} n={c['size']:<5} {c['label']}")
    print(f"wrote {args.out}")

    if args.apply:
        ddb = session.resource("dynamodb", region_name="us-east-1").Table(CONFIG_TABLE)
        for c in clusters:
            ddb.put_item(Item={
                "key": f"pool#{c['clusterId']}", "type": "pool",
                "label": c["label"], "itemIds": c["itemKeys"],
                "size": c["size"], "updatedAt": int(time.time() * 1000),
            })
        print(f"applied {len(clusters)} pool# rows to {CONFIG_TABLE}")


if __name__ == "__main__":
    main()
