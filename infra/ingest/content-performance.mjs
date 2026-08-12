#!/usr/bin/env node
import { writeFile } from "node:fs/promises";
import { DynamoDBClient } from "@aws-sdk/client-dynamodb";
import { DynamoDBDocumentClient, ScanCommand } from "@aws-sdk/lib-dynamodb";

const read = (flag, fallback) => process.argv.includes(flag) ? process.argv[process.argv.indexOf(flag) + 1] : fallback;
const days = Math.max(1, Number(read("--days", "30")));
const out = read("--out", `content-performance-${new Date().toISOString().slice(0, 10)}.json`);
const table = process.env.ANALYTICS_TABLE || `${process.env.ENV_PREFIX || "giftmaxxing-dev"}-analytics`;
const cutoff = Date.now() - days * 86400_000;
const ddb = DynamoDBDocumentClient.from(new DynamoDBClient({ region: process.env.AWS_REGION || "us-east-1" }));
const byPost = new Map();
let cursor;

do {
  const page = await ddb.send(new ScanCommand({
    TableName: table,
    ExclusiveStartKey: cursor,
    FilterExpression: "#timestamp >= :cutoff AND attribute_exists(postId)",
    ExpressionAttributeNames: { "#timestamp": "timestamp" },
    ExpressionAttributeValues: { ":cutoff": cutoff },
  }));
  for (const event of page.Items ?? []) {
    const postId = event.postId || event.itemId;
    if (!postId) continue;
    const row = byPost.get(postId) || { postId, impressions: 0, dwell: 0, likes: 0, comments: 0, saves: 0, hides: 0, offerClicks: 0, purchases: 0 };
    const type = String(event.type || "").replace(/^recommender_/, "").replace(/^content_/, "");
    const key = ({ impression: "impressions", feed_impression: "impressions", dwell: "dwell", feed_dwell: "dwell", like: "likes", comment: "comments", save: "saves", hide: "hides", offer_click: "offerClicks", product_affiliate_click: "offerClicks", purchase: "purchases" })[type];
    if (key) row[key]++;
    byPost.set(postId, row);
  }
  cursor = page.LastEvaluatedKey;
} while (cursor);

const ratio = (value, total) => total ? Number((value / total).toFixed(4)) : 0;
const rows = [...byPost.values()].map((row) => ({
  ...row,
  engagementRate: ratio(row.likes + row.comments + row.saves, row.impressions),
  hideRate: ratio(row.hides, row.impressions),
  commerceRate: ratio(row.offerClicks + row.purchases, row.impressions),
  qualityScore: Number(((row.likes * 3 + row.comments * 4 + row.saves * 5 + row.offerClicks * 6 + row.purchases * 15 - row.hides * 5) / Math.max(10, row.impressions)).toFixed(4)),
})).sort((a, b) => b.qualityScore - a.qualityScore);
await writeFile(out, `${JSON.stringify({ generatedAt: new Date().toISOString(), days, rows }, null, 2)}\n`);
console.log(JSON.stringify({ out, posts: rows.length, best: rows.slice(0, 10), worst: rows.slice(-10).reverse() }, null, 2));
