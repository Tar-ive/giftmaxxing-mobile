const BLOCKED_TOP_LEVEL = new Set([
  "Explicit",
  "Violence",
  "Visually Disturbing",
  "Drugs & Tobacco",
  "Hate Symbols",
  "Rude Gestures",
  "Gambling",
]);

const BLOCKED_TERMS = [
  "nudity",
  "sexual",
  "graphic violence",
  "weapon violence",
  "physical violence",
  "self-harm",
  "blood & gore",
  "hate symbol",
  "drug",
  "tobacco",
];

export function blockedModerationLabels(labels = [], minimumConfidence = 60) {
  return labels.filter((label) => {
    if (Number(label?.Confidence ?? 0) < minimumConfidence) return false;
    const name = String(label?.Name ?? "");
    const parent = String(label?.ParentName ?? "");
    if (name === "Kissing") return false;
    if (BLOCKED_TOP_LEVEL.has(name) || BLOCKED_TOP_LEVEL.has(parent)) return true;
    const path = `${parent} ${name}`.toLowerCase();
    return BLOCKED_TERMS.some((term) => path.includes(term));
  });
}

export function recommendationLabels(detections = [], limit = 24) {
  const best = new Map();
  for (const detection of detections) {
    const label = detection?.Label ?? detection;
    const name = String(label?.Name ?? "").trim();
    const confidence = Number(label?.Confidence ?? detection?.Confidence ?? 0);
    if (!name || confidence < 70) continue;
    best.set(name, Math.max(best.get(name) ?? 0, confidence));
  }
  return [...best.entries()]
    .sort((a, b) => b[1] - a[1])
    .slice(0, limit)
    .map(([name, confidence]) => ({ name, confidence: Math.round(confidence * 10) / 10 }));
}

export function recommendationCategory(labels = []) {
  const text = labels.map((label) => label.name).join(" ").toLowerCase();
  if (/food|meal|dessert|cake|drink|beverage|restaurant/.test(text)) return "food";
  if (/clothing|apparel|shoe|jewelry|handbag|fashion/.test(text)) return "fashion";
  if (/cosmetic|makeup|skin|beauty|hair/.test(text)) return "beauty";
  if (/electronic|computer|phone|headphone|gadget/.test(text)) return "tech";
  if (/home|furniture|decor|kitchen|garden/.test(text)) return "home";
  if (/sport|fitness|outdoor|camping/.test(text)) return "sports";
  return "ugc";
}
