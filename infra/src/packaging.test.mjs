// Contract tests for the pure half of POST /packaging.
//
// The two things that MUST hold: the signature is a stable cache key (or every
// cart re-renders and we pay per view), and normalizePlan survives whatever
// shape the model actually returns (or the sheet renders nothing).
import test from "node:test";
import assert from "node:assert/strict";

import {
  cartSignature,
  packagingCacheKey,
  publicKeyFor,
  seedFrom,
  buildVisionPrompt,
  buildCanvasPrompt,
  normalizePlan,
} from "./packaging.mjs";

const items = [
  { postId: "p1", title: "Ceramic pour-over dripper", category: "kitchen", price: 38 },
  { postId: "p2", title: "Single-origin coffee beans", category: "food", price: 18 },
];

test("signature is order-independent", () => {
  assert.equal(cartSignature(items), cartSignature([...items].reverse()));
});

test("signature ignores quantity and duplicate ids", () => {
  assert.equal(cartSignature(items), cartSignature([...items, items[0]]));
});

test("signature is sensitive to occasion", () => {
  assert.notEqual(
    cartSignature(items, { occasion: "birthday" }),
    cartSignature(items, { occasion: "anniversary" })
  );
});

test("occasion casing and padding do not change the signature", () => {
  assert.equal(
    cartSignature(items, { occasion: "Birthday" }),
    cartSignature(items, { occasion: "  birthday " })
  );
});

test("signature changes when an item is added or removed", () => {
  const more = [...items, { postId: "p3", title: "Mug" }];
  assert.notEqual(cartSignature(items), cartSignature(more));
  assert.notEqual(cartSignature(items), cartSignature([items[0]]));
});

test("empty cart still yields a stable signature", () => {
  assert.equal(cartSignature([]), cartSignature(undefined));
});

test("cache key is namespaced", () => {
  assert.ok(packagingCacheKey(cartSignature(items)).startsWith("packaging#"));
});

test("public key stays inside the prefix and is hex-only", () => {
  const key = publicKeyFor(cartSignature(items));
  assert.match(key, /^wrap\/public\/[a-f0-9]+\.png$/);
});

test("public key rejects path traversal", () => {
  // "../" contains no hex characters that survive the filter except 'a'..'f';
  // the point is that no separator can ever reach the key.
  assert.ok(!publicKeyFor("../../etc/passwd").includes(".."));
  assert.throws(() => publicKeyFor("///"));
  assert.throws(() => publicKeyFor(""));
});

test("seed is deterministic and in Nova Canvas range", () => {
  const sig = cartSignature(items);
  assert.equal(seedFrom(sig), seedFrom(sig));
  const seed = seedFrom(sig);
  assert.ok(Number.isInteger(seed) && seed >= 0 && seed < 2147483646);
});

test("vision prompt names every item and the occasion", () => {
  const prompt = buildVisionPrompt(items, { occasion: "birthday", recipientName: "Sarah" });
  assert.match(prompt, /Ceramic pour-over dripper/);
  assert.match(prompt, /Single-origin coffee beans/);
  assert.match(prompt, /birthday/);
  assert.match(prompt, /Sarah/);
  assert.match(prompt, /JSON only/);
});

test("normalizePlan survives code fences and trailing prose", () => {
  const raw = [
    "Sure! Here's a plan:",
    "```json",
    JSON.stringify({
      title: "Kraft & Sage",
      vibe: "quiet and handmade",
      materials: ["kraft paper", "sage ribbon", "eucalyptus sprig"],
      palette: ["#D9CBB3", "#8A9A7B", "#4A4238"],
      steps: ["Nest the dripper in tissue.", "Wrap in kraft.", "Tie with ribbon.", "Tuck a sprig under the knot."],
      noteIdea: "Slow mornings, on me.",
      imagePrompt: "a kraft-wrapped parcel with a sage ribbon",
    }),
    "```",
    "Let me know if you'd like a different palette!",
  ].join("\n");

  const plan = normalizePlan(raw);
  assert.equal(plan.title, "Kraft & Sage");
  assert.equal(plan.steps.length, 4);
  assert.equal(plan.palette.length, 3);
});

test("normalizePlan clamps an over-long plan", () => {
  const plan = normalizePlan({
    title: "x".repeat(200),
    materials: Array.from({ length: 12 }, (_, i) => `material ${i}`),
    steps: Array.from({ length: 9 }, (_, i) => `step ${i} ${"y".repeat(300)}`),
    palette: ["#ffffff", "#000000", "#123456", "#abcdef"],
  });
  assert.ok(plan.title.length <= 48);
  assert.equal(plan.materials.length, 6);
  assert.equal(plan.steps.length, 6);
  assert.ok(plan.steps[0].length <= 140);
  assert.equal(plan.palette.length, 3);
});

test("normalizePlan drops non-hex palette entries", () => {
  const plan = normalizePlan({
    steps: ["a", "b", "c"],
    palette: ["sage green", "#8A9A7B", "kraft", "#4A4238"],
  });
  assert.deepEqual(plan.palette, ["#8A9A7B", "#4A4238"]);
});

test("normalizePlan rejects a plan that isn't a method", () => {
  assert.equal(normalizePlan({ title: "Nice", steps: ["just wrap it"] }), null);
  assert.equal(normalizePlan("I'm not able to help with that."), null);
  assert.equal(normalizePlan(""), null);
  assert.equal(normalizePlan(null), null);
});

test("canvas prompt strips brand names and caps length", () => {
  const plan = { imagePrompt: "a Stanley tumbler wrapped in kraft paper beside a YETI mug" };
  const prompt = buildCanvasPrompt(plan, ["Stanley", "YETI"]);
  assert.ok(!/stanley/i.test(prompt));
  assert.ok(!/yeti/i.test(prompt));
  assert.ok(prompt.length <= 600);
  assert.match(prompt, /flat lay/);
});

test("canvas prompt falls back to materials when the model gave none", () => {
  const prompt = buildCanvasPrompt({ materials: ["linen wrap", "twine"] });
  assert.match(prompt, /linen wrap/);
  assert.match(prompt, /twine/);
});

test("canvas prompt ignores brand tokens too short to be distinctive", () => {
  const prompt = buildCanvasPrompt({ imagePrompt: "an ax handle wrapped in linen" }, ["ax"]);
  assert.match(prompt, /ax handle/);
});
