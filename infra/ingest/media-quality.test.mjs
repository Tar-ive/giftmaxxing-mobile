import assert from "node:assert/strict";
import test from "node:test";
import { evaluateMediaQuality, imageDimensions } from "./media-quality.mjs";

test("accepts a high-resolution product image as a primary", () => {
  const quality = evaluateMediaQuality({ url: "https://brand.com/product/front.png", width: 1400, height: 1400 });
  assert.equal(quality.primaryEligible, true);
  assert.equal(quality.status, "approved_primary");
});

test("rejects low-resolution and text-heavy marketing media", () => {
  const quality = evaluateMediaQuality({
    url: "https://brand.com/social-banner.jpg", width: 600, height: 400,
    detectedText: Array.from({ length: 9 }, (_, index) => `line ${index}`),
  });
  assert.equal(quality.primaryEligible, false);
  assert.equal(quality.galleryEligible, false);
  assert.deepEqual(quality.reasons, ["low_resolution", "marketing_or_thumbnail_url", "text_heavy"]);
});

test("reads PNG dimensions", () => {
  const bytes = Buffer.alloc(24);
  bytes.write("PNG", 1);
  bytes.writeUInt32BE(1200, 16);
  bytes.writeUInt32BE(1600, 20);
  assert.deepEqual(imageDimensions(bytes, "image/png"), { width: 1200, height: 1600 });
});
