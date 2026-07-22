import { DynamoDBClient } from "@aws-sdk/client-dynamodb";
import { DynamoDBDocumentClient, GetCommand, UpdateCommand } from "@aws-sdk/lib-dynamodb";
import {
  GetContentModerationCommand,
  GetLabelDetectionCommand,
  RekognitionClient,
} from "@aws-sdk/client-rekognition";
import { CopyObjectCommand, DeleteObjectCommand, S3Client } from "@aws-sdk/client-s3";
import { createHash } from "node:crypto";
import { blockedModerationLabels, recommendationCategory, recommendationLabels } from "./ugc-policy.mjs";

const ddb = DynamoDBDocumentClient.from(new DynamoDBClient({}), { marshallOptions: { removeUndefinedValues: true } });
const rekognition = new RekognitionClient({});
const s3 = new S3Client({});
const POSTS = process.env.POSTS_TABLE;
const MEDIA_BUCKET = process.env.MEDIA_BUCKET;

const feedPk = (postId) => {
  const count = Math.max(1, Number(process.env.FEED_SHARDS || 1));
  if (count === 1) return "all";
  return `all#${parseInt(createHash("sha256").update(postId).digest("hex").slice(0, 8), 16) % count}`;
};

async function allResults(Command, key, JobId) {
  const items = [];
  let NextToken;
  do {
    const page = await rekognition.send(new Command({ JobId, NextToken }));
    items.push(...(page[key] ?? []));
    NextToken = page.NextToken;
  } while (NextToken);
  return items;
}

async function maybePublish(postId) {
  const out = await ddb.send(new GetCommand({ TableName: POSTS, Key: { postId } }));
  const item = out.Item;
  if (!item || item.processingStatus === "REJECTED" || item.processingStatus === "READY") return;
  if (!item.moderationDone || !item.labelsDone) return;
  const extension = item.rawKey.split(".").pop();
  const publicKey = `ugc/public/${postId}.${extension}`;
  const posterPublicKey = `ugc/public/${postId}-poster.jpg`;
  await s3.send(new CopyObjectCommand({ Bucket: MEDIA_BUCKET, Key: publicKey, CopySource: `${MEDIA_BUCKET}/${item.rawKey}`, ContentType: item.mimeType, MetadataDirective: "REPLACE" }));
  if (item.posterRawKey) {
    await s3.send(new CopyObjectCommand({ Bucket: MEDIA_BUCKET, Key: posterPublicKey, CopySource: `${MEDIA_BUCKET}/${item.posterRawKey}`, ContentType: "image/jpeg", MetadataDirective: "REPLACE" }));
  }
  const labels = item.recommendationLabels ?? [];
  await ddb.send(new UpdateCommand({
    TableName: POSTS,
    Key: { postId },
    UpdateExpression: "SET moderationStatus = :approved, processingStatus = :ready, #status = :made, feedEligible = :yes, feedPk = :feed, publicKey = :publicKey, posterPublicKey = :posterPublicKey, mediaUrl = :mediaUrl, posterUrl = :posterUrl, product = :product, vibes = :vibes, category = :category, updatedAt = :now",
    ExpressionAttributeNames: { "#status": "status" },
    ExpressionAttributeValues: {
      ":approved": "APPROVED",
      ":ready": "READY",
      ":made": "made",
      ":yes": true,
      ":feed": feedPk(postId),
      ":publicKey": publicKey,
      ":posterPublicKey": posterPublicKey,
      ":mediaUrl": `/${publicKey}`,
      ":posterUrl": `/${posterPublicKey}`,
      ":product": { id: postId, name: item.caption.slice(0, 120), brand: item.authorName, price: 0, image: `/${posterPublicKey}` },
      ":vibes": labels.map((label) => label.name.toLowerCase()).slice(0, 12),
      ":category": recommendationCategory(labels),
      ":now": Date.now(),
    },
  }));
  await s3.send(new DeleteObjectCommand({ Bucket: MEDIA_BUCKET, Key: item.rawKey })).catch(() => {});
  if (item.posterRawKey) await s3.send(new DeleteObjectCommand({ Bucket: MEDIA_BUCKET, Key: item.posterRawKey })).catch(() => {});
}

async function reject(postId, item, blocked) {
  await ddb.send(new UpdateCommand({
    TableName: POSTS,
    Key: { postId },
    UpdateExpression: "SET moderationDone = :yes, moderationStatus = :rejected, processingStatus = :rejected, feedEligible = :no, moderationReason = :reason, updatedAt = :now REMOVE feedPk",
    ExpressionAttributeValues: { ":yes": true, ":rejected": "REJECTED", ":no": false, ":reason": blocked.map((label) => label.Name).filter(Boolean).slice(0, 6), ":now": Date.now() },
  }));
  await s3.send(new DeleteObjectCommand({ Bucket: MEDIA_BUCKET, Key: item.rawKey })).catch(() => {});
  if (item.posterRawKey) await s3.send(new DeleteObjectCommand({ Bucket: MEDIA_BUCKET, Key: item.posterRawKey })).catch(() => {});
}

async function processNotification(notification) {
  const postId = notification.JobTag;
  if (!postId) return;
  const out = await ddb.send(new GetCommand({ TableName: POSTS, Key: { postId } }));
  const item = out.Item;
  if (!item || item.source !== "ugc") return;
  if (notification.Status !== "SUCCEEDED") {
    await ddb.send(new UpdateCommand({
      TableName: POSTS,
      Key: { postId },
      UpdateExpression: "SET processingStatus = :failed, processingError = :error, updatedAt = :now",
      ExpressionAttributeValues: { ":failed": "FAILED", ":error": `${notification.API} ${notification.Status}`, ":now": Date.now() },
    }));
    return;
  }
  if (notification.API === "StartContentModeration") {
    const moderation = await allResults(GetContentModerationCommand, "ModerationLabels", notification.JobId);
    const labels = moderation.map((entry) => entry.ModerationLabel).filter(Boolean);
    const blocked = blockedModerationLabels(labels);
    if (blocked.length) return reject(postId, item, blocked);
    await ddb.send(new UpdateCommand({
      TableName: POSTS,
      Key: { postId },
      UpdateExpression: "SET moderationDone = :yes, moderationStatus = :approved, updatedAt = :now",
      ExpressionAttributeValues: { ":yes": true, ":approved": "APPROVED", ":now": Date.now() },
    }));
  } else if (notification.API === "StartLabelDetection") {
    const detected = await allResults(GetLabelDetectionCommand, "Labels", notification.JobId);
    await ddb.send(new UpdateCommand({
      TableName: POSTS,
      Key: { postId },
      UpdateExpression: "SET labelsDone = :yes, recommendationLabels = :labels, updatedAt = :now",
      ExpressionAttributeValues: { ":yes": true, ":labels": recommendationLabels(detected), ":now": Date.now() },
    }));
  }
  await maybePublish(postId);
}

export const handler = async (event) => {
  for (const record of event.Records ?? []) {
    const notification = JSON.parse(record.Sns?.Message ?? "{}");
    try {
      await processNotification(notification);
    } catch (error) {
      console.error("UGC result processing failed", { notification, error: error.message });
      throw error;
    }
  }
};
