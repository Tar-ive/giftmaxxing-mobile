import test from "node:test";
import assert from "node:assert/strict";
import { applyTasteEvent } from "./taste-profile-stream.mjs";

const item = {
  kind: "product",
  taxonomy: { primaryCategoryId: "home", labelIds: ["cozy", "handmade"] },
  commerce: { offers: [{ price: 50 }] },
};

test("strong positive events update a subject profile", () => {
  const profile = applyTasteEvent({}, {
    eventId: "e1", type: "recommender_save", itemId: "p1", actorId: "u1", subjectProfileId: "taste:u1", timestamp: 1000,
  }, item);
  assert.equal(profile.ownerId, "u1");
  assert.equal(profile.version, 1);
  assert.deepEqual(profile.positiveItemIds, ["p1"]);
  assert.ok(profile.labelWeights.cozy > 1);
  assert.equal(profile.preferredPrice, 50);
});

test("duplicate stream delivery is idempotent", () => {
  const event = { eventId: "e1", type: "recommender_like", itemId: "p1", actorId: "u1", subjectProfileId: "taste:u1", timestamp: 1000 };
  const once = applyTasteEvent({}, event, item);
  const twice = applyTasteEvent(once, event, item);
  assert.deepEqual(twice, once);
});

test("a negative challenge answer moves the item to negative history", () => {
  const profile = applyTasteEvent({ positiveItemIds: ["p1"] }, {
    eventId: "e2", type: "recommender_challenge_no", itemId: "p1", actorId: "u1", subjectProfileId: "taste:u1", timestamp: 2000,
  }, item);
  assert.deepEqual(profile.positiveItemIds, []);
  assert.deepEqual(profile.negativeItemIds, ["p1"]);
  assert.ok(profile.labelWeights.cozy < 0);
});
