import assert from "node:assert/strict";
import test from "node:test";

import { parseJsonl, sourceImages, verifySelection } from "./curate-tiktok-pilot.mjs";

test("parseJsonl reports the broken source line", () => {
  assert.throws(() => parseJsonl('{"id":"1"}\nnope'), /line 2/);
});

test("verifySelection keeps only explicitly approved source IDs", () => {
  const rows = [
    { id: "approved", playCount: 10, diggCount: 2, collectCount: 1 },
    { id: "rejected", playCount: 1000 },
  ];
  const manifest = { journeys: [{
    sourcePostId: "approved",
    sourceUrl: "https://example.com/approved",
    title: "Reviewed",
    imageCount: 1,
    productIds: ["verified-product"],
  }] };
  const result = verifySelection(rows, manifest);
  assert.deepEqual(result.approved.map((item) => item.sourcePostId), ["approved"]);
  assert.deepEqual(result.rejectedSourceIds, ["rejected"]);
});

test("verifySelection fails closed when an approved source is absent", () => {
  assert.throws(() => verifySelection([], { journeys: [{
    sourcePostId: "missing", title: "Missing", imageCount: 1, productIds: [],
  }] }), /missing from JSONL/);
});

test("sourceImages uses every slide and falls back to the video cover", () => {
  assert.deepEqual(sourceImages({ slideshowImageLinks: [
    { downloadLink: "https://example.com/1.jpg" },
    { tiktokLink: "https://example.com/2.jpg" },
  ] }), ["https://example.com/1.jpg", "https://example.com/2.jpg"]);
  assert.deepEqual(sourceImages({ videoMeta: { coverUrl: "https://example.com/cover.jpg" } }), [
    "https://example.com/cover.jpg",
  ]);
});
