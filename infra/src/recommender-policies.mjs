const CONTENT_KINDS = new Set(["product", "service", "ugc_post", "story", "generated_media"]);
export const POLICY_VERSION = "mixer-v2.6";

export const SURFACE_WEIGHTS = {
  home: { taste: 0.4, relevance: 0, commerce: 0.25, quality: 0.15, freshness: 0.1, exploration: 0.1 },
  search: { taste: 0.2, relevance: 0.55, commerce: 0.15, quality: 0.1, freshness: 0, exploration: 0 },
  challenge_learn: { taste: 0, relevance: 0.15, commerce: 0.1, quality: 0.05, freshness: 0, exploration: 0.7 },
  challenge_recommend: { taste: 0.45, relevance: 0.2, commerce: 0.2, quality: 0.1, freshness: 0, exploration: 0.05 },
};

const clamp = (n) => Math.max(0, Math.min(1, Number(n) || 0));
const text = (item) => `${item.title ?? ""} ${item.summary ?? ""} ${item.taxonomy?.primaryCategoryId ?? ""} ${(item.taxonomy?.labelIds ?? []).join(" ")}`.toLowerCase();

export function lexicalRelevance(item, terms = []) {
  if (!terms.length) return 0.5;
  const haystack = text(item);
  return terms.reduce((score, term) => score + (haystack.includes(String(term).toLowerCase()) ? 1 : 0), 0) / terms.length;
}

export function tasteFit(item, profile = {}) {
  const weights = profile.labelWeights ?? {};
  const labels = item.taxonomy?.labelIds ?? [];
  if (!labels.length || !Object.keys(weights).length) return 0.5;
  const sum = labels.reduce((score, label) => score + (Number(weights[label]) || 0), 0);
  return clamp(0.5 + sum / Math.max(2, labels.length * 4));
}

export function scoreCandidate(candidate, context) {
  const item = candidate.item;
  const weights = SURFACE_WEIGHTS[context.surface] ?? SURFACE_WEIGHTS.home;
  const commerce = item.commerce?.shoppability === "direct" ? 1 : item.commerce?.shoppability === "bridged" ? 0.75 : 0.15;
  const components = {
    taste: candidate.taste ?? tasteFit(item, context.profile),
    relevance: candidate.relevance ?? lexicalRelevance(item, context.terms),
    commerce,
    quality: clamp(item.quality?.score ?? 0.5),
    freshness: clamp(candidate.freshness ?? 0.5),
    exploration: clamp(candidate.informationGain ?? candidate.exploration ?? 0.5),
  };
  const score = Object.entries(weights).reduce((sum, [key, weight]) => sum + components[key] * weight, 0);
  return { ...candidate, components, score };
}

function violatesRun(output, item) {
  const tail = output.slice(-2);
  if (tail.length < 2) return false;
  const field = (entry, key) => key === "kind" ? entry.item.kind : entry.item[key] || entry.item.creator?.id;
  return ["kind", "merchant", "creator"].some((key) => {
    const value = key === "merchant" ? item.commerce?.offers?.[0]?.merchant : key === "creator" ? item.creator?.id : item.kind;
    return value && tail.every((entry) => field(entry, key) === value);
  });
}

export function mixCandidates(candidates, { surface = "home", limit = 20 } = {}) {
  const deduped = [];
  const seen = new Set();
  for (const candidate of candidates.sort((a, b) => b.score - a.score)) {
    const id = candidate.item?.entityId;
    if (!id || seen.has(id) || !CONTENT_KINDS.has(candidate.item.kind) || candidate.item.status !== "active") continue;
    seen.add(id);
    deduped.push(candidate);
  }
  if (surface === "challenge_learn") return challengeDeck(deduped, limit);
  if (surface !== "home") return diversify(deduped, limit);

  return scheduleHomeCarousels(deduped, limit);
}

function scheduleHomeCarousels(candidates, limit) {
  const allCarousels = diversify(candidates.filter((x) => x.item.kind === "ugc_post"), candidates.length);
  const bridged = allCarousels.filter((x) => x.item.commerce?.shoppability !== "inspiration_only");
  const inspiration = allCarousels.filter((x) => x.item.commerce?.shoppability === "inspiration_only")
    .slice(0, Math.floor(limit * 0.15));
  const carousels = [...bridged, ...inspiration];
  const stories = candidates.filter((x) => ["story", "generated_media"].includes(x.item.kind));
  const products = candidates.filter((x) => !["ugc_post", "story", "generated_media"].includes(x.item.kind));
  const cards = [];
  while (products.length || stories.length) {
    cards.push(...products.splice(0, Math.min(8, products.length)));
    if (stories.length) cards.push(stories.shift());
  }
  if (!carousels.length) return candidates.slice(0, limit);
  const output = [];
  while (output.length < limit && (cards.length || carousels.length)) {
    output.push(...cards.splice(0, Math.min(3, cards.length)));
    if (carousels.length && output.length < limit) output.push(carousels.shift());
    if (!cards.length) output.push(...carousels.splice(0, limit - output.length));
  }
  return output.slice(0, limit);
}

function challengeDeck(candidates, limit) {
  const selected = [], chosen = new Set(), categoryCount = new Map(), merchantCount = new Map();
  const add = (candidate, strict = true) => {
    const item = candidate.item, id = item.entityId;
    const category = item.taxonomy?.primaryCategoryId || "uncategorized";
    const merchant = item.commerce?.offers?.[0]?.merchant || item.creator?.id || "unknown";
    if (chosen.has(id) || (strict && ((categoryCount.get(category) || 0) >= 2 || (merchantCount.get(merchant) || 0) >= 2))) return false;
    selected.push(candidate); chosen.add(id);
    categoryCount.set(category, (categoryCount.get(category) || 0) + 1);
    merchantCount.set(merchant, (merchantCount.get(merchant) || 0) + 1);
    return true;
  };
  const priceBand = (candidate) => {
    const price = Number(candidate.item.commerce?.offers?.[0]?.price);
    return !Number.isFinite(price) ? "unknown" : price < 50 ? "low" : price < 150 ? "mid" : "high";
  };
  for (const band of ["low", "mid", "high"]) {
    const candidate = candidates.find((x) => priceBand(x) === band && !chosen.has(x.item.entityId));
    if (candidate) add(candidate);
  }
  for (const candidate of candidates) {
    if (selected.length >= limit) break;
    const category = candidate.item.taxonomy?.primaryCategoryId || "uncategorized";
    if (!categoryCount.has(category)) add(candidate);
  }
  for (const candidate of candidates) {
    if (selected.length >= limit) break;
    add(candidate);
  }
  for (const candidate of candidates) {
    if (selected.length >= limit) break;
    add(candidate, false);
  }
  return diversify(selected, limit);
}

function diversify(candidates, limit) {
  const output = [], deferred = [];
  for (const candidate of candidates) (violatesRun(output, candidate.item) ? deferred : output).push(candidate);
  for (const candidate of deferred) {
    const index = output.findIndex((_, i) => !violatesRun(output.slice(0, i + 1), candidate.item));
    output.splice(index < 0 ? output.length : index + 1, 0, candidate);
  }
  return output.slice(0, limit);
}

export function recommendationReason(candidate, surface) {
  if (surface === "challenge_learn") return { code: "learn_taste", label: "Helps reveal their taste" };
  if (candidate.item.commerce?.shoppability === "bridged") return { code: "inspiration_to_shop", label: "Inspiration with something similar to buy" };
  if (candidate.components?.taste >= 0.7) return { code: "taste_and_shoppable", label: "Matches their taste" };
  if (candidate.components?.relevance >= 0.7) return { code: "query_match", label: "Matches what you asked for" };
  return { code: "discovery", label: "Worth discovering" };
}
