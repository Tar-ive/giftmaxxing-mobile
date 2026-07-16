"""Shared feature construction — the SINGLE source of truth for every feature
the MTL value model consumes beyond the two embeddings.

Training/inference separation done right: export_training_data.py (offline,
training side) and inference.py (SageMaker endpoint, serving side) both import
THIS module, so a feature can never drift between the two. The serving payload
carries raw context (timestamp, relationship, occasion, title); featurization
happens here on both sides.

Context vector layout (CTX_DIM floats):
  [0:4]   time of day + day of week as sin/cos pairs (cyclical encoding)
  [4:11]  relationship-to-recipient one-hot (all zeros = unknown)
  [11:18] occasion one-hot (all zeros = unknown)
  [18:20] Reddit knowledge: global idea weight, recipient-specific idea weight

The Reddit features come from the r/Gifts mining (KNOWLEDGE table): an item
whose title matches a gift idea real people recommend ("headphones" for a
teen) carries that idea's popularity as a feature — per recipient when the
context knows one, globally otherwise. The knowledge snapshot rides inside
the dataset/model artifact (knowledge_snapshot.json) so the endpoint never
needs a DynamoDB read.
"""
import json
import math
import os
import re

RELATIONSHIPS = ["partner", "parent", "sibling", "child", "friend", "colleague", "other"]
OCCASIONS = ["birthday", "anniversary", "holiday", "wedding", "graduation", "justbecause", "other"]
CTX_DIM = 4 + len(RELATIONSHIPS) + len(OCCASIONS) + 2

# Map free-form relationship/recipient strings (client tags, KNOWLEDGE
# recipient keys) onto the canonical one-hot buckets.
_REL_ALIASES = {
    "partner": "partner", "wife": "partner", "husband": "partner", "girlfriend": "partner",
    "boyfriend": "partner", "spouse": "partner", "couple": "partner",
    "parent": "parent", "mom": "parent", "dad": "parent", "mother": "parent", "father": "parent",
    "sibling": "sibling", "sister": "sibling", "brother": "sibling",
    "child": "child", "son": "child", "daughter": "child", "kids": "child", "teen": "child",
    "friend": "friend", "coworker": "colleague", "colleague": "colleague", "boss": "colleague",
}
_OCC_ALIASES = {
    "birthday": "birthday", "anniversary": "anniversary",
    "christmas": "holiday", "holiday": "holiday", "hanukkah": "holiday", "valentines": "holiday",
    "wedding": "wedding", "graduation": "graduation",
    "justbecause": "justbecause", "just-because": "justbecause", "any": None,
}


def _onehot(value, vocab, aliases):
    v = aliases.get(str(value or "").strip().lower())
    out = [0.0] * len(vocab)
    if v is None:
        return out
    out[vocab.index(v) if v in vocab else vocab.index("other")] = 1.0
    return out


def time_features(ts_ms):
    """Cyclical hour-of-day + day-of-week from an epoch-ms timestamp (UTC)."""
    if not ts_ms:
        return [0.0, 0.0, 0.0, 0.0]
    secs = ts_ms / 1000.0
    hour = (secs % 86400) / 86400.0
    dow = ((int(secs // 86400) + 4) % 7) / 7.0  # epoch day 0 = Thursday
    return [math.sin(2 * math.pi * hour), math.cos(2 * math.pi * hour),
            math.sin(2 * math.pi * dow), math.cos(2 * math.pi * dow)]


class KnowledgeFeatures:
    """Matches item titles against the Reddit-mined gift-idea lexicon.

    Snapshot shape (built by export_training_data.py from the KNOWLEDGE table):
      { "ideas": { key: { "label": str, "global": float,        # 0..1
                          "recipients": { name: float } } } }   # 0..1 each
    """

    def __init__(self, snapshot=None):
        snap = snapshot or {"ideas": {}}
        self.ideas = snap.get("ideas", {})
        self._patterns = {
            key: re.compile(
                r"(?:^|[^a-z])(?:" + "|".join(
                    re.escape(w) for w in {key.lower(), *re.findall(r"[a-z]{3,}", str(idea.get("label", "")).lower())}
                    if w not in {"set", "the", "and", "for"}
                ) + r")(?:[^a-z]|$)"
            )
            for key, idea in self.ideas.items()
        }

    @classmethod
    def load(cls, model_dir):
        path = os.path.join(model_dir, "knowledge_snapshot.json")
        if os.path.exists(path):
            with open(path) as f:
                return cls(json.load(f))
        return cls()

    def features(self, title, recipient=None):
        """-> (global_weight, recipient_weight), each 0..1."""
        t = str(title or "").lower()
        if not t or not self.ideas:
            return 0.0, 0.0
        g, r = 0.0, 0.0
        rkey = str(recipient or "").strip().lower()
        for key, pat in self._patterns.items():
            if not pat.search(t):
                continue
            idea = self.ideas[key]
            g = max(g, float(idea.get("global", 0.0)))
            if rkey:
                r = max(r, float(idea.get("recipients", {}).get(rkey, 0.0)))
        return g, r


def build_context(ts_ms=None, relationship=None, occasion=None,
                  title=None, recipient=None, knowledge=None):
    """The CTX_DIM feature vector. Missing fields encode as zeros — the model
    learns 'unknown' as its own signal instead of crashing on sparse data."""
    reddit = knowledge.features(title, recipient) if knowledge else (0.0, 0.0)
    return [
        *time_features(ts_ms),
        *_onehot(relationship, RELATIONSHIPS, _REL_ALIASES),
        *_onehot(occasion, OCCASIONS, _OCC_ALIASES),
        *reddit,
    ]
