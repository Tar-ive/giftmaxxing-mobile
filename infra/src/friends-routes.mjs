// Friends, public people discovery, and 1:1 DMs.
//
// Wired from handler.mjs. Storage is a single DynamoDB table (FRIENDS_TABLE):
//
//   Friendship edges (mirrored on both users):
//     pk = userId, sk = FRIEND#<otherUserId>
//       → status: pending|accepted, requestedBy, circleId?, createdAt, updatedAt
//
//   DM thread index (on each participant):
//     pk = userId, sk = DM#<threadId>
//       → otherUserId, otherName, lastText, lastAt
//
//   DM messages (shared conversation partition):
//     pk = DM#<sortedPair>, sk = META | MSG#<ts>#<id>
//
// People discovery reads the USERS table (public profiles only).

import {
  BatchGetCommand,
  DynamoDBDocumentClient,
  GetCommand,
  PutCommand,
  QueryCommand,
  ScanCommand,
  DeleteCommand,
  UpdateCommand,
} from "@aws-sdk/lib-dynamodb";
import { DynamoDBClient } from "@aws-sdk/client-dynamodb";
import { sendPushToUser } from "./push.mjs";
import { publicPostsForProfile } from "./ugc-routes.mjs";

const ddb = DynamoDBDocumentClient.from(new DynamoDBClient({}), {
  marshallOptions: { removeUndefinedValues: true },
});

const FRIENDS = process.env.FRIENDS_TABLE;
const USERS = process.env.USERS_TABLE;
const EVENTS = process.env.EVENTS_TABLE;

const json = (statusCode, body) => ({
  statusCode,
  headers: { "content-type": "application/json" },
  body: JSON.stringify(body),
});

function gid() {
  return (
    globalThis.crypto?.randomUUID?.() ??
    `${Date.now().toString(36)}${Math.random().toString(36).slice(2, 10)}`
  );
}

function threadIdFor(a, b) {
  const [x, y] = [String(a), String(b)].sort();
  return `DM#${x}__${y}`;
}

function publicCard(item, allowPrivate = false) {
  if (!item || !item.userId) return null;
  const visibility = item.visibility ?? "public";
  if (visibility === "private" && !allowPrivate) return null;
  const name = String(item.name ?? item.identity?.name ?? "").trim() || "Someone";
  const handle =
    String(item.handle ?? "")
      .trim()
      .toLowerCase()
      .replace(/[^a-z0-9_]/g, "")
      .slice(0, 24) ||
    name
      .toLowerCase()
      .replace(/[^a-z0-9]+/g, "")
      .slice(0, 18) ||
    "user";
  // The "gift me right" facts: sizes, dislikes, the standing note, and a
  // photo showcase of gifts the owner would love. Everything is opt-in via
  // the same visibility gate above and length-capped here.
  const clothingSizes = allowPrivate &&
    item.clothingSizes && typeof item.clothingSizes === "object" && !Array.isArray(item.clothingSizes)
      ? Object.fromEntries(
          Object.entries(item.clothingSizes)
            .filter(([, v]) => typeof v === "string" && v.trim())
            .slice(0, 8)
            .map(([k, v]) => [String(k).slice(0, 20), String(v).trim().slice(0, 24)])
        )
      : null;
  const selfBoard = allowPrivate && Array.isArray(item.giftBoards)
    ? item.giftBoards.find((b) => b?.relationship === "self" || b?.name === "Gift ideas for me")
    : null;
  const boardIdeas = Array.isArray(selfBoard?.posts)
    ? selfBoard.posts.map((p) => ({
        postId: p?.id,
        name: p?.product?.name,
        imageUrl: p?.product?.image,
        brand: p?.product?.brand,
        price: p?.product?.price,
        productUrl: p?.productUrl ?? p?.url,
      }))
    : [];
  const showcaseSource = allowPrivate ? (boardIdeas.length ? boardIdeas : item.giftShowcase) : [];
  const giftShowcase = Array.isArray(showcaseSource)
    ? showcaseSource
        .slice(0, 6)
        .map((g) => ({
          postId: String(g?.postId ?? "").slice(0, 80),
          name: typeof g?.name === "string" ? g.name.slice(0, 120) : null,
          imageUrl: typeof g?.imageUrl === "string" ? g.imageUrl.slice(0, 500) : null,
          why: typeof g?.why === "string" ? g.why.slice(0, 200) : null,
          brand: typeof g?.brand === "string" ? g.brand.slice(0, 80) : null,
          price: Number.isFinite(Number(g?.price)) ? Number(g.price) : null,
          productUrl: typeof g?.productUrl === "string" ? g.productUrl.slice(0, 1000) : null,
        }))
        .filter((g) => g.postId)
    : [];
  return {
    userId: item.userId,
    name,
    handle,
    bio: typeof item.bio === "string" ? item.bio.slice(0, 160) : null,
    imageUrl: item.identity?.imageUrl ?? item.imageUrl ?? null,
    interests: allowPrivate && Array.isArray(item.interests) ? item.interests.slice(0, 12) : [],
    materialisticCategories: allowPrivate && Array.isArray(item.materialisticCategories)
      ? item.materialisticCategories.slice(0, 8)
      : [],
    style: item.style ?? null,
    role: item.role ?? null,
    visibility,
    tagline: typeof item.tagline === "string" ? item.tagline.slice(0, 120) : null,
    philosophy: typeof item.philosophy === "string" ? item.philosophy.slice(0, 500) : null,
    clothingSizes: clothingSizes && Object.keys(clothingSizes).length ? clothingSizes : null,
    dislikes: allowPrivate && Array.isArray(item.dislikes)
      ? item.dislikes.filter((d) => typeof d === "string").slice(0, 12)
      : [],
    giftNote: allowPrivate && typeof item.giftNote === "string" ? item.giftNote.slice(0, 240) : null,
    giftShowcase,
  };
}

function friendFromItem(item, viewerId) {
  const otherUserId = item.otherUserId ?? item.sk?.replace(/^FRIEND#/, "");
  return {
    friendId: otherUserId,
    status: item.status ?? "pending",
    requestedBy: item.requestedBy ?? null,
    circleId: item.circleId ?? null,
    createdAt: item.createdAt ?? 0,
    updatedAt: item.updatedAt ?? item.createdAt ?? 0,
    incoming: item.requestedBy && item.requestedBy !== viewerId,
    name: item.otherName ?? null,
    handle: item.otherHandle ?? null,
  };
}

async function loadUserCard(userId, allowPrivate = false) {
  if (!USERS || !userId) return null;
  const out = await ddb.send(new GetCommand({ TableName: USERS, Key: { userId } }));
  return publicCard(out.Item, allowPrivate);
}

async function getFriendship(userId, otherUserId) {
  if (!FRIENDS) return null;
  const out = await ddb.send(
    new GetCommand({
      TableName: FRIENDS,
      Key: { pk: userId, sk: `FRIEND#${otherUserId}` },
    })
  );
  return out.Item ?? null;
}

async function acceptedFriendCount(userId) {
  if (!FRIENDS || !userId) return 0;
  const out = await ddb.send(new QueryCommand({
    TableName: FRIENDS,
    KeyConditionExpression: "pk = :pk AND begins_with(sk, :friend)",
    ExpressionAttributeValues: { ":pk": userId, ":friend": "FRIEND#" },
  }));
  return (out.Items ?? []).filter((item) => item.status === "accepted").length;
}

async function circlesForUser(userId) {
  if (!EVENTS || !userId) return [];
  const seats = [];
  let cursor;
  do {
    const out = await ddb.send(new ScanCommand({
      TableName: EVENTS,
      FilterExpression: "linkedUserId = :user",
      ExpressionAttributeValues: { ":user": userId },
      ProjectionExpression: "userId",
      ExclusiveStartKey: cursor,
    }));
    seats.push(...(out.Items ?? []));
    cursor = out.LastEvaluatedKey;
  } while (cursor);
  const circleKeys = [...new Set(
    seats.map((item) => String(item.userId ?? "")).filter((value) => value.startsWith("CIRCLE#"))
  )].slice(0, 50);
  if (!circleKeys.length) return [];
  const out = await ddb.send(new BatchGetCommand({
    RequestItems: {
      [EVENTS]: {
        Keys: circleKeys.map((userId) => ({ userId, eventId: "META" })),
        ProjectionExpression: "userId, circleId, #name, emoji",
        ExpressionAttributeNames: { "#name": "name" },
      },
    },
  }));
  return (out.Responses?.[EVENTS] ?? []).map((item) => ({
    circleId: item.circleId ?? String(item.userId).replace(/^CIRCLE#/, ""),
    name: item.name ?? "Gift circle",
    emoji: item.emoji ?? null,
  }));
}

// ── Public people discovery ──────────────────────────────────────────────────

async function searchPeople(qs) {
  if (!USERS) return json(200, { items: [] });
  const q = String(qs.q ?? "")
    .trim()
    .toLowerCase()
    .slice(0, 60);
  const limit = Math.min(50, Math.max(1, Number(qs.limit) || 24));
  // Skeleton search: Scan + filter. Fine at current user scale; promote to a
  // handle GSI / OpenSearch once the directory is large.
  const out = await ddb.send(
    new ScanCommand({
      TableName: USERS,
      Limit: 200,
    })
  );
  const items = [];
  for (const raw of out.Items ?? []) {
    const card = publicCard(raw);
    if (!card) continue;
    if (q) {
      const hay = `${card.name} ${card.handle} ${(card.interests ?? []).join(" ")}`.toLowerCase();
      if (!hay.includes(q)) continue;
    }
    items.push(card);
    if (items.length >= limit) break;
  }
  return json(200, { items });
}

async function getPerson(userId, viewerId) {
  if (!USERS || !userId) return json(404, { error: "not found" });
  const out = await ddb.send(new GetCommand({ TableName: USERS, Key: { userId } }));
  const profile = out.Item;
  const friendship = viewerId && viewerId !== userId
    ? await getFriendship(viewerId, userId)
    : null;
  const allowPrivate = viewerId === userId || friendship?.status === "accepted";
  const card = publicCard(profile, allowPrivate);
  if (!card) return json(404, { error: "not found or private" });
  [card.posts, card.friendCount, card.circles] = await Promise.all([
    publicPostsForProfile(userId).catch(() => []),
    acceptedFriendCount(userId).catch(() => 0),
    allowPrivate ? circlesForUser(userId).catch(() => []) : [],
  ]);
  return json(200, { item: card });
}

// ── Friendships ──────────────────────────────────────────────────────────────

async function requestFriend(body, auth) {
  if (!FRIENDS) return json(503, { error: "friends table not configured" });
  const fromUserId = String(body.fromUserId || auth?.sub || "").trim();
  const toUserId = String(body.toUserId || "").trim();
  if (!fromUserId || !toUserId) return json(400, { error: "fromUserId and toUserId required" });
  if (fromUserId === toUserId) return json(400, { error: "cannot friend yourself" });

  const existing = await getFriendship(fromUserId, toUserId);
  if (existing?.status === "accepted") {
    return json(200, { ok: true, status: "accepted", already: true });
  }
  if (existing?.status === "pending") {
    // If they already requested us, auto-accept.
    if (existing.requestedBy === toUserId) {
      return acceptFriend({ userId: fromUserId, fromUserId: toUserId }, auth);
    }
    return json(200, { ok: true, status: "pending", already: true });
  }

  const now = Date.now();
  const circleId = body.circleId ? String(body.circleId).slice(0, 64) : null;
  const fromCard = await loadUserCard(fromUserId);
  const toCard = await loadUserCard(toUserId);

  const edgeA = {
    pk: fromUserId,
    sk: `FRIEND#${toUserId}`,
    otherUserId: toUserId,
    status: "pending",
    requestedBy: fromUserId,
    circleId,
    createdAt: now,
    updatedAt: now,
    otherName: toCard?.name ?? null,
    otherHandle: toCard?.handle ?? null,
  };
  const edgeB = {
    pk: toUserId,
    sk: `FRIEND#${fromUserId}`,
    otherUserId: fromUserId,
    status: "pending",
    requestedBy: fromUserId,
    circleId,
    createdAt: now,
    updatedAt: now,
    otherName: fromCard?.name ?? null,
    otherHandle: fromCard?.handle ?? null,
  };
  await Promise.all([
    ddb.send(new PutCommand({ TableName: FRIENDS, Item: edgeA })),
    ddb.send(new PutCommand({ TableName: FRIENDS, Item: edgeB })),
  ]);
  // Push to the person being asked (best-effort; no-op until APNs is wired).
  await sendPushToUser(toUserId, {
    title: "New friend request",
    body: `${fromCard?.name ?? "Someone"} wants to be gift friends`,
    data: { type: "friend_request", fromUserId },
  });
  return json(200, { ok: true, status: "pending" });
}

async function acceptFriend(body, auth) {
  if (!FRIENDS) return json(503, { error: "friends table not configured" });
  const userId = String(body.userId || auth?.sub || "").trim();
  const fromUserId = String(body.fromUserId || "").trim();
  if (!userId || !fromUserId) return json(400, { error: "userId and fromUserId required" });

  const mine = await getFriendship(userId, fromUserId);
  if (!mine) return json(404, { error: "friend request not found" });
  if (mine.status === "accepted") return json(200, { ok: true, status: "accepted", already: true });
  if (mine.requestedBy === userId) {
    return json(400, { error: "cannot accept your own outgoing request" });
  }

  const now = Date.now();
  await Promise.all([
    ddb.send(
      new UpdateCommand({
        TableName: FRIENDS,
        Key: { pk: userId, sk: `FRIEND#${fromUserId}` },
        UpdateExpression: "SET #s = :s, updatedAt = :now",
        ExpressionAttributeNames: { "#s": "status" },
        ExpressionAttributeValues: { ":s": "accepted", ":now": now },
      })
    ),
    ddb.send(
      new UpdateCommand({
        TableName: FRIENDS,
        Key: { pk: fromUserId, sk: `FRIEND#${userId}` },
        UpdateExpression: "SET #s = :s, updatedAt = :now",
        ExpressionAttributeNames: { "#s": "status" },
        ExpressionAttributeValues: { ":s": "accepted", ":now": now },
      })
    ),
  ]);
  // Open a DM thread so they can message immediately.
  await ensureDmThread(userId, fromUserId);
  const meCard = await loadUserCard(userId).catch(() => null);
  await sendPushToUser(fromUserId, {
    title: "Friend request accepted 🎉",
    body: `${meCard?.name ?? "Your friend"} accepted — start planning gifts together`,
    data: { type: "friend_accept", fromUserId: userId },
  });
  return json(200, { ok: true, status: "accepted" });
}

async function declineFriend(body, auth) {
  if (!FRIENDS) return json(503, { error: "friends table not configured" });
  const userId = String(body.userId || auth?.sub || "").trim();
  const fromUserId = String(body.fromUserId || body.friendId || "").trim();
  if (!userId || !fromUserId) return json(400, { error: "userId and fromUserId required" });
  await Promise.all([
    ddb.send(new DeleteCommand({ TableName: FRIENDS, Key: { pk: userId, sk: `FRIEND#${fromUserId}` } })),
    ddb.send(new DeleteCommand({ TableName: FRIENDS, Key: { pk: fromUserId, sk: `FRIEND#${userId}` } })),
  ]);
  return json(200, { ok: true });
}

async function listFriends(qs) {
  if (!FRIENDS) return json(200, { items: [] });
  const userId = String(qs.userId || "").trim();
  if (!userId) return json(400, { error: "userId required" });
  const status = qs.status ? String(qs.status) : null;
  const out = await ddb.send(
    new QueryCommand({
      TableName: FRIENDS,
      KeyConditionExpression: "pk = :p AND begins_with(sk, :pfx)",
      ExpressionAttributeValues: { ":p": userId, ":pfx": "FRIEND#" },
      Limit: 200,
    })
  );
  let items = (out.Items ?? []).map((it) => friendFromItem(it, userId));
  if (status) items = items.filter((f) => f.status === status);
  // Enrich with public profile cards when available.
  const enriched = await Promise.all(
    items.map(async (f) => {
      const card = await loadUserCard(f.friendId, f.status === "accepted");
      return card ? { ...f, ...card, friendId: f.friendId } : f;
    })
  );
  return json(200, { items: enriched });
}

async function friendshipStatus(qs) {
  const userId = String(qs.userId || "").trim();
  const otherId = String(qs.otherId || "").trim();
  if (!userId || !otherId) return json(400, { error: "userId and otherId required" });
  const item = await getFriendship(userId, otherId);
  if (!item) return json(200, { status: "none" });
  return json(200, {
    status: item.status,
    requestedBy: item.requestedBy ?? null,
    incoming: item.requestedBy && item.requestedBy !== userId,
  });
}

// ── Direct messages ──────────────────────────────────────────────────────────

async function ensureDmThread(userA, userB) {
  if (!FRIENDS) return null;
  const threadId = threadIdFor(userA, userB);
  const existing = await ddb.send(
    new GetCommand({ TableName: FRIENDS, Key: { pk: threadId, sk: "META" } })
  );
  if (existing.Item) return threadId;

  const now = Date.now();
  const cardA = await loadUserCard(userA);
  const cardB = await loadUserCard(userB);
  await Promise.all([
    ddb.send(
      new PutCommand({
        TableName: FRIENDS,
        Item: {
          pk: threadId,
          sk: "META",
          userA,
          userB,
          createdAt: now,
          lastAt: now,
          lastText: null,
        },
      })
    ),
    ddb.send(
      new PutCommand({
        TableName: FRIENDS,
        Item: {
          pk: userA,
          sk: `DM#${threadId}`,
          threadId,
          otherUserId: userB,
          otherName: cardB?.name ?? null,
          otherHandle: cardB?.handle ?? null,
          lastAt: now,
          lastText: null,
        },
      })
    ),
    ddb.send(
      new PutCommand({
        TableName: FRIENDS,
        Item: {
          pk: userB,
          sk: `DM#${threadId}`,
          threadId,
          otherUserId: userA,
          otherName: cardA?.name ?? null,
          otherHandle: cardA?.handle ?? null,
          lastAt: now,
          lastText: null,
        },
      })
    ),
  ]);
  return threadId;
}

async function openDm(body, auth) {
  if (!FRIENDS) return json(503, { error: "friends table not configured" });
  const userId = String(body.userId || auth?.sub || "").trim();
  const otherUserId = String(body.otherUserId || "").trim();
  if (!userId || !otherUserId) return json(400, { error: "userId and otherUserId required" });
  const edge = await getFriendship(userId, otherUserId);
  if (!edge || edge.status !== "accepted") {
    return json(403, { error: "must be friends to message" });
  }
  const threadId = await ensureDmThread(userId, otherUserId);
  return json(200, { ok: true, threadId });
}

async function listDms(qs) {
  if (!FRIENDS) return json(200, { items: [] });
  const userId = String(qs.userId || "").trim();
  if (!userId) return json(400, { error: "userId required" });
  const out = await ddb.send(
    new QueryCommand({
      TableName: FRIENDS,
      KeyConditionExpression: "pk = :p AND begins_with(sk, :pfx)",
      ExpressionAttributeValues: { ":p": userId, ":pfx": "DM#" },
      Limit: 100,
    })
  );
  const items = (out.Items ?? [])
    .map((it) => ({
      threadId: it.threadId ?? it.sk?.replace(/^DM#/, ""),
      otherUserId: it.otherUserId,
      otherName: it.otherName ?? null,
      otherHandle: it.otherHandle ?? null,
      lastText: it.lastText ?? null,
      lastAt: it.lastAt ?? 0,
    }))
    .sort((a, b) => (b.lastAt ?? 0) - (a.lastAt ?? 0));
  return json(200, { items });
}

async function getDmMessages(threadId, qs) {
  if (!FRIENDS) return json(200, { items: [] });
  const tid = decodeURIComponent(threadId);
  if (!tid.startsWith("DM#")) return json(400, { error: "invalid threadId" });
  const after = qs.after ? String(qs.after) : "";
  const out = await ddb.send(
    new QueryCommand(
      after
        ? {
            TableName: FRIENDS,
            KeyConditionExpression: "pk = :p AND sk > :after",
            ExpressionAttributeValues: { ":p": tid, ":after": `MSG#${after}` },
            Limit: 300,
          }
        : {
            TableName: FRIENDS,
            KeyConditionExpression: "pk = :p AND begins_with(sk, :pfx)",
            ExpressionAttributeValues: { ":p": tid, ":pfx": "MSG#" },
            Limit: 300,
          }
    )
  );
  const items = (out.Items ?? [])
    .map((it) => ({
      id: it.sk,
      userId: it.userId,
      name: it.name,
      text: it.text,
      at: it.at ?? 0,
    }))
    .sort((a, b) => a.at - b.at);
  return json(200, { items });
}

async function postDmMessage(threadId, body, auth) {
  if (!FRIENDS) return json(503, { error: "friends table not configured" });
  const tid = decodeURIComponent(threadId);
  if (!tid.startsWith("DM#")) return json(400, { error: "invalid threadId" });
  const userId = String(body.userId || auth?.sub || "").trim();
  const name = (String(body.name || "").trim() || "Someone").slice(0, 80);
  const text = String(body.text || "").trim().slice(0, 1000);
  if (!userId) return json(400, { error: "userId required" });
  if (!text) return json(400, { error: "text required" });

  const meta = await ddb.send(
    new GetCommand({ TableName: FRIENDS, Key: { pk: tid, sk: "META" } })
  );
  if (!meta.Item) return json(404, { error: "thread not found" });
  const { userA, userB } = meta.Item;
  if (userId !== userA && userId !== userB) {
    return json(403, { error: "not a participant" });
  }

  const at = Date.now();
  const item = {
    pk: tid,
    sk: `MSG#${at}#${gid()}`,
    userId,
    name,
    text,
    at,
  };
  await ddb.send(new PutCommand({ TableName: FRIENDS, Item: item }));

  // Bump META + both users' DM index rows.
  const otherId = userId === userA ? userB : userA;
  await Promise.all([
    ddb.send(
      new UpdateCommand({
        TableName: FRIENDS,
        Key: { pk: tid, sk: "META" },
        UpdateExpression: "SET lastAt = :at, lastText = :t",
        ExpressionAttributeValues: { ":at": at, ":t": text.slice(0, 140) },
      })
    ),
    ddb.send(
      new UpdateCommand({
        TableName: FRIENDS,
        Key: { pk: userId, sk: `DM#${tid}` },
        UpdateExpression: "SET lastAt = :at, lastText = :t",
        ExpressionAttributeValues: { ":at": at, ":t": text.slice(0, 140) },
      })
    ),
    ddb.send(
      new UpdateCommand({
        TableName: FRIENDS,
        Key: { pk: otherId, sk: `DM#${tid}` },
        UpdateExpression: "SET lastAt = :at, lastText = :t",
        ExpressionAttributeValues: { ":at": at, ":t": text.slice(0, 140) },
      })
    ),
  ]);

  await sendPushToUser(otherId, {
    title: name,
    body: text.slice(0, 120),
    data: { type: "dm", threadId: tid, fromUserId: userId },
  });

  return json(200, {
    ok: true,
    message: { id: item.sk, userId, name, text, at },
  });
}

// ── Circle ↔ account linking ─────────────────────────────────────────────────
// Lets a signed-in user claim their seat in a circle so other members who also
// have the app can friend / message / gift them from the circle page.

async function claimCircleMember(circleId, body, auth) {
  if (!EVENTS) return json(503, { error: "events table not configured" });
  const userId = String(body.userId || auth?.sub || "").trim();
  const memberName = String(body.memberName || body.name || "").trim().slice(0, 40);
  if (!userId || !memberName) return json(400, { error: "userId and memberName required" });

  const pk = `CIRCLE#${circleId}`;
  const out = await ddb.send(
    new QueryCommand({
      TableName: EVENTS,
      KeyConditionExpression: "userId = :u",
      ExpressionAttributeValues: { ":u": pk },
    })
  );
  const rows = out.Items ?? [];
  if (!rows.some((r) => r.eventId === "META")) return json(404, { error: "circle not found" });
  const members = rows.filter((r) => String(r.eventId || "").startsWith("MEMBER#"));
  const existing = members.find(
    (r) => String(r.name ?? "").toLowerCase() === memberName.toLowerCase()
  );
  if (!existing) return json(404, { error: "member not found — join the circle first" });

  // Clear this userId from any other member seat in the same circle.
  for (const m of members) {
    if (m.linkedUserId === userId && m.eventId !== existing.eventId) {
      await ddb.send(
        new UpdateCommand({
          TableName: EVENTS,
          Key: { userId: pk, eventId: m.eventId },
          UpdateExpression: "REMOVE linkedUserId, linkedAt",
        })
      );
    }
  }

  const card = await loadUserCard(userId);
  await ddb.send(
    new UpdateCommand({
      TableName: EVENTS,
      Key: { userId: pk, eventId: existing.eventId },
      UpdateExpression:
        "SET linkedUserId = :u, linkedAt = :now, linkedName = :n, linkedHandle = :h",
      ExpressionAttributeValues: {
        ":u": userId,
        ":now": Date.now(),
        ":n": card?.name ?? memberName,
        ":h": card?.handle ?? null,
      },
    })
  );
  return json(200, {
    ok: true,
    memberId: existing.eventId.slice(7),
    linkedUserId: userId,
  });
}

// ── Router ───────────────────────────────────────────────────────────────────

export async function friendsRoutes(method, path, body, qs = {}, auth = null) {
  // GET /people?q=
  if (method === "GET" && path === "/people") return searchPeople(qs);
  // GET /people/{userId}
  if (method === "GET" && /^\/people\/[^/]+$/.test(path)) {
    return getPerson(decodeURIComponent(path.split("/")[2]), auth?.sub ?? null);
  }

  // Friendships
  if (method === "POST" && path === "/friends/request") return requestFriend(body, auth);
  if (method === "POST" && path === "/friends/accept") return acceptFriend(body, auth);
  if (method === "POST" && path === "/friends/decline") return declineFriend(body, auth);
  if (method === "POST" && path === "/friends/remove") return declineFriend(body, auth);
  if (method === "GET" && path === "/friends") return listFriends(qs);
  if (method === "GET" && path === "/friends/status") return friendshipStatus(qs);

  // DMs
  if (method === "POST" && path === "/dms/open") return openDm(body, auth);
  if (method === "GET" && path === "/dms") return listDms(qs);
  if (method === "GET" && /^\/dms\/[^/]+\/messages$/.test(path)) {
    const tid = path.split("/")[2];
    return getDmMessages(tid, qs);
  }
  if (method === "POST" && /^\/dms\/[^/]+\/messages$/.test(path)) {
    const tid = path.split("/")[2];
    return postDmMessage(tid, body, auth);
  }

  // Circle account claim
  if (method === "POST" && /^\/circles\/[^/]+\/claim$/.test(path)) {
    const circleId = decodeURIComponent(path.split("/")[2]);
    return claimCircleMember(circleId, body, auth);
  }

  return null; // not handled — let the main handler keep going
}
