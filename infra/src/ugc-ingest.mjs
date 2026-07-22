import { DynamoDBClient } from "@aws-sdk/client-dynamodb";
import { DynamoDBDocumentClient, GetCommand, UpdateCommand } from "@aws-sdk/lib-dynamodb";
import { CopyObjectCommand, DeleteObjectCommand, S3Client } from "@aws-sdk/client-s3";
import {
  DetectLabelsCommand,
  DetectModerationLabelsCommand,
  RekognitionClient,
  StartContentModerationCommand,
  StartLabelDetectionCommand,
} from "@aws-sdk/client-rekognition";
import { createHash } from "node:crypto";
import {
  blockedModerationLabels,
  recommendationCategory,
  recommendationLabels,
} from "./ugc-policy.mjs";

const ddb = DynamoDBDocumentClient.from(new DynamoDBClient({}), { marshallOptions: { removeUndefinedValues: true } });
const s3 = new S3Client({});
const rekognition = new RekognitionClient({});
const POSTS = process.env.POSTS_TABLE;
const MEDIA_BUCKET = process.env.MEDIA_BUCKET;
const SNS_TOPIC_ARN = process.env.UGC_REKOGNITION_TOPIC_ARN;
const REKOGNITION_ROLE_ARN = process.env.UGC_REKOGNITION_ROLE_ARN;

const token = (postId, kind) => createHash("sha256").update(`${postId}:${kind}`).digest("hex");
const postIdFromKey = (key) => key.split("/").pop()?.split(".")[0];
const feedPk = (postId) => {
  const count = Math.max(1, Number(process.env.FEED_SHARDS || 1));
  if (count === 1) return "all";
  return `all#${parseInt(createHash("sha256").update(postId).digest("hex").slice(0, 8), 16) % count}`;
};

async function publish(item, labels) {
  const extension = item.rawKey.split(".").pop();
  const publicKey = `ugc/public/${item.postId}.${extension}`;
  const posterPublicKey = item.mediaType === "video" ? `ugc/public/${item.postId}-poster.jpg` : publicKey;
  await s3.send(new CopyObjectCommand({ Bucket: MEDIA_BUCKET, Key: publicKey, CopySource: `${MEDIA_BUCKET}/${item.rawKey}`, ContentType: item.mimeType, MetadataDirective: "REPLACE" }));
  if (item.mediaType === "video" && item.posterRawKey) {
    await s3.send(new CopyObjectCommand({ Bucket: MEDIA_BUCKET, Key: posterPublicKey, CopySource: `${MEDIA_BUCKET}/${item.posterRawKey}`, ContentType: "image/jpeg", MetadataDirective: "REPLACE" }));
  }
  const category = recommendationCategory(labels);
  const labelNames = labels.map((label) => label.name.toLowerCase());
  const image = `/${posterPublicKey}`;
  await ddb.send(new UpdateCommand({
    TableName: POSTS,
    Key: { postId: item.postId },
    UpdateExpression: "SET moderationStatus = :approved, processingStatus = :ready, #status = :made, feedEligible = :yes, feedPk = :feed, publicKey = :publicKey, posterPublicKey = :posterPublicKey, mediaUrl = :mediaUrl, posterUrl = :posterUrl, product = :product, recommendationLabels = :labels, vibes = :vibes, category = :category, updatedAt = :now REMOVE moderationReason",
    ExpressionAttributeNames: { "#status": "status" },
    ExpressionAttributeValues: {
      ":approved": "APPROVED",
      ":ready": "READY",
      ":made": "made",
      ":yes": true,
      ":feed": feedPk(item.postId),
      ":publicKey": publicKey,
      ":posterPublicKey": posterPublicKey,
      ":mediaUrl": `/${publicKey}`,
      ":posterUrl": `/${posterPublicKey}`,
      ":product": { id: item.postId, name: item.caption.slice(0, 120), brand: item.authorName, price: 0, image },
      ":labels": labels,
      ":vibes": labelNames.slice(0, 12),
      ":category": category,
      ":now": Date.now(),
    },
  }));
  await s3.send(new DeleteObjectCommand({ Bucket: MEDIA_BUCKET, Key: item.rawKey })).catch(() => {});
  if (item.posterRawKey) await s3.send(new DeleteObjectCommand({ Bucket: MEDIA_BUCKET, Key: item.posterRawKey })).catch(() => {});
}

async function reject(item, blocked) {
  await ddb.send(new UpdateCommand({
    TableName: POSTS,
    Key: { postId: item.postId },
    UpdateExpression: "SET moderationStatus = :rejected, processingStatus = :rejected, feedEligible = :no, moderationReason = :reason, updatedAt = :now REMOVE feedPk",
    ExpressionAttributeValues: {
      ":rejected": "REJECTED",
      ":no": false,
      ":reason": blocked.map((label) => label.Name).filter(Boolean).slice(0, 6),
      ":now": Date.now(),
    },
  }));
  await s3.send(new DeleteObjectCommand({ Bucket: MEDIA_BUCKET, Key: item.rawKey })).catch(() => {});
  if (item.posterRawKey) await s3.send(new DeleteObjectCommand({ Bucket: MEDIA_BUCKET, Key: item.posterRawKey })).catch(() => {});
}

async function processImage(item) {
  const image = { S3Object: { Bucket: MEDIA_BUCKET, Name: item.rawKey } };
  const [moderation, detected] = await Promise.all([
    rekognition.send(new DetectModerationLabelsCommand({ Image: image, MinConfidence: 50 })),
    rekognition.send(new DetectLabelsCommand({ Image: image, MaxLabels: 40, MinConfidence: 70 })),
  ]);
  const blocked = blockedModerationLabels(moderation.ModerationLabels);
  if (blocked.length) return reject(item, blocked);
  return publish(item, recommendationLabels(detected.Labels));
}

async function processVideo(item) {
  if (!SNS_TOPIC_ARN || !REKOGNITION_ROLE_ARN) throw new Error("video moderation is not configured");
  const video = { S3Object: { Bucket: MEDIA_BUCKET, Name: item.rawKey } };
  const channel = { SNSTopicArn: SNS_TOPIC_ARN, RoleArn: REKOGNITION_ROLE_ARN };
  const [moderation, labels] = await Promise.all([
    rekognition.send(new StartContentModerationCommand({
      Video: video,
      MinConfidence: 50,
      ClientRequestToken: token(item.postId, "moderation"),
      JobTag: item.postId,
      NotificationChannel: channel,
    })),
    rekognition.send(new StartLabelDetectionCommand({
      Video: video,
      MinConfidence: 70,
      ClientRequestToken: token(item.postId, "labels"),
      JobTag: item.postId,
      NotificationChannel: channel,
    })),
  ]);
  await ddb.send(new UpdateCommand({
    TableName: POSTS,
    Key: { postId: item.postId },
    UpdateExpression: "SET processingStatus = :processing, moderationJobId = :moderation, labelsJobId = :labels, updatedAt = :now",
    ExpressionAttributeValues: { ":processing": "MODERATING", ":moderation": moderation.JobId, ":labels": labels.JobId, ":now": Date.now() },
  }));
}

async function processRecord(record) {
  const key = decodeURIComponent(record.s3.object.key.replace(/\+/g, " "));
  if (!key.startsWith("ugc/raw/")) return;
  const postId = postIdFromKey(key);
  if (!postId) return;
  const out = await ddb.send(new GetCommand({ TableName: POSTS, Key: { postId } }));
  const item = out.Item;
  if (!item || item.rawKey !== key || ["READY", "REJECTED"].includes(item.processingStatus)) return;
  await ddb.send(new UpdateCommand({
    TableName: POSTS,
    Key: { postId },
    UpdateExpression: "SET processingStatus = :processing, updatedAt = :now",
    ExpressionAttributeValues: { ":processing": "MODERATING", ":now": Date.now() },
  }));
  return item.mediaType === "video" ? processVideo(item) : processImage(item);
}

export const handler = async (event) => {
  for (const record of event.Records ?? []) {
    try {
      await processRecord(record);
    } catch (error) {
      console.error("UGC ingest failed", { key: record.s3?.object?.key, error: error.message });
      throw error;
    }
  }
};
