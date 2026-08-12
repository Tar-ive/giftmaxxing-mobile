import { DynamoDBClient } from "@aws-sdk/client-dynamodb";
import { DynamoDBDocumentClient, GetCommand, UpdateCommand } from "@aws-sdk/lib-dynamodb";
import { CopyObjectCommand, DeleteObjectCommand, S3Client } from "@aws-sdk/client-s3";
import {
  DetectLabelsCommand,
  DetectModerationLabelsCommand,
  DetectTextCommand,
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
const postIdFromKey = (key) => {
  const parts = key.split("/");
  const file = parts.pop()?.split(".")[0];
  return /^\d+$/.test(file ?? "") ? parts.pop() : file;
};
const feedPk = (postId) => {
  const count = Math.max(1, Number(process.env.FEED_SHARDS || 1));
  if (count === 1) return "all";
  return `all#${parseInt(createHash("sha256").update(postId).digest("hex").slice(0, 8), 16) % count}`;
};

async function publish(item, labels, detectedText = []) {
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
  const shoppable = (item.productLinks ?? []).map((link, index) => ({
    postId: `${item.postId}-declared-${index}`,
    name: link.name,
    productUrl: link.url,
    merchant: (() => { try { return new URL(link.url).hostname.replace(/^www\./, ""); } catch { return null; } })(),
  }));
  await ddb.send(new UpdateCommand({
    TableName: POSTS,
    Key: { postId: item.postId },
    UpdateExpression: "SET moderationStatus = :approved, processingStatus = :ready, #status = :made, feedEligible = :yes, feedPk = :feed, publicKey = :publicKey, posterPublicKey = :posterPublicKey, mediaUrl = :mediaUrl, posterUrl = :posterUrl, product = :product, recommendationLabels = :labels, detectedText = :text, vibes = :vibes, category = :category, shoppable = :shoppable, updatedAt = :now REMOVE moderationReason",
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
      ":text": detectedText,
      ":vibes": labelNames.slice(0, 12),
      ":category": category,
      ":shoppable": shoppable,
      ":now": Date.now(),
    },
  }));
  await s3.send(new DeleteObjectCommand({ Bucket: MEDIA_BUCKET, Key: item.rawKey })).catch(() => {});
  if (item.posterRawKey) await s3.send(new DeleteObjectCommand({ Bucket: MEDIA_BUCKET, Key: item.posterRawKey })).catch(() => {});
}

async function publishCarousel(item, results) {
  const ordered = item.mediaItems.slice().sort((a, b) => a.index - b.index);
  const publicKeys = ordered.map((value) => `ugc/public/${item.postId}-${value.index}.${value.extension}`);
  await Promise.all(ordered.map((value, index) => s3.send(new CopyObjectCommand({
    Bucket: MEDIA_BUCKET,
    Key: publicKeys[index],
    CopySource: `${MEDIA_BUCKET}/${value.rawKey}`,
    ContentType: value.mimeType,
    MetadataDirective: "REPLACE",
  }))));
  const labels = recommendationLabels(Object.values(results).flatMap((value) => value.labels ?? []));
  const mediaUrls = publicKeys.map((key) => `/${key}`);
  const category = recommendationCategory(labels);
  const labelNames = labels.map((label) => label.name.toLowerCase());
  const shoppable = (item.productLinks ?? []).map((link, index) => ({
    postId: `${item.postId}-declared-${index}`,
    name: link.name,
    productUrl: link.url,
    merchant: (() => { try { return new URL(link.url).hostname.replace(/^www\./, ""); } catch { return null; } })(),
  }));
  await ddb.send(new UpdateCommand({
    TableName: POSTS,
    Key: { postId: item.postId },
    UpdateExpression: "SET moderationStatus = :approved, processingStatus = :ready, #status = :made, feedEligible = :yes, feedPk = :feed, publicKeys = :keys, mediaUrls = :urls, mediaUrl = :cover, posterUrl = :cover, product = :product, recommendationLabels = :labels, vibes = :vibes, category = :category, shoppable = :shoppable, updatedAt = :now REMOVE moderationReason",
    ExpressionAttributeNames: { "#status": "status" },
    ExpressionAttributeValues: {
      ":approved": "APPROVED",
      ":ready": "READY",
      ":made": "made",
      ":yes": true,
      ":feed": feedPk(item.postId),
      ":keys": publicKeys,
      ":urls": mediaUrls,
      ":cover": mediaUrls[0],
      ":product": { id: item.postId, name: item.caption.slice(0, 120), brand: item.authorName, price: 0, image: mediaUrls[0], images: mediaUrls },
      ":labels": labels,
      ":vibes": labelNames.slice(0, 12),
      ":category": category,
      ":shoppable": shoppable,
      ":now": Date.now(),
    },
  }));
  await Promise.all(ordered.map((value) => s3.send(new DeleteObjectCommand({
    Bucket: MEDIA_BUCKET,
    Key: value.rawKey,
  })).catch(() => {})));
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
  const rawKeys = item.mediaItems?.length ? item.mediaItems.map((value) => value.rawKey) : [item.rawKey];
  await Promise.all(rawKeys.map((Key) => s3.send(new DeleteObjectCommand({ Bucket: MEDIA_BUCKET, Key })).catch(() => {})));
  if (item.posterRawKey) await s3.send(new DeleteObjectCommand({ Bucket: MEDIA_BUCKET, Key: item.posterRawKey })).catch(() => {});
}

async function processCarouselImage(item, key) {
  const descriptor = item.mediaItems.find((value) => value.rawKey === key);
  if (!descriptor) return;
  const image = { S3Object: { Bucket: MEDIA_BUCKET, Name: key } };
  const [moderation, detected, text] = await Promise.all([
    rekognition.send(new DetectModerationLabelsCommand({ Image: image, MinConfidence: 50 })),
    rekognition.send(new DetectLabelsCommand({ Image: image, MaxLabels: 40, MinConfidence: 70 })),
    rekognition.send(new DetectTextCommand({ Image: image })),
  ]);
  const blocked = blockedModerationLabels(moderation.ModerationLabels);
  if (blocked.length) return reject(item, blocked);
  try {
    await ddb.send(new UpdateCommand({
      TableName: POSTS,
      Key: { postId: item.postId },
      UpdateExpression: "SET mediaResults.#index = :result, processingStatus = :processing, updatedAt = :now",
      ConditionExpression: "processingStatus <> :rejected",
      ExpressionAttributeNames: { "#index": String(descriptor.index) },
      ExpressionAttributeValues: {
        ":result": {
          labels: detected.Labels ?? [],
          text: (text.TextDetections ?? []).filter((value) => value.Type === "LINE" && value.Confidence >= 75).map((value) => value.DetectedText).slice(0, 30),
          moderatedAt: Date.now(),
        },
        ":processing": "MODERATING",
        ":rejected": "REJECTED",
        ":now": Date.now(),
      },
    }));
  } catch (error) {
    if (error.name === "ConditionalCheckFailedException") return;
    throw error;
  }
  const current = await ddb.send(new GetCommand({ TableName: POSTS, Key: { postId: item.postId }, ConsistentRead: true }));
  const results = current.Item?.mediaResults ?? {};
  if (current.Item?.processingStatus !== "REJECTED" && Object.keys(results).length === item.mediaItems.length) {
    await publishCarousel(current.Item, results);
  }
}

async function processImage(item) {
  const image = { S3Object: { Bucket: MEDIA_BUCKET, Name: item.rawKey } };
  const [moderation, detected, text] = await Promise.all([
    rekognition.send(new DetectModerationLabelsCommand({ Image: image, MinConfidence: 50 })),
    rekognition.send(new DetectLabelsCommand({ Image: image, MaxLabels: 40, MinConfidence: 70 })),
    rekognition.send(new DetectTextCommand({ Image: image })),
  ]);
  const blocked = blockedModerationLabels(moderation.ModerationLabels);
  if (blocked.length) return reject(item, blocked);
  const lines = (text.TextDetections ?? []).filter((value) => value.Type === "LINE" && value.Confidence >= 75).map((value) => value.DetectedText).slice(0, 30);
  return publish(item, recommendationLabels(detected.Labels), lines);
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
  const isCarouselItem = item?.mediaItems?.length > 1 && item.mediaItems.some((value) => value.rawKey === key);
  if (!item || (!isCarouselItem && item.rawKey !== key) || ["READY", "REJECTED"].includes(item.processingStatus)) return;
  try {
    await ddb.send(new UpdateCommand({
      TableName: POSTS,
      Key: { postId },
      UpdateExpression: "SET processingStatus = :processing, updatedAt = :now",
      ConditionExpression: "processingStatus <> :rejected AND processingStatus <> :ready",
      ExpressionAttributeValues: {
        ":processing": "MODERATING",
        ":rejected": "REJECTED",
        ":ready": "READY",
        ":now": Date.now(),
      },
    }));
  } catch (error) {
    if (error.name === "ConditionalCheckFailedException") return;
    throw error;
  }
  if (isCarouselItem) return processCarouselImage(item, key);
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
