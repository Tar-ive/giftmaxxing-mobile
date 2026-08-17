import test from "node:test";
import assert from "node:assert/strict";
import { createRecommenderV2 } from "./recommender-v2.mjs";

const product = (id, kind = "product") => ({
  entityId: id, entityType: "item", status: "active", kind, title: `Cozy gift ${id}`,
  taxonomy: { primaryCategoryId: "cozy", labelIds: ["cozy"] },
  commerce: { shoppability: "direct", offers: [{ price: 25, merchant: `store-${id}`, url: `https://example.com/${id}` }] },
  quality: { score: 0.8, giftable: true, mediaVerified: true, mediaSource: "retailer_listing" },
  media: [{ url: `https://example.com/${id}.jpg`, role: "primary" }],
  legacyPost: { postId: id, privateSourcePayload: true },
});

const curate = (item, version = "test-v1") => ({
  ...item,
  provenance: { type: "editorial", provider: "giftmaxxing-curation" },
  quality: {
    ...item.quality,
    curationStatus: "approved",
    curationCollectionId: "giftmaxxing-reviewed",
    curationCollectionVersion: version,
  },
});

function route(items = [product("a"), product("b"), product("c", "ugc_post")], activeVersion = "test-v1") {
  return createRecommenderV2({
    ddb: { send: async (command) => {
      if (command.input.Key?.entityId === "curation_collection:giftmaxxing-reviewed") {
        return activeVersion ? { Item: { activeVersion, itemIds: items.map((item) => item.entityId) } } : {};
      }
      if (command.input.RequestItems?.entities) {
        const ids = new Set(command.input.RequestItems.entities.Keys.map(({ entityId }) => entityId));
        return { Responses: { entities: items.filter((item) => ids.has(item.entityId)) } };
      }
      return command.input.TableName === "entities" ? { Items: items } : {};
    } },
    s3v: null, bedrock: null, s3: null,
    tables: { entities: "entities", edges: "edges", profiles: null, posts: null, analytics: "analytics" },
  });
}

test("taxonomy is server-readable", async () => {
  const response = await route()("GET", "/v2/feed-taxonomy");
  const body = JSON.parse(response.body);
  assert.equal(response.statusCode, 200);
  assert.ok(body.themes.some((theme) => theme.id === "for-you"));
});

test("home returns typed, ranked, attributed catalog items", async () => {
  const items = [curate(product("a")), curate(product("b")), curate(product("c", "ugc_post"))];
  const response = await route(items)("POST", "/v2/recommendations", { surface: "home", context: { themeId: "cozy" }, page: { limit: 3 } });
  const body = JSON.parse(response.body);
  assert.equal(response.statusCode, 200);
  assert.equal(body.items.length, 3);
  assert.equal(body.items[0].rank, 1);
  assert.equal(body.items[0].item.entityType, "item");
  assert.equal(body.items[0].item.legacyPost, undefined);
  assert.match(body.items[0].attributionToken, /\./);
  assert.equal(body.modelVersion, "deterministic-cosine-v1");
});

test("challenge surfaces admit only approved curated products", async () => {
  const approved = Array.from({ length: 16 }, (_, index) => {
    const item = curate(product(`approved-${index}`));
    item.taxonomy.primaryCategoryId = `category-${index % 8}`;
    return item;
  });
  const service = curate(product("approved-service", "service"));
  const wrongProvider = curate(product("wrong-provider"));
  wrongProvider.provenance.provider = "pinterest";
  const stale = curate(product("stale"), "old-v0");
  const response = await route([...approved, service, wrongProvider, stale, product("unreviewed")])(
    "POST", "/v2/recommendations", { surface: "challenge_learn", page: { limit: 14 } }
  );
  const body = JSON.parse(response.body);
  assert.equal(body.items.length, 14);
  assert.equal(body.curationVersion, "test-v1");
  assert.ok(body.items.every(({ item }) => item.kind === "product"
    && item.provenance.provider === "giftmaxxing-curation"
    && item.quality.curationCollectionVersion === "test-v1"));
});

test("challenge surfaces reject editorial images and unverified product media", async () => {
  const verified = curate(product("verified"));
  const editorial = curate(product("editorial"));
  editorial.quality.mediaVerified = false;
  editorial.quality.mediaSource = "curated_inspiration";
  const response = await route([verified, editorial])(
    "POST", "/v2/recommendations", { surface: "challenge_learn", page: { limit: 10 } }
  );
  assert.deepEqual(JSON.parse(response.body).items.map(({ item }) => item.entityId), ["verified"]);
});

test("theme All returns the union of child-tag inventory", async () => {
  const hiker = curate(product("hiker"));
  hiker.taxonomy.labelIds = ["hiker", "trail-gear"];
  const runner = curate(product("runner"));
  runner.taxonomy.labelIds = ["runner", "running"];
  const unrelated = curate(product("unrelated"));
  unrelated.taxonomy.labelIds = ["fragrance"];
  const response = await route([hiker, runner, unrelated])(
    "POST", "/v2/recommendations", {
      surface: "home", context: { themeId: "outdoors-and-active" }, page: { limit: 10 },
    }
  );
  assert.deepEqual(new Set(JSON.parse(response.body).items.map(({ item }) => item.entityId)), new Set(["hiker", "runner"]));
});

test("all mixer requests fail closed to the active reviewed collection", async () => {
  const current = curate(product("current"));
  const stale = curate(product("stale"), "old-v0");
  const wrongProvider = curate(product("wrong-provider"));
  wrongProvider.provenance.provider = "shopify";
  const request = { surface: "search", query: { text: "cozy" }, page: { limit: 10 } };

  const response = await route([current, stale, wrongProvider, product("unreviewed")])("POST", "/v2/recommendations", request);
  assert.deepEqual(JSON.parse(response.body).items.map(({ item }) => item.entityId), ["current"]);

  const missingPointer = await route([current], null)("POST", "/v2/recommendations", request);
  assert.equal(JSON.parse(missingPointer.body).items.length, 0);
});

test("recipient leaderboard falls back to approved catalog when analytics is sparse", async () => {
  const women = curate(product("women-pick"));
  women.taxonomy.labelIds = ["women", "beauty"];
  const response = await route([women])("POST", "/v2/recipient-leaderboard", { segment: "women", limit: 5 });
  const body = JSON.parse(response.body);
  assert.equal(response.statusCode, 200);
  assert.equal(body.items[0].item.entityId, "women-pick");
  assert.equal(body.items[0].score, 0);
});

test("reliability votes are accepted as item-quality labels", async () => {
  const writes = [];
  const handler = createRecommenderV2({
    ddb: { send: async (command) => { writes.push(command.input); return {}; } },
    s3v: null, bedrock: null, s3: null,
    tables: { entities: "entities", edges: "edges", profiles: null, posts: null, analytics: "analytics" },
  });
  const response = await handler("POST", "/v2/events/batch", {
    anonymousId: "anon-test",
    events: [{ eventId: "quality-1", type: "reliability_reliable", itemId: "p1", context: { labelSource: "post_15_swipe_poll" } }],
  });
  assert.equal(response.statusCode, 202);
  assert.equal(JSON.parse(response.body).accepted, 1);
  assert.equal(writes[0].RequestItems.analytics[0].PutRequest.Item.type, "recommender_reliability_reliable");
});
