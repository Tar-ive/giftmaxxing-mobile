#!/usr/bin/env node
// One-off: backfill `aspectRatio` onto already-ingested Instagram posts.
//
// The dimensions were in the Apify payload all along; the first ingest simply
// didn't store them, so every card fell back to an editorial crop. This reads
// the same dataset dump and updates ONLY that attribute — no re-upload, no
// re-embed, nothing else touched.
import { readFile } from "node:fs/promises";
import { aspectOf } from "./ingest-apify-instagram.mjs";

const file = process.argv[2] || "/tmp/gift1dea.json";
const apply = process.argv.includes("--apply");
const table = process.env.POSTS_TABLE || "giftmaxxing-dev-posts";
const region = process.env.AWS_REGION || "us-east-1";

const items = JSON.parse(await readFile(file, "utf8"));
const updates = items
  .map((item) => ({ postId: `ig-${item.shortCode || item.id}`, aspectRatio: aspectOf(item) }))
  .filter((u) => u.aspectRatio != null);

const shapes = updates.reduce((acc, u) => {
  const key = u.aspectRatio < 0.9 ? "portrait" : u.aspectRatio > 1.1 ? "landscape" : "square";
  acc[key] = (acc[key] || 0) + 1;
  return acc;
}, {});
console.log(`${updates.length} posts have real dimensions`);
console.log(`shapes: ${Object.entries(shapes).map(([k, v]) => `${k}=${v}`).join("  ")}`);

if (!apply) {
  console.log("\nDry run — pass --apply to write.");
  process.exit(0);
}

const { DynamoDBClient } = await import("@aws-sdk/client-dynamodb");
const { DynamoDBDocumentClient, UpdateCommand } = await import("@aws-sdk/lib-dynamodb");
const ddb = DynamoDBDocumentClient.from(new DynamoDBClient({ region }));

let written = 0;
for (const u of updates) {
  try {
    await ddb.send(new UpdateCommand({
      TableName: table,
      // POSTS is keyed on postId alone.
      Key: { postId: u.postId },
      UpdateExpression: "SET aspectRatio = :a",
      ExpressionAttributeValues: { ":a": u.aspectRatio },
      // Never CREATE a row here — only patch ones the ingest already wrote.
      ConditionExpression: "attribute_exists(postId)",
    }));
    written++;
  } catch (error) {
    if (error.name !== "ConditionalCheckFailedException") throw error;
  }
}
console.log(`Updated ${written} rows in ${table}`);
