import test from "node:test";
import assert from "node:assert/strict";
import { interleaveAuthors } from "./feed-diversity.mjs";

const item = (id, author, category) => ({ postId: id, author, category });

const maxCategoryRun = (items) => {
  let best = 0, run = 0, prev = null;
  for (const it of items) {
    const c = String(it.category ?? "").toLowerCase();
    run = c && c === prev ? run + 1 : 1;
    prev = c;
    best = Math.max(best, run);
  }
  return best;
};

test("breaks up a same-category wall spanning multiple brands", () => {
  // 12 shoes from 3 brands + 6 other items — the reported failure mode:
  // author spacing alone lets shoes alternate brands and still fill the page.
  const shoes = Array.from({ length: 12 }, (_, i) =>
    item(`s${i}`, ["vessi", "rothys", "allbirds"][i % 3], "shoes"));
  const other = Array.from({ length: 6 }, (_, i) =>
    item(`o${i}`, `brand${i}`, ["tech", "kitchen", "beauty"][i % 3]));
  const out = interleaveAuthors([...shoes, ...other]);
  assert.equal(out.length, 18);
  // The FIRST SCREEN is the product goal — once only shoes remain, tail runs
  // are unavoidable (graceful degradation), so assert on the head.
  const head = out.slice(0, 12);
  assert.ok(maxCategoryRun(head) <= 2, `head category run was ${maxCategoryRun(head)}`);
  // Pool is 2/3 shoes; the cap holds shoes to 5 per window until the 6
  // non-shoes run out, then one forced pick lands — 6 is the constrained
  // optimum for this pool (vs 12 straight shoes before the fix).
  const headShoes = head.filter((p) => p.category === "shoes").length;
  assert.ok(headShoes <= 6, `first 12 slots held ${headShoes} shoes`);
});

test("caps one brand per window", () => {
  const gym = Array.from({ length: 10 }, (_, i) => item(`g${i}`, "gymshark", "fitness"));
  const rest = Array.from({ length: 10 }, (_, i) => item(`r${i}`, `b${i}`, `c${i}`));
  const out = interleaveAuthors([...gym, ...rest]);
  // Head window (before the pool degrades to gymshark-only remainder).
  const n = out.slice(0, 12).filter((p) => p.author === "gymshark").length;
  assert.ok(n <= 4, `first window held ${n} gymshark items`);
});

test("degrades to score order instead of starving a one-category pool", () => {
  const all = Array.from({ length: 8 }, (_, i) => item(`x${i}`, "one-brand", "shoes"));
  const out = interleaveAuthors(all);
  assert.deepEqual(out.map((p) => p.postId), all.map((p) => p.postId));
});

test("untagged items never block placement", () => {
  const untagged = Array.from({ length: 6 }, (_, i) => ({ postId: `u${i}` }));
  const out = interleaveAuthors(untagged);
  assert.equal(out.length, 6);
});

test("keeps relative score order within constraints (stable head)", () => {
  const items = [item("a", "b1", "tech"), item("b", "b2", "kitchen"), item("c", "b3", "beauty")];
  assert.deepEqual(interleaveAuthors(items).map((p) => p.postId), ["a", "b", "c"]);
});
