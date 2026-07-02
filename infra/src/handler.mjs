// Giftmaxxing API — single Lambda behind an HTTP API ($default proxy route).
// Uses AWS SDK v3, which is bundled into the nodejs20.x runtime (no deps to ship).
import { DynamoDBClient } from "@aws-sdk/client-dynamodb";
import {
  DynamoDBDocumentClient,
  GetCommand,
  PutCommand,
  QueryCommand,
  ScanCommand,
  BatchWriteCommand,
  UpdateCommand,
  DeleteCommand,
} from "@aws-sdk/lib-dynamodb";
import {
  S3VectorsClient,
  QueryVectorsCommand,
  GetVectorsCommand,
  ListVectorsCommand,
} from "@aws-sdk/client-s3vectors";
import { BedrockRuntimeClient, InvokeModelCommand, ConverseCommand } from "@aws-sdk/client-bedrock-runtime";
import { classifyPin } from "./quality.mjs";
import { createRemoteJWKSet, jwtVerify } from "jose";

const ddb = DynamoDBDocumentClient.from(new DynamoDBClient({}), {
  marshallOptions: { removeUndefinedValues: true },
});

const USERS = process.env.USERS_TABLE;
const POSTS = process.env.POSTS_TABLE;
const INTERACTIONS = process.env.INTERACTIONS_TABLE;
const KNOWLEDGE = process.env.KNOWLEDGE_TABLE;
const CONNECTIONS = process.env.CONNECTIONS_TABLE;
const POOLS = process.env.POOLS_TABLE;
const EVENTS = process.env.EVENTS_TABLE;
const GRAPH = process.env.GRAPH_TABLE;
const CONFIG = process.env.CONFIG_TABLE;

// ── byFeed GSI sharding (Phase 4b) ───────────────────────────────────────────
// The global feed rides one GSI partition key (feedPk="all"). Past a few thousand
// RCU/s that single partition is a bottleneck, so FEED_SHARDS>1 spreads writes
// across feedPk="all#0".."all#<N-1>" (deterministic by postId) and reads scatter-
// gather across every shard. Default 1 = the original single-partition layout, so
// turning this on is a no-op until posts are (re-)ingested into shards.
const FEED_SHARDS = Math.max(1, Number(process.env.FEED_SHARDS || 1));

// Deterministic shard for a post's feedPk on write (hashStr is hoisted below).
function feedShardForPost(postId) {
  return FEED_SHARDS <= 1 ? "all" : `all#${hashStr(postId) % FEED_SHARDS}`;
}

// Every feedPk a read must cover. Always includes the legacy "all" so rows written
// before sharding was enabled are still served during/after the migration.
function feedShardKeys() {
  if (FEED_SHARDS <= 1) return ["all"];
  const keys = ["all"];
  for (let i = 0; i < FEED_SHARDS; i++) keys.push(`all#${i}`);
  return keys;
}

// ── API authentication ───────────────────────────────────────────────────────
// Protects the API so the live data store isn't world-readable/writable. A
// request is authorized if it carries EITHER a valid Clerk session JWT (real
// signed-in users) OR the x-admin-token shared secret (the local admin-dev
// bypass + server-side ingest). Enforcement is gated by AUTH_ENFORCE so the code
// can ship dark, then be switched on (and instantly rolled back) via one env
// flip — no code change needed.
const AUTH_ENFORCE = process.env.AUTH_ENFORCE === "1";
const ADMIN_API_SECRET = process.env.ADMIN_API_SECRET || "";
const CLERK_ISSUER = process.env.CLERK_ISSUER || "";
const _clerkJwks = CLERK_ISSUER
  ? createRemoteJWKSet(new URL(`${CLERK_ISSUER}/.well-known/jwks.json`))
  : null;

// Open routes (no token): public product catalog + the anonymous guest viral
// write (POST /connections). Default-deny: anything not listed is protected.
function isPublicRoute(method, path) {
  if (method === "OPTIONS") return true;
  if (method === "GET") {
    if (path === "/feed" || path === "/recommendations" || path === "/pins") return true;
    if (path === "/recipients" || path === "/ideas") return true;
    if (path === "/vectors") return true;
    if (path.startsWith("/posts/")) return true;
  }
  if (method === "POST" && (path === "/visual-search" || path === "/connections")) return true;
  return false;
}

// Constant-time compare so the admin secret can't be guessed via timing.
function timingSafeEqual(a, b) {
  if (typeof a !== "string" || typeof b !== "string" || a.length !== b.length) return false;
  let r = 0;
  for (let i = 0; i < a.length; i++) r |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return r === 0;
}

function hasAdminToken(event) {
  if (!ADMIN_API_SECRET) return false;
  const h = event.headers || {};
  const tok = h["x-admin-token"] || h["X-Admin-Token"] || "";
  return timingSafeEqual(tok, ADMIN_API_SECRET);
}

function bearerToken(event) {
  const h = event.headers || {};
  const auth = h.authorization || h.Authorization || "";
  const m = /^Bearer\s+(.+)$/i.exec(auth);
  return m ? m[1] : null;
}

async function verifyClerkJwt(event) {
  if (!_clerkJwks || !CLERK_ISSUER) return null;
  const token = bearerToken(event);
  if (!token) return null;
  try {
    const { payload } = await jwtVerify(token, _clerkJwks, { issuer: CLERK_ISSUER });
    return payload?.sub ? String(payload.sub) : null;
  } catch {
    return null;
  }
}

// ── iOS-app identities ───────────────────────────────────────────────────────
// The native app signs users in with Google (ASWebAuthenticationSession) or
// Sign in with Apple→Cognito, not Clerk. Accept those verified ID tokens too so
// signed-in iOS users reach the auth-gated routes (/maxi, /me, /events, …).
// Both verifiers are env-gated: unset vars = feature dark, zero behavior change.
const GOOGLE_OAUTH_CLIENT_ID = process.env.GOOGLE_OAUTH_CLIENT_ID || "";
const _googleJwks = GOOGLE_OAUTH_CLIENT_ID
  ? createRemoteJWKSet(new URL("https://www.googleapis.com/oauth2/v3/certs"))
  : null;

async function verifyGoogleIdToken(event) {
  if (!_googleJwks) return null;
  const token = bearerToken(event);
  if (!token) return null;
  try {
    const { payload } = await jwtVerify(token, _googleJwks, {
      issuer: ["https://accounts.google.com", "accounts.google.com"],
      audience: GOOGLE_OAUTH_CLIENT_ID,
    });
    // Prefix mirrors the iOS client's local userId convention ("google_<sub>")
    // so profile/memory rows line up across sessions.
    return payload?.sub ? `google_${payload.sub}` : null;
  } catch {
    return null;
  }
}

const COGNITO_ISSUER = process.env.COGNITO_ISSUER || "";
const _cognitoJwks = COGNITO_ISSUER
  ? createRemoteJWKSet(new URL(`${COGNITO_ISSUER}/.well-known/jwks.json`))
  : null;

async function verifyCognitoJwt(event) {
  if (!_cognitoJwks || !COGNITO_ISSUER) return null;
  const token = bearerToken(event);
  if (!token) return null;
  try {
    const { payload } = await jwtVerify(token, _cognitoJwks, { issuer: COGNITO_ISSUER });
    return payload?.sub ? String(payload.sub) : null;
  } catch {
    return null;
  }
}

// /seed is admin-only (ingest). Other protected routes accept a Clerk JWT (web),
// a Google/Cognito ID token (iOS app), OR the admin token.
async function authorizeRequest(event, method, path) {
  if (hasAdminToken(event)) return { ok: true, sub: "admin", via: "admin" };
  if (method === "POST" && path === "/seed") return { ok: false };
  const clerkSub = await verifyClerkJwt(event);
  if (clerkSub) return { ok: true, sub: clerkSub, via: "clerk" };
  const googleSub = await verifyGoogleIdToken(event);
  if (googleSub) return { ok: true, sub: googleSub, via: "google" };
  const cognitoSub = await verifyCognitoJwt(event);
  if (cognitoSub) return { ok: true, sub: cognitoSub, via: "cognito" };
  return { ok: false };
}

// ── Cost guard: tiered degradation flag (DynamoDB config table) ──────────────
// The breaker Lambda writes a { level } onto the feature-flags item (Phase 3):
//   • "active"   — everything on.
//   • "degraded" — a real-time alarm tripped: shed the heaviest AI (visual search,
//     vector recs, /pins) and run Maxi cheap+short (base model, fewer steps). Set
//     by an ALARM transition; AUTO-RESUMES when the alarm clears (OK transition) or
//     after the 30-min backstop below — no human, no 3 AM page.
//   • "paused"   — the monthly budget LIMIT tripped (hard cost cap): kill all
//     non-essential AI. Human resume only.
// Read with a short in-memory cache and FAIL-OPEN: any error / missing flag means
// "active", so a config glitch never takes the app down. Auth, feed/posts, and
// data-collection keep serving at every level. Legacy { paused:true } items still
// map to "paused" for back-compat.
const DEGRADE_LEVELS = new Set(["active", "degraded", "paused"]);
let _flagCache = { at: 0, level: "active" };
async function getDegradeLevel() {
  if (!CONFIG) return "active";
  const now = Date.now();
  if (now - _flagCache.at < 30000) return _flagCache.level;
  try {
    const out = await ddb.send(new GetCommand({ TableName: CONFIG, Key: { key: "feature-flags" } }));
    const it = out.Item || {};
    let level = DEGRADE_LEVELS.has(it.level) ? it.level : (it.paused === true ? "paused" : "active");
    // 30-min auto-resume backstop: if a DEGRADED window's autoResumeAt has passed,
    // self-heal to active on read even if the alarm-clear event was never delivered.
    // (A hard "paused" carries no autoResumeAt, so it never auto-resumes.)
    if (level === "degraded" && it.autoResumeAt && now >= Number(it.autoResumeAt)) {
      level = "active";
    }
    _flagCache = { at: now, level };
  } catch (err) {
    console.warn("getDegradeLevel read failed (fail-open):", err.message);
    _flagCache = { at: now, level: "active" };
  }
  return _flagCache.level;
}
// The expensive AI routes (Bedrock embeds, S3 Vectors) only run at full health;
// "degraded" and "paused" both shed them. /maxi reads getDegradeLevel() directly
// (it stays up, just cheaper, when degraded).
async function aiEnabled() {
  return (await getDegradeLevel()) === "active";
}

// S3 Vectors (the vector store powering similarity-based recommendations).
const VECTOR_BUCKET = process.env.VECTOR_BUCKET;
const VECTOR_INDEX = process.env.VECTOR_INDEX;
const s3v = VECTOR_BUCKET ? new S3VectorsClient({}) : null;

// Bedrock Titan Multimodal embeddings power visual search: an uploaded image is
// embedded into the SAME shared space the pin index was built with (see
// infra/ingest/embed.mjs), so image->image kNN works directly.
const EMBED_MODEL = process.env.BEDROCK_EMBED_MODEL_ID || "amazon.titan-embed-image-v1";
const VECTOR_DIM = Number(process.env.VECTOR_DIM || 1024);
const bedrock = new BedrockRuntimeClient({});

// Embed an uploaded image (base64, with or without a data-URL prefix) + optional
// text into a single 1024-d query vector via Titan Multimodal.
async function embedImage(imageB64, text) {
  const inputImage = String(imageB64).replace(/^data:image\/[a-z0-9.+-]+;base64,/i, "");
  const reqBody = { inputImage, embeddingConfig: { outputEmbeddingLength: VECTOR_DIM } };
  if (text) reqBody.inputText = String(text).slice(0, 200);
  const out = await bedrock.send(
    new InvokeModelCommand({
      modelId: EMBED_MODEL,
      contentType: "application/json",
      accept: "application/json",
      body: JSON.stringify(reqBody),
    })
  );
  return JSON.parse(Buffer.from(out.body).toString("utf8")).embedding;
}

const json = (statusCode, body, headers = {}) => ({
  statusCode,
  headers: { "content-type": "application/json", ...headers },
  body: JSON.stringify(body),
});

// Opaque pagination cursor = base64url(LastEvaluatedKey) for infinite scroll.
const encodeCursor = (k) => (k ? Buffer.from(JSON.stringify(k)).toString("base64url") : null);
const decodeCursor = (c) => {
  try {
    return c ? JSON.parse(Buffer.from(c, "base64url").toString()) : undefined;
  } catch {
    return undefined;
  }
};

const parseList = (s) => (s ? String(s).split(",").map((x) => x.trim()).filter(Boolean) : []);

// Content-based score over the enriched facets (mirrors web/lib/recommend.ts).
// Surfaces real giftable products (find/made) over idea-requests, blends in
// social proof, taste (vibes), explicit facet matches, and mild recency.
function scorePost(p, { vibes = [], recipient, occasion, category, budget, eventBoost = 0, now = Date.now() } = {}) {
  let s = 0;
  s += Math.min(1, (p.likes ?? 0) / 500) * 0.35; // social proof
  s += p.status === "find" ? 0.15 : p.status === "made" ? 0.12 : 0; // gift type
  if (vibes.length && Array.isArray(p.vibes)) {
    const hit = p.vibes.filter((v) => vibes.includes(v)).length;
    s += Math.min(1, hit / 2) * 0.25; // taste match
  }
  // Recipient/occasion matches count for more as a logged event approaches
  // (eventBoost ramps 0→1 over ~45 days; see web/lib/events.ts).
  const occMult = 1 + Math.max(0, Math.min(1, eventBoost));
  if (recipient && recipient !== "anyone" && p.recipient === recipient) s += 0.2 * occMult;
  if (occasion && occasion !== "any" && p.occasion === occasion) s += 0.15 * occMult;
  if (category && p.category === category) s += 0.2;
  // Budget fit: reward at/under the event's target, gently penalize over-budget.
  const price = Number(p.price ?? p.product?.price);
  if (budget && Number.isFinite(price) && price > 0) {
    s += price <= budget ? 0.15 : Math.max(-0.1, 0.15 - ((price - budget) / budget) * 0.25);
  }
  const ageDays = (now - (p.createdAt ?? now)) / 86400000;
  s += Math.max(0, 1 - ageDays / 365) * 0.1; // recency
  s += Math.random() * 0.08; // exploration
  return s;
}

// ── Feed freshness: per-user de-dup + variety ────────────────────────────────
// The byFeed GSI is newest-first and deterministic, so every visit used to serve
// the SAME head items. We (a) start each fresh load at a RANDOM point in the
// catalog's createdAt range and (b) drop anything the user has already
// seen/liked/saved — so the feed feels new every visit and never repeats. Bounds
// are cached (5 min) to avoid two extra reads per request.
let _feedBounds = { at: 0, min: 0, max: 0 };
async function getFeedBounds() {
  const now = Date.now();
  if (now - _feedBounds.at < 300000 && _feedBounds.max) return _feedBounds;
  try {
    const edge = (forward) =>
      ddb.send(
        new QueryCommand({
          TableName: POSTS,
          IndexName: "byFeed",
          KeyConditionExpression: "feedPk = :f",
          ExpressionAttributeValues: { ":f": "all" },
          ProjectionExpression: "createdAt",
          ScanIndexForward: forward,
          Limit: 1,
        })
      );
    const [newest, oldest] = await Promise.all([edge(false), edge(true)]);
    _feedBounds = {
      at: now,
      min: oldest.Items?.[0]?.createdAt ?? 0,
      max: newest.Items?.[0]?.createdAt ?? now,
    };
  } catch (e) {
    console.warn("getFeedBounds failed (no variety this req):", e.message);
  }
  return _feedBounds;
}

// Every target a user has already interacted with (seen/liked/saved/hidden) so
// the feed and recs can exclude them. One query on the interactions table.
async function userExcludeSet(userId) {
  if (!userId || !INTERACTIONS) return new Set();
  try {
    const inter = await ddb.send(
      new QueryCommand({
        TableName: INTERACTIONS,
        KeyConditionExpression: "userId = :u",
        ExpressionAttributeValues: { ":u": userId },
        ProjectionExpression: "target",
      })
    );
    return new Set((inter.Items ?? []).map((i) => i.target).filter(Boolean));
  } catch (e) {
    console.warn("userExcludeSet failed:", e.message);
    return new Set();
  }
}

// ── Vector recommendations (S3 Vectors) ──────────────────────────────────────
// Replaces the hand-tuned "taste" term with real embedding similarity: build a
// taste vector = centroid of the user's seed pin embeddings, then ask the index
// for nearest neighbors. Falls back (returns null) when no vectors are available.
async function getCentroid(keys) {
  if (!s3v || !keys.length) return null;
  const out = await s3v.send(
    new GetVectorsCommand({
      vectorBucketName: VECTOR_BUCKET,
      indexName: VECTOR_INDEX,
      keys: keys.slice(0, 20),
      returnData: true,
    })
  );
  const vecs = (out.vectors ?? []).map((v) => v.data?.float32).filter(Array.isArray);
  if (!vecs.length) return null;
  const dim = vecs[0].length;
  const c = new Array(dim).fill(0);
  for (const v of vecs) for (let i = 0; i < dim; i++) c[i] += v[i];
  for (let i = 0; i < dim; i++) c[i] /= vecs.length;
  return c;
}

function vecToItem(v) {
  const m = v.metadata ?? {};
  // Prefer the REAL outbound product link embedded in the vector metadata; fall
  // back to the Pinterest pin page for legacy vectors that predate that field.
  const productUrl = m.link || m.pinUrl || "";
  const price = typeof m.price === "number" ? m.price : Number(m.price) || 0;
  const merchant = m.domain || m.sourceUser || "Pinterest";
  const q = classifyPin({ title: m.title, domain: m.domain, link: productUrl, price });
  return {
    postId: v.key,
    author: m.sourceUser || "pinterest",
    image: m.imageUrl || "",
    s3Key: m.s3Key || "",
    name: m.title || "",
    contentType: q.contentType,
    qualityScore: q.qualityScore,
    feedEligible: q.feedEligible,
    route: q.route,
    // url = real product link (feed items use `url`); keep link for back-compat.
    url: productUrl,
    link: productUrl,
    pinUrl: m.pinUrl || "",
    price,
    priceDisplay: price > 0 ? `$${price}` : null,
    merchant,
    domain: m.domain || "",
    category: m.category || "",
    recipient: m.recipient || "anyone",
    occasion: m.occasion || "any",
    source: m.source || "pinterest",
    rec: true,
    reason: "Similar to your taste",
    // Nested product so card components that read item.product render buyable.
    product: {
      id: v.key,
      name: m.title || "",
      brand: merchant,
      price,
      image: m.imageUrl || "",
      url: productUrl,
    },
    _score: v.distance != null ? 1 - v.distance : null,
    _distance: v.distance ?? null,
  };
}

// Ranked post-shaped items from S3 Vectors, or null to fall back to facets.
async function vectorRecommend(seedKeys, { limit, sourceUser }) {
  const centroid = await getCentroid(seedKeys);
  if (!centroid) return null;
  const seen = new Set(seedKeys);
  const out = await s3v.send(
    new QueryVectorsCommand({
      vectorBucketName: VECTOR_BUCKET,
      indexName: VECTOR_INDEX,
      // Over-fetch: the quality filter below drops listicles/guides (~37%).
      topK: (limit + seedKeys.length) * 3,
      queryVector: { float32: centroid },
      returnMetadata: true,
      returnDistance: true,
      filter: sourceUser ? { sourceUser: { $eq: sourceUser } } : undefined,
    })
  );
  return (out.vectors ?? [])
    .filter((v) => !seen.has(v.key))
    .map(vecToItem)
    .filter((it) => it.feedEligible)
    .slice(0, limit);
}

// Server-side mirror of web/lib/events.ts date math: whole days until an event's
// next occurrence (annual rolls forward a year if it already passed; once is
// absolute). Returns null on a malformed date.
function eventDaysUntil(ev, now = new Date()) {
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

function computeUpcoming(events, withinDays = 90, now = new Date()) {
  return (events ?? [])
    .map((ev) => ({ ...ev, daysUntil: eventDaysUntil(ev, now) }))
    .filter((e) => e.daysUntil != null && e.daysUntil >= 0 && (withinDays <= 0 || e.daysUntil <= withinDays))
    .sort((a, b) => a.daysUntil - b.daysUntil);
}

// ── Network graph (DynamoDB single-table: nodes + edges) ─────────────────────
// Captures ALL data (hard onboarding data + soft swipe-derived taste) as one
// connected graph so nothing is lost. Partitioned by owner (userId); the
// byEntity GSI enables cross-owner traversal of edges into any node.
const gid = () =>
  globalThis.crypto?.randomUUID?.() ??
  `${Date.now().toString(36)}${Math.random().toString(36).slice(2, 10)}`;

// A node item (Put-safe: fully specified on every write).
function gNode(ownerId, type, id, { scope, label, data } = {}) {
  return {
    pk: ownerId,
    sk: `N#${type}#${id}`,
    kind: "node",
    entityId: `${type}#${id}`,
    type,
    ...(scope ? { scope } : {}),
    ...(label ? { label: String(label).slice(0, 120) } : {}),
    data: data ?? {},
    updatedAt: Date.now(),
  };
}

// A directed edge item. src/dst use "type:id" inside the sort key.
function gEdge(ownerId, rel, srcType, srcId, dstType, dstId, data) {
  return {
    pk: ownerId,
    sk: `E#${rel}#${srcType}:${srcId}#${dstType}:${dstId}`,
    kind: "edge",
    entityId: `${dstType}#${dstId}`,
    rel,
    srcRef: `${srcType}#${srcId}`,
    dstRef: `${dstType}#${dstId}`,
    data: data ?? {},
    updatedAt: Date.now(),
  };
}

// Interest nodes + LIKES edges connecting a source (user/recipient/soft) to each
// normalized interest tag — this is what makes the graph a real "network".
function interestItems(ownerId, srcType, srcId, interests) {
  const out = [];
  for (const raw of interests ?? []) {
    const tag = String(raw).trim().toLowerCase().slice(0, 40);
    if (!tag) continue;
    out.push(gNode(ownerId, "interest", tag, { label: tag }));
    out.push(gEdge(ownerId, "LIKES", srcType, srcId, "interest", tag));
  }
  return out;
}

// Best-effort batch Put of graph items. Never throws (the graph is a mirror).
async function graphWrite(items) {
  if (!GRAPH || !Array.isArray(items) || items.length === 0) return;
  const now = Date.now();
  const all = items.filter(Boolean).map((it) => ({ createdAt: now, ...it }));
  try {
    for (let i = 0; i < all.length; i += 25) {
      const chunk = all.slice(i, i + 25);
      await ddb.send(
        new BatchWriteCommand({
          RequestItems: { [GRAPH]: chunk.map((Item) => ({ PutRequest: { Item } })) },
        })
      );
    }
  } catch (err) {
    console.error("graphWrite error", err);
  }
}

// Merge-update a node's flat attributes (used for the user node so frequent
// identity pings never clobber profile data written by PUT /me, and vice versa).
async function graphMergeNode(ownerId, type, id, attrs = {}) {
  if (!GRAPH || !ownerId) return;
  const now = Date.now();
  const names = { "#type": "type", "#kind": "kind" };
  const values = { ":kind": "node", ":type": type, ":eid": `${type}#${id}`, ":now": now };
  const sets = [
    "#kind = :kind",
    "#type = :type",
    "entityId = :eid",
    "updatedAt = :now",
    "createdAt = if_not_exists(createdAt, :now)",
  ];
  let i = 0;
  for (const [k, v] of Object.entries(attrs)) {
    if (v === undefined || v === null) continue;
    const nk = `#a${i}`;
    const vk = `:a${i}`;
    names[nk] = k;
    values[vk] = v;
    sets.push(`${nk} = ${vk}`);
    i++;
  }
  try {
    await ddb.send(
      new UpdateCommand({
        TableName: GRAPH,
        Key: { pk: ownerId, sk: `N#${type}#${id}` },
        UpdateExpression: "SET " + sets.join(", "),
        ExpressionAttributeNames: names,
        ExpressionAttributeValues: values,
      })
    );
  } catch (err) {
    console.error("graphMergeNode error", err);
  }
}

// Fan out a saved profile into the events table (scope-tagged) + the network
// graph (user/recipient/event/interest nodes + edges). Best-effort.
async function captureProfile(userId, profile) {
  try {
    const recipients = Array.isArray(profile.recipients) ? profile.recipients : [];
    const events = Array.isArray(profile.events) ? profile.events : [];
    const byId = Object.fromEntries(recipients.map((r) => [r.id, r]));

    await graphMergeNode(userId, "user", userId, {
      scope: "personal",
      label: profile.name || undefined,
      role: profile.role || undefined,
      style: profile.style || undefined,
      interests: Array.isArray(profile.interests) ? profile.interests : undefined,
    });

    const g = [];
    g.push(...interestItems(userId, "user", userId, profile.interests));
    for (const r of recipients) {
      if (!r?.id) continue;
      g.push(
        gNode(userId, "recipient", r.id, {
          scope: "shared",
          label: r.name,
          data: { name: r.name, relation: r.relation, interests: r.interests ?? [] },
        })
      );
      g.push(gEdge(userId, "GIFTS_TO", "user", userId, "recipient", r.id, { relation: r.relation }));
      g.push(...interestItems(userId, "recipient", r.id, r.interests));
    }
    for (const ev of events) {
      if (!ev?.id) continue;
      const scope = ev.recipientId ? "shared" : "personal";
      g.push(
        gNode(userId, "event", ev.id, {
          scope,
          label: ev.type,
          data: { type: ev.type, date: ev.date, recurrence: ev.recurrence, budget: ev.budget, recipientId: ev.recipientId },
        })
      );
      if (ev.recipientId)
        g.push(gEdge(userId, "HAS_EVENT", "recipient", ev.recipientId, "event", ev.id, { type: ev.type, date: ev.date }));
      else g.push(gEdge(userId, "HAS_EVENT", "user", userId, "event", ev.id, { type: ev.type, date: ev.date }));
    }
    await graphWrite(g);

    if (EVENTS && events.length) {
      const now = Date.now();
      const evItems = events
        .filter((e) => e?.id)
        .map((ev) => ({
          userId,
          eventId: ev.id,
          scope: ev.recipientId ? "shared" : "personal",
          kind: "occasion",
          type: ev.type,
          date: ev.date,
          recurrence: ev.recurrence,
          reminderLeadDays: ev.reminderLeadDays,
          budget: ev.budget,
          recipientId: ev.recipientId,
          recipientName: byId[ev.recipientId]?.name,
          updatedAt: now,
          createdAt: now,
        }));
      for (let i = 0; i < evItems.length; i += 25) {
        const chunk = evItems.slice(i, i + 25);
        if (chunk.length)
          await ddb.send(
            new BatchWriteCommand({ RequestItems: { [EVENTS]: chunk.map((Item) => ({ PutRequest: { Item } })) } })
          );
      }
    }
  } catch (err) {
    console.error("captureProfile error", err);
  }
}

// Mirror a soft profile (challenge connection) into the events table (shared) +
// the network graph (soft node, COLLECTED edge, interest edges). Best-effort.
async function captureConnection(item) {
  try {
    const ownerId = item.userId;
    const g = [
      gNode(ownerId, "soft", item.connectionId, {
        scope: "shared",
        label: item.guestName,
        data: {
          guestName: item.guestName,
          birthday: item.birthday,
          vibes: item.vibes,
          seeds: item.seeds,
          interests: item.interests,
          yesCount: item.yesCount,
          totalSwipes: item.totalSwipes,
        },
      }),
      gEdge(ownerId, "COLLECTED", "user", ownerId, "soft", item.connectionId, { kind: "challenge" }),
      ...interestItems(ownerId, "soft", item.connectionId, [...(item.interests || []), ...(item.vibes || [])]),
    ];
    await graphWrite(g);
    if (EVENTS) {
      await ddb.send(
        new PutCommand({
          TableName: EVENTS,
          Item: {
            userId: ownerId,
            eventId: item.connectionId,
            scope: "shared",
            kind: "soft-profile",
            type: "birthday",
            date: item.birthday,
            recipientName: item.guestName,
            soft: true,
            taste: { vibes: item.vibes, seeds: item.seeds, interests: item.interests },
            createdAt: item.createdAt,
            updatedAt: Date.now(),
          },
        })
      );
    }
  } catch (err) {
    console.error("captureConnection error", err);
  }
}

// ── Maxi: the Haiku 4.5 gift concierge (Bedrock Converse + tool use) ─────────
// Real LLM agent hosted IN this Lambda (no container): the browser POSTs the
// chat transcript to /maxi, we run a bounded tool-use loop where each tool reads
// the SAME data the rest of the API serves, then return { say, pins, actions }.
// Long-term memory lives as MEM# items in the graph table (pk=userId) and is
// invisible to GET /graph (which only returns kind node|edge).
// ── Maxi model router ───────────────────────────────────────────────────
// Two Bedrock tiers, chosen per request to keep cost low:
//   • BASE (default): Amazon's own model (Nova) — cheapest; handles browsing,
//     gift discovery, taste chat, and Q&A.
//   • SHOPPING: a stronger model (Claude Haiku) — used when an AGENTIC SHOPPING
//     experience is triggered (the user wants to add to cart / buy / checkout, or
//     the agent itself reaches for a cart/checkout tool mid-loop), where reliable
//     multi-step tool orchestration matters more than raw token price.
const MAXI_BASE_MODEL_ID = process.env.MAXI_BASE_MODEL_ID || "us.amazon.nova-lite-v1:0";
const MAXI_SHOPPING_MODEL_ID =
  process.env.MAXI_SHOPPING_MODEL_ID || process.env.MAXI_MODEL_ID || "us.anthropic.claude-haiku-4-5-20251001-v1:0";

// Tools that, once the agent reaches for them, mean we're in a shopping flow.
const MAXI_SHOPPING_TOOLS = new Set(["add_to_cart", "checkout"]);

// Transactional intent in the user's message. Mirrors the offline responder's
// regexes (web/lib/maxi.ts) so the router and the fallback agree on "shopping".
const MAXI_SHOPPING_INTENT_RE = new RegExp(
  [
    "check\\s?out",
    "place (an |the |my )?order",
    "order now",
    "buy\\b",
    "purchase",
    "complete (my )?(purchase|order)",
    "pay( now)?",
    "add .*(cart|basket)",
    "add (it|that|this|these|them|the first|the second|the third|one|two|three|all)\\b",
    "(my|the) (cart|basket)",
    "add to cart",
    "re-?stock",
    "re-?order",
    "buy (it |them )?again",
    "(things?|stuff|items?) i (buy|order|use|restock)",
    "deals? on .*(buy|order|restock|use|need)",
  ].join("|"),
  "i"
);

// Pick the tier for a request: an explicit client signal wins, otherwise sniff
// transactional intent from the latest user message.
function maxiIsShopping(userText, body) {
  if (body && (body.mode === "shopping" || body.agentic === true || body.shopping === true)) return true;
  return MAXI_SHOPPING_INTENT_RE.test(String(userText || ""));
}

// ── Maxi budgets (token-per-interaction + monthly Bedrock $ cap) ─────────────
// Per-INTERACTION: maxTokens caps output per model call; MAXI_INTERACTION_TOKEN_
// BUDGET hard-caps TOTAL tokens (in+out) summed across the tool-use loop — when
// exceeded we stop looping. Per-MONTH: an estimated-USD Bedrock cap tracked in
// the config table (key maxi-budget#YYYY-MM, atomic ADD, per-month key so there's
// no reset logic); when hit, /maxi 503s and the client falls back to the offline
// responder. Prices are env-driven — VERIFY against Bedrock's Haiku 4.5 pricing.
const MAXI_MAX_TOKENS = Number(process.env.MAXI_MAX_TOKENS || 768);
const MAXI_INTERACTION_TOKEN_BUDGET = Number(process.env.MAXI_INTERACTION_TOKEN_BUDGET || 30000);
const MAXI_MAX_STEPS = Number(process.env.MAXI_MAX_STEPS || 5);
const MAXI_MONTHLY_BUDGET_USD = Number(process.env.MAXI_MONTHLY_BUDGET_USD || 25);
// Per-user daily chat cap (abuse guard, not a usage cap). 0 = unlimited.
const MAXI_DAILY_LIMIT = Number(process.env.MAXI_DAILY_LIMIT || 50);
// Per-tier Bedrock prices (USD per 1M tokens) so the monthly $ budget stays
// accurate even when one interaction spans both models. BASE defaults to Amazon
// Nova Lite; SHOPPING falls back to the legacy MAXI_PRICE_* (Haiku) numbers.
// VERIFY all four against current Bedrock pricing.
const MAXI_BASE_PRICE_IN_PER_1M = Number(process.env.MAXI_BASE_PRICE_IN_PER_1M || 0.06);
const MAXI_BASE_PRICE_OUT_PER_1M = Number(process.env.MAXI_BASE_PRICE_OUT_PER_1M || 0.24);
const MAXI_SHOPPING_PRICE_IN_PER_1M = Number(
  process.env.MAXI_SHOPPING_PRICE_IN_PER_1M || process.env.MAXI_PRICE_IN_PER_1M || 1.0
);
const MAXI_SHOPPING_PRICE_OUT_PER_1M = Number(
  process.env.MAXI_SHOPPING_PRICE_OUT_PER_1M || process.env.MAXI_PRICE_OUT_PER_1M || 5.0
);

const maxiMonthKey = () => `maxi-budget#${new Date().toISOString().slice(0, 7)}`;

// Cost of a single model call, priced by the model that actually served it.
function maxiStepCostUsd(modelId, inTok, outTok) {
  const shopping = modelId === MAXI_SHOPPING_MODEL_ID;
  const pin = shopping ? MAXI_SHOPPING_PRICE_IN_PER_1M : MAXI_BASE_PRICE_IN_PER_1M;
  const pout = shopping ? MAXI_SHOPPING_PRICE_OUT_PER_1M : MAXI_BASE_PRICE_OUT_PER_1M;
  return ((Number(inTok) || 0) / 1e6) * pin + ((Number(outTok) || 0) / 1e6) * pout;
}

// Month-to-date Maxi Bedrock spend (USD). Fail-open to 0 so a read error never
// blocks Maxi (the per-interaction token cap still bounds any single call).
async function maxiSpentThisMonth() {
  if (!CONFIG) return 0;
  try {
    const out = await ddb.send(new GetCommand({ TableName: CONFIG, Key: { key: maxiMonthKey() } }));
    return Number(out.Item?.spentUsd) || 0;
  } catch (e) {
    console.warn("maxiSpentThisMonth read failed (fail-open):", e.message);
    return 0;
  }
}

// Atomically add this interaction's usage to the month's counter (best-effort).
async function recordMaxiUsage(inTok, outTok, costUsd) {
  if (!CONFIG) return;
  try {
    await ddb.send(
      new UpdateCommand({
        TableName: CONFIG,
        Key: { key: maxiMonthKey() },
        UpdateExpression: "SET updatedAt = :now ADD spentUsd :c, tokensIn :i, tokensOut :o",
        ExpressionAttributeValues: {
          ":now": Date.now(),
          ":c": Number(costUsd) || 0,
          ":i": Number(inTok) || 0,
          ":o": Number(outTok) || 0,
        },
      })
    );
  } catch (e) {
    console.warn("recordMaxiUsage failed:", e.message);
  }
}

// ── Per-user Maxi rate limit (Phase 3) ───────────────────────────────────────
// Abuse guard, not a usage cap: cap chats per principal per UTC day with an atomic
// counter in the config table (key maxi-rate#<day>#<principal>). The principal is
// the VERIFIED Clerk sub when auth is enforced, so it can't be spoofed via
// body.userId. Rows carry a TTL (expiresAt) so they self-purge. FAIL-OPEN: a
// counter error never blocks a real user.
const _utcDay = () => new Date().toISOString().slice(0, 10);
function _secondsUntilUtcMidnight() {
  const now = Date.now();
  const d = new Date(now);
  const next = Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate() + 1);
  return Math.max(1, Math.ceil((next - now) / 1000));
}
async function checkMaxiRateLimit(principal) {
  if (!CONFIG || MAXI_DAILY_LIMIT <= 0 || !principal) return { ok: true };
  const key = `maxi-rate#${_utcDay()}#${principal}`;
  const expiresAt = Math.floor(Date.now() / 1000) + 2 * 86400; // self-purge after 2 days
  try {
    const out = await ddb.send(
      new UpdateCommand({
        TableName: CONFIG,
        Key: { key },
        UpdateExpression: "ADD #c :one SET expiresAt = if_not_exists(expiresAt, :ttl), updatedAt = :now",
        ExpressionAttributeNames: { "#c": "count" },
        ExpressionAttributeValues: { ":one": 1, ":ttl": expiresAt, ":now": Date.now() },
        ReturnValues: "UPDATED_NEW",
      })
    );
    const count = Number(out.Attributes?.count) || 0;
    if (count > MAXI_DAILY_LIMIT) return { ok: false, count, retryAfterSec: _secondsUntilUtcMidnight() };
    return { ok: true, count };
  } catch (e) {
    console.warn("checkMaxiRateLimit failed (fail-open):", e.message);
    return { ok: true };
  }
}

const MAXI_SYSTEM = `You are Maxi, the gift concierge inside Giftmaxxing. You help people find, shortlist, and (simulated) check out gifts, and you remember their taste and the people they shop for.

Voice: warm, concise, a little playful — 1 to 3 sentences. You may be read aloud, so avoid markdown tables and long lists; at most one tasteful emoji.

IMPORTANT — identity rules:
- The user's first name is provided in the system prompt below (if known). ALWAYS use that name when addressing the user.
- get_profile returns the user's OWN profile. The "yourName" field is the user's own name. The "recipients" list contains OTHER people the user shops for — never confuse a recipient's name with the user's name.
- list_connections returns friends/contacts ("soft profiles") — these are OTHER people, NOT the user. Their "friendName" field is the friend's name.
- relationship_graph returns "otherPeople" — these are OTHER people in the user's gifting network, NOT the user themselves.
- If the user asks "what is my name?" or similar, respond with the name from the system prompt or from get_profile's "yourName" field. NEVER return a connection's or recipient's name as the user's name.

Use tools, don't guess:
- Find gifts by budget / vibe / recipient / category with find_gifts.
- "Deals on what I buy/restock most", "reorder", "buy again": call order_history FIRST to find the user's most-restocked categories, THEN call find_deals for those categories, then briefly summarize the best deals (the product cards render automatically). find_deals also handles any "find a deal / what's on sale" request.
- Look up Reddit-mined ideas for a recipient with gift_ideas, or list types with list_recipients.
- Recall who they shop for and key dates with get_profile, upcoming_events, list_connections, relationship_graph — and proactively flag a date that's near.
- When the user states a durable fact (a budget, a like/dislike, who they shop for), call remember_fact. When they give a concrete dated occasion, call save_event so reminders fire.
- add_to_cart and checkout are SIMULATED — say so honestly; never imply a real charge or shipment.

After find_gifts or gift_ideas, briefly say what you found; the products render automatically, so don't recite every price in prose. Ground all product claims in tool results — never invent prices, brands, or links. If a tool returns nothing, say so and offer an alternative.`;

async function recallMemories(userId, limit = 8) {
  if (!GRAPH || !userId) return [];
  try {
    const out = await ddb.send(
      new QueryCommand({
        TableName: GRAPH,
        KeyConditionExpression: "pk = :u AND begins_with(sk, :p)",
        ExpressionAttributeValues: { ":u": userId, ":p": "MEM#" },
        ScanIndexForward: false,
        Limit: limit,
      })
    );
    return (out.Items ?? []).map((m) => m.text).filter(Boolean);
  } catch (e) {
    console.warn("recallMemories failed:", e.message);
    return [];
  }
}

async function saveMemory(userId, kind, text) {
  if (!GRAPH || !userId || !text) return;
  const k = ["preference", "semantic", "summary"].includes(kind) ? kind : "semantic";
  await ddb.send(
    new PutCommand({
      TableName: GRAPH,
      Item: {
        pk: userId,
        sk: `MEM#${k}#${gid()}`,
        kind: "memory",
        memKind: k,
        text: String(text).slice(0, 280),
        createdAt: Date.now(),
      },
    })
  );
}

function maxiProduct(p) {
  const price = p.price ?? p.product?.price;
  return {
    postId: p.postId,
    title: String(p.product?.name || p.caption || p.title || p.name || "").slice(0, 90),
    price: typeof price === "number" && price > 0 ? price : null,
    brand: p.product?.brand || p.merchant || p.brand || null,
    image: p.product?.image || p.image || p.imageUrl || null,
    category: p.category || p.product?.category || null,
  };
}

// ── Maxi catalog cache (Phase 2) ──────────────────────────────────────────────
// Maxi's find_gifts / find_deals / order_history tools used to FULL-SCAN the posts
// table on EVERY chat turn — at 10K posts that burns seconds + thousands of RCUs
// per message and only ever saw the first ~150-250 arbitrary items. Instead we
// load a recency-ordered slice ONCE via the byFeed GSI and cache it in the warm
// Lambda container, shared across all three tools and every turn. Falls back to a
// bounded Scan only if the GSI is missing.
const MAXI_CATALOG_TTL = Number(process.env.MAXI_CATALOG_TTL_MS || 300000); // 5 min
const MAXI_CATALOG_SIZE = Number(process.env.MAXI_CATALOG_SIZE || 600);
let _catalogCache = { at: 0, items: [] };
const _categoryCache = new Map(); // category -> { at, items }

// Newest-first page of the byFeed GSI, scatter-gathered across feed shards. Each
// shard query is createdAt-sorted; we merge, de-dup, and take the newest `limit`.
async function feedRecencyItems(limit) {
  const keys = feedShardKeys();
  const perShard = Math.ceil(limit / keys.length) + 25; // headroom for the merge
  const pages = await Promise.all(
    keys.map(async (f) => {
      const items = [];
      let ExclusiveStartKey;
      do {
        const out = await ddb.send(
          new QueryCommand({
            TableName: POSTS,
            IndexName: "byFeed",
            KeyConditionExpression: "feedPk = :f",
            ExpressionAttributeValues: { ":f": f },
            ScanIndexForward: false,
            Limit: Math.min(perShard, 200),
            ExclusiveStartKey,
          })
        );
        items.push(...(out.Items ?? []));
        ExclusiveStartKey = out.LastEvaluatedKey;
      } while (ExclusiveStartKey && items.length < perShard);
      return items;
    })
  );
  const seen = new Set();
  const dedup = [];
  for (const p of pages.flat().sort((a, b) => (b.createdAt ?? 0) - (a.createdAt ?? 0))) {
    if (p.postId && !seen.has(p.postId)) { seen.add(p.postId); dedup.push(p); }
  }
  return dedup.slice(0, limit);
}

// Shared recency slice of the catalog, cached in-container for MAXI_CATALOG_TTL.
async function getCatalog() {
  const now = Date.now();
  if (now - _catalogCache.at < MAXI_CATALOG_TTL && _catalogCache.items.length) {
    return _catalogCache.items;
  }
  let items = [];
  try {
    items = await feedRecencyItems(MAXI_CATALOG_SIZE);
  } catch (e) {
    console.warn("getCatalog byFeed query failed, falling back to scan:", e.message);
  }
  if (!items.length) {
    try {
      const out = await ddb.send(new ScanCommand({ TableName: POSTS, Limit: MAXI_CATALOG_SIZE }));
      items = out.Items ?? [];
    } catch (e) {
      console.warn("getCatalog scan fallback failed:", e.message);
    }
  }
  if (items.length) _catalogCache = { at: now, items };
  return _catalogCache.items;
}

// Deep, category-specific pool via the byCategory GSI (Phase 4a), cached per
// category. Lets Maxi pull every product in a category instead of being limited
// to whatever happens to fall in the recency window. Falls back to filtering the
// cached recency slice if the GSI isn't deployed yet.
async function getCatalogByCategory(category) {
  const cat = String(category || "").toLowerCase().trim();
  if (!cat) return [];
  const now = Date.now();
  const hit = _categoryCache.get(cat);
  if (hit && now - hit.at < MAXI_CATALOG_TTL && hit.items.length) return hit.items;
  let items = [];
  try {
    const out = await ddb.send(
      new QueryCommand({
        TableName: POSTS,
        IndexName: "byCategory",
        KeyConditionExpression: "category = :c",
        ExpressionAttributeValues: { ":c": cat },
        ScanIndexForward: false,
        Limit: 200,
      })
    );
    items = out.Items ?? [];
  } catch (e) {
    console.warn(`getCatalogByCategory(${cat}) failed, filtering cached catalog:`, e.message);
    items = (await getCatalog()).filter((p) => String(catOf(p)).toLowerCase() === cat);
  }
  if (items.length) _categoryCache.set(cat, { at: now, items });
  return items;
}

async function toolFindGifts({ budget, category, recipient, vibes, limit }) {
  const n = Math.min(Number(limit) || 6, 10);
  const opts = {
    vibes: Array.isArray(vibes) ? vibes : parseList(vibes),
    recipient: recipient || undefined,
    category: category || undefined,
    budget: Number(budget) || undefined,
  };
  // Category given -> deep category pool (byCategory GSI); else the recency cache.
  let pool = opts.category ? await getCatalogByCategory(opts.category) : await getCatalog();
  if (!pool.length) pool = await getCatalog();
  if (opts.budget) pool = pool.filter((p) => { const pr = p.price ?? p.product?.price; return (typeof pr === "number" && pr > 0 ? pr : 1e9) <= opts.budget; });
  const items = pool
    .map((p) => ({ p, s: scorePost(p, opts) }))
    .sort((a, b) => b.s - a.s)
    .slice(0, n)
    .map(({ p }) => maxiProduct(p));
  return { items, count: items.length };
}

async function toolGiftIdeas({ recipient }) {
  if (!recipient) return { error: "recipient required" };
  const out = await ddb.send(
    new GetCommand({ TableName: KNOWLEDGE, Key: { recipient: String(recipient).toLowerCase() } })
  );
  if (!out.Item) return { ideas: [], bundles: [], note: "no mined data for that recipient" };
  const ideas = (out.Item.ideas ?? [])
    .slice(0, 8)
    .map((i) => ({ item: i.item || i.label || i.name, count: i.count }));
  const bundles = (out.Item.bundles ?? []).slice(0, 4).map((b) => ({ items: (b.items || []).slice(0, 4) }));
  return { ideas, bundles };
}

// The KNOWLEDGE table is tiny (~16 recipient partitions) and has no GSI to list
// every partition, so a Scan is the right primitive — but cache it so warm
// containers don't re-scan on every Maxi turn.
const RECIPIENTS_TTL = Number(process.env.RECIPIENTS_TTL_MS || 600000); // 10 min
let _recipientsCache = { at: 0, items: [] };
async function toolListRecipients() {
  const now = Date.now();
  if (now - _recipientsCache.at < RECIPIENTS_TTL && _recipientsCache.items.length) {
    return { items: _recipientsCache.items };
  }
  const out = await ddb.send(new ScanCommand({ TableName: KNOWLEDGE }));
  const items = (out.Items ?? [])
    .filter((r) => r.recipient !== "anyone" && r.recipient !== "self")
    .map((r) => ({ recipient: r.recipient, label: r.label || r.recipient, postCount: r.postCount ?? 0 }))
    .sort((a, b) => (b.postCount ?? 0) - (a.postCount ?? 0))
    .slice(0, 20);
  if (items.length) _recipientsCache = { at: now, items };
  return { items: _recipientsCache.items };
}

async function toolGetProfile(userId) {
  if (!userId) return { error: "not signed in" };
  const out = await ddb.send(new GetCommand({ TableName: USERS, Key: { userId } }));
  const it = out.Item;
  if (!it) return { exists: false };
  return {
    exists: true,
    yourName: it.identity?.name || it.name || it.profile?.name || null,
    note: "yourName is the user's OWN name. recipients below are OTHER people they shop for.",
    interests: (it.interests || it.profile?.interests || []).slice(0, 12),
    recipients: (it.recipients || []).slice(0, 12).map((r) => ({ id: r.id, name: r.name, relation: r.relation })),
    events: (it.events || []).slice(0, 12).map((e) => ({ type: e.type || e.title, date: e.date, recipientId: e.recipientId })),
  };
}

async function toolUpcomingEvents(userId, withinDays) {
  if (!userId) return { error: "not signed in" };
  const out = await ddb.send(new GetCommand({ TableName: USERS, Key: { userId } }));
  const events = Array.isArray(out.Item?.events) ? out.Item.events : [];
  const recipients = Array.isArray(out.Item?.recipients) ? out.Item.recipients : [];
  const byId = Object.fromEntries(recipients.map((r) => [r.id, r]));
  const items = computeUpcoming(events, Number(withinDays) || 90).map((u) => ({
    type: u.type,
    date: u.date,
    daysUntil: u.daysUntil,
    recipient: byId[u.recipientId]?.name ?? u.recipientName ?? null,
  }));
  return { items };
}

async function toolListConnections(userId) {
  if (!userId) return { error: "not signed in" };
  const out = await ddb.send(
    new QueryCommand({
      TableName: CONNECTIONS,
      KeyConditionExpression: "userId = :u",
      ExpressionAttributeValues: { ":u": userId },
    })
  );
  const items = (out.Items ?? [])
    .sort((a, b) => (b.createdAt ?? 0) - (a.createdAt ?? 0))
    .slice(0, 15)
    .map((c) => ({
      friendName: c.guestName,
      birthday: c.birthday || null,
      interests: (c.interests || []).slice(0, 6),
      vibes: (c.vibes || []).slice(0, 6),
      connectionId: c.connectionId,
    }));
  return { items, note: "These are the user's FRIENDS/CONNECTIONS (other people), not the user. friendName is the friend's name." };
}

async function toolRelationshipGraph(userId) {
  if (!userId || !GRAPH) return { error: "no graph" };
  const out = await ddb.send(
    new QueryCommand({
      TableName: GRAPH,
      KeyConditionExpression: "pk = :u",
      ExpressionAttributeValues: { ":u": userId },
    })
  );
  const all = (out.Items ?? []).filter((i) => i.kind === "node" || i.kind === "edge");
  const nodes = all.filter((i) => i.kind === "node");
  const edges = all.filter((i) => i.kind === "edge");
  const byType = {};
  for (const n of nodes) byType[n.type] = (byType[n.type] || 0) + 1;
  const otherPeople = nodes
    .filter((n) => n.type === "recipient" || n.type === "soft")
    .map((n) => n.label)
    .filter(Boolean)
    .slice(0, 12);
  return {
    counts: { nodes: nodes.length, edges: edges.length, byType },
    otherPeople,
    note: "otherPeople are people in the user's gifting NETWORK — friends, family, recipients. They are NOT the user themselves.",
  };
}

async function toolSaveEvent(userId, { title, date, recipientName }) {
  if (!userId) return { error: "not signed in — can't save" };
  if (!title || !date) return { error: "need a title and a date (YYYY-MM-DD)" };
  const out = await ddb.send(new GetCommand({ TableName: USERS, Key: { userId } }));
  const item = out.Item || { userId, createdAt: Date.now() };
  const events = Array.isArray(item.events) ? item.events : [];
  const ev = {
    id: `evt_${gid()}`,
    type: String(title).slice(0, 80),
    date: String(date).slice(0, 10),
    recipientName: recipientName ? String(recipientName).slice(0, 60) : undefined,
    source: "maxi",
    createdAt: Date.now(),
  };
  events.push(ev);
  item.events = events;
  item.updatedAt = Date.now();
  await ddb.send(new PutCommand({ TableName: USERS, Item: item }));
  return { ok: true, saved: { type: ev.type, date: ev.date } };
}

async function toolRememberFact(userId, { fact, kind }) {
  if (!userId) return { error: "not signed in — no long-term memory" };
  if (!fact) return { error: "nothing to remember" };
  await saveMemory(userId, kind, fact);
  return { ok: true };
}

// ── Maxi orders + deals: the Alexa-style "deals on what you restock most" flow ─
// Orders live in the GRAPH table as ORDER# items (pk=userId) — the same pattern
// as MEM# memories, so they're invisible to GET /graph (kind node|edge only).
// The agent records an order when it (simulated-)checks out, then reads them back
// to find the categories the user restocks most. New users with no orders get a
// deterministic starter history synthesized from the live catalog so the flow
// works on the very first run.
function hashStr(s) {
  let h = 2166136261;
  const str = String(s || "");
  for (let i = 0; i < str.length; i++) { h ^= str.charCodeAt(i); h = Math.imul(h, 16777619); }
  return h >>> 0;
}

// Stable, deterministic commerce metadata for the SIMULATED storefront (there is
// no real retailer feed): list price + % off, star rating, review count, "bought
// past month", and a near-term delivery date. Honest demo data — the same kind of
// simulation as the cart/checkout. Derived from the postId so a product always
// shows the same numbers.
function dealMeta(postId, price) {
  const h = hashStr(postId);
  const p = typeof price === "number" && price > 0 ? price : 18 + (h % 80);
  const discountPct = 8 + (h % 38); // 8–45% off
  const listPrice = Math.max(p + 1, Math.round((p / (1 - discountPct / 100)) * 100) / 100);
  const rating = Math.round(39 + ((h >>> 3) % 11)) / 10; // 3.9–4.9
  const reviews = 40 + ((h >>> 5) % 9000);
  const boughtBuckets = ["50+", "100+", "200+", "500+", "1K+"];
  const boughtPastMonth = boughtBuckets[(h >>> 7) % boughtBuckets.length];
  const days = 2 + ((h >>> 9) % 5);
  const delivery = new Date(Date.now() + days * 86400000).toISOString().slice(0, 10);
  return { price: Math.round(p * 100) / 100, listPrice, discountPct, rating, reviews, boughtPastMonth, delivery };
}

const CATEGORY_LABELS = {
  home: "Home & Cozy", kitchen: "Kitchen", plants: "Plants", jewelry: "Jewelry",
  art: "Art & Craft", vintage: "Vintage", wellness: "Wellness & Self-Care",
  sports: "Sports & Outdoors", tech: "Tech", travel: "Travel", party: "Party",
};
const categoryLabel = (c) => CATEGORY_LABELS[c] || (c ? String(c).charAt(0).toUpperCase() + String(c).slice(1) : "Gifts");
const priceOf = (p) => { const v = p?.price ?? p?.product?.price; return typeof v === "number" && v > 0 ? v : 0; };
const catOf = (p) => p?.category || p?.product?.category || "gift";

async function listOrders(userId, limit = 25) {
  if (!GRAPH || !userId) return [];
  try {
    const out = await ddb.send(new QueryCommand({
      TableName: GRAPH,
      KeyConditionExpression: "pk = :u AND begins_with(sk, :p)",
      ExpressionAttributeValues: { ":u": userId, ":p": "ORDER#" },
      ScanIndexForward: false,
      Limit: limit,
    }));
    return (out.Items ?? []).map((o) => ({ items: o.items ?? [], total: o.total ?? 0, createdAt: o.createdAt ?? 0 }));
  } catch (e) {
    console.warn("listOrders failed:", e.message);
    return [];
  }
}

async function saveOrder(userId, items, total) {
  if (!GRAPH || !userId || !Array.isArray(items) || !items.length) return null;
  const order = {
    pk: userId,
    sk: `ORDER#${Date.now()}#${gid()}`,
    kind: "order",
    items: items.slice(0, 20).map((it) => ({
      postId: String(it.postId || ""),
      title: String(it.title || it.name || "").slice(0, 90),
      category: it.category || null,
      brand: it.brand || null,
      price: typeof it.price === "number" ? it.price : null,
      qty: Number(it.qty) || 1,
    })),
    total: Number(total) || items.reduce((s, it) => s + (Number(it.price) || 0) * (Number(it.qty) || 1), 0),
    createdAt: Date.now(),
  };
  try { await ddb.send(new PutCommand({ TableName: GRAPH, Item: order })); } catch (e) { console.warn("saveOrder failed:", e.message); }
  return order;
}

// A believable starter purchase history from the live catalog: concentrate past
// orders in the 2 categories with the most priced products, with repeat buys
// (qty 2–3) so "most restocked" is meaningful. Deterministic per catalog.
function synthStarterOrders(pool) {
  const priced = (pool || []).filter((p) => priceOf(p) > 0);
  const byCat = {};
  for (const p of priced) { const c = catOf(p); (byCat[c] = byCat[c] || []).push(p); }
  const cats = Object.keys(byCat).sort((a, b) => byCat[b].length - byCat[a].length).slice(0, 2);
  const orders = [];
  cats.forEach((cat, ci) => {
    const picks = byCat[cat].sort((a, b) => hashStr(a.postId) - hashStr(b.postId)).slice(0, 2);
    picks.forEach((p, pi) => {
      const price = priceOf(p);
      const qty = 2 + ((hashStr(p.postId) >>> 2) % 2); // 2–3 (restocked)
      orders.push({
        items: [{ postId: p.postId, title: String(p.product?.name || p.caption || "Gift").slice(0, 90), category: cat, brand: p.product?.brand || p.merchant || null, price, qty }],
        total: price * qty,
        createdAt: Date.now() - (14 + ci * 21 + pi * 9) * 86400000,
        _synthetic: true,
      });
    });
  });
  return orders;
}

async function toolOrderHistory(userId) {
  // Read real orders; if none, synthesize a starter history from the catalog and
  // persist it once so future reads (and real orders) build on it.
  let orders = await listOrders(userId, 25);
  let seeded = false;
  if (!orders.length) {
    orders = synthStarterOrders(await getCatalog());
    seeded = true;
    if (userId) { for (const o of orders) { await saveOrder(userId, o.items, o.total).catch(() => {}); } }
  }
  const catCount = {};
  const prod = {};
  for (const o of orders) {
    for (const it of o.items || []) {
      const q = Number(it.qty) || 1;
      const cat = it.category || "gift";
      catCount[cat] = (catCount[cat] || 0) + q;
      const key = it.postId || it.title;
      if (!prod[key]) prod[key] = { postId: it.postId, title: it.title, category: cat, timesOrdered: 0, lastOrdered: 0 };
      prod[key].timesOrdered += q;
      prod[key].lastOrdered = Math.max(prod[key].lastOrdered, o.createdAt || 0);
    }
  }
  const topCategories = Object.entries(catCount).sort((a, b) => b[1] - a[1]).slice(0, 3)
    .map(([category, count]) => ({ category, label: categoryLabel(category), count }));
  const restockables = Object.values(prod).sort((a, b) => b.timesOrdered - a.timesOrdered).slice(0, 6)
    .map((r) => ({ ...r, lastOrdered: r.lastOrdered ? new Date(r.lastOrdered).toISOString().slice(0, 10) : null }));
  return { orderCount: orders.length, seeded, topCategories, restockables };
}

function maxiDealProduct(p) {
  const meta = dealMeta(p.postId, priceOf(p));
  return {
    postId: p.postId,
    title: String(p.product?.name || p.caption || p.title || "").slice(0, 90),
    brand: p.product?.brand || p.merchant || p.brand || null,
    image: p.product?.image || p.image || p.imageUrl || null,
    category: catOf(p),
    price: meta.price,
    listPrice: meta.listPrice,
    discountPct: meta.discountPct,
    rating: meta.rating,
    reviews: meta.reviews,
    boughtPastMonth: meta.boughtPastMonth,
    delivery: meta.delivery,
    onDeal: true,
  };
}

async function toolFindDeals({ categories, budget, limit }) {
  const cats = Array.isArray(categories) ? categories : parseList(categories);
  const catSet = new Set(cats.map((c) => String(c).toLowerCase()));
  const n = Math.min(Number(limit) || 8, 12);
  // Categories given -> union of deep per-category pools (byCategory GSI); else
  // the cached recency catalog. Both replace the old full-table scan.
  let catalog;
  if (catSet.size) {
    const pools = await Promise.all([...catSet].map((c) => getCatalogByCategory(c)));
    catalog = pools.flat();
    if (!catalog.length) catalog = await getCatalog();
  } else {
    catalog = await getCatalog();
  }
  let pool = catalog.filter((p) => priceOf(p) > 0);
  if (catSet.size) pool = pool.filter((p) => catSet.has(String(catOf(p)).toLowerCase()));
  if (budget) pool = pool.filter((p) => priceOf(p) <= Number(budget));
  if (!pool.length) {
    const fallback = await getCatalog();
    pool = fallback.filter((p) => priceOf(p) > 0 && (!budget || priceOf(p) <= Number(budget)));
  }
  const products = pool.map((p) => maxiDealProduct(p)).sort((a, b) => b.discountPct - a.discountPct).slice(0, n);
  const groupsMap = {};
  for (const pr of products) {
    const c = pr.category || "gift";
    (groupsMap[c] = groupsMap[c] || { category: c, label: categoryLabel(c), items: [] }).items.push(pr);
  }
  return { products, groups: Object.values(groupsMap), count: products.length };
}

// Human-readable "layer" labels for the agent's tool calls, surfaced to the UI as
// the visible reasoning trace (like Alexa's "scanning your order history…").
function maxiStepLabel(name, input, out) {
  const o = out || {};
  switch (name) {
    case "order_history": {
      const cats = (o.topCategories || []).map((c) => c.label).join(", ");
      return { tool: name, label: "Scanned your past orders", detail: cats ? `Top categories you restock: ${cats}` : "Looking at what you buy most" };
    }
    case "find_deals": {
      const cats = (o.groups || []).map((g) => g.label).join(", ");
      return { tool: name, label: `Found ${o.count || 0} active deal${(o.count || 0) === 1 ? "" : "s"}`, detail: cats ? `in ${cats}` : "" };
    }
    case "find_gifts":
      return { tool: name, label: "Searched the catalog", detail: `${o.count || 0} matching pick${(o.count || 0) === 1 ? "" : "s"}` };
    case "gift_ideas":
      return { tool: name, label: "Pulled gift ideas", detail: input?.recipient ? `for ${input.recipient}` : "" };
    case "get_profile":
      return { tool: name, label: "Checked your profile", detail: "" };
    case "upcoming_events":
      return { tool: name, label: "Checked your upcoming dates", detail: "" };
    case "list_connections":
      return { tool: name, label: "Checked your people", detail: "" };
    case "add_to_cart":
      return { tool: name, label: `Added ${o.added || 0} to your cart`, detail: "simulated" };
    case "checkout":
      return { tool: name, label: "Placed your order", detail: "simulated — no real charge" };
    case "remember_fact":
      return { tool: name, label: "Saved that to memory", detail: "" };
    case "save_event":
      return { tool: name, label: "Saved the occasion", detail: "" };
    default:
      return { tool: name, label: String(name).replace(/_/g, " "), detail: "" };
  }
}

// Tool specs advertised to the model (JSON Schema per Converse toolConfig).
const MAXI_TOOLS = [
  {
    name: "find_gifts",
    description: "Search the gift catalog by budget, category, recipient type, and/or vibes. Returns products that render to the user.",
    schema: {
      type: "object",
      properties: {
        budget: { type: "number", description: "max price in USD" },
        category: { type: "string", description: "e.g. home, kitchen, jewelry, tech, wellness, plants, art" },
        recipient: { type: "string", description: "recipient type, e.g. mom, dad, friend, partner" },
        vibes: { type: "array", items: { type: "string" }, description: "taste keywords, e.g. cozy, minimal" },
        limit: { type: "number", description: "how many to return (max 10)" },
      },
    },
  },
  {
    name: "gift_ideas",
    description: "Reddit-mined gift ideas and bundles for a specific recipient type.",
    schema: { type: "object", properties: { recipient: { type: "string" } }, required: ["recipient"] },
  },
  {
    name: "list_recipients",
    description: "List the recipient types we have mined gift ideas for.",
    schema: { type: "object", properties: {} },
  },
  {
    name: "get_profile",
    description: "The signed-in user's OWN profile. 'yourName' = the user's own name. 'recipients' = OTHER people the user shops for (not the user). Never confuse a recipient name with the user's name.",
    schema: { type: "object", properties: {} },
  },
  {
    name: "upcoming_events",
    description: "The user's upcoming saved occasions (soonest first) within a window of days.",
    schema: { type: "object", properties: { withinDays: { type: "number" } } },
  },
  {
    name: "list_connections",
    description: "Friends the user collected from swipe challenges. 'friendName' = the friend's name (NOT the user). These are OTHER people in the user's network.",
    schema: { type: "object", properties: {} },
  },
  {
    name: "relationship_graph",
    description: "A compact summary of the user's gifting network graph. 'otherPeople' = friends/family/recipients in the network (NOT the user themselves).",
    schema: { type: "object", properties: {} },
  },
  {
    name: "save_event",
    description: "Save a concrete dated occasion to the user's profile so reminders fire. Date must be YYYY-MM-DD.",
    schema: {
      type: "object",
      properties: {
        title: { type: "string" },
        date: { type: "string", description: "YYYY-MM-DD" },
        recipientName: { type: "string" },
      },
      required: ["title", "date"],
    },
  },
  {
    name: "remember_fact",
    description: "Remember a durable preference or fact about the user for future sessions (e.g. budget, a like/dislike).",
    schema: {
      type: "object",
      properties: {
        fact: { type: "string" },
        kind: { type: "string", enum: ["preference", "semantic"] },
      },
      required: ["fact"],
    },
  },
  {
    name: "add_to_cart",
    description: "Add products (by postId) to the user's SIMULATED cart in the browser.",
    schema: {
      type: "object",
      properties: { postIds: { type: "array", items: { type: "string" } } },
      required: ["postIds"],
    },
  },
  {
    name: "checkout",
    description: "Place the user's SIMULATED order (no real charge or shipment). Records the order so future restock suggestions know what they bought.",
    schema: { type: "object", properties: {} },
  },
  {
    name: "order_history",
    description: "Scan the user's PAST ORDERS to find what they buy/restock most. Returns recent orders, their top (most-restocked) categories, and the products they reorder. Call this FIRST for 'deals on what I buy most', 'reorder', 'restock', or 'buy again' requests.",
    schema: { type: "object", properties: {} },
  },
  {
    name: "find_deals",
    description: "Find products currently ON DEAL (discounted off list price), optionally filtered to categories and/or a budget. Returns buyable products with list price, % off, rating, and delivery, grouped by category — they render to the user. Pair with order_history to surface deals in the categories the user restocks most.",
    schema: {
      type: "object",
      properties: {
        categories: { type: "array", items: { type: "string" }, description: "category keys to find deals in, e.g. wellness, kitchen, home" },
        budget: { type: "number", description: "max price in USD" },
        limit: { type: "number", description: "how many to return (max 12)" },
      },
    },
  },
];

async function runMaxiTool(name, input, ctx) {
  const i = input || {};
  switch (name) {
    case "find_gifts": {
      const r = await toolFindGifts(i);
      ctx.pins.push(...(r.items || []));
      return r;
    }
    case "gift_ideas":
      return toolGiftIdeas(i);
    case "list_recipients":
      return toolListRecipients();
    case "get_profile":
      return toolGetProfile(ctx.userId);
    case "upcoming_events":
      return toolUpcomingEvents(ctx.userId, i.withinDays);
    case "list_connections":
      return toolListConnections(ctx.userId);
    case "relationship_graph":
      return toolRelationshipGraph(ctx.userId);
    case "save_event":
      return toolSaveEvent(ctx.userId, i);
    case "remember_fact":
      return toolRememberFact(ctx.userId, i);
    case "order_history":
      return toolOrderHistory(ctx.userId);
    case "find_deals": {
      const r = await toolFindDeals(i);
      ctx.pins.push(...(r.products || []));
      return r;
    }
    case "add_to_cart": {
      const ids = Array.isArray(i.postIds) ? i.postIds.map(String) : [];
      ctx.actions.push({ type: "add_to_cart", postIds: ids });
      // Track items so a later checkout records a real order. Resolve from the
      // products already shown this turn; fall back to a direct lookup.
      for (const id of ids) {
        let prod = (ctx.pins || []).find((p) => p.postId === id);
        if (!prod && POSTS) {
          try {
            const o = await ddb.send(new GetCommand({ TableName: POSTS, Key: { postId: id } }));
            if (o.Item) prod = maxiProduct(o.Item);
          } catch { /* ignore */ }
        }
        if (prod) ctx.cartItems.push({ postId: prod.postId, title: prod.title, category: prod.category, brand: prod.brand, price: prod.price, qty: 1 });
      }
      return { ok: true, added: ids.length };
    }
    case "checkout": {
      ctx.actions.push({ type: "checkout" });
      const order = ctx.cartItems.length ? await saveOrder(ctx.userId, ctx.cartItems) : null;
      ctx.cartItems = [];
      return { ok: true, recorded: order ? order.items.length : 0 };
    }
    default:
      return { error: `unknown tool ${name}` };
  }
}

// Build a clean alternating Converse transcript (must start + end on a user turn).
// Redact sensitive identifiers from anything we send to the AI provider (Bedrock).
// First names are intentionally kept (Maxi needs them to personalize), but emails,
// phone numbers, and card/ID-like numbers are stripped so they never leave for the
// model. Recurses into tool-result objects/arrays. Backs the privacy statement.
function scrubPII(v) {
  if (typeof v === "string") {
    return v
      .replace(/[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/g, "[email]")
      .replace(/\b(?:\d[ -]?){13,19}\b/g, "[number]")
      .replace(/\b\d{3}-\d{2}-\d{4}\b/g, "[id]")
      .replace(/(?:\+?\d{1,3}[\s.-]?)?\(?\d{3}\)?[\s.-]?\d{3}[\s.-]?\d{4}\b/g, "[phone]");
  }
  if (Array.isArray(v)) return v.map(scrubPII);
  if (v && typeof v === "object") {
    const o = {};
    for (const [k, val] of Object.entries(v)) o[k] = scrubPII(val);
    return o;
  }
  return v;
}

function buildMaxiMessages(incoming, userText) {
  const turns = [];
  for (const m of (Array.isArray(incoming) ? incoming : []).slice(-12)) {
    const role = m.role === "assistant" ? "assistant" : "user";
    const text = typeof m.text === "string" ? m.text : typeof m.content === "string" ? m.content : "";
    const t = String(text).trim();
    if (t) turns.push({ role, content: [{ text: scrubPII(t.slice(0, 2000)) }] });
  }
  if (userText) turns.push({ role: "user", content: [{ text: scrubPII(userText.slice(0, 2000)) }] });
  const norm = [];
  for (const m of turns) {
    if (!norm.length && m.role !== "user") continue;
    const last = norm[norm.length - 1];
    if (last && last.role === m.role) last.content.push(...m.content);
    else norm.push({ role: m.role, content: [...m.content] });
  }
  while (norm.length && norm[norm.length - 1].role !== "user") norm.pop();
  return norm;
}

// ── Group gifts (pools) ──────────────────────────────────────────────────────
// Backend-backed group-gift pools (POOLS table) so contributions + the group
// chat sync across everyone in a pool. One DynamoDB partition per pool, keyed by
// itemId:
//   { poolId, itemId:"META", ...pool, raised, contribCount, memberCount }
//   { poolId, itemId:"MEMBER#<userId>", memberId, name, joinedAt, role }
//   { poolId, itemId:"CONTRIB#<ts>#<id>", userId, name, amount, at }
//   { poolId, itemId:"MSG#<ts>#<id>", userId, name, text, at }
// "MSG#" sorts AFTER every other prefix, so `sk > "MSG#<ts>"` returns only chat
// messages newer than ts (used for incremental polling).
const POOL_GRADS = new Set(["peach", "rose", "butter", "lilac", "sky", "sage", "coral"]);
const poolGrad = (g) => (POOL_GRADS.has(g) ? g : "coral");

// Shape a stored META row into the wire pool object the client expects.
function poolFromMeta(m) {
  if (!m) return null;
  return {
    poolId: m.poolId,
    title: m.title,
    occasion: m.occasion,
    goal: Number(m.goal) || 0,
    blurb: m.blurb ?? "",
    emoji: m.emoji ?? "🎁",
    grad: poolGrad(m.grad),
    image: m.image ?? null,
    recipient: m.recipient ?? "",
    organizerId: m.organizerId,
    organizerName: m.organizerName ?? "a friend",
    raised: Number(m.raised) || 0,
    contribCount: Number(m.contribCount) || 0,
    memberCount: Number(m.memberCount) || 0,
    deadline: m.deadline,
    createdAt: m.createdAt,
  };
}

// Add a MEMBER row if absent and bump META.memberCount only on first join.
// Idempotent — a no-op when the user is already a member of the pool.
async function ensurePoolMember(poolId, userId, name) {
  if (!POOLS || !poolId || !userId) return;
  try {
    await ddb.send(
      new PutCommand({
        TableName: POOLS,
        Item: {
          poolId,
          itemId: `MEMBER#${userId}`,
          memberId: userId,
          name: String(name || "Someone").slice(0, 80),
          joinedAt: Date.now(),
          role: "member",
        },
        ConditionExpression: "attribute_not_exists(itemId)",
      })
    );
    await ddb.send(
      new UpdateCommand({
        TableName: POOLS,
        Key: { poolId, itemId: "META" },
        UpdateExpression: "ADD memberCount :one",
        ExpressionAttributeValues: { ":one": 1 },
      })
    );
  } catch (e) {
    // Already a member → the conditional Put fails; that's the expected no-op.
    if (e.name !== "ConditionalCheckFailedException") throw e;
  }
}

// List the META rows for every pool a user belongs to (via the byMember GSI).
// Parallel GetItem on the META rows (handful of pools per user) keeps it simple.
async function listPoolsForMember(userId) {
  if (!POOLS || !userId) return [];
  const mem = await ddb.send(
    new QueryCommand({
      TableName: POOLS,
      IndexName: "byMember",
      KeyConditionExpression: "memberId = :u",
      ExpressionAttributeValues: { ":u": userId },
      ScanIndexForward: false,
    })
  );
  const poolIds = [...new Set((mem.Items ?? []).map((m) => m.poolId).filter(Boolean))];
  const metas = await Promise.all(
    poolIds.map((poolId) =>
      ddb
        .send(new GetCommand({ TableName: POOLS, Key: { poolId, itemId: "META" } }))
        .then((o) => o.Item)
        .catch(() => null)
    )
  );
  return metas
    .map(poolFromMeta)
    .filter(Boolean)
    .sort((a, b) => (b.createdAt ?? 0) - (a.createdAt ?? 0));
}

// Normalize a stored chat row into the wire message shape.
function msgFromItem(it) {
  return {
    id: it.itemId,
    userId: it.userId,
    name: it.name,
    text: it.text,
    at: Number(it.at) || 0,
  };
}

export const handler = async (event) => {
  const method = event.requestContext?.http?.method ?? "GET";
  const path = event.requestContext?.http?.path ?? "/";
  const qs = event.queryStringParameters ?? {};

  // CORS preflight: API Gateway's catch-all ($default) route forwards OPTIONS to
  // this Lambda instead of auto-answering it, so reply 204 with the preflight
  // headers. access-control-allow-origin is added by the API's CORS config, so
  // we omit it here to avoid emitting a duplicate header.
  if (method === "OPTIONS") {
    return {
      statusCode: 204,
      headers: {
        "access-control-allow-methods": "GET,POST,PUT,DELETE,OPTIONS",
        "access-control-allow-headers": "content-type,authorization,x-admin-token",
        "access-control-max-age": "3600",
      },
      body: "",
    };
  }

  // ── Auth gate ────────────────────────────────────────────────────────────
  // Default-deny for protected routes when enforcement is on. Public catalog +
  // the anonymous guest write stay open; /seed is admin-only. The result is kept
  // so downstream routes (e.g. /maxi rate limiting) can use the verified identity.
  let auth = null;
  if (AUTH_ENFORCE && !isPublicRoute(method, path)) {
    // authorizeRequest is the only awaited call before the main try/catch below,
    // so guard it too — a JWKS/network hiccup must return a clean 500, never an
    // unhandled rejection (which API Gateway would surface as an opaque 500).
    try {
      auth = await authorizeRequest(event, method, path);
    } catch (err) {
      console.error("authorization check threw", err);
      return json(500, { error: "internal error" });
    }
    if (!auth.ok) {
      return json(401, {
        error: "unauthorized",
        hint: "Sign in (Clerk) or send a valid x-admin-token.",
      });
    }
  }

  let body = {};
  try {
    body = event.body ? JSON.parse(event.body) : {};
  } catch {
    return json(400, { error: "invalid JSON body" });
  }

  try {
    // GET /feed?limit=&author=&cursor=&vibes=&recipient=&occasion=&category=
    // Cursor-paginated infinite feed; each page is ranked by scorePost().
    if (method === "GET" && path === "/feed") {
      const limit = Math.min(Number(qs.limit) || 20, 50);
      const start = decodeCursor(qs.cursor);
      if (qs.author) {
        const out = await ddb.send(
          new QueryCommand({
            TableName: POSTS,
            IndexName: "byAuthor",
            KeyConditionExpression: "author = :a",
            ExpressionAttributeValues: { ":a": qs.author },
            ScanIndexForward: false,
            Limit: limit,
            ExclusiveStartKey: start,
          })
        );
        return json(200, { items: out.Items ?? [], cursor: encodeCursor(out.LastEvaluatedKey) });
      }
      const opts = {
        vibes: parseList(qs.vibes),
        recipient: qs.recipient,
        occasion: qs.occasion,
        category: qs.category,
        budget: Number(qs.budget) || undefined,
        eventBoost: Number(qs.eventBoost) || 0,
      };

      // Per-user de-dup: skip anything this viewer has already seen/liked/saved.
      const exclude = await userExcludeSet(qs.userId);

      // Sharded feed path (FEED_SHARDS > 1): the byFeed partition is split across
      // "all#<n>", so scatter-gather a recency window across every shard (filters
      // pushed down per shard), then rank + paginate by offset. Variety = a random
      // offset on a fresh, unfiltered load. The single-partition path below runs
      // unchanged when FEED_SHARDS == 1; on a sharded error we drop to the scan.
      if (FEED_SHARDS > 1) {
        try {
          const filters = [];
          const baseEav = {};
          if (qs.recipient && qs.recipient !== "anyone") { filters.push("recipient = :r"); baseEav[":r"] = qs.recipient; }
          if (qs.occasion && qs.occasion !== "any") { filters.push("occasion = :o"); baseEav[":o"] = qs.occasion; }
          if (qs.category) { filters.push("category = :c"); baseEav[":c"] = String(qs.category).toLowerCase(); }
          const keys = feedShardKeys();
          const perShard = Math.ceil((filters.length ? 600 : 400) / keys.length);
          const pages = await Promise.all(
            keys.map((f) =>
              ddb
                .send(
                  new QueryCommand({
                    TableName: POSTS,
                    IndexName: "byFeed",
                    KeyConditionExpression: "feedPk = :f",
                    ExpressionAttributeValues: { ...baseEav, ":f": f },
                    FilterExpression: filters.length ? filters.join(" AND ") : undefined,
                    ScanIndexForward: false,
                    Limit: perShard,
                  })
                )
                .then((o) => o.Items ?? [])
            )
          );
          const seen = new Set();
          const ranked = [];
          for (const p of pages.flat()) {
            if (!p.postId || seen.has(p.postId) || exclude.has(p.postId)) continue;
            seen.add(p.postId);
            const q = classifyPin({ title: p.caption ?? p.product?.name, domain: p.domain ?? p.merchant, link: p.url ?? p.productUrl, price: p.price ?? p.product?.price });
            if (!q.feedEligible) continue;
            ranked.push({ ...p, contentType: q.contentType, qualityScore: q.qualityScore, feedEligible: true, _score: scorePost(p, opts) + q.qualityScore * 0.4 });
          }
          ranked.sort((a, b) => b._score - a._score);
          let offset = start?._offset ?? 0;
          if (!start && !filters.length && qs.fresh !== "0" && ranked.length > limit) {
            offset = Math.floor(Math.random() * Math.max(1, ranked.length - limit));
          }
          const page = ranked.slice(offset, offset + limit);
          const nextOffset = offset + limit;
          return json(200, { items: page, cursor: nextOffset < ranked.length ? encodeCursor({ _offset: nextOffset }) : null });
        } catch (err) {
          console.warn("sharded byFeed query failed, falling back to full scan:", err.message);
        }
      }

      // Preferred path: read a recency-ordered page from the byFeed GSI (PK
      // feedPk="all", SK createdAt) instead of scanning the whole table. Facets
      // are hard-filtered; the page is ranked by scorePost() + qualityScore.
      try {
        // When sharded, the scatter-gather above already ran; bail to the scan
        // fallback below rather than querying the (now-empty) legacy "all" key.
        if (FEED_SHARDS > 1) throw new Error("sharded: use scan fallback");
        const eav = { ":f": "all" };
        const filters = [];
        if (qs.recipient && qs.recipient !== "anyone") { filters.push("recipient = :r"); eav[":r"] = qs.recipient; }
        if (qs.occasion && qs.occasion !== "any") { filters.push("occasion = :o"); eav[":o"] = qs.occasion; }
        if (qs.category) { filters.push("category = :c"); eav[":c"] = qs.category; }
        // Over-read: the quality + de-dup filters below remove listicles/guides
        // (~37%) and already-seen items, so fetch a wider window than the page.
        const fetchN = filters.length ? 150 : Math.min(Math.max(limit * 4, 80), 150);
        // Variety: on a fresh (uncursored, unfiltered) load, jump to a RANDOM
        // spot in the catalog instead of always the newest head. Paginated loads
        // (cursor present) continue deterministically from there.
        let kce = "feedPk = :f";
        if (!start && !filters.length && qs.fresh !== "0") {
          const b = await getFeedBounds();
          if (b.max > b.min) {
            eav[":seek"] = b.min + Math.floor((0.1 + Math.random() * 0.9) * (b.max - b.min));
            kce = "feedPk = :f AND createdAt <= :seek";
          }
        }
        const runQuery = (keyCond, startKey) =>
          ddb.send(
            new QueryCommand({
              TableName: POSTS,
              IndexName: "byFeed",
              KeyConditionExpression: keyCond,
              ExpressionAttributeValues: eav,
              FilterExpression: filters.length ? filters.join(" AND ") : undefined,
              ScanIndexForward: false, // newest first
              Limit: fetchN,
              ExclusiveStartKey: startKey,
            })
          );
        // Fill a full page of feed-eligible products, reading more GSI pages as
        // needed. The random-seek entry point can land in a listicle/gift-guide
        // cluster (those boards are adjacent in createdAt) that filters out almost
        // entirely, so a single page can come back empty — keep walking the older
        // range (then wrap to the newest head once) until we reach `limit`. Keeps
        // only single buyable products; qualityScore boosts priced/retailer items.
        const eligible = [];
        const picked = new Set();
        const take = (items) => {
          for (const p of items ?? []) {
            if (picked.has(p.postId) || exclude.has(p.postId)) continue;
            const q = classifyPin({ title: p.caption ?? p.product?.name, domain: p.domain ?? p.merchant, link: p.url ?? p.productUrl, price: p.price ?? p.product?.price });
            if (!q.feedEligible) continue;
            picked.add(p.postId);
            eligible.push({ ...p, contentType: q.contentType, qualityScore: q.qualityScore, feedEligible: true, _score: scorePost(p, opts) + q.qualityScore * 0.4 });
          }
        };
        // First read the random variety window (or, when paginating, the cursor
        // page). If a FRESH load under-fills — the seek landed in a listicle
        // cluster — top up from the product-dense NEWEST head instead of walking
        // deeper into the (older, listicle-heavy) tail. Cursor pages just walk LEK.
        let lastKey = start;
        let toppedUp = false;
        for (let attempt = 0; attempt < 6 && eligible.length < limit; attempt++) {
          const out = await runQuery(kce, lastKey);
          take(out.Items);
          lastKey = out.LastEvaluatedKey;
          if (eav[":seek"]) { delete eav[":seek"]; kce = "feedPk = :f"; } // seek = entry only
          if (eligible.length >= limit) break;
          if (!start && !toppedUp) {
            toppedUp = true;
            lastKey = undefined;  // jump to the newest (product-dense) head
            continue;
          }
          if (!lastKey) break;    // reached the end of the range
        }
        eligible.sort((a, b) => b._score - a._score);
        return json(200, { items: eligible.slice(0, limit), cursor: encodeCursor(lastKey) });
      } catch (err) {
        // byFeed GSI not deployed yet (or transient error) -> legacy fallback.
        console.warn("byFeed query failed, falling back to full scan:", err.message);
      }

      // Legacy fallback: scan the whole table, rank globally, paginate by offset.
      // Only used until the byFeed GSI exists; fine for a few hundred items.
      const allItems = [];
      let scanKey = undefined;
      do {
        const out = await ddb.send(
          new ScanCommand({ TableName: POSTS, ExclusiveStartKey: scanKey })
        );
        allItems.push(...(out.Items ?? []));
        scanKey = out.LastEvaluatedKey;
      } while (scanKey);
      const ranked = allItems
        .map((p) => ({ p, q: classifyPin({ title: p.caption ?? p.product?.name, domain: p.domain ?? p.merchant, link: p.url ?? p.productUrl, price: p.price ?? p.product?.price }) }))
        .filter((x) => x.q.feedEligible && !exclude.has(x.p.postId))
        .map(({ p, q }) => ({ ...p, contentType: q.contentType, qualityScore: q.qualityScore, _score: scorePost(p, opts) + q.qualityScore * 0.4 }))
        .sort((a, b) => b._score - a._score);
      const offset = start?._offset ?? 0;
      const page = ranked.slice(offset, offset + limit);
      const nextOffset = offset + limit;
      const cursor = nextOffset < ranked.length ? encodeCursor({ _offset: nextOffset }) : null;
      return json(200, { items: page, cursor });
    }

    // GET /posts/{id}
    if (method === "GET" && path.startsWith("/posts/")) {
      const postId = decodeURIComponent(path.split("/")[2] ?? "");
      const out = await ddb.send(new GetCommand({ TableName: POSTS, Key: { postId } }));
      return out.Item ? json(200, out.Item) : json(404, { error: "not found" });
    }

    // GET /recipients — list of recipients for the picker (label + counts).
    // Sourced from the Reddit-mined knowledge base (KNOWLEDGE table).
    if (method === "GET" && path === "/recipients") {
      const out = await ddb.send(new ScanCommand({ TableName: KNOWLEDGE }));
      const items = (out.Items ?? [])
        .filter((r) => r.recipient !== "anyone" && r.recipient !== "self")
        .map((r) => ({
          recipient: r.recipient,
          label: r.label ?? r.recipient,
          postCount: r.postCount ?? 0,
          ideaCount: Array.isArray(r.ideas) ? r.ideas.length : 0,
        }))
        .sort((a, b) => b.postCount - a.postCount);
      return json(200, { items });
    }

    // GET /ideas?recipient=mom — ranked gift ideas + bundles for one recipient.
    if (method === "GET" && path === "/ideas") {
      const recipient = qs.recipient || "anyone";
      const out = await ddb.send(new GetCommand({ TableName: KNOWLEDGE, Key: { recipient } }));
      return out.Item ? json(200, out.Item) : json(404, { error: "unknown recipient" });
    }

    // GET /pins?limit= — list embedded Pinterest pins (key + metadata) straight
    // from S3 Vectors. The browser uses these keys as seed vectors for the
    // recommendation kNN (a pin's key == its postId in the posts table).
    if (method === "GET" && path === "/pins") {
      if (!s3v || !(await aiEnabled())) return json(200, { items: [] });
      const limit = Math.min(Number(qs.limit) || 60, 200);
      const out = await s3v.send(
        new ListVectorsCommand({
          vectorBucketName: VECTOR_BUCKET,
          indexName: VECTOR_INDEX,
          maxResults: limit,
          returnMetadata: true,
        })
      );
      const items = (out.vectors ?? []).map(vecToItem).filter((it) => it.feedEligible);
      return json(200, { items });
    }

    // POST /visual-search  { imageBase64, text?, limit?, sourceUser? }
    // True "find gifts that look like this": embed the uploaded image with Titan
    // Multimodal, then kNN against the pin index. Returns post-shaped items.
    if (method === "POST" && path === "/visual-search") {
      if (!(await aiEnabled())) return json(503, { error: "temporarily disabled (cost guard)" });
      if (!s3v) return json(503, { error: "vector store not configured" });
      const imageBase64 = body.imageBase64 || body.image;
      if (!imageBase64) return json(400, { error: "imageBase64 required" });
      const limit = Math.min(Number(body.limit) || 12, 50);
      let queryVector;
      try {
        queryVector = await embedImage(imageBase64, body.text);
      } catch (e) {
        console.warn("titan image embed failed:", e.message);
        return json(502, { error: "embedding failed" });
      }
      const out = await s3v.send(
        new QueryVectorsCommand({
          vectorBucketName: VECTOR_BUCKET,
          indexName: VECTOR_INDEX,
          topK: limit * 3, // over-fetch; quality filter drops listicles/guides
          queryVector: { float32: queryVector },
          returnMetadata: true,
          returnDistance: true,
          filter: body.sourceUser ? { sourceUser: { $eq: body.sourceUser } } : undefined,
        })
      );
      const items = (out.vectors ?? []).map(vecToItem).filter((it) => it.feedEligible).slice(0, limit);
      return json(200, { items, source: "visual" });
    }

    // GET /interactions?userId=&types=like,save,comment
    // Returns the user's persisted interactions filtered by type(s).
    if (method === "GET" && path === "/interactions") {
      const userId = qs.userId;
      if (!userId) return json(400, { error: "userId required" });
      const types = parseList(qs.types);
      const inter = await ddb.send(
        new QueryCommand({
          TableName: INTERACTIONS,
          KeyConditionExpression: "userId = :u",
          ExpressionAttributeValues: { ":u": userId },
        })
      );
      let items = (inter.Items ?? []).map((i) => ({
        targetId: i.target,
        type: i.type,
        createdAt: i.createdAt,
        data: i.data ?? undefined,
      }));
      if (types.length) items = items.filter((i) => types.includes(i.type));
      return json(200, { items });
    }

    // POST /interactions  { userId, targetId, type, data? }  — single event
    //                     { items: [{ userId, targetId, type, createdAt? }] } — batch
    // The iOS client queues events locally and flushes them in batches (one
    // Lambda invocation per ~10-100 events instead of one per tap).
    if (method === "POST" && path === "/interactions") {
      if (Array.isArray(body.items)) {
        const rows = [];
        const seenKeys = new Set(); // BatchWrite rejects duplicate keys in one request
        for (const it of body.items.slice(0, 100)) {
          const { userId, targetId, type } = it ?? {};
          if (!userId || !targetId || !type) continue;
          const sk = type === "comment" ? `${type}#${targetId}#${Date.now()}` : `${type}#${targetId}`;
          const key = `${userId}|${sk}`;
          if (seenKeys.has(key)) continue;
          seenKeys.add(key);
          rows.push({
            userId,
            targetId: sk,
            type,
            target: targetId,
            createdAt: Number(it.createdAt) || Date.now(),
          });
        }
        if (!rows.length) return json(400, { error: "items must contain { userId, targetId, type }" });
        for (let i = 0; i < rows.length; i += 25) {
          await ddb.send(
            new BatchWriteCommand({
              RequestItems: {
                [INTERACTIONS]: rows.slice(i, i + 25).map((Item) => ({ PutRequest: { Item } })),
              },
            })
          );
        }
        return json(200, { ok: true, count: rows.length });
      }

      const { userId, targetId, type, data } = body;
      if (!userId || !targetId || !type) {
        return json(400, { error: "userId, targetId, type required" });
      }
      // Comments are NOT idempotent (many per post), so they get a unique sort key.
      const sk = type === "comment"
        ? `${type}#${targetId}#${Date.now()}`
        : `${type}#${targetId}`;
      const item = {
        userId,
        targetId: sk,
        type,
        target: targetId,
        createdAt: Date.now(),
      };
      if (data) item.data = data;
      await ddb.send(new PutCommand({ TableName: INTERACTIONS, Item: item }));
      return json(200, { ok: true });
    }

    // GET /vectors?keys=a,b,c — int8-quantized embeddings for the given pin
    // keys, so the mobile client can cache them and run taste-centroid +
    // cosine ranking ON-DEVICE (see Giftmaxxing/Services/Recommendation/).
    // Each vector is unit-normalized then quantized to int8 with a per-vector
    // scale (~1 KB over the wire vs ~8 KB as JSON floats). Sheds with the AI
    // breaker: clients fall back to facet-only local ranking when degraded.
    if (method === "GET" && path === "/vectors") {
      const keys = parseList(qs.keys).slice(0, 60);
      if (!keys.length) return json(400, { error: "keys required" });
      if (!s3v || !(await aiEnabled())) {
        // no-store: an empty degraded payload must never stick in the edge cache.
        return json(200, { items: [], source: s3v ? "degraded" : "disabled" }, { "cache-control": "no-store" });
      }
      const out = await s3v.send(
        new GetVectorsCommand({
          vectorBucketName: VECTOR_BUCKET,
          indexName: VECTOR_INDEX,
          keys,
          returnData: true,
        })
      );
      const items = (out.vectors ?? [])
        .map((v) => {
          const f = v.data?.float32;
          if (!Array.isArray(f) || !f.length) return null;
          const norm = Math.sqrt(f.reduce((s, x) => s + x * x, 0)) || 1;
          let maxAbs = 0;
          const unit = f.map((x) => {
            const u = x / norm;
            const a = Math.abs(u);
            if (a > maxAbs) maxAbs = a;
            return u;
          });
          const scale = maxAbs > 0 ? maxAbs / 127 : 1;
          const q = Int8Array.from(unit.map((u) => Math.max(-127, Math.min(127, Math.round(u / scale)))));
          return { key: v.key, dim: f.length, scale, data: Buffer.from(q.buffer).toString("base64") };
        })
        .filter(Boolean);
      // Embeddings are immutable per key (re-ingest aside), so let CloudFront
      // hold them for a day — repeat on-device cache fills never reach us.
      // Keys with no vector yet (not embedded) only cache briefly, so they
      // become visible shortly after the embed backfill runs.
      const ttl = items.length ? 86400 : 300;
      return json(200, { items, source: "s3v" }, { "cache-control": `public, max-age=${ttl}` });
    }

    // GET /recommendations?userId=&limit=&cursor=&vibes=&recipient=&occasion=&category=
    // Personalized ranked picks. Taste can come from server-side interactions
    // (userId) and/or explicit facet hints passed by the client.
    if (method === "GET" && path === "/recommendations") {
      const userId = qs.userId;
      let likedTargets = new Set();
      if (userId) {
        const inter = await ddb.send(
          new QueryCommand({
            TableName: INTERACTIONS,
            KeyConditionExpression: "userId = :u",
            ExpressionAttributeValues: { ":u": userId },
          })
        );
        likedTargets = new Set((inter.Items ?? []).map((i) => i.target));
      }

      const limit = Math.min(Number(qs.limit) || 12, 50);

      // Vector path: taste = centroid of the user's seed pins -> kNN in S3 Vectors.
      // Seeds come from ?seedKeys=pin-a,pin-b or from the user's interactions.
      const seedKeys = parseList(qs.seedKeys);
      const seeds = seedKeys.length ? seedKeys : [...likedTargets];
      if (s3v && seeds.length && (await aiEnabled())) {
        try {
          const vitems = await vectorRecommend(seeds, { limit, sourceUser: qs.sourceUser });
          if (vitems && vitems.length) {
            return json(200, { items: vitems, cursor: null, source: "vector" });
          }
        } catch (e) {
          console.warn("vector recommend failed, falling back to facets:", e.message);
        }
      }

      const opts = {
        vibes: parseList(qs.vibes),
        recipient: qs.recipient,
        occasion: qs.occasion,
        category: qs.category,
        budget: Number(qs.budget) || undefined,
        eventBoost: Number(qs.eventBoost) || 0,
      };
      const scan = {
        TableName: POSTS,
        Limit: 120,
        ExclusiveStartKey: decodeCursor(qs.cursor),
      };
      const out = await ddb.send(new ScanCommand(scan));
      const items = (out.Items ?? [])
        .filter((p) => !likedTargets.has(p.postId) && p.author !== userId)
        .map((p) => ({ p, q: classifyPin({ title: p.caption ?? p.product?.name, domain: p.domain ?? p.merchant, link: p.url ?? p.productUrl, price: p.price ?? p.product?.price }) }))
        .filter((x) => x.q.feedEligible)
        .map(({ p, q }) => ({ ...p, contentType: q.contentType, qualityScore: q.qualityScore, _score: scorePost(p, opts) + q.qualityScore * 0.4 }))
        .sort((a, b) => b._score - a._score)
        .slice(0, limit);

      return json(200, { items, cursor: encodeCursor(out.LastEvaluatedKey), source: "facet" });
    }

    // POST /seed  { users:[], posts:[] }  — dev convenience to load sample data
    if (method === "POST" && path === "/seed") {
      const chunks = (arr) =>
        Array.from({ length: Math.ceil(arr.length / 25) }, (_, i) =>
          arr.slice(i * 25, i * 25 + 25)
        );
      // Posts must carry feedPk (the byFeed recency-GSI partition — a single "all"
      // or, when FEED_SHARDS>1, a deterministic "all#<n>" shard) + a numeric
      // createdAt. We also normalize `category` to a trimmed lowercase value so the
      // byCategory GSI exact-match is reliable, and DROP it when empty so that
      // (sparse) index skips uncategorized posts rather than choking on an empty key.
      const prep = (name, Item) => {
        if (name !== POSTS) return Item;
        const out = { ...Item, feedPk: feedShardForPost(Item.postId), createdAt: Number(Item.createdAt) || Date.now() };
        const cat = String(Item.category ?? "").toLowerCase().trim();
        if (cat) out.category = cat;
        else delete out.category;
        return out;
      };
      for (const table of [
        [USERS, body.users ?? []],
        [POSTS, body.posts ?? []],
      ]) {
        const [name, items] = table;
        for (const c of chunks(items)) {
          if (c.length === 0) continue;
          await ddb.send(
            new BatchWriteCommand({
              RequestItems: { [name]: c.map((Item) => ({ PutRequest: { Item: prep(name, Item) } })) },
            })
          );
        }
      }
      return json(200, { ok: true, users: (body.users ?? []).length, posts: (body.posts ?? []).length });
    }

    // GET /me?userId=  — fetch the signed-in user's stored profile. Recipients +
    // events ride along on the same item, so the whole profile hydrates at once.
    if (method === "GET" && path === "/me") {
      const userId = qs.userId;
      if (!userId) return json(400, { error: "userId required" });
      const out = await ddb.send(new GetCommand({ TableName: USERS, Key: { userId } }));
      return json(200, { item: out.Item ?? null });
    }

    // PUT /me  { userId, profile }  — upsert the profile keyed by the Clerk
    // userId. Stored as one item (incl. recipients + events) for easy hydration.
    if (method === "PUT" && path === "/me") {
      const { userId, profile } = body;
      if (!userId || !profile || typeof profile !== "object") {
        return json(400, { error: "userId and profile required" });
      }
      const item = { ...profile, userId, updatedAt: Date.now() };
      await ddb.send(new PutCommand({ TableName: USERS, Item: item }));
      // Fan out into the events table + network graph so nothing is missed.
      await captureProfile(userId, profile);
      return json(200, { ok: true, item });
    }

    // GET /events/upcoming?userId=&withinDays=  — events due soon, soonest-first,
    // each joined with its recipient. Powers reminders + feed event context.
    if (method === "GET" && path === "/events/upcoming") {
      const userId = qs.userId;
      if (!userId) return json(400, { error: "userId required" });
      const out = await ddb.send(new GetCommand({ TableName: USERS, Key: { userId } }));
      const events = Array.isArray(out.Item?.events) ? out.Item.events : [];
      const recipients = Array.isArray(out.Item?.recipients) ? out.Item.recipients : [];
      const byId = Object.fromEntries(recipients.map((r) => [r.id, r]));
      const withinDays = Number(qs.withinDays) || 90;
      const items = computeUpcoming(events, withinDays).map((u) => ({
        ...u,
        recipient: byId[u.recipientId] ?? null,
      }));
      return json(200, { items });
    }

    // ── Soft profiles (viral swipe challenge) ────────────────────────────────
    // POST /connections  { senderId, guest:{ name, handle?, birthday?, genderPref?,
    //   vibes?, seeds?, interests?, yesCount?, totalSwipes? } }
    // Created when an invited guest finishes the swipe challenge. The sender
    // (senderId, embedded in the invite link) "owns" the resulting soft profile;
    // consent is implied by the guest completing a link the sender shared.
    if (method === "POST" && path === "/connections") {
      const senderId = body.senderId;
      const guest = body.guest ?? {};
      if (!senderId || typeof guest !== "object" || !String(guest.name || "").trim()) {
        return json(400, { error: "senderId and guest.name required" });
      }
      const rid =
        globalThis.crypto?.randomUUID?.() ??
        `${Date.now().toString(36)}${Math.random().toString(36).slice(2, 10)}`;
      const birthday =
        typeof guest.birthday === "string" && /^\d{4}-\d{2}-\d{2}$/.test(guest.birthday)
          ? guest.birthday
          : undefined;
      const VALID_GENDER_PREFS = ["he", "she", "they"];
      const genderPref =
        typeof guest.genderPref === "string" && VALID_GENDER_PREFS.includes(guest.genderPref)
          ? guest.genderPref
          : undefined;
      // Parse dwell timing signals (how long the guest spent on each card)
      const dwellSignals = Array.isArray(guest.dwellSignals)
        ? guest.dwellSignals
            .slice(0, 100)
            .filter((s) => s && typeof s.id === "string" && typeof s.dwellMs === "number")
            .map((s) => ({ id: String(s.id), dir: String(s.dir), dwellMs: Math.round(Number(s.dwellMs)) }))
        : undefined;
      const item = {
        userId: senderId,
        connectionId: `conn_${rid}`,
        soft: true,
        kind: "challenge",
        guestName: String(guest.name).trim().slice(0, 80),
        guestHandle: guest.handle ? String(guest.handle).slice(0, 40) : undefined,
        birthday,
        genderPref,
        vibes: Array.isArray(guest.vibes) ? guest.vibes.slice(0, 12).map(String) : [],
        seeds: Array.isArray(guest.seeds) ? guest.seeds.slice(0, 20).map(String) : [],
        interests: Array.isArray(guest.interests) ? guest.interests.slice(0, 12).map(String) : [],
        yesCount: Number(guest.yesCount) || 0,
        totalSwipes: Number(guest.totalSwipes) || 0,
        dwellSignals,
        seen: false,
        createdAt: Date.now(),
      };
      await ddb.send(new PutCommand({ TableName: CONNECTIONS, Item: item }));
      // Mirror the soft profile into the events table + network graph.
      await captureConnection(item);
      return json(200, { ok: true, connectionId: item.connectionId });
    }

    // GET /connections?userId=&unseenOnly=  — soft profiles the sender collected,
    // newest first. `unseen` is the notification badge count.
    if (method === "GET" && path === "/connections") {
      const userId = qs.userId;
      if (!userId) return json(400, { error: "userId required" });
      const out = await ddb.send(
        new QueryCommand({
          TableName: CONNECTIONS,
          KeyConditionExpression: "userId = :u",
          ExpressionAttributeValues: { ":u": userId },
        })
      );
      let items = (out.Items ?? []).sort((a, b) => (b.createdAt ?? 0) - (a.createdAt ?? 0));
      const unseen = items.filter((i) => !i.seen).length;
      if (qs.unseenOnly === "1" || qs.unseenOnly === "true") {
        items = items.filter((i) => !i.seen);
      }
      return json(200, { items, unseen });
    }

    // POST /connections/seen  { userId, connectionIds? }  — clear notification
    // state. Omit connectionIds to mark every unseen connection as seen.
    if (method === "POST" && path === "/connections/seen") {
      const { userId, connectionIds } = body;
      if (!userId) return json(400, { error: "userId required" });
      let ids = Array.isArray(connectionIds) ? connectionIds : null;
      if (!ids) {
        const out = await ddb.send(
          new QueryCommand({
            TableName: CONNECTIONS,
            KeyConditionExpression: "userId = :u",
            FilterExpression: "#seen = :f",
            ExpressionAttributeNames: { "#seen": "seen" },
            ExpressionAttributeValues: { ":u": userId, ":f": false },
          })
        );
        ids = (out.Items ?? []).map((i) => i.connectionId);
      }
      await Promise.all(
        ids.map((connectionId) =>
          ddb.send(
            new UpdateCommand({
              TableName: CONNECTIONS,
              Key: { userId, connectionId },
              UpdateExpression: "SET #seen = :t",
              ExpressionAttributeNames: { "#seen": "seen" },
              ExpressionAttributeValues: { ":t": true },
            })
          )
        )
      );
      return json(200, { ok: true, updated: ids.length });
    }

    // POST /connections/claim  { anonId, userId }  — re-key every soft profile
    // collected under a signed-out creator's anon id onto their real account.
    // Called by AccountSync on sign-in. Bound to the caller: you can only claim
    // INTO an account you're authenticated as (or via the admin token).
    if (method === "POST" && path === "/connections/claim") {
      const anonId = String(body.anonId || "");
      const claimUserId = String(body.userId || "");
      if (!anonId || !claimUserId) return json(400, { error: "anonId and userId required" });
      if (!anonId.startsWith("anon_")) return json(400, { error: "invalid anonId" });
      // Only allow claiming INTO your own account (or admin/ingest).
      const auth = await authorizeRequest(event, method, path);
      if (!(auth.via === "admin" || auth.sub === claimUserId)) {
        return json(403, { error: "forbidden" });
      }
      const out = await ddb.send(
        new QueryCommand({
          TableName: CONNECTIONS,
          KeyConditionExpression: "userId = :u",
          ExpressionAttributeValues: { ":u": anonId },
        })
      );
      const rows = out.Items ?? [];
      let claimed = 0;
      for (const row of rows) {
        await ddb.send(
          new PutCommand({ TableName: CONNECTIONS, Item: { ...row, userId: claimUserId } })
        );
        await ddb.send(
          new DeleteCommand({
            TableName: CONNECTIONS,
            Key: { userId: anonId, connectionId: row.connectionId },
          })
        );
        claimed++;
      }
      return json(200, { ok: true, claimed });
    }

    // ── Gift bundles (Maxi's picks from a completed challenge) ─────────────────
    // GET /bundles?connectionId=&userId=  — generate a gift bundle from a
    // completed swipe challenge. Uses the connection's seeds + genderPref to rank
    // items and compute estimated delivery dates relative to the birthday/date.
    if (method === "GET" && path === "/bundles") {
      const userId = qs.userId;
      const connectionId = qs.connectionId;
      if (!userId || !connectionId) return json(400, { error: "userId and connectionId required" });
      // Authorization: only the owner (or admin) can read their bundles
      const auth = await authorizeRequest(event, method, path);
      if (!(auth.via === "admin" || auth.sub === userId)) {
        return json(403, { error: "forbidden" });
      }
      // Fetch the connection record
      const connOut = await ddb.send(
        new GetCommand({ TableName: CONNECTIONS, Key: { userId, connectionId } })
      );
      const conn = connOut.Item;
      if (!conn) return json(404, { error: "connection not found" });
      // Build a bundle from the seeds — query the posts table for matching items
      const seeds = conn.seeds ?? [];
      const genderPref = conn.genderPref; // "he" | "she" | "they" | undefined
      const deadline = conn.birthday; // "YYYY-MM-DD" or undefined
      let bundleItems = [];
      if (seeds.length > 0) {
        // Look up seed pins from the posts table
        for (const seed of seeds.slice(0, 8)) {
          const out = await ddb.send(new GetCommand({ TableName: POSTS, Key: { postId: seed } }));
          if (out.Item) bundleItems.push(out.Item);
        }
      }
      // Compute delivery estimates for each item
      const today = new Date();
      today.setHours(0, 0, 0, 0);
      let deadlineDays = null;
      if (deadline && /^\d{4}-\d{2}-\d{2}$/.test(deadline)) {
        const [y, m, d] = deadline.split("-").map(Number);
        const target = new Date(y, m - 1, d);
        deadlineDays = Math.ceil((target.getTime() - today.getTime()) / 86_400_000);
      }
      const bundle = bundleItems.map((item) => {
        const price = Number(item.price ?? item.product?.price) || 50;
        const deliveryDays = price > 200 ? 7 : price > 100 ? 5 : 3;
        const canDeliverByDeadline = deadlineDays === null || deliveryDays <= deadlineDays;
        return {
          postId: item.postId,
          title: item.caption ?? item.product?.name ?? item.title ?? "",
          image: item.product?.image ?? item.image ?? "",
          price,
          category: item.category ?? item.product?.category,
          deliveryDays,
          canDeliverByDeadline,
        };
      });
      return json(200, {
        connectionId,
        guestName: conn.guestName,
        genderPref,
        deadline,
        deadlineDays,
        bundle,
        bundleTotal: bundle.reduce((sum, i) => sum + i.price, 0),
      });
    }

    // ── Group gifts (pools) ──────────────────────────────────────────────────
    // POST /pools  { userId, name, pool:{ title, occasion, goal, blurb?, emoji?,
    //   grad?, image?, recipient? } } — create a pool; the creator becomes the
    // organizer + first member. Returns the created pool.
    if (method === "POST" && path === "/pools") {
      if (!POOLS) return json(503, { error: "pools table not configured" });
      const userId = String(body.userId || auth?.sub || "").trim();
      const name = (String(body.name || "").trim() || "Someone").slice(0, 80);
      const p = body.pool ?? {};
      if (!userId) return json(400, { error: "userId required" });
      if (typeof p !== "object" || !String(p.title || "").trim()) {
        return json(400, { error: "pool.title required" });
      }
      const poolId = `pool_${gid()}`;
      const now = Date.now();
      const meta = {
        poolId,
        itemId: "META",
        title: String(p.title).trim().slice(0, 120),
        occasion: String(p.occasion || "Gift").slice(0, 40),
        goal: Math.max(10, Math.round(Number(p.goal) || 100)),
        blurb: String(p.blurb || "").slice(0, 500),
        emoji: String(p.emoji || "🎁").slice(0, 8),
        grad: poolGrad(p.grad),
        image: p.image ? String(p.image).slice(0, 600) : null,
        recipient: String(p.recipient || "").slice(0, 80),
        organizerId: userId,
        organizerName: name,
        raised: 0,
        contribCount: 0,
        memberCount: 1,
        deadline: p.deadline ? String(p.deadline).slice(0, 40) : undefined,
        createdAt: now,
      };
      await ddb.send(new PutCommand({ TableName: POOLS, Item: meta }));
      await ddb.send(
        new PutCommand({
          TableName: POOLS,
          Item: { poolId, itemId: `MEMBER#${userId}`, memberId: userId, name, joinedAt: now, role: "organizer" },
        })
      );
      // Seed a Maxi welcome so the group chat opens warm and everyone (including
      // invitees) sees the AI concierge is in the loop. "maxi" is a bot author —
      // it never becomes a member (see the messages route), so memberCount stays
      // accurate.
      const welcomeAt = now + 1;
      await ddb.send(
        new PutCommand({
          TableName: POOLS,
          Item: {
            poolId,
            itemId: `MSG#${welcomeAt}#${gid()}`,
            userId: "maxi",
            name: "Maxi",
            text: `👋 I'm Maxi, your gift concierge. ${name} started "${meta.title}" — chip in what you can, invite friends, and let's make it happen! 🎁`,
            at: welcomeAt,
          },
        })
      );
      return json(200, { ok: true, pool: poolFromMeta(meta) });
    }

    // GET /pools?userId=  — every pool the user belongs to (organizer or member).
    if (method === "GET" && path === "/pools") {
      if (!POOLS) return json(200, { items: [] });
      const userId = qs.userId;
      if (!userId) return json(400, { error: "userId required" });
      return json(200, { items: await listPoolsForMember(userId) });
    }

    // /pools/{poolId}              GET  → full pool (meta+members+contribs+chat)
    // /pools/{poolId}/join         POST → become a member
    // /pools/{poolId}/contribute   POST → chip in { amount }
    // /pools/{poolId}/messages     GET/POST → the group chat
    if (path.startsWith("/pools/")) {
      if (!POOLS) return json(503, { error: "pools table not configured" });
      const parts = path.split("/");
      const poolId = decodeURIComponent(parts[2] || "");
      const sub = parts[3] || "";
      if (!poolId) return json(400, { error: "poolId required" });

      // GET /pools/{poolId} — one Query over the whole pool partition.
      if (method === "GET" && !sub) {
        const out = await ddb.send(
          new QueryCommand({
            TableName: POOLS,
            KeyConditionExpression: "poolId = :p",
            ExpressionAttributeValues: { ":p": poolId },
          })
        );
        const all = out.Items ?? [];
        const metaItem = all.find((i) => i.itemId === "META");
        if (!metaItem) return json(404, { error: "pool not found" });
        const members = all
          .filter((i) => typeof i.itemId === "string" && i.itemId.startsWith("MEMBER#"))
          .map((m) => ({ userId: m.memberId, name: m.name, joinedAt: m.joinedAt, role: m.role }))
          .sort((a, b) => (a.joinedAt ?? 0) - (b.joinedAt ?? 0));
        const contributions = all
          .filter((i) => typeof i.itemId === "string" && i.itemId.startsWith("CONTRIB#"))
          .map((c) => ({ id: c.itemId, userId: c.userId, name: c.name, amount: Number(c.amount) || 0, at: Number(c.at) || 0 }))
          .sort((a, b) => (b.at ?? 0) - (a.at ?? 0));
        const messages = all
          .filter((i) => typeof i.itemId === "string" && i.itemId.startsWith("MSG#"))
          .map(msgFromItem)
          .sort((a, b) => (a.at ?? 0) - (b.at ?? 0))
          .slice(-300);
        return json(200, { pool: poolFromMeta(metaItem), members, contributions, messages });
      }

      // POST /pools/{poolId}/join  { userId, name }
      if (method === "POST" && sub === "join") {
        const userId = String(body.userId || auth?.sub || "").trim();
        const name = String(body.name || "").trim() || "Someone";
        if (!userId) return json(400, { error: "userId required" });
        const meta = await ddb.send(new GetCommand({ TableName: POOLS, Key: { poolId, itemId: "META" } }));
        if (!meta.Item) return json(404, { error: "pool not found" });
        await ensurePoolMember(poolId, userId, name);
        return json(200, { ok: true, pool: poolFromMeta(meta.Item) });
      }

      // POST /pools/{poolId}/contribute  { userId, name, amount } — chip in. Adds
      // a CONTRIB row, bumps the denormalized raised total, ensures membership.
      if (method === "POST" && sub === "contribute") {
        const userId = String(body.userId || auth?.sub || "").trim();
        const name = (String(body.name || "").trim() || "Someone").slice(0, 80);
        const amount = Math.round(Number(body.amount) || 0);
        if (!userId) return json(400, { error: "userId required" });
        if (!(amount > 0)) return json(400, { error: "amount must be > 0" });
        const meta = await ddb.send(new GetCommand({ TableName: POOLS, Key: { poolId, itemId: "META" } }));
        if (!meta.Item) return json(404, { error: "pool not found" });
        await ensurePoolMember(poolId, userId, name);
        const at = Date.now();
        await ddb.send(
          new PutCommand({
            TableName: POOLS,
            Item: { poolId, itemId: `CONTRIB#${at}#${gid()}`, userId, name, amount, at },
          })
        );
        const upd = await ddb.send(
          new UpdateCommand({
            TableName: POOLS,
            Key: { poolId, itemId: "META" },
            UpdateExpression: "ADD raised :a, contribCount :one",
            ExpressionAttributeValues: { ":a": amount, ":one": 1 },
            ReturnValues: "UPDATED_NEW",
          })
        );
        return json(200, { ok: true, raised: Number(upd.Attributes?.raised) || amount });
      }

      // GET /pools/{poolId}/messages?after=<ms>  — group chat, oldest-first.
      // `after` (a ms timestamp) returns only newer messages for incremental polling.
      if (method === "GET" && sub === "messages") {
        const after = qs.after ? String(qs.after) : "";
        const out = await ddb.send(
          new QueryCommand(
            after
              ? {
                  TableName: POOLS,
                  KeyConditionExpression: "poolId = :p AND itemId > :after",
                  ExpressionAttributeValues: { ":p": poolId, ":after": `MSG#${after}` },
                  Limit: 300,
                }
              : {
                  TableName: POOLS,
                  KeyConditionExpression: "poolId = :p AND begins_with(itemId, :pfx)",
                  ExpressionAttributeValues: { ":p": poolId, ":pfx": "MSG#" },
                  Limit: 300,
                }
          )
        );
        const items = (out.Items ?? []).map(msgFromItem).sort((a, b) => (a.at ?? 0) - (b.at ?? 0));
        return json(200, { items });
      }

      // POST /pools/{poolId}/messages  { userId, name, text } — post to the chat.
      if (method === "POST" && sub === "messages") {
        const userId = String(body.userId || auth?.sub || "").trim();
        const name = (String(body.name || "").trim() || "Someone").slice(0, 80);
        const text = String(body.text || "").trim();
        if (!userId) return json(400, { error: "userId required" });
        if (!text) return json(400, { error: "text required" });
        const meta = await ddb.send(new GetCommand({ TableName: POOLS, Key: { poolId, itemId: "META" } }));
        if (!meta.Item) return json(404, { error: "pool not found" });
        // The "maxi" concierge is a bot author — it posts to the chat but never
        // joins as a member or counts toward the pool size.
        if (userId !== "maxi") await ensurePoolMember(poolId, userId, name);
        const at = Date.now();
        const item = { poolId, itemId: `MSG#${at}#${gid()}`, userId, name, text: text.slice(0, 1000), at };
        await ddb.send(new PutCommand({ TableName: POOLS, Item: item }));
        return json(200, { ok: true, message: msgFromItem(item) });
      }

      return json(404, { error: `no route for ${method} ${path}` });
    }

    // ── Unified events (personal milestones + shared occasions/soft profiles) ──
    // GET /events?userId=&scope=  — a user's events, optionally filtered by scope.
    if (method === "GET" && path === "/events") {
      const userId = qs.userId;
      if (!userId) return json(400, { error: "userId required" });
      if (!EVENTS) return json(200, { items: [] });
      const scope = qs.scope;
      const out = await ddb.send(
        scope
          ? new QueryCommand({
              TableName: EVENTS,
              IndexName: "byScope",
              KeyConditionExpression: "userId = :u AND #s = :s",
              ExpressionAttributeNames: { "#s": "scope" },
              ExpressionAttributeValues: { ":u": userId, ":s": scope },
            })
          : new QueryCommand({
              TableName: EVENTS,
              KeyConditionExpression: "userId = :u",
              ExpressionAttributeValues: { ":u": userId },
            })
      );
      const items = (out.Items ?? []).sort((a, b) => (b.createdAt ?? 0) - (a.createdAt ?? 0));
      return json(200, { items });
    }

    // POST /events  { userId, event }  — create/upsert one event (personal|shared).
    if (method === "POST" && path === "/events") {
      const userId = body.userId;
      const ev = body.event ?? {};
      if (!userId || typeof ev !== "object") return json(400, { error: "userId and event required" });
      if (!EVENTS) return json(503, { error: "events table not configured" });
      const eventId = String(ev.eventId || ev.id || `evt_${gid()}`);
      const scope = ev.scope === "shared" ? "shared" : "personal";
      const item = { ...ev, userId, eventId, scope, createdAt: Number(ev.createdAt) || Date.now(), updatedAt: Date.now() };
      delete item.id;
      await ddb.send(new PutCommand({ TableName: EVENTS, Item: item }));
      await graphWrite([
        gNode(userId, "event", eventId, { scope, label: item.type || item.title || "event", data: item }),
        gEdge(userId, "HAS_EVENT", "user", userId, "event", eventId, { scope }),
      ]);
      return json(200, { ok: true, eventId, item });
    }

    // PUT /events  { userId, eventId, patch }  — partial update (e.g. complete).
    if (method === "PUT" && path === "/events") {
      const { userId, eventId, patch } = body;
      if (!userId || !eventId || typeof patch !== "object") {
        return json(400, { error: "userId, eventId, patch required" });
      }
      if (!EVENTS) return json(503, { error: "events table not configured" });
      const names = {};
      const values = { ":now": Date.now() };
      const sets = ["updatedAt = :now"];
      let i = 0;
      for (const [k, v] of Object.entries(patch)) {
        if (k === "userId" || k === "eventId" || v === undefined) continue;
        const nk = `#p${i}`;
        const vk = `:p${i}`;
        names[nk] = k;
        values[vk] = v;
        sets.push(`${nk} = ${vk}`);
        i++;
      }
      const out = await ddb.send(
        new UpdateCommand({
          TableName: EVENTS,
          Key: { userId, eventId },
          UpdateExpression: "SET " + sets.join(", "),
          ExpressionAttributeNames: Object.keys(names).length ? names : undefined,
          ExpressionAttributeValues: values,
          ReturnValues: "ALL_NEW",
        })
      );
      return json(200, { ok: true, item: out.Attributes ?? null });
    }

    // POST /events/delete  { userId, eventId }  (POST avoids DELETE CORS issues).
    if (method === "POST" && path === "/events/delete") {
      const { userId, eventId } = body;
      if (!userId || !eventId) return json(400, { error: "userId, eventId required" });
      if (!EVENTS) return json(503, { error: "events table not configured" });
      await ddb.send(new DeleteCommand({ TableName: EVENTS, Key: { userId, eventId } }));
      return json(200, { ok: true });
    }

    // POST /events/migrate  { userId, items:[...] }  — bulk import (e.g. local
    // milestones -> events, scope "personal"). Idempotent on eventId.
    if (method === "POST" && path === "/events/migrate") {
      const userId = body.userId;
      const list = Array.isArray(body.items) ? body.items : [];
      if (!userId) return json(400, { error: "userId required" });
      if (!EVENTS) return json(503, { error: "events table not configured" });
      const now = Date.now();
      const items = list.slice(0, 200).map((ev) => {
        const eventId = String(ev.eventId || ev.id || `evt_${gid()}`);
        const scope = ev.scope === "shared" ? "shared" : "personal";
        const it = { ...ev, userId, eventId, scope, createdAt: Number(ev.createdAt) || now, updatedAt: now };
        delete it.id;
        return it;
      });
      const g = [];
      for (const it of items) {
        g.push(gNode(userId, "event", it.eventId, { scope: it.scope, label: it.type || it.title || "event", data: it }));
        g.push(gEdge(userId, "HAS_EVENT", "user", userId, "event", it.eventId, { scope: it.scope }));
      }
      for (let i = 0; i < items.length; i += 25) {
        const chunk = items.slice(i, i + 25);
        if (chunk.length)
          await ddb.send(
            new BatchWriteCommand({ RequestItems: { [EVENTS]: chunk.map((Item) => ({ PutRequest: { Item } })) } })
          );
      }
      await graphWrite(g);
      return json(200, { ok: true, migrated: items.length });
    }

    // GET /graph?userId=  — the user's whole subgraph (nodes + edges) so we can
    // verify nothing was missed / render a network view.
    if (method === "GET" && path === "/graph") {
      const userId = qs.userId;
      if (!userId) return json(400, { error: "userId required" });
      if (!GRAPH) return json(200, { nodes: [], edges: [], counts: { nodes: 0, edges: 0 } });
      const out = await ddb.send(
        new QueryCommand({
          TableName: GRAPH,
          KeyConditionExpression: "pk = :u",
          ExpressionAttributeValues: { ":u": userId },
        })
      );
      const all = out.Items ?? [];
      const nodes = all
        .filter((i) => i.kind === "node")
        .map((n) => ({ id: n.entityId, type: n.type, scope: n.scope, label: n.label, data: n.data ?? {}, createdAt: n.createdAt }));
      const edges = all
        .filter((i) => i.kind === "edge")
        .map((e) => ({ rel: e.rel, from: e.srcRef, to: e.dstRef, data: e.data ?? {}, createdAt: e.createdAt }));
      return json(200, { nodes, edges, counts: { nodes: nodes.length, edges: edges.length } });
    }

    // POST /me/identity  { userId, email?, name?, imageUrl? }  — ensure a users
    // row (+ graph user node) exists from the FIRST sign-in, WITHOUT clobbering a
    // profile written later by PUT /me.
    if (method === "POST" && path === "/me/identity") {
      const { userId, email, name, imageUrl } = body;
      if (!userId) return json(400, { error: "userId required" });
      const now = Date.now();
      await ddb.send(
        new UpdateCommand({
          TableName: USERS,
          Key: { userId },
          UpdateExpression: "SET #id = :id, lastSeenAt = :now, createdAt = if_not_exists(createdAt, :now)",
          ExpressionAttributeNames: { "#id": "identity" },
          ExpressionAttributeValues: {
            ":id": { email: email ?? null, name: name ?? null, imageUrl: imageUrl ?? null },
            ":now": now,
          },
        })
      );
      await graphMergeNode(userId, "user", userId, {
        scope: "personal",
        label: name || undefined,
        email: email || undefined,
        imageUrl: imageUrl || undefined,
      });
      return json(200, { ok: true });
    }

    // POST /maxi  { userId?, name?, message, messages? } — Maxi, the Haiku 4.5
    // gift concierge. Runs a bounded Bedrock Converse tool-use loop and returns
    // { say, pins, actions }. Falls back client-side if this 5xx's.
    if (method === "POST" && path === "/maxi") {
      // Tiered cost guard: hard "paused" stops Maxi; "degraded" runs it cheap+short.
      const level = await getDegradeLevel();
      if (level === "paused") return json(503, { error: "Maxi is napping (cost guard)" });
      const degraded = level === "degraded";
      // Per-MONTH Bedrock budget: hard stop once month-to-date Maxi spend is used up.
      if (MAXI_MONTHLY_BUDGET_USD > 0 && (await maxiSpentThisMonth()) >= MAXI_MONTHLY_BUDGET_USD) {
        return json(503, { error: "maxi_budget_exhausted" });
      }
      const userId = typeof body.userId === "string" && body.userId ? body.userId : null;
      const userText = typeof body.message === "string" ? body.message.trim() : "";
      const messages = buildMaxiMessages(body.messages, userText);
      if (!messages.length) return json(400, { error: "message required" });

      // Per-user daily rate limit (abuse guard, not a usage cap). Admin/ingest
      // token bypasses; identity is the verified Clerk sub when enforced, else the
      // client userId, else the source IP.
      const rlPrincipal = auth?.via === "admin"
        ? null
        : (auth?.sub || userId || event.requestContext?.http?.sourceIp || null);
      if (rlPrincipal) {
        const rl = await checkMaxiRateLimit(rlPrincipal);
        if (!rl.ok) {
          return json(429, {
            error: "rate_limited",
            scope: "maxi_daily",
            limit: MAXI_DAILY_LIMIT,
            retryAfterSec: rl.retryAfterSec,
          });
        }
      }

      const memories = await recallMemories(userId, 8);
      const memBlock = memories.length
        ? `\n\nWhat you remember about this user (these are facts ABOUT the user, not about other people):\n- ${memories.map(scrubPII).join("\n- ")}`
        : "";
      const nameLine = typeof body.name === "string" && body.name ? `\n\nThe user's first name is ${body.name}. Always address them by this name. Do NOT confuse this with names from connections, recipients, or the relationship graph — those are other people.` : "";
      const signedOut = userId
        ? ""
        : "\n\nThe user is signed out: get_profile, upcoming_events, list_connections, relationship_graph, save_event, and remember_fact are unavailable — help with catalog search only and gently suggest signing in to unlock memory.";
      const sys = MAXI_SYSTEM + nameLine + signedOut + memBlock;

      const toolConfig = {
        tools: MAXI_TOOLS.map((t) => ({
          toolSpec: { name: t.name, description: t.description, inputSchema: { json: t.schema } },
        })),
      };
      const tctx = { userId, pins: [], actions: [], cartItems: [], steps: [] };
      // Model routing: cheap Amazon Nova by default; Claude Haiku once an agentic
      // shopping experience is triggered (intent now, or a cart/checkout tool below).
      // In DEGRADED mode we pin the cheap base model + cap the tool loop to shed cost.
      let isShopping = !degraded && maxiIsShopping(userText, body);
      let modelId = isShopping ? MAXI_SHOPPING_MODEL_ID : MAXI_BASE_MODEL_ID;
      const maxSteps = degraded ? Math.min(2, MAXI_MAX_STEPS) : MAXI_MAX_STEPS;
      let say = "";
      let usedIn = 0;
      let usedOut = 0;
      let usedCost = 0;
      try {
        for (let step = 0; step < maxSteps; step++) {
          const res = await bedrock.send(
            new ConverseCommand({
              modelId,
              system: [{ text: sys }],
              messages,
              toolConfig,
              inferenceConfig: { maxTokens: MAXI_MAX_TOKENS, temperature: 0.4 },
            })
          );
          // Per-interaction token budget: sum usage across the tool-use loop.
          const stepIn = res.usage?.inputTokens || 0;
          const stepOut = res.usage?.outputTokens || 0;
          usedIn += stepIn;
          usedOut += stepOut;
          usedCost += maxiStepCostUsd(modelId, stepIn, stepOut);
          const overTokenBudget = usedIn + usedOut >= MAXI_INTERACTION_TOKEN_BUDGET;
          const msg = res.output?.message;
          if (msg) messages.push(msg);
          const blocks = msg?.content ?? [];
          const textOut = blocks.filter((b) => b.text).map((b) => b.text).join(" ").trim();
          if (textOut) say = textOut;
          const toolUses = blocks.filter((b) => b.toolUse).map((b) => b.toolUse);
          if (res.stopReason === "tool_use" && toolUses.length && !overTokenBudget) {
            // Agentic-shopping trigger: if the agent reaches for a cart/checkout
            // tool while still on the cheap base model, escalate the rest of the
            // loop (incl. the order-confirmation turn) to the shopping model.
            if (!degraded && !isShopping && toolUses.some((tu) => MAXI_SHOPPING_TOOLS.has(tu.name))) {
              isShopping = true;
              modelId = MAXI_SHOPPING_MODEL_ID;
            }
            const results = [];
            for (const tu of toolUses) {
              let out;
              try {
                out = await runMaxiTool(tu.name, tu.input, tctx);
              } catch (e) {
                out = { error: e.message };
              }
              tctx.steps.push(maxiStepLabel(tu.name, tu.input, out));
              results.push({
                toolResult: {
                  toolUseId: tu.toolUseId,
                  content: [{ json: scrubPII(out) }],
                  status: out && out.error ? "error" : "success",
                },
              });
            }
            messages.push({ role: "user", content: results });
            continue;
          }
          break;
        }
      } catch (e) {
        console.warn("maxi converse failed:", e.name, e.message);
        return json(502, { error: "agent_unavailable", detail: e.name });
      }

      // Bill this interaction's Bedrock usage to the monthly budget counter.
      await recordMaxiUsage(usedIn, usedOut, usedCost);
      const costUsd = usedCost;
      console.log(
        "maxi usage",
        JSON.stringify({ userId, tier: isShopping ? "shopping" : "base", model: modelId, usedIn, usedOut, costUsd })
      );

      // Nova models can wrap their reasoning in <thinking>…</thinking>; strip it
      // so only the final, user-facing reply shows (Claude doesn't emit these).
      say = say.replace(/<thinking>[\s\S]*?<\/thinking>/gi, "").replace(/<\/?thinking>/gi, "").trim();

      const seen = new Set();
      const pins = tctx.pins
        .filter((p) => p && p.postId && !seen.has(p.postId) && seen.add(p.postId))
        .slice(0, 10);
      return json(200, {
        say: say || "Hmm, I didn't quite catch that — tell me a budget or who it's for and I'll find something.",
        pins,
        actions: tctx.actions,
        steps: tctx.steps,
        source: "agent",
        usage: { inputTokens: usedIn, outputTokens: usedOut, costUsd: Math.round(costUsd * 1e5) / 1e5 },
      });
    }

    return json(404, { error: `no route for ${method} ${path}` });
  } catch (err) {
    console.error("handler error", err);
    return json(500, { error: "internal error" });
  }
};
