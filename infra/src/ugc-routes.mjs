import { createHash, randomUUID } from "node:crypto";
import { DynamoDBClient } from "@aws-sdk/client-dynamodb";
import {
  BatchWriteCommand,
  DynamoDBDocumentClient,
  GetCommand,
  PutCommand,
  QueryCommand,
  UpdateCommand,
} from "@aws-sdk/lib-dynamodb";
import {
  DeleteObjectsCommand,
  HeadObjectCommand,
  PutObjectCommand,
  S3Client,
} from "@aws-sdk/client-s3";
import { getSignedUrl } from "@aws-sdk/s3-request-presigner";

const ddb = DynamoDBDocumentClient.from(new DynamoDBClient({}), {
  marshallOptions: { removeUndefinedValues: true },
});
const s3 = new S3Client({});
const POSTS = process.env.POSTS_TABLE;
const USERS = process.env.USERS_TABLE;
const INTERACTIONS = process.env.INTERACTIONS_TABLE;
const REPORTS = process.env.UGC_REPORTS_TABLE;
const MEDIA_BUCKET = process.env.MEDIA_BUCKET;

const IMAGE_TYPES = new Map([
  ["image/jpeg", "jpg"],
  ["image/png", "png"],
  ["image/heic", "heic"],
]);
const VIDEO_TYPES = new Map([
  ["video/mp4", "mp4"],
  ["video/quicktime", "mov"],
]);
const MAX_IMAGE_BYTES = 20 * 1024 * 1024;
const MAX_VIDEO_BYTES = 200 * 1024 * 1024;

const json = (statusCode, body) => ({
  statusCode,
  headers: { "content-type": "application/json" },
  body: JSON.stringify(body),
});

const safeOwner = (ownerId) => createHash("sha256").update(ownerId).digest("hex").slice(0, 24);
const mediaPath = (key) => `/${key}`;

function publicPost(item) {
  if (!item) return null;
  const { rawKey, posterRawKey, ownerId, ...safe } = item;
  return safe;
}

async function getOwnedPost(postId, ownerId) {
  const out = await ddb.send(new GetCommand({ TableName: POSTS, Key: { postId } }));
  if (!out.Item || out.Item.source !== "ugc") return { error: json(404, { error: "post not found" }) };
  if (out.Item.ownerId !== ownerId) return { error: json(403, { error: "not your post" }) };
  return { item: out.Item };
}

async function createUpload(body, ownerId) {
  if (!POSTS || !MEDIA_BUCKET) return json(503, { error: "uploads are not configured" });
  const mediaType = body.mediaType === "video" ? "video" : body.mediaType === "image" ? "image" : null;
  const mimeType = String(body.mimeType ?? "").toLowerCase();
  const types = mediaType === "image" ? IMAGE_TYPES : VIDEO_TYPES;
  const extension = types?.get(mimeType);
  const fileSize = Number(body.fileSize);
  const maxBytes = mediaType === "image" ? MAX_IMAGE_BYTES : MAX_VIDEO_BYTES;
  const caption = String(body.caption ?? "").trim();
  if (!mediaType || !extension) return json(400, { error: "unsupported media type" });
  if (!Number.isFinite(fileSize) || fileSize <= 0 || fileSize > maxBytes) {
    return json(400, { error: `${mediaType} is too large` });
  }
  if (!caption || caption.length > 2200) return json(400, { error: "caption must be 1-2200 characters" });

  const postId = randomUUID();
  const ownerKey = safeOwner(ownerId);
  const rawKey = `ugc/raw/${ownerKey}/${postId}.${extension}`;
  const posterRawKey = mediaType === "video" ? `ugc/posters-raw/${ownerKey}/${postId}.jpg` : null;
  const user = USERS
    ? await ddb.send(new GetCommand({ TableName: USERS, Key: { userId: ownerId } })).catch(() => ({}))
    : {};
  const authorName = String(user.Item?.name ?? user.Item?.identity?.name ?? "Giftmaxxer").slice(0, 80);
  const now = Date.now();
  const item = {
    postId,
    ownerId,
    author: ownerId,
    authorName,
    createdAt: now,
    updatedAt: now,
    caption,
    source: "ugc",
    mediaType,
    mimeType,
    fileSize,
    rawKey,
    posterRawKey,
    status: "processing",
    processingStatus: "UPLOAD_PENDING",
    moderationStatus: "PENDING",
    likes: 0,
    comments: 0,
    contentType: mediaType === "video" ? "ugc_video" : "ugc_image",
    feedEligible: false,
  };
  await ddb.send(new PutCommand({ TableName: POSTS, Item: item, ConditionExpression: "attribute_not_exists(postId)" }));

  const uploadHeaders = { "Content-Type": mimeType, "Content-Length": String(fileSize) };
  const uploadUrl = await getSignedUrl(
    s3,
    new PutObjectCommand({ Bucket: MEDIA_BUCKET, Key: rawKey, ContentType: mimeType, ContentLength: fileSize }),
    { expiresIn: 900 }
  );
  let posterUploadUrl = null;
  if (posterRawKey) {
    posterUploadUrl = await getSignedUrl(
      s3,
      new PutObjectCommand({ Bucket: MEDIA_BUCKET, Key: posterRawKey, ContentType: "image/jpeg" }),
      { expiresIn: 900 }
    );
  }
  return json(201, {
    post: publicPost(item),
    uploadUrl,
    uploadHeaders,
    posterUploadUrl,
    posterUploadHeaders: posterUploadUrl ? { "Content-Type": "image/jpeg" } : null,
    expiresIn: 900,
  });
}

async function markComplete(postId, ownerId) {
  const owned = await getOwnedPost(postId, ownerId);
  if (owned.error) return owned.error;
  // The S3 event can reach the moderator before the client sends this
  // acknowledgement. Once processing has started (or finished), the raw object
  // may already be gone, so completion must stay idempotent.
  if (owned.item.processingStatus !== "UPLOAD_PENDING") {
    return json(202, { ok: true, postId, status: owned.item.processingStatus });
  }
  try {
    const head = await s3.send(new HeadObjectCommand({ Bucket: MEDIA_BUCKET, Key: owned.item.rawKey }));
    if (!head.ContentLength) return json(409, { error: "upload is empty" });
  } catch {
    return json(409, { error: "upload has not reached storage" });
  }
  await ddb.send(new UpdateCommand({
    TableName: POSTS,
    Key: { postId },
    UpdateExpression: "SET uploadCompletedAt = :now, updatedAt = :now",
    ExpressionAttributeValues: { ":now": Date.now() },
  }));
  return json(202, { ok: true, postId, status: owned.item.processingStatus });
}

async function listPosts(ownerId, limit) {
  const out = await ddb.send(new QueryCommand({
    TableName: POSTS,
    IndexName: "byAuthor",
    KeyConditionExpression: "author = :author",
    ExpressionAttributeValues: { ":author": ownerId },
    ScanIndexForward: false,
    Limit: Math.min(Math.max(Number(limit) || 30, 1), 50),
  }));
  return json(200, { items: (out.Items ?? []).filter((item) => item.source === "ugc").map(publicPost) });
}

async function getPost(postId, ownerId) {
  const owned = await getOwnedPost(postId, ownerId);
  return owned.error ?? json(200, { item: publicPost(owned.item) });
}

async function reportPost(postId, ownerId, body) {
  if (!REPORTS) return json(503, { error: "reporting is not configured" });
  const post = await ddb.send(new GetCommand({ TableName: POSTS, Key: { postId } }));
  if (!post.Item || post.Item.source !== "ugc") return json(404, { error: "post not found" });
  if (post.Item.ownerId === ownerId) return json(400, { error: "you cannot report your own post" });
  const reason = String(body.reason ?? "other").trim().slice(0, 120);
  const reportId = `${postId}#${safeOwner(ownerId)}`;
  await ddb.send(new PutCommand({
    TableName: REPORTS,
    Item: {
      reportId,
      postId,
      postOwnerId: safeOwner(post.Item.ownerId),
      reporterId: safeOwner(ownerId),
      reason,
      status: "OPEN",
      createdAt: Date.now(),
    },
  }));
  return json(201, { ok: true });
}

async function blockUser(blockedUserId, ownerId) {
  if (!INTERACTIONS) return json(503, { error: "blocking is not configured" });
  if (!blockedUserId || blockedUserId === ownerId) return json(400, { error: "invalid user" });
  await ddb.send(new PutCommand({
    TableName: INTERACTIONS,
    Item: {
      userId: ownerId,
      targetId: `block#${blockedUserId}`,
      target: blockedUserId,
      type: "block",
      createdAt: Date.now(),
    },
  }));
  return json(201, { ok: true });
}

export async function ugcRoutes(method, path, body, qs, auth) {
  const ownerId = auth?.sub;
  if (!ownerId) return json(401, { error: "sign in required" });
  if (method === "POST" && path === "/ugc/uploads") return createUpload(body, ownerId);
  if (method === "GET" && path === "/ugc/posts") return listPosts(ownerId, qs.limit);
  const blockMatch = /^\/ugc\/users\/([^/]+)\/block$/.exec(path);
  if (method === "POST" && blockMatch) return blockUser(decodeURIComponent(blockMatch[1]), ownerId);
  const match = /^\/ugc\/posts\/([^/]+)(?:\/(complete|report))?$/.exec(path);
  if (!match) return json(404, { error: `no route for ${method} ${path}` });
  const postId = decodeURIComponent(match[1]);
  if (method === "GET" && !match[2]) return getPost(postId, ownerId);
  if (method === "POST" && match[2] === "complete") return markComplete(postId, ownerId);
  if (method === "POST" && match[2] === "report") return reportPost(postId, ownerId, body);
  return json(405, { error: "method not allowed" });
}

async function batchDeletePosts(items) {
  for (let index = 0; index < items.length; index += 25) {
    await ddb.send(new BatchWriteCommand({
      RequestItems: { [POSTS]: items.slice(index, index + 25).map((item) => ({ DeleteRequest: { Key: { postId: item.postId } } })) },
    }));
  }
}

export async function purgeUserUGC(ownerId) {
  if (!POSTS) return 0;
  const out = await ddb.send(new QueryCommand({
    TableName: POSTS,
    IndexName: "byAuthor",
    KeyConditionExpression: "author = :author",
    ExpressionAttributeValues: { ":author": ownerId },
  }));
  const posts = (out.Items ?? []).filter((item) => item.source === "ugc");
  const keys = posts.flatMap((item) => [item.rawKey, item.posterRawKey, item.publicKey, item.posterPublicKey]).filter(Boolean);
  if (keys.length && MEDIA_BUCKET) {
    for (let index = 0; index < keys.length; index += 1000) {
      await s3.send(new DeleteObjectsCommand({
        Bucket: MEDIA_BUCKET,
        Delete: { Objects: keys.slice(index, index + 1000).map((Key) => ({ Key })), Quiet: true },
      })).catch((error) => console.warn("purge UGC media failed", error.message));
    }
  }
  await batchDeletePosts(posts);
  return posts.length;
}
