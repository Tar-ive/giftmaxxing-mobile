import { DynamoDBClient } from "@aws-sdk/client-dynamodb";
import { DynamoDBDocumentClient, GetCommand, PutCommand } from "@aws-sdk/lib-dynamodb";

const ddb = DynamoDBDocumentClient.from(new DynamoDBClient({}), { marshallOptions: { removeUndefinedValues: true } });
const PROFILES = process.env.TASTE_PROFILES_TABLE;
const ENTITIES = process.env.CATALOG_ENTITIES_TABLE;
const POSTS = process.env.POSTS_TABLE;
const HALF_LIFE_MS = 30 * 86400 * 1000;
const HISTORY_CAP = 24;
const EVENT_CAP = 200;

const WEIGHTS = {
  recommender_impression: 0.02,
  recommender_dwell: 0.12,
  recommender_search_tap: 0.5,
  recommender_like: 1,
  recommender_save: 1.6,
  recommender_hide: -1.2,
  recommender_offer_click: 1.1,
  recommender_purchase: 2.5,
  recommender_challenge_yes: 1.8,
  recommender_challenge_no: -1.5,
  recommender_challenge_uncertain: 0,
  // Quality labels belong to the item, not the person's taste profile.
  recommender_reliability_reliable: 0,
  recommender_reliability_questionable: 0,
};

const positive = (type) => ["recommender_like", "recommender_save", "recommender_offer_click", "recommender_purchase", "recommender_challenge_yes"].includes(type);
const negative = (type) => ["recommender_hide", "recommender_challenge_no"].includes(type);
const capped = (id, values = [], cap = HISTORY_CAP) => [id, ...values.filter((value) => value !== id)].slice(0, cap);

export function applyTasteEvent(profile = {}, event, item = {}) {
  if (!event?.eventId || !event?.type || !event?.itemId) return profile;
  if ((profile.processedEventIds ?? []).includes(event.eventId)) return profile;
  const now = Number(event.timestamp) || Date.now();
  const elapsed = Math.max(0, now - Number(profile.lastEventAt || now));
  const decay = Math.pow(0.5, elapsed / HALF_LIFE_MS);
  const weight = WEIGHTS[event.type] ?? 0;
  const labels = [...new Set([...(item.taxonomy?.labelIds ?? []), item.taxonomy?.primaryCategoryId].filter(Boolean))];
  const labelWeights = Object.fromEntries(Object.entries(profile.labelWeights ?? {}).map(([key, value]) => [key, Number(value) * decay]));
  for (const label of labels) labelWeights[label] = (labelWeights[label] || 0) + weight;
  const kindWeights = Object.fromEntries(Object.entries(profile.kindWeights ?? {}).map(([key, value]) => [key, Number(value) * decay]));
  if (item.kind) kindWeights[item.kind] = (kindWeights[item.kind] || 0) + weight;
  const price = Number(item.commerce?.offers?.[0]?.price);
  const priceWeight = Math.max(0, Number(profile.priceWeight || 0) * decay + (weight > 0 && Number.isFinite(price) ? weight : 0));
  const priceSum = Number(profile.priceSum || 0) * decay + (weight > 0 && Number.isFinite(price) ? price * weight : 0);
  let positiveItemIds = profile.positiveItemIds ?? [];
  let negativeItemIds = profile.negativeItemIds ?? [];
  if (positive(event.type)) {
    positiveItemIds = capped(event.itemId, positiveItemIds);
    negativeItemIds = negativeItemIds.filter((id) => id !== event.itemId);
  } else if (negative(event.type)) {
    negativeItemIds = capped(event.itemId, negativeItemIds);
    positiveItemIds = positiveItemIds.filter((id) => id !== event.itemId);
  }
  const uncertainty = Object.fromEntries(Object.entries(labelWeights).map(([label, value]) => [label, 1 / (1 + Math.abs(value))]));
  if (event.type === "recommender_challenge_uncertain") for (const label of labels) uncertainty[label] = 1;
  return {
    ...profile,
    profileId: event.subjectProfileId,
    ownerId: profile.ownerId || event.actorId,
    profileType: profile.profileType || (String(event.subjectProfileId).startsWith("taste:guest:") ? "guest" : "person"),
    status: profile.status || "active",
    consent: profile.consent || "implicit_app_use",
    version: Number(profile.version || 0) + 1,
    labelWeights,
    kindWeights,
    uncertainty,
    positiveItemIds,
    negativeItemIds,
    priceSum,
    priceWeight,
    preferredPrice: priceWeight > 0 ? priceSum / priceWeight : null,
    eventCount: Number(profile.eventCount || 0) + 1,
    processedEventIds: capped(event.eventId, profile.processedEventIds ?? [], EVENT_CAP),
    lastEventAt: now,
    updatedAt: Date.now(),
  };
}

function fromAttribute(value) {
  if (!value) return undefined;
  if ("S" in value) return value.S;
  if ("N" in value) return Number(value.N);
  if ("BOOL" in value) return value.BOOL;
  if ("NULL" in value) return null;
  if ("L" in value) return value.L.map(fromAttribute);
  if ("M" in value) return Object.fromEntries(Object.entries(value.M).map(([key, entry]) => [key, fromAttribute(entry)]));
  if ("SS" in value) return value.SS;
  return undefined;
}

function unmarshall(image = {}) {
  return Object.fromEntries(Object.entries(image).map(([key, value]) => [key, fromAttribute(value)]));
}

async function loadItem(itemId) {
  if (ENTITIES) {
    const out = await ddb.send(new GetCommand({ TableName: ENTITIES, Key: { entityId: itemId } }));
    if (out.Item) return out.Item;
  }
  if (!POSTS) return {};
  const out = await ddb.send(new GetCommand({ TableName: POSTS, Key: { postId: itemId } }));
  const post = out.Item ?? {};
  return {
    kind: post.source === "ugc" ? "ugc_post" : post.giftType === "service" ? "service" : "product",
    taxonomy: { primaryCategoryId: post.category, labelIds: post.vibes ?? [] },
    commerce: { offers: [{ price: Number(post.price ?? post.product?.price) || null }] },
  };
}

async function project(event) {
  if (!PROFILES || !event.subjectProfileId) return;
  const item = await loadItem(event.itemId);
  for (let attempt = 0; attempt < 3; attempt++) {
    const current = await ddb.send(new GetCommand({ TableName: PROFILES, Key: { profileId: event.subjectProfileId }, ConsistentRead: true }));
    if ((current.Item?.processedEventIds ?? []).includes(event.eventId)) return;
    const next = applyTasteEvent(current.Item, event, item);
    try {
      await ddb.send(new PutCommand({
        TableName: PROFILES,
        Item: next,
        ConditionExpression: current.Item ? "#version = :expected" : "attribute_not_exists(profileId)",
        ExpressionAttributeNames: current.Item ? { "#version": "version" } : undefined,
        ExpressionAttributeValues: current.Item ? { ":expected": current.Item.version } : undefined,
      }));
      return;
    } catch (error) {
      if (error.name !== "ConditionalCheckFailedException" || attempt === 2) throw error;
    }
  }
}

export const handler = async (streamEvent) => {
  const failures = [];
  for (const record of streamEvent.Records ?? []) {
    if (record.eventName !== "INSERT") continue;
    const row = unmarshall(record.dynamodb?.NewImage);
    if (!String(row.type || "").startsWith("recommender_")) continue;
    try {
      await project({
        eventId: row.eventId,
        type: row.type,
        itemId: row.itemId || row.postId,
        actorId: row.userId,
        subjectProfileId: row.subjectProfileId || `taste:${row.userId}`,
        timestamp: row.timestamp,
      });
    } catch (error) {
      console.error("taste profile projection failed", { eventId: row.eventId, error: error.message });
      failures.push({ itemIdentifier: record.eventID });
    }
  }
  return { batchItemFailures: failures };
};
