// Mobile analytics ingestion endpoint for the giftmaxxing iOS app.
// Receives batched behavioral events (Instagram-style impressions, Tinder-style
// swipe telemetry, session lifecycle) and writes them to DynamoDB for analysis.
//
// To integrate: import { analyticsRoutes } from "./analytics-routes.mjs" in
// handler.mjs, then route POST /mobile/analytics to it.

import { DynamoDBDocumentClient, BatchWriteCommand, PutCommand } from "@aws-sdk/lib-dynamodb";
import { DynamoDBClient } from "@aws-sdk/client-dynamodb";

const ddb = DynamoDBDocumentClient.from(new DynamoDBClient({}), {
  marshallOptions: { removeUndefinedValues: true },
});

const ANALYTICS_TABLE = process.env.ANALYTICS_TABLE;

const json = (statusCode, body) => ({
  statusCode,
  headers: { "content-type": "application/json" },
  body: JSON.stringify(body),
});

// POST /mobile/analytics — batch upload behavioral events from iOS app.
// Body: { events: [{ eventId, type, timestamp, ...properties }] }
//
// Event types map to tracking patterns:
//   Instagram-style: feed_impression, feed_dwell, feed_scroll_depth, feed_revisit
//   Tinder-style:    swipe_card_shown, swipe_right, swipe_left, swipe_hesitation,
//                    swipe_decision_time, swipe_velocity, swipe_deck_complete
//   Session:         session_start, session_end, session_resume, session_background
//   Content:         content_like, content_save, content_share, product_affiliate_click
//   Navigation:      tab_switch, screen_view
//
// Each event is stored with a composite key:
//   PK = userId (or "anonymous")
//   SK = timestamp#eventId (for time-ordered queries)
//
// The table enables queries like:
//   - "Show me all swipe_right events for user X in the last 7 days"
//   - "What is the average dwell time for posts in position 1-5 vs 20+"
//   - "Which posts have the highest hesitation rate?"
//   - "What is the session duration distribution?"
export async function analyticsRoutes(method, path, body) {
  if (method === "POST" && path === "/mobile/analytics") {
    return ingestAnalytics(body);
  }
  if (method === "GET" && path === "/mobile/analytics/summary") {
    return analyticsSummary(body);
  }
  return json(404, { error: "not found" });
}

async function ingestAnalytics(body) {
  const { events } = body;
  if (!Array.isArray(events) || events.length === 0) {
    return json(400, { error: "events array required" });
  }

  if (!ANALYTICS_TABLE) {
    // Table not provisioned yet — accept silently so the app doesn't retry
    return json(200, { ok: true, written: 0, reason: "table_not_configured" });
  }

  // DynamoDB BatchWrite: max 25 items per call
  const batches = [];
  for (let i = 0; i < events.length; i += 25) {
    batches.push(events.slice(i, i + 25));
  }

  let totalWritten = 0;

  for (const batch of batches) {
    const items = batch.map((evt) => {
      const userId = evt.userId || "anonymous";
      const timestamp = evt.timestamp || Date.now();
      const eventId = evt.eventId || `${timestamp}-${Math.random().toString(36).slice(2, 10)}`;

      return {
        PutRequest: {
          Item: {
            userId,
            sk: `${timestamp}#${eventId}`,
            eventId,
            type: evt.type,
            timestamp,
            // Flatten all properties into the item for flexible querying
            platform: evt.platform || "ios",
            appVersion: evt.appVersion,
            sessionId: evt.sessionId,
            postId: evt.postId,
            position: evt.position,
            source: evt.source,
            // Dwell/timing metrics (Instagram-style)
            dwellMs: evt.dwellMs,
            dwellBucket: evt.dwellBucket,
            dwellBeforeActionMs: evt.dwellBeforeActionMs,
            // Swipe metrics (Tinder-style)
            decisionTimeMs: evt.decisionTimeMs,
            decisionBucket: evt.decisionBucket,
            swipeVelocity: evt.swipeVelocity,
            consecutiveRights: evt.consecutiveRights,
            consecutiveLefts: evt.consecutiveLefts,
            dragDistance: evt.dragDistance,
            dragDurationMs: evt.dragDurationMs,
            // Deck completion
            yesCount: evt.yesCount,
            noCount: evt.noCount,
            yesRate: evt.yesRate,
            totalCards: evt.totalCards,
            // Scroll depth (Instagram-style)
            depth: evt.depth,
            avgScrollVelocity: evt.avgScrollVelocity,
            // Session metrics
            totalDurationMs: evt.totalDurationMs,
            activeDurationMs: evt.activeDurationMs,
            backgroundDurationMs: evt.backgroundDurationMs,
            thermalState: evt.thermalState,
            // Navigation
            fromTab: evt.fromTab,
            toTab: evt.toTab,
            screen: evt.screen,
            // Product funnel
            productUrl: evt.productUrl,
            // Search
            query: evt.query,
            resultCount: evt.resultCount,
            // TTL: auto-delete after 90 days
            expiresAt: Math.floor(timestamp / 1000) + 90 * 86400,
          },
        },
      };
    });

    try {
      await ddb.send(new BatchWriteCommand({
        RequestItems: { [ANALYTICS_TABLE]: items },
      }));
      totalWritten += items.length;
    } catch (e) {
      console.warn("Analytics batch write failed:", e.message);
      // Don't fail the whole request — partial success is fine
    }
  }

  return json(200, { ok: true, written: totalWritten });
}

// GET /mobile/analytics/summary — lightweight read-only summary for admin dashboard.
// Returns aggregate counts by event type for the last 24 hours.
async function analyticsSummary() {
  // Placeholder — would use a GSI on type + timestamp for efficient aggregation.
  // For now, return a static schema description so the admin knows what data is available.
  return json(200, {
    availableEventTypes: [
      // Session lifecycle
      "session_start", "session_end", "session_resume", "session_background",
      // Feed engagement (Instagram-style)
      "feed_impression", "feed_dwell", "feed_scroll_depth", "feed_revisit",
      // Content interaction
      "content_like", "content_unlike", "content_save", "content_unsave",
      "content_share", "content_tap",
      // Swipe deck (Tinder-style)
      "swipe_card_shown", "swipe_right", "swipe_left",
      "swipe_hesitation", "swipe_deck_complete",
      // Navigation
      "tab_switch", "screen_view",
      // Product funnel
      "product_affiliate_click",
      // Search
      "search_query", "search_result_tap",
      // Maxi AI
      "maxi_message_sent", "maxi_response_received",
    ],
    dwellBuckets: ["glance (<1s)", "scan (1-3s)", "read (3-10s)", "study (>10s)"],
    decisionBuckets: ["snap (<500ms)", "quick (500ms-2s)", "considered (2-5s)", "studied (>5s)"],
    retentionDays: 90,
  });
}
