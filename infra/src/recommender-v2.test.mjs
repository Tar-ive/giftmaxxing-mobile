import test from "node:test";
import assert from "node:assert/strict";
import { createRecommenderV2 } from "./recommender-v2.mjs";

const product = (id, kind = "product") => ({
  entityId: id, entityType: "item", status: "active", kind, title: `Cozy gift ${id}`,
  taxonomy: { primaryCategoryId: "cozy", labelIds: ["cozy"] },
  commerce: { shoppability: "direct", offers: [{ price: 25, merchant: `store-${id}`, url: `https://example.com/${id}` }] },
  quality: { score: 0.8, giftable: true }, media: [{ url: `https://example.com/${id}.jpg`, role: "primary" }],
  legacyPost: { postId: id, privateSourcePayload: true },
});

function route(items = [product("a"), product("b"), product("c", "ugc_post")]) {
  return createRecommenderV2({
    ddb: { send: async (command) => command.input.TableName === "entities" ? { Items: items } : {} },
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
  const response = await route()("POST", "/v2/recommendations", { surface: "home", context: { themeId: "cozy" }, page: { limit: 3 } });
  const body = JSON.parse(response.body);
  assert.equal(response.statusCode, 200);
  assert.equal(body.items.length, 3);
  assert.equal(body.items[0].rank, 1);
  assert.equal(body.items[0].item.entityType, "item");
  assert.equal(body.items[0].item.legacyPost, undefined);
  assert.match(body.items[0].attributionToken, /\./);
  assert.equal(body.modelVersion, "deterministic-cosine-v1");
});
