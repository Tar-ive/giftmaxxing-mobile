// Mobile-specific API routes for the giftmaxxing iOS app.
// These are designed to be imported and registered alongside the existing
// handler.mjs routes in the main Lambda. They add:
//   POST /mobile/device       — register APNs push token
//   GET  /mobile/sync         — delta sync (changed items since timestamp)
//   POST /mobile/interactions/batch — batch upload offline interactions
//
// To integrate: import { mobileRoutes } from "./mobile-routes.mjs" in handler.mjs,
// then add a check in the main router: if (path.startsWith("/mobile/")) return mobileRoutes(...)

import { DynamoDBDocumentClient, PutCommand, QueryCommand, BatchWriteCommand } from "@aws-sdk/lib-dynamodb";
import { DynamoDBClient } from "@aws-sdk/client-dynamodb";
import { SNSClient, CreatePlatformEndpointCommand } from "@aws-sdk/client-sns";

const ddb = DynamoDBDocumentClient.from(new DynamoDBClient({}), {
  marshallOptions: { removeUndefinedValues: true },
});
const sns = new SNSClient({});

const DEVICES_TABLE = process.env.DEVICES_TABLE;
const POSTS_TABLE = process.env.POSTS_TABLE;
const INTERACTIONS_TABLE = process.env.INTERACTIONS_TABLE;
const EVENTS_TABLE = process.env.EVENTS_TABLE;
const SNS_PLATFORM_APP_ARN = process.env.SNS_PLATFORM_APP_ARN;

const json = (statusCode, body) => ({
  statusCode,
  headers: { "content-type": "application/json" },
  body: JSON.stringify(body),
});

// POST /mobile/device — register an APNs device token for push notifications.
// Body: { userId, platform, token }
// Stores the token in the devices table and creates an SNS platform endpoint.
async function registerDevice(body) {
  const { userId, platform, token } = body;
  if (!userId || !token) return json(400, { error: "userId and token required" });

  const deviceId = `${platform || "ios"}-${token.slice(0, 16)}`;
  const now = Date.now();
  const ttl = Math.floor(now / 1000) + 90 * 86400; // 90 days

  // Create the SNS platform endpoint FIRST so its ARN persists with the token
  // (it used to be created after the Put and thrown away — every send had to
  // re-create it). No-ops until the APNs key is supplied to Terraform.
  let endpointArn = null;
  if (SNS_PLATFORM_APP_ARN && token) {
    try {
      const result = await sns.send(new CreatePlatformEndpointCommand({
        PlatformApplicationArn: SNS_PLATFORM_APP_ARN,
        Token: token,
        CustomUserData: userId,
      }));
      endpointArn = result.EndpointArn;
    } catch (e) {
      console.warn("SNS CreatePlatformEndpoint failed:", e.message);
    }
  }

  if (DEVICES_TABLE) {
    await ddb.send(new PutCommand({
      TableName: DEVICES_TABLE,
      Item: {
        userId,
        deviceId,
        platform: platform || "ios",
        token,
        ...(endpointArn ? { endpointArn } : {}),
        createdAt: now,
        updatedAt: now,
        expiresAt: ttl,
      },
    }));
  }

  return json(200, { ok: true, deviceId, endpointArn });
}

// GET /mobile/sync?since=<epochMs> — delta sync for offline-first mobile clients.
// Returns posts and events that have changed since the given timestamp.
// The mobile app calls this on launch and periodic background fetch to pull
// only what changed, rather than re-fetching the entire feed.
async function deltaSync(params) {
  const since = Number(params.since || 0);
  if (!since) return json(400, { error: "since parameter required (epoch ms)" });

  const results = { updatedPosts: [], deletedPostIds: [], updatedEvents: [], serverTime: Date.now() };

  // Fetch posts updated since the timestamp
  if (POSTS_TABLE) {
    try {
      const res = await ddb.send(new QueryCommand({
        TableName: POSTS_TABLE,
        IndexName: "byFeed",
        KeyConditionExpression: "feedPk = :f AND createdAt > :since",
        ExpressionAttributeValues: { ":f": "all", ":since": since },
        Limit: 100,
      }));
      results.updatedPosts = res.Items || [];
    } catch (e) {
      console.warn("deltaSync posts query failed:", e.message);
    }
  }

  // Fetch events updated since the timestamp
  if (EVENTS_TABLE) {
    try {
      const res = await ddb.send(new QueryCommand({
        TableName: EVENTS_TABLE,
        IndexName: "byScope",
        KeyConditionExpression: "scope = :s",
        ExpressionAttributeValues: { ":s": "personal" },
        Limit: 50,
      }));
      // Filter client-side for events created/updated after `since`
      results.updatedEvents = (res.Items || []).filter(
        (e) => (e.createdAt || 0) > since || (e.updatedAt || 0) > since
      );
    } catch (e) {
      console.warn("deltaSync events query failed:", e.message);
    }
  }

  return json(200, results);
}

// POST /mobile/interactions/batch — batch upload interactions accumulated offline.
// Body: { interactions: [{ userId, targetId, type, data?, timestamp? }] }
// Writes up to 25 interactions in a single BatchWrite (DynamoDB limit).
async function batchInteractions(body) {
  const { interactions } = body;
  if (!Array.isArray(interactions) || interactions.length === 0) {
    return json(400, { error: "interactions array required" });
  }

  if (!INTERACTIONS_TABLE) return json(200, { ok: true, written: 0 });

  // DynamoDB BatchWrite max 25 items
  const batch = interactions.slice(0, 25).map((ix) => ({
    PutRequest: {
      Item: {
        userId: ix.userId || "anonymous",
        targetId: `${ix.type || "view"}#${ix.targetId}`,
        type: ix.type || "view",
        createdAt: ix.timestamp || Date.now(),
        source: "mobile",
        data: ix.data || {},
      },
    },
  }));

  try {
    await ddb.send(new BatchWriteCommand({
      RequestItems: { [INTERACTIONS_TABLE]: batch },
    }));
  } catch (e) {
    console.warn("batchInteractions failed:", e.message);
    return json(500, { error: "batch write failed" });
  }

  return json(200, { ok: true, written: batch.length });
}

// Main router for /mobile/* paths
export async function mobileRoutes(method, path, body, params) {
  if (method === "POST" && path === "/mobile/device") {
    return registerDevice(body);
  }
  if (method === "GET" && path === "/mobile/sync") {
    return deltaSync(params);
  }
  if (method === "POST" && path === "/mobile/interactions/batch") {
    return batchInteractions(body);
  }
  return json(404, { error: "not found" });
}
