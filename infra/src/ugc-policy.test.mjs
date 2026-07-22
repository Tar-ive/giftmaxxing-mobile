import test from "node:test";
import assert from "node:assert/strict";
import {
  blockedModerationLabels,
  recommendationCategory,
  recommendationLabels,
} from "./ugc-policy.mjs";

test("blocks high-confidence sexual and violent content", () => {
  const labels = [
    { Name: "Explicit Nudity", ParentName: "Explicit", Confidence: 99 },
    { Name: "Physical Violence", ParentName: "Violence", Confidence: 88 },
  ];
  assert.deepEqual(blockedModerationLabels(labels), labels);
});

test("does not block low-confidence or benign labels", () => {
  const labels = [
    { Name: "Explicit Nudity", ParentName: "Explicit", Confidence: 32 },
    { Name: "Kissing", ParentName: "Non-Explicit Nudity of Intimate parts and Kissing", Confidence: 91 },
  ];
  assert.deepEqual(blockedModerationLabels(labels), []);
});

test("deduplicates labels for recommendation metadata", () => {
  const labels = recommendationLabels([
    { Label: { Name: "Shoe", Confidence: 91 } },
    { Label: { Name: "Shoe", Confidence: 96 } },
    { Label: { Name: "Person", Confidence: 60 } },
  ]);
  assert.deepEqual(labels, [{ name: "Shoe", confidence: 96 }]);
  assert.equal(recommendationCategory(labels), "fashion");
});
