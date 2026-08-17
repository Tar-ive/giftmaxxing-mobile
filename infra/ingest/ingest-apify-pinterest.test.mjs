import test from "node:test";
import assert from "node:assert/strict";
import { curate, scorePin } from "./ingest-apify-pinterest.mjs";

const pin = (id, extra = {}) => ({
  id, title: "DIY personalized photo memory gift for a best friend", description: "Thoughtful birthday present",
  imageUrl: `https://i.pinimg.com/originals/${id}.jpg`, url: `https://www.pinterest.com/pin/${id}/`,
  saves: 200, pinnerUsername: `maker-${id}`, ...extra,
});

test("keeps strong gift inspiration", () => {
  const quality = scorePin(pin("1"));
  assert.equal(quality.accepted, true);
  assert.ok(quality.score >= 70);
});

test("rejects missing images and video", () => {
  assert.equal(scorePin(pin("2", { imageUrl: null })).accepted, false);
  assert.equal(scorePin(pin("3", { isVideo: true })).accepted, false);
});

test("curation deduplicates creators and images", () => {
  const items = [
    pin("1"), pin("2", { pinnerUsername: "maker-1" }),
    pin("3"), pin("4", { imageUrl: "https://i.pinimg.com/originals/3.jpg" }),
  ];
  const out = curate(items, { maxPins: 4, queries: ["thoughtful birthday gift ideas"], perCarousel: 6, minScore: 50 });
  assert.equal(out.carousels[0].selected.length, 2);
});

