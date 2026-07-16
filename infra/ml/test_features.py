"""Plain-python checks for the shared feature module (no AWS, no torch).
Run: .venv/bin/python test_features.py
"""
import math

from features import (CTX_DIM, KnowledgeFeatures, RELATIONSHIPS, build_context, time_features)

# dimension contract
v = build_context()
assert len(v) == CTX_DIM, f"CTX_DIM mismatch: {len(v)} != {CTX_DIM}"
assert all(x == 0.0 for x in v), "empty context must be all zeros"

# cyclical time: noon UTC -> hour angle pi (sin~0, cos~-1)
tf = time_features(12 * 3600 * 1000)
assert abs(tf[0]) < 1e-6 and abs(tf[1] + 1) < 1e-6, tf

# relationship aliases map onto canonical buckets
v = build_context(relationship="wife")
assert v[4 + RELATIONSHIPS.index("partner")] == 1.0
v = build_context(relationship="mom")
assert v[4 + RELATIONSHIPS.index("parent")] == 1.0
v = build_context(relationship="martian")  # unknown-but-present -> other... no alias -> zeros
assert sum(v[4:4 + len(RELATIONSHIPS)]) == 0.0

# knowledge matching: title hits idea keywords; recipient weight only when known
kf = KnowledgeFeatures({"ideas": {
    "headphones": {"label": "Headphones", "global": 0.8, "recipients": {"teen": 1.0, "mom": 0.1}},
    "candle": {"label": "Scented candle", "global": 0.5, "recipients": {"mom": 0.9}},
}})
g, r = kf.features("Sony WH-1000XM5 Headphones, noise cancelling")
assert g == 0.8 and r == 0.0, (g, r)
g, r = kf.features("Wireless headphones for gaming", recipient="teen")
assert g == 0.8 and r == 1.0, (g, r)
g, r = kf.features("Lavender scented CANDLE gift", recipient="mom")
assert (g, r) == (0.5, 0.9), (g, r)
g, r = kf.features("Leather wallet")
assert (g, r) == (0.0, 0.0), (g, r)
# 'candlestick' must not match 'candle' (word-boundary check)
g, _ = kf.features("Brass candlestick holder")
assert g == 0.0, "substring leak: candlestick matched candle"

print(f"features.py ok — CTX_DIM={CTX_DIM}")
