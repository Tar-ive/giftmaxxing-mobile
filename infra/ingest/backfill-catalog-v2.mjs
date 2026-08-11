#!/usr/bin/env node
import { DynamoDBClient } from "@aws-sdk/client-dynamodb";
import { BatchWriteCommand, DynamoDBDocumentClient, ScanCommand } from "@aws-sdk/lib-dynamodb";
import { setTimeout as delay } from "node:timers/promises";
import { normalizeLegacyPost } from "../src/catalog-v2.mjs";
import { classifyPin } from "../src/quality.mjs";

const apply = process.argv.includes("--apply");
const read = (name, fallback) => process.argv.includes(name) ? process.argv[process.argv.indexOf(name) + 1] : fallback;
const prefix = process.env.ENV_PREFIX || "giftmaxxing-dev";
const postsTable = process.env.POSTS_TABLE || `${prefix}-posts`;
const entitiesTable = process.env.CATALOG_ENTITIES_TABLE || `${prefix}-catalog-entities`;
const edgesTable = process.env.CATALOG_EDGES_TABLE || `${prefix}-catalog-edges`;
const limit = Number(read("--limit", "0"));
const ddb = DynamoDBDocumentClient.from(new DynamoDBClient({ region: process.env.AWS_REGION || "us-east-1" }), { marshallOptions: { removeUndefinedValues: true } });
let start, scanned = 0, eligible = 0, written = 0;

async function batch(table, items) {
  if (!apply) return;
  const key = table === entitiesTable ? (item) => item.entityId : (item) => `${item.fromId}\0${item.edgeKey}`;
  const unique = [...new Map(items.map((item) => [key(item), item])).values()];
  for (let i = 0; i < unique.length; i += 25) {
    let pending = unique.slice(i, i + 25).map((Item) => ({ PutRequest: { Item } }));
    for (let attempt = 0; pending.length && attempt < 8; attempt++) {
      const result = await ddb.send(new BatchWriteCommand({ RequestItems: { [table]: pending } }));
      pending = result.UnprocessedItems?.[table] || [];
      if (pending.length) await delay(50 * 2 ** attempt);
    }
    if (pending.length) throw new Error(`${pending.length} ${table} writes remained unprocessed`);
  }
}

do {
  const page = await ddb.send(new ScanCommand({ TableName: postsTable, ExclusiveStartKey: start, Limit: limit ? Math.min(100, limit - scanned) : 100 }));
  scanned += page.Items?.length || 0;
  const entities = [], edges = [];
  for (const post of page.Items || []) {
    const product = post.product || {};
    const quality = classifyPin({ title: product.name || post.caption, domain: post.domain || product.brand, link: post.productUrl || post.url || product.url, price: post.price ?? product.price, giftType: post.giftType });
    if (!quality.feedEligible && post.source !== "ugc") continue;
    const item = normalizeLegacyPost({ ...post, feedEligible: true, qualityScore: post.qualityScore ?? quality.score });
    entities.push(item); eligible++;
    for (const assertion of item.taxonomy.assertions) {
      const labelId = `label:${assertion.labelId}`;
      entities.push({ entityId: labelId, entityType: "label", schemaVersion: 2, title: assertion.labelId, status: "active", updatedAt: Date.now() });
      edges.push({ fromId: item.entityId, edgeKey: `HAS_LABEL#${labelId}`, toId: labelId, reverseKey: `HAS_LABEL#${item.entityId}`, relation: "HAS_LABEL", evidence: assertion });
    }
    for (const offer of item.commerce.offers) {
      entities.push({ entityId: offer.offerId, entityType: "offer", schemaVersion: 2, ...offer, status: "active", updatedAt: Date.now() });
      edges.push({ fromId: item.entityId, edgeKey: `AVAILABLE_AS#${offer.offerId}`, toId: offer.offerId, reverseKey: `AVAILABLE_AS#${item.entityId}`, relation: "AVAILABLE_AS" });
    }
  }
  await batch(entitiesTable, entities); await batch(edgesTable, edges); written += entities.length;
  start = page.LastEvaluatedKey;
} while (start && (!limit || scanned < limit));
console.log(JSON.stringify({ mode: apply ? "apply" : "dry-run", scanned, eligible, entities: written }));
