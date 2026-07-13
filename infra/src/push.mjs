// APNs push delivery via SNS platform endpoints. The write half has existed
// for a while (devices table + POST /mobile/device); this is the missing SEND
// half: look up a user's registered devices, ensure each has an SNS platform
// endpoint, and publish an APNS payload. Used by friends-routes (requests /
// accepts / DMs), handler.mjs (challenge responses, pool pledges), and
// reminders.mjs (event reminders).
//
// Every function here is BEST-EFFORT and never throws: a push must never fail
// the API call that triggered it. When DEVICES_TABLE or SNS_PLATFORM_APP_ARN
// is unset (APNs key not yet supplied to Terraform), everything no-ops.
//
// Config (env): DEVICES_TABLE, SNS_PLATFORM_APP_ARN.

import { DynamoDBClient } from "@aws-sdk/client-dynamodb";
import {
  DynamoDBDocumentClient,
  QueryCommand,
  UpdateCommand,
  DeleteCommand,
} from "@aws-sdk/lib-dynamodb";
import {
  SNSClient,
  PublishCommand,
  CreatePlatformEndpointCommand,
} from "@aws-sdk/client-sns";

const ddb = DynamoDBDocumentClient.from(new DynamoDBClient({}), {
  marshallOptions: { removeUndefinedValues: true },
});
const sns = new SNSClient({});

const DEVICES = process.env.DEVICES_TABLE;
const PLATFORM_ARN = process.env.SNS_PLATFORM_APP_ARN;

export function pushConfigured() {
  return Boolean(DEVICES && PLATFORM_ARN);
}

// The APNs payload, duplicated under APNS and APNS_SANDBOX so the same code
// serves TestFlight/App Store (production gateway) and Xcode debug builds.
// `data` keys land in userInfo — PushManager.handleNotification routes on
// data.type (friend_request | friend_accept | dm | challenge_completed |
// pool_contribution | event_reminder | …).
function apnsMessage({ title, body, badge, data = {} }) {
  const aps = {
    alert: { title, body },
    sound: "default",
    ...(Number.isFinite(badge) ? { badge } : {}),
  };
  const payload = JSON.stringify({ aps, ...data });
  return JSON.stringify({
    default: body || title || "Giftmaxxing",
    APNS: payload,
    APNS_SANDBOX: payload,
  });
}

async function ensureEndpoint(device) {
  if (device.endpointArn) return device.endpointArn;
  const out = await sns.send(
    new CreatePlatformEndpointCommand({
      PlatformApplicationArn: PLATFORM_ARN,
      Token: device.token,
      CustomUserData: device.userId,
    })
  );
  const arn = out.EndpointArn;
  if (arn) {
    await ddb
      .send(
        new UpdateCommand({
          TableName: DEVICES,
          Key: { userId: device.userId, deviceId: device.deviceId },
          UpdateExpression: "SET endpointArn = :a, updatedAt = :t",
          ExpressionAttributeValues: { ":a": arn, ":t": Date.now() },
        })
      )
      .catch(() => {});
  }
  return arn;
}

async function dropDevice(device) {
  await ddb
    .send(
      new DeleteCommand({
        TableName: DEVICES,
        Key: { userId: device.userId, deviceId: device.deviceId },
      })
    )
    .catch(() => {});
}

// Push one notification to every device a user has registered.
// Returns { sent, failed } and NEVER throws.
export async function sendPushToUser(userId, { title, body, badge, data } = {}) {
  if (!pushConfigured() || !userId || !(title || body)) return { sent: 0, failed: 0 };
  let devices = [];
  try {
    const out = await ddb.send(
      new QueryCommand({
        TableName: DEVICES,
        KeyConditionExpression: "userId = :u",
        ExpressionAttributeValues: { ":u": String(userId) },
      })
    );
    devices = out.Items ?? [];
  } catch (e) {
    console.warn("push: devices query failed:", e.message);
    return { sent: 0, failed: 0 };
  }

  let sent = 0;
  let failed = 0;
  for (const device of devices) {
    if (!device?.token) continue;
    try {
      const endpointArn = await ensureEndpoint(device);
      if (!endpointArn) {
        failed++;
        continue;
      }
      await sns.send(
        new PublishCommand({
          TargetArn: endpointArn,
          MessageStructure: "json",
          Message: apnsMessage({ title, body, badge, data }),
        })
      );
      sent++;
    } catch (e) {
      failed++;
      // Token rotated or app uninstalled — SNS disables the endpoint. Drop the
      // row; the app re-registers a fresh token on next launch.
      if (/EndpointDisabled|NotFound|InvalidParameter.*Token/i.test(String(e?.name) + String(e?.message))) {
        await dropDevice(device);
      } else {
        console.warn(`push: publish failed for ${userId}:`, e.message);
      }
    }
  }
  return { sent, failed };
}

// Fan a notification out to several users (deduped). Sequential on purpose —
// call sites push to a handful of users at most.
export async function sendPushToUsers(userIds, payload) {
  const unique = [...new Set((userIds ?? []).filter(Boolean).map(String))];
  let sent = 0;
  for (const id of unique) {
    const r = await sendPushToUser(id, payload);
    sent += r.sent;
  }
  return { sent };
}
