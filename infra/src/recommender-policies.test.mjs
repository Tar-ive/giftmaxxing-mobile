import test from "node:test";
import assert from "node:assert/strict";
import { normalizeLegacyPost } from "./catalog-v2.mjs";
import { mixCandidates, scoreCandidate } from "./recommender-policies.mjs";

const post = (id, source, kind, extra = {}) => normalizeLegacyPost({
  postId: id, source, kind, category: extra.category ?? "home", vibes: extra.vibes ?? ["cozy"],
  product: { name: id, brand: extra.brand ?? `brand-${id}`, image: `https://img/${id}.jpg`, price: extra.price ?? 20 },
  productUrl: extra.url ?? (kind === "product" ? `https://shop/${id}` : ""), qualityScore: 0.8,
});

test("normalizer separates provenance, item kind and shoppability", () => {
  const ugc = normalizeLegacyPost({ postId: "u1", source: "ugc", caption: "Cozy desk", mediaUrl: "https://img/u1.jpg" });
  assert.equal(ugc.kind, "ugc_post");
  assert.equal(ugc.provenance.type, "ugc");
  assert.equal(ugc.commerce.shoppability, "inspiration_only");
});

test("home mixer deduplicates and keeps a shoppable majority", () => {
  const items = [
    ...Array.from({ length: 12 }, (_, i) => post(`p${i}`, "Shopify/Test", "product")),
    ...Array.from({ length: 4 }, (_, i) => post(`u${i}`, "ugc", "ugc_post")),
    ...Array.from({ length: 3 }, (_, i) => {
      const item = post(`s${i}`, "editorial", "story");
      item.commerce = { shoppability: "bridged", offers: [{ price: 20, merchant: `story-store-${i}`, url: `https://shop/story-${i}` }] };
      return item;
    }),
  ];
  const scored = [...items, items[0]].map((item) => scoreCandidate({ item }, { surface: "home", terms: ["cozy"], profile: {} }));
  const mixed = mixCandidates(scored, { surface: "home", limit: 12 });
  assert.equal(new Set(mixed.map((x) => x.item.entityId)).size, mixed.length);
  assert.ok(mixed.filter((x) => x.item.commerce.shoppability !== "inspiration_only").length / mixed.length >= 0.85);
  assert.ok(mixed.some((x) => x.item.kind === "ugc_post"));
  assert.ok(mixed.some((x) => x.item.kind === "story"));
});

test("home schedules one inspiration carousel per four cards", () => {
  const items = [
    ...Array.from({ length: 15 }, (_, i) => post(`p${i}`, "catalog", "product")),
    ...Array.from({ length: 5 }, (_, i) => {
      const item = post(`u${i}`, "ugc", "ugc_post");
      item.commerce = { shoppability: "bridged", offers: [] };
      return item;
    }),
  ];
  const mixed = mixCandidates(items.map((item) => ({ item, score: 1 })), { surface: "home", limit: 20 });
  assert.equal(mixed.filter((x) => x.item.kind === "ugc_post").length, 5);
  assert.deepEqual([3, 7, 11, 15, 19].map((index) => mixed[index].item.kind), Array(5).fill("ugc_post"));
});

test("search weights query relevance above a conflicting taste", () => {
  const coffee = post("coffee", "Shopify/Test", "product", { category: "coffee", vibes: ["coffee"] });
  const tech = post("tech", "Shopify/Test", "product", { category: "tech", vibes: ["tech"] });
  const context = { surface: "search", terms: ["coffee"], profile: { labelWeights: { tech: 5, coffee: -1 } } };
  assert.ok(scoreCandidate({ item: coffee }, context).score > scoreCandidate({ item: tech }, context).score);
});

test("challenge learning builds a unique, category-balanced 14-card deck", () => {
  const candidates = Array.from({ length: 24 }, (_, index) => {
    const item = post(`deck-${index}`, "Shopify/Test", "product", { url: `https://shop/deck-${index}` });
    item.taxonomy.primaryCategoryId = `category-${index % 7}`;
    item.commerce.offers[0].merchant = `merchant-${index % 9}`;
    item.commerce.offers[0].price = [25, 85, 220][index % 3];
    return { item, score: 1 - index / 100 };
  });
  const deck = mixCandidates(candidates, { surface: "challenge_learn", limit: 14 });
  assert.equal(deck.length, 14);
  assert.equal(new Set(deck.map((x) => x.item.entityId)).size, 14);
  assert.ok(new Set(deck.map((x) => x.item.taxonomy.primaryCategoryId)).size >= 4);
  const counts = deck.reduce((all, x) => ({ ...all, [x.item.taxonomy.primaryCategoryId]: (all[x.item.taxonomy.primaryCategoryId] || 0) + 1 }), {});
  assert.ok(Math.max(...Object.values(counts)) <= 2);
  assert.ok(deck.every((x) => x.item.kind === "product"));
});
