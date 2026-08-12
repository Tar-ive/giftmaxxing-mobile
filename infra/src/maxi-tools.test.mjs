import test from "node:test";
import assert from "node:assert/strict";
import {
  MAXI_TOOL_DEFINITIONS,
  MAXI_TOOL_NAMES,
  effectiveCatalogPrice,
  isCheaperRequest,
  normalizeMaxiToolInput,
  shownProductPriceCeiling,
} from "./maxi-tools.mjs";

test("Maxi exposes exactly the seven allowed primitives", () => {
  assert.deepEqual(MAXI_TOOL_DEFINITIONS.map(({ name }) => name), MAXI_TOOL_NAMES);
  assert.deepEqual(MAXI_TOOL_NAMES, [
    "memory_write", "memory_read", "calender_refer", "calender_update", "catalog_read", "cart_write", "cart_read",
  ]);
});

test("tool inputs are validated and unknown tools fail closed", () => {
  assert.equal(normalizeMaxiToolInput("find_gifts", {}).ok, false);
  assert.equal(normalizeMaxiToolInput("memory_write", {}).ok, false);
  assert.equal(normalizeMaxiToolInput("calender_update", { title: "Birthday", date: "tomorrow" }).ok, false);
  assert.deepEqual(normalizeMaxiToolInput("cart_write", { postIds: ["a", "b"] }).value.postIds, ["a", "b"]);
});

test("cheaper intent creates a strict server-side catalog ceiling", () => {
  assert.equal(isCheaperRequest("Can I get cheaper options?"), true);
  assert.equal(shownProductPriceCeiling([{ price: 89 }, { price: 38 }, { price: 18 }]), 18);
  assert.equal(effectiveCatalogPrice({ maxPrice: 50, cheaperThan: 30 }, 18), 18);
});
