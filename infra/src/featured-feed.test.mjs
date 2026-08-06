import assert from "node:assert/strict";
import test from "node:test";
import { prependFeatured } from "./featured-feed.mjs";

test("featured posts lead page one and are de-duplicated", () => {
  const page = [{ postId: "a" }, { postId: "featured" }, { postId: "b" }];
  const result = prependFeatured(page, [{ postId: "featured", caption: "Gift guide" }], 3);
  assert.deepEqual(result.map((item) => item.postId), ["featured", "a", "b"]);
  assert.equal(result[0].featured, true);
});

test("featured posts respect the requested page size", () => {
  const result = prependFeatured([{ postId: "a" }], [{ postId: "featured" }], 1);
  assert.deepEqual(result.map((item) => item.postId), ["featured"]);
});
