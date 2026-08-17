// Collapse colourway/size variants to one card per real product.
//
// Shopify `/products.json` lists every variant as its own product, so the feed
// served "Men's Strider - Natural Black (Blizzard Sole)", "- Medium Grey
// (Blizzard Sole)", "- Rugged Beige (Stony Cream Sole)" … as separate cards.
// Diversity spacing can't help: they are different titles under the same brand,
// so they read as a wall of one shoe — the single loudest reason the feed feels
// like a store dump rather than a gift feed.
//
// The variant marker is the retailer convention itself: everything after the
// first " - " or " | " separator is the colourway/fit ("Crossover Polo | Sage
// Signature Fit"). Key on brand + the stem before it, keep the first (best
// ranked) and drop the rest. Titles with no separator are their own stem, so
// distinct products are never merged.
export function collapseVariants(items) {
  if (!Array.isArray(items) || items.length < 2) return items;
  const seen = new Set();
  const out = [];
  for (const item of items) {
    const key = variantKey(item);
    if (key && seen.has(key)) continue;
    if (key) seen.add(key);
    out.push(item);
  }
  return out;
}

export function variantKey(item) {
  const title = String(item?.product?.name ?? item?.title ?? item?.caption ?? "");
  const brand = String(item?.product?.brand ?? item?.author ?? item?.merchant ?? "").toLowerCase().trim();
  // Split on a SPACED separator only: "Wonder Oven Baker's Kit – 3-piece" is a
  // description, but so is anything after it — while "Non-Stick" and "T-Shirt"
  // keep their unspaced hyphens intact.
  const stem = title.split(/\s+[-–|]\s+/)[0].toLowerCase().replace(/\s+/g, " ").trim();
  if (!stem || !brand) return null;
  // A stem that IS the whole title carries no variant marker — two products
  // genuinely named the same thing under one brand are duplicates anyway.
  return `${brand}::${stem}`;
}

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
  // Collapse first: spacing near-identical variants apart still shows the same
  // shoe five times, just further down the page.
  items = collapseVariants(items);
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
