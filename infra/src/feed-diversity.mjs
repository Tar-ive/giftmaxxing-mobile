// Greedy diversity spacing for ranked feed pages (MMR-lite).
//
// The catalog is dominated by a few big Shopify inventories (shoes, gym
// apparel, beauty), and every ranker — scorePost, cosine kNN, the MTL value
// model — scores near-identical items near-identically, so raw score order
// produces "15 shoes in a row". Author-only spacing didn't help: a shoe wall
// spans three different brands. This spaces BOTH dimensions:
//
//   brand/author — run cap 2 (unchanged) and ≤4 per 12-slot window
//                  (was 8, which let one store own most of a page)
//   category     — run cap 2 and ≤5 per 12-slot window ("shoes" from three
//                  brands can no longer stack)
//
// Greedy with graceful degradation: prefer a candidate satisfying both
// constraints, then brand-only, then take the best-scored remainder — a
// one-category candidate pool degrades to score order rather than starving.
export function interleaveAuthors(items, {
  maxRun = 2, perWindow = 4, window = 12,
  catRun = 2, catPerWindow = 5,
} = {}) {
  if (!Array.isArray(items) || items.length <= maxRun) return items;
  const authorOf = (p) => p.author || p.sourceUser || p.merchant || "";
  const catOf = (p) => String(p.category ?? p.product?.category ?? "").toLowerCase();

  const remaining = [...items];
  const out = [];

  const runLen = (of, val) => {
    if (!val) return 0; // untagged never blocks
    let run = 0;
    for (let j = out.length - 1; j >= 0 && of(out[j]) === val; j--) run++;
    return run;
  };
  const inWindow = (of, val) => {
    if (!val) return 0;
    let n = 0;
    for (let j = Math.max(0, out.length - window); j < out.length; j++) {
      if (of(out[j]) === val) n++;
    }
    return n;
  };
  const brandOk = (p) =>
    runLen(authorOf, authorOf(p)) < maxRun && inWindow(authorOf, authorOf(p)) < perWindow;
  const catOk = (p) =>
    runLen(catOf, catOf(p)) < catRun && inWindow(catOf, catOf(p)) < catPerWindow;

  while (remaining.length) {
    let idx = remaining.findIndex((p) => brandOk(p) && catOk(p));
    if (idx < 0) idx = remaining.findIndex((p) => brandOk(p));
    if (idx < 0) idx = 0;
    out.push(remaining.splice(idx, 1)[0]);
  }
  return out;
}

// Give approved community posts a predictable place in the product-heavy feed.
// The ranker still orders each cohort; this only prevents a zero-price UGC post
// from losing every slot to catalog inventory with stronger commerce signals.
export function interleaveUGC(items, { firstSlot = 2, every = 8, max = 2 } = {}) {
  if (!Array.isArray(items) || !items.some((item) => item.source === "ugc")) return items;
  const ugc = items
    .filter((item) => item.source === "ugc")
    .sort((a, b) => Number(b.createdAt ?? 0) - Number(a.createdAt ?? 0))
    .slice(0, max);
  const out = items.filter((item) => item.source !== "ugc");
  ugc.forEach((item, index) => out.splice(Math.min(firstSlot + index * every, out.length), 0, item));
  return out;
}
