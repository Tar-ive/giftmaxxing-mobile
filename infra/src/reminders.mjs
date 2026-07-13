// Giftmaxxing reminder job — invoked daily by EventBridge. Scans the users
// table for logged events whose next occurrence is exactly `reminderLeadDays`
// away (or today) and publishes one reminder per due event to an SNS topic.
// Subscribe an email/SMS/HTTPS endpoint to the topic to actually receive them.
//
// DynamoDB + lib-dynamodb come from the nodejs20.x runtime SDK; @aws-sdk/client-sns
// is npm-installed into src/node_modules and bundled (see infra/src/package.json).
import { DynamoDBClient } from "@aws-sdk/client-dynamodb";
import { DynamoDBDocumentClient, ScanCommand } from "@aws-sdk/lib-dynamodb";
import { SNSClient, PublishCommand } from "@aws-sdk/client-sns";
import { sendPushToUser } from "./push.mjs";

const ddb = DynamoDBDocumentClient.from(new DynamoDBClient({}));
const sns = new SNSClient({});

const USERS = process.env.USERS_TABLE;
const TOPIC_ARN = process.env.REMINDERS_TOPIC_ARN;

// Whole days until an event's next occurrence (annual rolls forward; once is
// absolute). Mirrors web/lib/events.ts + handler.mjs.
function daysUntil(ev, now = new Date()) {
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(String(ev?.date ?? "").trim());
  if (!m) return null;
  const y = Number(m[1]), mo = Number(m[2]), da = Number(m[3]);
  const today = new Date(now.getFullYear(), now.getMonth(), now.getDate());
  let next;
  if (ev.recurrence === "once") {
    next = new Date(y, mo - 1, da);
  } else {
    next = new Date(today.getFullYear(), mo - 1, da);
    if (next.getTime() < today.getTime()) next = new Date(today.getFullYear() + 1, mo - 1, da);
  }
  return Math.round((next.getTime() - today.getTime()) / 86400000);
}

export const handler = async () => {
  // Catch-all so a single DynamoDB/SNS hiccup can't crash the daily job opaquely.
  try {
    return await runReminders();
  } catch (err) {
    console.error("reminders job failed", err);
    return { ok: false, error: err?.message || "reminders error" };
  }
};

async function runReminders() {
  if (!USERS) return { ok: false, error: "USERS_TABLE not set" };

  const due = [];
  let key;
  do {
    const out = await ddb.send(new ScanCommand({ TableName: USERS, ExclusiveStartKey: key }));
    for (const u of out.Items ?? []) {
      if (u.eventLoggingEnabled === false) continue;
      const events = Array.isArray(u.events) ? u.events : [];
      const recipients = Array.isArray(u.recipients) ? u.recipients : [];
      const byId = Object.fromEntries(recipients.map((r) => [r.id, r]));
      for (const ev of events) {
        const d = daysUntil(ev);
        if (d == null) continue;
        const lead = Number(ev.reminderLeadDays ?? 7);
        // Fire at the lead-day mark and again on the day itself.
        if (d === lead || d === 0) {
          due.push({
            userId: u.userId,
            name: u.name ?? "there",
            event: ev,
            recipient: byId[ev.recipientId] ?? null,
            days: d,
          });
        }
      }
    }
    key = out.LastEvaluatedKey;
  } while (key);

  for (const r of due) {
    const who = r.recipient?.name ?? "someone";
    const when = r.days === 0 ? "today" : `in ${r.days} day${r.days === 1 ? "" : "s"}`;
    const message = `Hi ${r.name} — ${r.event.type} for ${who} is ${when} (${r.event.date}). Open Giftmaxxing to find the perfect gift.`;
    if (TOPIC_ARN) {
      // Per-item guard: one failed publish shouldn't abort the rest of the batch.
      try {
        await sns.send(
          new PublishCommand({
            TopicArn: TOPIC_ARN,
            Subject: "Giftmaxxing gift reminder",
            Message: message,
            MessageAttributes: {
              userId: { DataType: "String", StringValue: String(r.userId) },
            },
          })
        );
      } catch (err) {
        console.error("reminder publish failed for", r.userId, err?.message);
      }
    } else {
      console.log("[reminder]", message);
    }
    // Also push straight to the user's own devices ("circles & events" push).
    // Best-effort; no-op until the APNs platform app is configured.
    await sendPushToUser(r.userId, {
      title: r.days === 0 ? `${who}'s ${r.event.type} is today 🎁` : `${who}'s ${r.event.type} is ${when}`,
      body: `Open Giftmaxxing to find the perfect gift before ${r.event.date}.`,
      data: { type: "event_reminder", eventId: String(r.event.id ?? "") },
    });
  }

  return { ok: true, scanned: true, due: due.length };
};
