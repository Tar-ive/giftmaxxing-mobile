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
  BatchGetCommand,
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
import { SageMakerRuntimeClient, InvokeEndpointCommand } from "@aws-sdk/client-sagemaker-runtime";
import { CognitoIdentityProviderClient, InitiateAuthCommand } from "@aws-sdk/client-cognito-identity-provider";
import { SESClient, SendEmailCommand } from "@aws-sdk/client-ses";
import { createHash } from "node:crypto";
import { classifyPin, isMajorUSRetailer } from "./quality.mjs";
import { interleaveAuthors, interleaveUGC } from "./feed-diversity.mjs";
import { sendPushToUser } from "./push.mjs";
import { mobileRoutes } from "./mobile-routes.mjs";
import { analyticsRoutes } from "./analytics-routes.mjs";
import { birthdayFreebiesRoute } from "./birthday-freebies.mjs";
import { friendsRoutes } from "./friends-routes.mjs";
import { purgeUserAvatar, purgeUserUGC, ugcRoutes } from "./ugc-routes.mjs";
import { createRemoteJWKSet, jwtVerify, SignJWT } from "jose";

const ddb = DynamoDBDocumentClient.from(new DynamoDBClient({}), {
  marshallOptions: { removeUndefinedValues: true },
});

const USERS = process.env.USERS_TABLE;
const POSTS = process.env.POSTS_TABLE;
const INTERACTIONS = process.env.INTERACTIONS_TABLE;
const KNOWLEDGE = process.env.KNOWLEDGE_TABLE;
const CONNECTIONS = process.env.CONNECTIONS_TABLE;
const CHALLENGES = process.env.CHALLENGES_TABLE;
const POOLS = process.env.POOLS_TABLE;
const EVENTS = process.env.EVENTS_TABLE;
const GRAPH = process.env.GRAPH_TABLE;
const CONFIG = process.env.CONFIG_TABLE;
const FRIENDS = process.env.FRIENDS_TABLE;
const ANALYTICS = process.env.ANALYTICS_TABLE;
const DEVICES = process.env.DEVICES_TABLE;
const COGNITO_CLIENT_ID = process.env.COGNITO_CLIENT_ID || "";
const LOGIN_RESET_URL = process.env.LOGIN_RESET_URL || "";
const LOGIN_EMAIL_FROM = process.env.LOGIN_EMAIL_FROM || "";
const cognito = new CognitoIdentityProviderClient({});
const ses = new SESClient({});

// This is intentionally process-local: it is a safe fallback for the current
// Lambda/App Runner deployment when no Redis provider is configured. For a
// multi-instance deployment, replace this map with Redis/Upstash atomics.
const loginState = new Map();
const LOGIN_WINDOW_MS = 60_000;
const LOGIN_MAX_PER_IP = 10;
const LOGIN_MAX_FAILURES = 5;
const LOGIN_LOCK_MS = 15 * 60_000;
const loginKey = (email) => createHash("sha256").update(String(email).trim().toLowerCase()).digest("hex");
const sourceIp = (event) => event.requestContext?.http?.sourceIp || event.headers?.["x-forwarded-for"]?.split(",")[0]?.trim() || "unknown";
function loginEntry(email) {
  const key = loginKey(email);
  const entry = loginState.get(key) || { failures: 0, lockedUntil: 0, notified: false };
  loginState.set(key, entry);
  return entry;
}
function pruneLoginState(now = Date.now()) {
  for (const [key, item] of loginState) if (item.windowUntil < now && !item.lockedUntil) loginState.delete(key);
}
async function sendLockoutEmail(email) {
  if (!LOGIN_EMAIL_FROM || !LOGIN_RESET_URL) return;
  const resetLink = `${LOGIN_RESET_URL}${LOGIN_RESET_URL.includes("?") ? "&" : "?"}token=${encodeURIComponent(Buffer.from(String(email)).toString("base64url"))}`;
  await ses.send(new SendEmailCommand({
    Source: LOGIN_EMAIL_FROM,
    Destination: { ToAddresses: [email] },
    Message: {
      Subject: { Data: "Reset your Giftmaxxing password", Charset: "UTF-8" },
      Body: { Text: { Data: `We blocked sign-in attempts on your Giftmaxxing account. Reset your password here: ${resetLink}`, Charset: "UTF-8" } },
    },
  }));
}
async function loginRoute(event, body) {
  pruneLoginState();
  const email = typeof body.email === "string" ? body.email.trim().toLowerCase() : "";
  const password = typeof body.password === "string" ? body.password : "";
  const ip = sourceIp(event);
  const now = Date.now();
  const ipEntry = loginState.get(`ip:${ip}`) || { windowUntil: now + LOGIN_WINDOW_MS, requests: 0 };
  if (now >= ipEntry.windowUntil) Object.assign(ipEntry, { windowUntil: now + LOGIN_WINDOW_MS, requests: 0 });
  ipEntry.requests += 1;
  loginState.set(`ip:${ip}`, ipEntry);
  if (ipEntry.requests > LOGIN_MAX_PER_IP) return json(429, { error: "Unable to sign in. Please try again later." }, { "retry-after": String(Math.ceil((ipEntry.windowUntil - now) / 1000)) });

  const entry = loginEntry(email);
  if (entry.lockedUntil > now) return json(401, { error: "Unable to sign in. Please use the password reset link if needed." });
  if (entry.failures > 0) await new Promise((resolve) => setTimeout(resolve, Math.min(2000, 250 * 2 ** (entry.failures - 1))));
  try {
    if (!COGNITO_CLIENT_ID || !email || !password) throw new Error("invalid credentials");
    const result = await cognito.send(new InitiateAuthCommand({
      ClientId: COGNITO_CLIENT_ID,
      AuthFlow: "USER_PASSWORD_AUTH",
      AuthParameters: { USERNAME: email, PASSWORD: password },
    }));
    loginState.delete(loginKey(email));
    return json(200, { authenticationResult: result.AuthenticationResult });
  } catch (error) {
    entry.failures += 1;
    if (entry.failures >= LOGIN_MAX_FAILURES) {
      entry.lockedUntil = now + LOGIN_LOCK_MS;
      if (!entry.notified) { entry.notified = true; sendLockoutEmail(email).catch((err) => console.warn("lockout email failed", err.message)); }
    }
    // Same response for bad credentials and lockout, preventing account-state disclosure.
    return json(401, { error: "Unable to sign in. Please use the password reset link if needed." });
  }
}

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
  if (method === "POST" && path === "/login") return true;
  if (method === "GET") {
    if (path === "/feed" || path === "/recommendations" || path === "/pins") return true;
    if (path === "/recipients" || path === "/ideas") return true;
    // Curated gallery membership + Reddit-mined gift bundles — public catalog
    // browse surfaces, same trust level as /feed.
    if (/^\/galleries\/[^/]+$/.test(path) || path === "/bundles") return true;
    if (path === "/birthday-freebies") return true;
    if (path === "/vectors") return true;
    if (path.startsWith("/posts/")) return true;
    // Guest deck fetch (the invited friend swipes without an account). The
    // sender-only fields (seed, verdicts) are stripped unless the request
    // authenticates as the challenge's sender — see the route.
    if (/^\/challenges\/[^/]+$/.test(path)) return true;
    // Circle page (family/friend group) — the share link IS the membership
    // credential, same trust model as invite/challenge links.
    if (/^\/circles\/[^/]+$/.test(path)) return true;
    // Public people directory — discover other Giftmaxxing users by name/handle.
    if (path === "/people" || /^\/people\/[^/]+$/.test(path)) return true;
  }
  // Behavioral analytics ingestion — events arrive before sign-in completes
  // (and from guests), keyed by userId/anonymousId inside the payload.
  if (method === "POST" && path === "/mobile/analytics") return true;
  // APNs token registration — arrives before sign-in completes (guests/anon
  // senders need pushes for challenge responses); token is opaque + harmless.
  if (method === "POST" && path === "/mobile/device") return true;
  // Session mint: authenticates via the PROVIDER token in the bearer header
  // (verified inside the route), so the route itself is public.
  if (method === "POST" && path === "/auth/session") return true;
  if (method === "POST" && (path === "/visual-search" || path === "/connections")) return true;
  // Challenge create (anon senders allowed, same trust as POST /connections;
  // Bedrock embed cost rides the aiEnabled() breaker) + the guest's response.
  if (method === "POST" && (path === "/challenges" || /^\/challenges\/[^/]+\/response$/.test(path))) return true;
  // Circle create/join/events: anonymous family members add their birthday
  // via the shared link — no account, exactly like guest challenge responses.
  // `/claim` requires auth (links a signed-in account to a circle seat).
  if (method === "POST" && (path === "/circles" || /^\/circles\/[^/]+\/(join|events|events\/delete)$/.test(path))) return true;
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

// ── First-party sessions ──────────────────────────────────────────────────────────────────
// POST /auth/session exchanges a VERIFIED provider identity (Google ID token
// or Sign in with Apple identity token) for a 30-day HS256 session JWT.
// Why: Apple identity tokens die in ~10 minutes and Google's in ~1 hour, so
// signed-in iOS users kept falling out of the auth-gated routes (/maxi, /me)
// mid-session. The session token's sub is the CANONICAL user id — whichever
// identity claimed the (token-verified) email first — so a tester who onboards
// on the web (Clerk) and later installs the app lands in the SAME account.
const SESSION_JWT_SECRET = process.env.SESSION_JWT_SECRET || "";
const SESSION_TTL_SECONDS = 30 * 24 * 3600;
const APPLE_BUNDLE_ID = process.env.APPLE_BUNDLE_ID || "com.giftmaxxing.ios";
const _appleJwks = createRemoteJWKSet(new URL("https://appleid.apple.com/auth/keys"));

async function verifyProviderToken(token) {
  if (_googleJwks) {
    try {
      const { payload } = await jwtVerify(token, _googleJwks, {
        issuer: ["https://accounts.google.com", "accounts.google.com"],
        audience: GOOGLE_OAUTH_CLIENT_ID,
      });
      if (payload?.sub) {
        return {
          providerId: `google_${payload.sub}`,
          // Only a VERIFIED email may drive account merging — an unverified
          // one would let anyone claim anyone's account.
          email: payload.email_verified && payload.email ? String(payload.email).toLowerCase() : null,
          name: payload.name ? String(payload.name) : null,
        };
      }
    } catch {}
  }
  try {
    const { payload } = await jwtVerify(token, _appleJwks, {
      issuer: "https://appleid.apple.com",
      audience: APPLE_BUNDLE_ID,
    });
    if (payload?.sub) {
      return {
        providerId: `apple_${payload.sub}`,
        // Apple emails (incl. private relay) are verified by Apple.
        email: payload.email ? String(payload.email).toLowerCase() : null,
        name: null,
      };
    }
  } catch {}
  return null;
}

const emailAliasKey = (email) => `email#${String(email).trim().toLowerCase()}`;

// First identity to claim a verified email becomes canonical for it; every
// later identity with the same email ADOPTS that user id. Alias rows live in
// the users table under "email#<addr>" — web Clerk sign-ins write the same
// rows via POST /me/identity, which is what makes web ↔ iOS data seamless.
async function resolveCanonicalUserId(providerId, email) {
  if (!email || !USERS) return providerId;
  const key = emailAliasKey(email);
  try {
    const existing = await ddb.send(new GetCommand({ TableName: USERS, Key: { userId: key } }));
    if (existing.Item?.canonicalUserId) return existing.Item.canonicalUserId;
    await ddb.send(
      new PutCommand({
        TableName: USERS,
        Item: { userId: key, canonicalUserId: providerId, alias: true, createdAt: Date.now() },
        ConditionExpression: "attribute_not_exists(userId)",
      })
    );
    return providerId;
  } catch {
    // Lost a concurrent claim race — read back the winner.
    try {
      const again = await ddb.send(new GetCommand({ TableName: USERS, Key: { userId: key } }));
      if (again.Item?.canonicalUserId) return again.Item.canonicalUserId;
    } catch {}
    return providerId;
  }
}

async function signSessionJwt(sub, email, name) {
  const jwt = new SignJWT({ email: email || undefined, name: name || undefined })
    .setProtectedHeader({ alg: "HS256" })
    .setSubject(sub)
    .setIssuer("giftmaxxing")
    .setIssuedAt()
    .setExpirationTime(`${SESSION_TTL_SECONDS}s`);
  return jwt.sign(new TextEncoder().encode(SESSION_JWT_SECRET));
}

async function verifySessionJwt(event) {
  if (!SESSION_JWT_SECRET) return null;
  const token = bearerToken(event);
  if (!token) return null;
  try {
    const { payload } = await jwtVerify(token, new TextEncoder().encode(SESSION_JWT_SECRET), {
      issuer: "giftmaxxing",
    });
    return payload?.sub ? String(payload.sub) : null;
  } catch {
    return null;
  }
}

// /seed is admin-only (ingest). Other protected routes accept a first-party
// session JWT (iOS), a Clerk JWT (web), a Google/Cognito ID token (iOS app),
// OR the admin token.
async function authorizeRequest(event, method, path) {
  if (hasAdminToken(event)) return { ok: true, sub: "admin", via: "admin" };
  if (method === "POST" && path === "/seed") return { ok: false };
  const sessionSub = await verifySessionJwt(event);
  if (sessionSub) return { ok: true, sub: sessionSub, via: "session" };
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

function feedClassification(post) {
  if (post.source === "ugc") {
    if (post.moderationStatus === "APPROVED" && post.processingStatus === "READY" && post.feedEligible === true) {
      return { contentType: post.contentType ?? "ugc", qualityScore: 0.8, feedEligible: true };
    }
    return { contentType: post.contentType ?? "ugc", qualityScore: 0, feedEligible: false };
  }
  return classifyPin({
    title: post.caption ?? post.product?.name,
    domain: post.domain ?? post.merchant,
    link: post.url ?? post.productUrl,
    price: post.price ?? post.product?.price,
    giftType: post.giftType,
  });
}

// S3 Vectors (the vector store powering similarity-based recommendations).
const VECTOR_BUCKET = process.env.VECTOR_BUCKET;
const VECTOR_INDEX = process.env.VECTOR_INDEX;
const s3v = VECTOR_BUCKET ? new S3VectorsClient({}) : null;

// Hydrate an ordered id list into post items (BatchGet, order preserved,
// quality-gated). Backs /galleries/{id} and /bundles — their CONFIG rows
// store postId lists, not documents, so the posts stay the single source
// of truth for price/image/link freshness.
async function hydratePosts(ids, limit = 60) {
  const wanted = [...new Set(ids)].slice(0, Math.min(limit, 100));
  if (!wanted.length) return [];
  const found = new Map();
  for (let i = 0; i < wanted.length; i += 100) {
    const out = await ddb.send(
      new BatchGetCommand({
        RequestItems: { [POSTS]: { Keys: wanted.slice(i, i + 100).map((postId) => ({ postId })) } },
      })
    );
    for (const p of out.Responses?.[POSTS] ?? []) found.set(p.postId, p);
  }
  return wanted
    .map((id) => found.get(id))
    .filter(Boolean)
    .map((p) => {
      const q = feedClassification(p);
      return { ...p, contentType: q.contentType, qualityScore: q.qualityScore, feedEligible: q.feedEligible };
    })
    .filter((p) => p.feedEligible);
}

// MTL value model (SageMaker serverless endpoint, infra/ml). When configured,
// /recommendations re-ranks its kNN candidates by
//   Score = 2·P_Time + 5·P_Custom + 1·P_Buy
// instead of raw cosine order. Empty env -> feature off, zero new latency.
const MTL_ENDPOINT = process.env.MTL_ENDPOINT || "";
// Interaction-model serving split (fast front-end / intelligent back-end):
// the DEFAULT /recommendations response is the fast path — cosine order,
// no model invoke, instant. `?rank=full` is the back-end path the client
// calls in the background after first paint; it runs the MTL value model
// with a generous deadline (a serverless cold start is fine there because
// nobody is staring at a spinner).
const MTL_TIMEOUT_FAST_MS = Number(process.env.MTL_TIMEOUT_MS || 2500);
const MTL_TIMEOUT_FULL_MS = Number(process.env.MTL_TIMEOUT_FULL_MS || 12000);
const smr = MTL_ENDPOINT ? new SageMakerRuntimeClient({}) : null;

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
// Who is this product actually FOR? Most pins carry no audience tag (the
// catalog skews feminine), so recipient personalization needs text inference:
// one-sided keywords only — ambiguous items stay null (neutral) so unisex
// gifts are never excluded. Mirrors AudienceClassifier.swift; keep in sync.
const WOMEN_RE = /\b(her|hers|woman|women|womens|girl|girls|girly|girlfriend|wife|mom|mama|mother|sister|aunt|auntie|grandma|nana|bride|bridal|bridesmaid|princess|queen|goddess|babe|lady|ladies|feminine)\b|makeup|skincare|lipstick|lip gloss|lip oil|lip tint|lip butter|mascara|eyeshadow|eyelash|nail polish|press.?on nail|manicure|scrunchie|claw clip|hair clip|barrette|handbag|purse|crossbody|shoulder bag|mini bag|baggu|heels\b|floral|rose gold|blush|dainty|bling|glitter|sparkl|kawaii|perfume|parfum|eau de|fragrance|body mist|earring|necklace|pendant|charm bracelet|bralette|leggings?\b|bodysuit|\bdress\b|skirt\b/gi;
const MEN_RE = /\b(him|his|man|men|mens|guy|guys|dude|boyfriend|husband|dad|father|papa|grandpa|uncle|brother|groom|groomsman|groomsmen|gentleman|gentlemen|masculine)\b|beard|mustache|shaving|aftershave|cologne|whiskey|whisky|bourbon|scotch|cigar|\bedc\b|tactical|multi.?tool|pocket knife|cufflink|necktie|tie clip|tie bar|\bbbq\b|grilling|garage|woodworking|decanter|flask|pint glass|\bbeer\b|jerky|hot sauce|poker|golf\b|fishing|camping|hatchet|dopp kit|leather wallet|leather belt|suspenders|humidor/gi;

function inferAudience(text) {
  if (!text) return null;
  const women = (String(text).match(WOMEN_RE) || []).length;
  const men = (String(text).match(MEN_RE) || []).length;
  if (women > men) return "women";
  if (men > women) return "men";
  return null;
}

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
  // Recipient is a SOFT preference: most of the catalog is tagged "anyone",
  // so hard-filtering on it used to blank the whole feed for anyone whose
  // consult said "for him"/"for her". Match on the recipient tag, the ingest's
  // attrs.audience, or (since most pins are untagged) the TEXT-inferred
  // audience; clear opposites sink hard — a "for him" feed was still serving
  // bling phone cases and makeup kits on social proof alone.
  if (recipient === "men" || recipient === "women") {
    const audience = p.attrs?.audience || inferAudience(`${p.caption ?? ""} ${p.product?.name ?? ""}`);
    if (p.recipient === recipient || audience === recipient) {
      s += 0.2 * occMult;
    } else if (audience === "men" || audience === "women" || p.recipient === "men" || p.recipient === "women") {
      s -= 0.3;
    }
  } else if (recipient && recipient !== "anyone" && p.recipient === recipient) {
    s += 0.2 * occMult;
  }
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
async function userExclusions(userId) {
  if (!userId || !INTERACTIONS) return { posts: new Set(), authors: new Set() };
  try {
    const inter = await ddb.send(
      new QueryCommand({
        TableName: INTERACTIONS,
        KeyConditionExpression: "userId = :u",
        ExpressionAttributeValues: { ":u": userId },
        ProjectionExpression: "target, #type",
        ExpressionAttributeNames: { "#type": "type" },
      })
    );
    const rows = inter.Items ?? [];
    return {
      posts: new Set(rows.filter((item) => item.type !== "block").map((item) => item.target).filter(Boolean)),
      authors: new Set(rows.filter((item) => item.type === "block").map((item) => item.target).filter(Boolean)),
    };
  } catch (e) {
    console.warn("userExclusions failed:", e.message);
    return { posts: new Set(), authors: new Set() };
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
  const giftType = m.giftType === "service" ? "service" : "product";
  const q = classifyPin({ title: m.title, domain: m.domain, link: productUrl, price, giftType });
  return {
    postId: v.key,
    giftType,
    ...(m.serviceDuration ? { serviceDuration: m.serviceDuration } : {}),
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
// rank: "fast" (default) returns cosine order immediately — the front-end
// path; "full" re-ranks through the MTL value model with request context —
// the intelligent back-end path (see MTL_TIMEOUT_* above).
async function vectorRecommend(seedKeys, { limit, sourceUser, rank, context }) {
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
  const items = (out.vectors ?? [])
    .filter((v) => !seen.has(v.key))
    .map(vecToItem)
    .filter((it) => it.feedEligible);
  const ranked = rank === "full" ? await mtlRerank(centroid, items, seedKeys.length, context) : null;
  return (ranked ?? items).slice(0, limit);
}

// Re-rank candidates through the MTL value model (infra/ml, SageMaker
// serverless endpoint). Soft-fails to cosine order on any error or timeout —
// a cold serverless container (~10-30 s) will miss the deadline, warm up in
// the background, and serve the next request.
async function mtlRerank(centroid, items, userEvents, context) {
  if (!smr || !items.length) return null;
  try {
    const keys = items.map((it) => it.postId);
    const vecs = new Map();
    for (let i = 0; i < keys.length; i += 100) {
      const out = await s3v.send(
        new GetVectorsCommand({
          vectorBucketName: VECTOR_BUCKET,
          indexName: VECTOR_INDEX,
          keys: keys.slice(i, i + 100),
          returnData: true,
        })
      );
      for (const v of out.vectors ?? []) vecs.set(v.key, v.data?.float32);
    }
    const payload = {
      user: centroid,
      user_events: userEvents,
      // Raw context only — featurization (time cyclical encoding, one-hots,
      // Reddit idea weights) happens inside the endpoint via features.py,
      // the same module the training export used. No feature skew possible.
      context: {
        ts: Date.now(),
        relationship: context?.relationship || undefined,
        occasion: context?.occasion || undefined,
        recipient: context?.relationship || undefined,
      },
      items: items
        .filter((it) => vecs.has(it.postId))
        .map((it) => ({
          key: it.postId,
          vector: vecs.get(it.postId),
          price: it.price || 0,
          title: it.name || undefined,
          source: it.source === "pinterest" || it.postId.startsWith("pin-") ? "pinterest"
            : it.author && it.author !== "pinterest" ? "shopify" : "other",
        })),
    };
    if (!payload.items.length) return null;
    const resp = await smr.send(
      new InvokeEndpointCommand({
        EndpointName: MTL_ENDPOINT,
        ContentType: "application/json",
        Body: JSON.stringify(payload),
      }),
      { abortSignal: AbortSignal.timeout(MTL_TIMEOUT_FULL_MS) }
    );
    const scored = JSON.parse(Buffer.from(resp.Body).toString("utf8"));
    const byKey = new Map((scored.items ?? []).map((s) => [s.key, s]));
    if (!byKey.size) return null;
    return items
      .map((it) => {
        const s = byKey.get(it.postId);
        return s
          ? { ...it, mtl: { pTime: s.p_time, pCustom: s.p_custom, pBuy: s.p_buy, score: s.score } }
          : it;
      })
      .sort((a, b) => (b.mtl?.score ?? -1) - (a.mtl?.score ?? -1));
  } catch (e) {
    console.warn("mtl rerank skipped:", e.name === "TimeoutError" ? "timeout (cold endpoint?)" : e.message);
    return null;
  }
}

// ── Challenge engine (product-seeded swipe challenges) ───────────────────────
// A challenge packages a SEED (a catalog pin, a taste-key set, or an uploaded
// image — e.g. shared from Instagram) into a swipe deck of catalog items around
// that seed: near-twins ("same thing, other colorways/varieties"), same-vibe
// items at mid distance, and a few taste probes further out. The guest never
// sees which card was the ask; their swipes are scored against the seed vector
// to answer the sender's real question — "would they like THIS?" — indirectly.
const CHALLENGE_DECK_SIZE = 14;
// Cosine-DISTANCE bands over the Titan multimodal space: twins | same-vibe.
const CHALLENGE_BAND_TWIN = 0.35;
const CHALLENGE_BAND_VIBE = 0.55;
// Visual search relevance gate — same cosine-distance space as the challenge
// bands: anything past "same vibe" plus a small margin is not a visual match.
const VISUAL_SEARCH_MAX_DISTANCE = Number(process.env.VISUAL_SEARCH_MAX_DISTANCE || 0.62);

function cosSim(a, b) {
  let dot = 0, na = 0, nb = 0;
  for (let i = 0; i < a.length; i++) {
    dot += a[i] * b[i];
    na += a[i] * a[i];
    nb += b[i] * b[i];
  }
  const d = Math.sqrt(na) * Math.sqrt(nb);
  return d > 0 ? dot / d : 0;
}

// int8-quantize a float vector for storage inside the challenge META item
// (~1.4 KB vs ~20 KB as JSON floats). Same scheme as GET /vectors; cosine only
// needs direction, so the per-vector scale fully preserves what we use.
function packVector(f) {
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
  return { dim: f.length, scale, data: Buffer.from(q.buffer).toString("base64") };
}

function unpackVector(p) {
  if (!p?.data || !p?.dim) return null;
  const buf = Buffer.from(p.data, "base64");
  const q = new Int8Array(buf.buffer, buf.byteOffset, Math.min(p.dim, buf.length));
  const scale = Number(p.scale) || 1;
  return Array.from(q, (v) => v * scale);
}

// GetVectors in chunks of 20 (API cap) -> Map(key -> vector record with data).
async function getVectorsByKeys(keys) {
  const out = new Map();
  if (!s3v) return out;
  for (let i = 0; i < keys.length; i += 20) {
    const res = await s3v.send(
      new GetVectorsCommand({
        vectorBucketName: VECTOR_BUCKET,
        indexName: VECTOR_INDEX,
        keys: keys.slice(i, i + 20),
        returnData: true,
        returnMetadata: true,
      })
    );
    for (const v of res.vectors ?? []) {
      if (Array.isArray(v.data?.float32)) out.set(v.key, v);
    }
  }
  return out;
}

// The condensed per-card snapshot stored on the challenge META item. `band` and
// `distance` are sender-side internals — strip them before showing a guest.
function deckSnapshot(it, band) {
  return {
    postId: it.postId,
    name: it.name,
    image: it.image,
    price: it.price,
    priceDisplay: it.priceDisplay,
    category: it.category,
    domain: it.domain,
    url: it.url,
    // Products vs services split so guests render service cards correctly and
    // the verdict can report "they're a services person" (giftTypeSplit).
    giftType: it.giftType === "service" ? "service" : "product",
    ...(it.serviceDuration ? { serviceDuration: it.serviceDuration } : {}),
    band,
    distance: it._distance,
  };
}

// A couple of gift-able SERVICES (a year of Netflix, a Costco membership, …)
// mixed into every challenge deck as probes. Whether the guest swipes yes on
// services vs products is itself a taste read (verdict.giftTypeSplit) — "they'd
// rather get a membership than a thing" makes gifting materially easier.
// Sourced from the posts byCategory GSI (category "services", written by
// infra/ingest/ingest-catalog.mjs); returns [] when none are seeded yet.
async function fetchServiceCards(count = 3) {
  if (!POSTS || count <= 0) return [];
  try {
    const out = await ddb.send(
      new QueryCommand({
        TableName: POSTS,
        IndexName: "byCategory",
        KeyConditionExpression: "category = :c",
        ExpressionAttributeValues: { ":c": "services" },
        Limit: 24,
      })
    );
    const rows = (out.Items ?? []).filter((p) => p.giftType === "service");
    // Cheap shuffle so repeat challenges don't always probe the same services.
    for (let i = rows.length - 1; i > 0; i--) {
      const j = Math.floor(Math.random() * (i + 1));
      [rows[i], rows[j]] = [rows[j], rows[i]];
    }
    return rows.slice(0, count).map((p) => ({
      postId: p.postId,
      name: p.product?.name || p.caption || "",
      image: p.product?.image || null,
      price: Number(p.price ?? p.product?.price) || 0,
      priceDisplay: p.priceDisplay ?? null,
      category: p.category || "services",
      domain: p.domain || null,
      url: p.productUrl || p.url || "",
      giftType: "service",
      ...(p.serviceDuration ? { serviceDuration: p.serviceDuration } : {}),
      band: "probe",
    }));
  } catch (e) {
    console.warn("fetchServiceCards failed (deck ships without services):", e.message);
    return [];
  }
}

// kNN around the seed, quality-filtered, then a banded diversity pass:
// ~30% twins (variant/colorway candidates), ~40% same vibe, rest probes —
// capped per merchant + category, then shuffled so the deck order never leaks
// the similarity gradient to the guest.
async function buildChallengeDeck(seedVector, { size = CHALLENGE_DECK_SIZE, excludeKeys = [] } = {}) {
  // Reserve ~20% of the deck for service probes (2–3 cards at default size).
  // They come from the catalog, not the kNN, so the vibe/twin bands keep their
  // meaning; if no services are seeded yet the deck fills entirely from kNN.
  const serviceTarget = Math.max(0, Math.min(3, Math.round(size * 0.2)));
  const serviceCards = (await fetchServiceCards(serviceTarget)).filter(
    (c) => !excludeKeys.includes(c.postId)
  );
  size = Math.max(4, size - serviceCards.length);

  const out = await s3v.send(
    new QueryVectorsCommand({
      vectorBucketName: VECTOR_BUCKET,
      indexName: VECTOR_INDEX,
      topK: Math.min(Math.max(size * 6, 60), 100),
      queryVector: { float32: seedVector },
      returnMetadata: true,
      returnDistance: true,
    })
  );
  const seen = new Set(excludeKeys);
  const candidates = (out.vectors ?? [])
    .filter((v) => !seen.has(v.key))
    .map((v) => {
      const it = vecToItem(v);
      const d = v.distance ?? 1;
      it._band = d < CHALLENGE_BAND_TWIN ? "twin" : d < CHALLENGE_BAND_VIBE ? "vibe" : "probe";
      return it;
    })
    .filter((it) => it.feedEligible && it.image);

  const quota = { twin: Math.round(size * 0.3), vibe: Math.round(size * 0.4), probe: size };
  const picked = [];
  const pickedKeys = new Set();
  const byDomain = {};
  const byCategory = {};
  const taken = { twin: 0, vibe: 0, probe: 0 };
  const admit = (it, band, enforceQuota) => {
    if (picked.length >= size || pickedKeys.has(it.postId)) return;
    if (enforceQuota && taken[band] >= quota[band]) return;
    if ((byDomain[it.domain] ?? 0) >= 3 || (byCategory[it.category] ?? 0) >= 5) return;
    picked.push(deckSnapshot(it, band));
    pickedKeys.add(it.postId);
    taken[band]++;
    byDomain[it.domain] = (byDomain[it.domain] ?? 0) + 1;
    byCategory[it.category] = (byCategory[it.category] ?? 0) + 1;
  };
  for (const band of ["twin", "vibe", "probe"]) {
    for (const it of candidates) if (it._band === band) admit(it, band, true);
  }
  // Backfill closest-first if any band under-delivered.
  for (const it of candidates) admit(it, it._band, false);

  // Service probes join the pool before the shuffle so their position never
  // gives them away (dedup on postId in case a service also matched the kNN).
  for (const card of serviceCards) {
    if (!pickedKeys.has(card.postId)) {
      picked.push(card);
      pickedKeys.add(card.postId);
    }
  }

  // Fisher-Yates so twins aren't clustered at the front of the deck.
  for (let i = picked.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [picked[i], picked[j]] = [picked[j], picked[i]];
  }
  return picked;
}

// Score a guest's swipes against the seed. Two signals, blended:
//   1. weightedApproval — on cards SIMILAR to the seed, did they say yes?
//      (each swipe weighted by cos(card, seed)^2, so far-away probes barely count)
//   2. centroidDelta — is their yes-centroid closer to the seed than their
//      no-centroid? (sign = direction of their taste relative to the ask)
// Plus a taste summary the sender can act on (categories, price band, dwell
// favorite, and liked TWINS = direct "buy this variant" candidates).
function computeChallengeVerdict({ seedVec, swipes, vectorsByKey, deckByKey }) {
  const yes = swipes.filter((s) => s.dir === "yes");
  const dim = seedVec.length;
  let wYes = 0, wTot = 0, nYes = 0, nNo = 0;
  const accYes = new Array(dim).fill(0);
  const accNo = new Array(dim).fill(0);
  let directSeedSwipe = null; // the seed card itself, if it was in the deck
  for (const s of swipes) {
    if (deckByKey.get(s.id)?.band === "seed") directSeedSwipe = s.dir;
    const v = vectorsByKey.get(s.id)?.data?.float32;
    if (!v || v.length !== dim) continue;
    const w = Math.max(0, cosSim(v, seedVec)) ** 2;
    wTot += w;
    if (s.dir === "yes") {
      wYes += w;
      nYes++;
      for (let i = 0; i < dim; i++) accYes[i] += v[i];
    } else {
      nNo++;
      for (let i = 0; i < dim; i++) accNo[i] += v[i];
    }
  }
  const plainYesRate = swipes.length ? yes.length / swipes.length : 0;
  const weightedApproval = wTot > 1e-6 ? wYes / wTot : plainYesRate;
  let centroidDelta = 0;
  if (nYes && nNo) {
    centroidDelta =
      cosSim(accYes.map((x) => x / nYes), seedVec) - cosSim(accNo.map((x) => x / nNo), seedVec);
  } else if (nYes) centroidDelta = 0.1;
  else if (nNo) centroidDelta = -0.1;
  const deltaNorm = Math.max(0, Math.min(1, (centroidDelta + 0.2) / 0.4));
  let score = Math.max(0, Math.min(1, 0.65 * weightedApproval + 0.35 * deltaNorm));
  // A direct swipe on the hidden seed card overrides inference in that direction.
  if (directSeedSwipe === "yes") score = Math.max(score, 0.85);
  if (directSeedSwipe === "no") score = Math.min(score, 0.25);
  const label = score >= 0.72 ? "love" : score >= 0.55 ? "like" : score >= 0.4 ? "unsure" : "pass";

  // Product-vs-service read: services in the deck are probes (see
  // fetchServiceCards) — a guest who says yes to "a year of Spotify" but no to
  // objects is telling us the gift should be a SERVICE. Rates are null until
  // that gift type actually appeared in the deck.
  const split = { productYes: 0, productTotal: 0, serviceYes: 0, serviceTotal: 0 };
  for (const s of swipes) {
    const isService = deckByKey.get(s.id)?.giftType === "service";
    if (isService) {
      split.serviceTotal++;
      if (s.dir === "yes") split.serviceYes++;
    } else {
      split.productTotal++;
      if (s.dir === "yes") split.productYes++;
    }
  }
  const giftTypeSplit = {
    ...split,
    productYesRate: split.productTotal ? Math.round((split.productYes / split.productTotal) * 100) / 100 : null,
    serviceYesRate: split.serviceTotal ? Math.round((split.serviceYes / split.serviceTotal) * 100) / 100 : null,
  };

  const likedItems = yes.map((s) => deckByKey.get(s.id)).filter(Boolean);
  const catCounts = {};
  for (const it of likedItems) if (it.category) catCounts[it.category] = (catCounts[it.category] ?? 0) + 1;
  const topCategories = Object.entries(catCounts)
    .sort((a, b) => b[1] - a[1])
    .slice(0, 4)
    .map(([c]) => c);
  const prices = likedItems.map((it) => it.price).filter((p) => p > 0).sort((a, b) => a - b);
  const priceBand = prices.length
    ? { min: prices[0], median: prices[Math.floor(prices.length / 2)], max: prices[prices.length - 1] }
    : null;
  const favoriteId =
    swipes
      .filter((s) => s.dir === "yes" && s.dwellMs > 0)
      .sort((a, b) => b.dwellMs - a.dwellMs)[0]?.id ?? null;
  const variantPicks = likedItems
    .filter((it) => it.band === "twin" || it.band === "seed")
    .map((it) => it.postId);

  return {
    score: Math.round(score * 100) / 100,
    label,
    directSeedSwipe,
    weightedApproval: Math.round(weightedApproval * 100) / 100,
    centroidDelta: Math.round(centroidDelta * 1000) / 1000,
    topCategories,
    priceBand,
    favoriteId,
    variantPicks,
    giftTypeSplit,
    yesCount: yes.length,
    swipeCount: swipes.length,
  };
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

// ── Account deletion (App Store 5.1.1(v)) ────────────────────────────────────
// Query every row on one partition key and batch-delete it (25 at a time,
// paginated). Each table hands us the attribute names that make up its key so
// we can rebuild the exact Key for the delete request.
async function purgeByPartition(table, pkName, pkValue, keyAttrs) {
  if (!table || !pkValue) return 0;
  let deleted = 0;
  let lastKey;
  try {
    do {
      const out = await ddb.send(
        new QueryCommand({
          TableName: table,
          KeyConditionExpression: "#pk = :v",
          ExpressionAttributeNames: { "#pk": pkName },
          ExpressionAttributeValues: { ":v": pkValue },
          ExclusiveStartKey: lastKey,
        })
      );
      const items = out.Items ?? [];
      for (let i = 0; i < items.length; i += 25) {
        const chunk = items.slice(i, i + 25);
        const requests = chunk.map((it) => {
          const Key = {};
          for (const attr of keyAttrs) Key[attr] = it[attr];
          return { DeleteRequest: { Key } };
        });
        if (requests.length) {
          await ddb.send(new BatchWriteCommand({ RequestItems: { [table]: requests } }));
          deleted += requests.length;
        }
      }
      lastKey = out.LastEvaluatedKey;
    } while (lastKey);
  } catch (e) {
    console.warn(`purge ${table} failed:`, e.message);
  }
  return deleted;
}

// POOLS is keyed by poolId, so the user's rows there (their MEMBER#, CONTRIB#
// and MSG# items) are found with a filtered scan. META rows the user organized
// are the group's shared record — other members still need the pool — so they
// are kept but stripped of the organizer's identity instead of deleted.
async function purgePoolRows(userId) {
  if (!POOLS || !userId) return 0;
  let cleared = 0;
  let lastKey;
  try {
    do {
      const out = await ddb.send(
        new ScanCommand({
          TableName: POOLS,
          FilterExpression: "userId = :u OR memberId = :u OR organizerId = :u",
          ExpressionAttributeValues: { ":u": userId },
          ExclusiveStartKey: lastKey,
        })
      );
      for (const it of out.Items ?? []) {
        if (it.itemId === "META") {
          await ddb.send(
            new UpdateCommand({
              TableName: POOLS,
              Key: { poolId: it.poolId, itemId: "META" },
              UpdateExpression: "SET organizerId = :d, organizerName = :n",
              ExpressionAttributeValues: { ":d": "deleted", ":n": "a former member" },
            })
          );
        } else {
          await ddb.send(
            new DeleteCommand({ TableName: POOLS, Key: { poolId: it.poolId, itemId: it.itemId } })
          );
        }
        cleared++;
      }
      lastKey = out.LastEvaluatedKey;
    } while (lastKey);
  } catch (e) {
    console.warn("purge POOLS failed:", e.message);
  }
  return cleared;
}

// CHALLENGES partitions belong to the sender who created them. Find the META
// rows this user owns and purge each challenge wholesale — deck items and the
// guests' RESP# rows included, since those responses exist only for the sender.
async function purgeOwnedChallenges(userId) {
  if (!CHALLENGES || !userId) return 0;
  let deleted = 0;
  let lastKey;
  try {
    do {
      const out = await ddb.send(
        new ScanCommand({
          TableName: CHALLENGES,
          FilterExpression: "itemId = :m AND senderId = :u",
          ExpressionAttributeValues: { ":m": "META", ":u": userId },
          ProjectionExpression: "challengeId",
          ExclusiveStartKey: lastKey,
        })
      );
      for (const it of out.Items ?? []) {
        deleted += await purgeByPartition(CHALLENGES, "challengeId", it.challengeId, [
          "challengeId",
          "itemId",
        ]);
      }
      lastKey = out.LastEvaluatedKey;
    } while (lastKey);
  } catch (e) {
    console.warn("purge CHALLENGES failed:", e.message);
  }
  return deleted;
}

// Sign-in writes `email#<addr>` alias rows pointing at the canonical user id
// (see resolveCanonicalUserId). Left behind, they would re-link a future
// sign-in with the deleted account's email, so clear every alias it owns.
async function purgeEmailAliases(userId) {
  if (!USERS || !userId) return 0;
  let deleted = 0;
  let lastKey;
  try {
    do {
      const out = await ddb.send(
        new ScanCommand({
          TableName: USERS,
          FilterExpression: "#a = :t AND canonicalUserId = :u",
          ExpressionAttributeNames: { "#a": "alias" },
          ExpressionAttributeValues: { ":t": true, ":u": userId },
          ProjectionExpression: "userId",
          ExclusiveStartKey: lastKey,
        })
      );
      for (const it of out.Items ?? []) {
        await ddb.send(new DeleteCommand({ TableName: USERS, Key: { userId: it.userId } }));
        deleted++;
      }
      lastKey = out.LastEvaluatedKey;
    } while (lastKey);
  } catch (e) {
    console.warn("purge email aliases failed:", e.message);
  }
  return deleted;
}

// Irreversibly delete everything we hold for a user: their profile (and its
// email# alias rows), every interaction, the soft profiles (connections) they
// own, their events, their graph rows (incl. Maxi memory + photo seeds), their
// friend edges and DMs, their analytics history, their push-device tokens,
// their group-gift rows, and the swipe challenges they created. Tables keyed
// by the user id (or `pk`) use a per-partition query + batch delete; POOLS,
// CHALLENGES and the alias rows key by other ids, so those go through a
// filtered scan (see the helpers above). The privacy policy promises exactly
// this scope — extend both together.
async function purgeAccount(userId) {
  const summary = {
    profile: 0,
    aliases: 0,
    interactions: 0,
    connections: 0,
    events: 0,
    graph: 0,
    friends: 0,
    analytics: 0,
    devices: 0,
    pools: 0,
    challenges: 0,
    ugcPosts: 0,
    avatarObjects: 0,
  };
  // Clear the alias rows before the profile: the scan matches on
  // canonicalUserId, which does not depend on the profile item existing.
  summary.aliases = await purgeEmailAliases(userId);
  summary.avatarObjects = await purgeUserAvatar(userId);
  if (USERS) {
    try {
      await ddb.send(new DeleteCommand({ TableName: USERS, Key: { userId } }));
      summary.profile = 1;
    } catch (e) {
      console.warn("purge USERS failed:", e.message);
    }
  }
  summary.interactions = await purgeByPartition(INTERACTIONS, "userId", userId, ["userId", "targetId"]);
  summary.connections = await purgeByPartition(CONNECTIONS, "userId", userId, ["userId", "connectionId"]);
  summary.events = await purgeByPartition(EVENTS, "userId", userId, ["userId", "eventId"]);
  summary.graph = await purgeByPartition(GRAPH, "pk", userId, ["pk", "sk"]);
  summary.friends = await purgeByPartition(FRIENDS, "pk", userId, ["pk", "sk"]);
  summary.analytics = await purgeByPartition(ANALYTICS, "userId", userId, ["userId", "sk"]);
  summary.devices = await purgeByPartition(DEVICES, "userId", userId, ["userId", "deviceId"]);
  summary.pools = await purgePoolRows(userId);
  summary.challenges = await purgeOwnedChallenges(userId);
  summary.ugcPosts = await purgeUserUGC(userId);
  return summary;
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
    if (method === "POST" && path === "/login") return await loginRoute(event, body);

    // User-generated media is always identity-bound, even while the broader
    // AUTH_ENFORCE migration flag is off. Raw uploads remain private until the
    // separate Rekognition workers mark the post safe.
    if (path === "/ugc" || path.startsWith("/ugc/")) {
      const ugcAuth = auth?.ok ? auth : await authorizeRequest(event, method, path);
      if (!ugcAuth?.ok) return json(401, { error: "sign in required" });
      return await ugcRoutes(method, path, body, qs, ugcAuth);
    }

    // Mobile behavioral analytics (POST ingest is public; GET summary rides
    // the auth gate above like every other protected route).
    if (path.startsWith("/mobile/analytics")) {
      return await analyticsRoutes(method, path, body);
    }

    // Mobile app routes: APNs device registration (public — see isPublicRoute),
    // delta sync, and offline interaction batch upload. Without this dispatch the
    // routes 404'd, so no device could ever register a push token.
    if (
      path === "/mobile/device" ||
      path === "/mobile/sync" ||
      path === "/mobile/interactions/batch"
    ) {
      return await mobileRoutes(method, path, body, qs);
    }

    // Friends / people discovery / 1:1 DMs / circle account claim.
    {
      // /people/{id} is public, so the auth gate above never ran — but a
      // signed-in viewer's identity is what unlocks a private profile they're
      // friends with. Best-effort parse: a bad/absent token just stays public.
      let friendsAuth = auth;
      if (!friendsAuth?.ok && bearerToken(event)) {
        try {
          const attempt = await authorizeRequest(event, method, path);
          if (attempt?.ok) friendsAuth = attempt;
        } catch {}
      }
      const friendsRes = await friendsRoutes(method, path, body, qs, friendsAuth);
      if (friendsRes) return friendsRes;
    }

    // POST /auth/session — provider ID token (bearer) → 30-day session JWT
    // with the canonical (email-merged) user id. See the sessions block above.
    if (method === "POST" && path === "/auth/session") {
      if (!SESSION_JWT_SECRET) return json(503, { error: "sessions not configured" });
      const providerToken = bearerToken(event);
      if (!providerToken) return json(401, { error: "provider token required as bearer" });
      const identity = await verifyProviderToken(providerToken);
      if (!identity) return json(401, { error: "invalid provider token" });
      const userId = await resolveCanonicalUserId(identity.providerId, identity.email);
      const name = typeof body.name === "string" && body.name.trim() ? body.name.trim().slice(0, 80) : identity.name;
      // Keep the users row warm without wiping a profile photo on every login.
      try {
        const existing = await ddb.send(new GetCommand({ TableName: USERS, Key: { userId } }));
        await ddb.send(
          new UpdateCommand({
            TableName: USERS,
            Key: { userId },
            UpdateExpression: "SET #id = :id, lastSeenAt = :now, createdAt = if_not_exists(createdAt, :now)",
            ExpressionAttributeNames: { "#id": "identity" },
            ExpressionAttributeValues: {
              ":id": {
                ...(existing.Item?.identity ?? {}),
                email: identity.email ?? existing.Item?.identity?.email ?? null,
                name: name ?? existing.Item?.identity?.name ?? null,
              },
              ":now": Date.now(),
            },
          })
        );
      } catch (err) {
        console.warn("session identity upsert failed:", err.message);
      }
      const token = await signSessionJwt(userId, identity.email, name);
      return json(200, { token, userId, email: identity.email, expiresIn: SESSION_TTL_SECONDS });
    }

    // GET /birthday-freebies?category= — curated "free on your birthday" perks
    // (Sephora/Starbucks/Denny's...). Static in-code dataset, cacheable hard.
    if (method === "GET" && path === "/birthday-freebies") {
      return json(200, birthdayFreebiesRoute(qs), { "cache-control": "public, max-age=86400" });
    }

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
      const exclude = await userExclusions(qs.userId);

      // Sharded feed path (FEED_SHARDS > 1): the byFeed partition is split across
      // "all#<n>", so scatter-gather a recency window across every shard (filters
      // pushed down per shard), then rank + paginate by offset. Variety = a random
      // offset on a fresh, unfiltered load. The single-partition path below runs
      // unchanged when FEED_SHARDS == 1; on a sharded error we drop to the scan.
      if (FEED_SHARDS > 1) {
        try {
          const filters = [];
          const baseEav = {};
          // recipient intentionally NOT a filter — soft-ranked in scorePost().
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
            if (!p.postId || seen.has(p.postId) || exclude.posts.has(p.postId) || exclude.authors.has(p.ownerId)) continue;
            seen.add(p.postId);
            const q = feedClassification(p);
            if (!q.feedEligible) continue;
            ranked.push({ ...p, contentType: q.contentType, qualityScore: q.qualityScore, feedEligible: true, _score: scorePost(p, opts) + q.qualityScore * 0.4 });
          }
          ranked.sort((a, b) => b._score - a._score);
          const mixed = interleaveUGC(interleaveAuthors(ranked));
          let offset = start?._offset ?? 0;
          const personalized = qs.recipient && qs.recipient !== "anyone";
          if (!start && !filters.length && !personalized && qs.fresh !== "0" && ranked.length > limit) {
            offset = Math.floor(Math.random() * Math.max(1, ranked.length - limit));
          }
          const page = mixed.slice(offset, offset + limit);
          const nextOffset = offset + limit;
          return json(200, { items: page, cursor: nextOffset < mixed.length ? encodeCursor({ _offset: nextOffset }) : null });
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
        // recipient intentionally NOT a filter — soft-ranked in scorePost().
        if (qs.occasion && qs.occasion !== "any") { filters.push("occasion = :o"); eav[":o"] = qs.occasion; }
        if (qs.category) { filters.push("category = :c"); eav[":c"] = qs.category; }
        // Over-read: the quality + de-dup filters below remove listicles/guides
        // (~37%) and already-seen items, so fetch a wider window than the page.
        const fetchN = filters.length ? 150 : Math.min(Math.max(limit * 4, 80), 150);
        // Variety: on a fresh (uncursored, unfiltered) load, jump to RANDOM
        // spots in the catalog instead of always the newest head. Posts
        // adjacent in createdAt are the SAME ingest batch (one store's whole
        // inventory), so a single seek lands the entire candidate window in a
        // monoculture — 20/20 beauty pages verified live. Three independent
        // seeks sample three batches; the merged pool gives the category/brand
        // interleave something to actually space. Paginated loads (cursor
        // present) continue deterministically from one stream.
        let kce = "feedPk = :f";
        let seekPoints = [];
        if (!start && !filters.length && qs.fresh !== "0" && !(qs.recipient && qs.recipient !== "anyone")) {
          const b = await getFeedBounds();
          if (b.max > b.min) {
            // STRATIFIED: one seek per third of the createdAt range. Purely
            // random seeks can all land inside one mega-batch (Fashion Nova
            // alone is 262 adjacent rows) and reproduce the monoculture page.
            const span = b.max - b.min;
            seekPoints = [0, 1, 2].map(
              (i) => b.min + Math.floor(((i + 0.2 + Math.random() * 0.8) / 3) * span)
            );
          }
        }
        const runQuery = (keyCond, startKey, vals = eav, limitOverride) =>
          ddb.send(
            new QueryCommand({
              TableName: POSTS,
              IndexName: "byFeed",
              KeyConditionExpression: keyCond,
              ExpressionAttributeValues: vals,
              FilterExpression: filters.length ? filters.join(" AND ") : undefined,
              ScanIndexForward: false, // newest first
              Limit: limitOverride ?? fetchN,
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
            if (picked.has(p.postId) || exclude.posts.has(p.postId) || exclude.authors.has(p.ownerId)) continue;
            const q = feedClassification(p);
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
        // Fresh variety load: three parallel windows at independent seek
        // points, merged before ranking (see the seekPoints comment above).
        if (seekPoints.length) {
          const windows = await Promise.all(
            seekPoints.map((seek) =>
              runQuery(
                "feedPk = :f AND createdAt <= :seek",
                undefined,
                { ...eav, ":seek": seek },
                Math.ceil(fetchN / 2)
              )
            )
          );
          for (const out of windows) take(out.Items);
          lastKey = windows[windows.length - 1]?.LastEvaluatedKey;
        }
        for (let attempt = 0; attempt < 6 && eligible.length < limit; attempt++) {
          const out = await runQuery(kce, lastKey);
          take(out.Items);
          lastKey = out.LastEvaluatedKey;
          if (eligible.length >= limit) break;
          if (!start && !toppedUp) {
            toppedUp = true;
            lastKey = undefined;  // jump to the newest (product-dense) head
            continue;
          }
          if (!lastKey) break;    // reached the end of the range
        }
        eligible.sort((a, b) => b._score - a._score);
        return json(200, { items: interleaveUGC(interleaveAuthors(eligible)).slice(0, limit), cursor: encodeCursor(lastKey) });
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
        .map((p) => ({ p, q: feedClassification(p) }))
        .filter((x) => x.q.feedEligible && !exclude.posts.has(x.p.postId) && !exclude.authors.has(x.p.ownerId))
        .map(({ p, q }) => ({ ...p, contentType: q.contentType, qualityScore: q.qualityScore, _score: scorePost(p, opts) + q.qualityScore * 0.4 }))
        .sort((a, b) => b._score - a._score);
      const rankedMixed = interleaveUGC(interleaveAuthors(ranked));
      const offset = start?._offset ?? 0;
      const page = rankedMixed.slice(offset, offset + limit);
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

    // GET /galleries/{id} — a curated gift gallery's REAL member items.
    // Membership is precomputed by infra/ingest/build-shelves.mjs (Titan
    // text-embed of the shelf theme → kNN → quality/price/brand filters) into
    // a CONFIG gallery#<id> row; here we just hydrate the posts. 404 lets the
    // client fall back to its legacy query-by-vibes path.
    if (method === "GET" && /^\/galleries\/[^/]+$/.test(path)) {
      const id = decodeURIComponent(path.split("/")[2]);
      const row = await ddb.send(new GetCommand({ TableName: CONFIG, Key: { key: `gallery#${id}` } }));
      if (!row.Item?.itemIds?.length) return json(404, { error: "no curated list for that gallery" });
      const items = await hydratePosts(row.Item.itemIds, Math.min(Number(qs.limit) || 60, 100));
      return json(200, { id, title: row.Item.title, items }, { "cache-control": "public, max-age=3600" });
    }

    // GET /bundles?recipient=mom&limit= — Reddit-mined "goes together" gift
    // bundles resolved to buyable products (build-shelves.mjs). Without a
    // recipient, serves a sampler across all mined recipients.
    if (method === "GET" && path === "/bundles") {
      const limit = Math.min(Number(qs.limit) || 6, 12);
      let recipients = qs.recipient ? [String(qs.recipient).toLowerCase()] : null;
      if (!recipients) {
        const idx = await ddb.send(new GetCommand({ TableName: CONFIG, Key: { key: "bundles#index" } }));
        recipients = idx.Item?.recipients ?? [];
      }
      // Round-robin across recipients (one bundle each, then seconds…) so the
      // sampler rail reads "for mom / for a friend / for him", not three
      // bundles for whichever recipient sorts first in the index.
      const rows = await Promise.all(
        recipients.map((r) =>
          ddb.send(new GetCommand({ TableName: CONFIG, Key: { key: `bundles#${r}` } }))
            .then((o) => ({ r, list: o.Item?.bundles ?? [] }))
        )
      );
      const queue = [];
      for (let round = 0; queue.length < limit; round++) {
        const before = queue.length;
        for (const { r, list } of rows) {
          if (queue.length >= limit) break;
          if (list[round]) queue.push({ recipient: r, ...list[round] });
        }
        if (queue.length === before) break; // all lists exhausted
      }
      const bundles = [];
      for (const b of queue) {
        const slots = [];
        for (const s of b.slots ?? []) {
          const items = await hydratePosts(s.itemIds ?? [], 4);
          if (items.length) slots.push({ key: s.key, label: s.label, emoji: s.emoji, items });
        }
        if (slots.length >= 2) bundles.push({ recipient: b.recipient, why: b.why, slots });
      }
      return json(200, { bundles }, { "cache-control": "public, max-age=3600" });
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
    // Results beyond VISUAL_SEARCH_MAX_DISTANCE are dropped: kNN always returns
    // the K nearest vectors even when nothing in the catalog resembles the query
    // (a couch photo "matching" jeans), so an explicit relevance gate is the
    // difference between "no close matches" and confidently wrong results.
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
      // Among near-equal visual matches, float major US retailers (Amazon /
      // Target / Walmart…) above niche shops — a match the shopper can
      // actually buy beats an aesthetic twin on a boutique domain.
      const rankDistance = (it) =>
        (it._distance ?? 1) - (isMajorUSRetailer(it.domain) ? 0.05 : 0);
      const items = (out.vectors ?? [])
        .map(vecToItem)
        .filter(
          (it) =>
            it.feedEligible && (it._distance == null || it._distance <= VISUAL_SEARCH_MAX_DISTANCE)
        )
        .sort((a, b) => rankDistance(a) - rankDistance(b))
        .slice(0, limit);

      // A photo someone searches is one of the strongest taste/intent signals
      // we ever see — don't discard its embedding (research doc gap G3).
      // (1) Return it packed (int8, ~1.4 KB — same scheme as GET /vectors) so
      //     the client can fold it into its on-device centroid math.
      // (2) When the caller identifies itself, persist a photoseed node in its
      //     graph; recipientRef ties the seed to the person the photo is FOR
      //     (e.g. a screenshot of something the recipient posted).
      const packed = packVector(queryVector);
      const seedOwner = String(body.userId || body.anonId || "").slice(0, 80);
      if (seedOwner) {
        const recipientRef = body.recipientRef ? String(body.recipientRef).slice(0, 80) : undefined;
        await graphWrite([
          gNode(seedOwner, "photoseed", gid(), {
            scope: recipientRef ? "shared" : "personal",
            label: body.text ? String(body.text).slice(0, 120) : "photo search",
            data: {
              vec: packed,
              intent: body.intent ? String(body.intent).slice(0, 24) : "search",
              ...(recipientRef ? { recipientRef } : {}),
              topMatch: items[0]?.postId ?? null,
            },
          }),
        ]);
      }
      return json(200, { items, source: "visual", queryVector: packed });
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
      // Optional per-event context: {mode:"gift", recipientRef, giftType,
      // decisionMs, amount, …} — the mode tag keeps gift-mode browsing out of
      // the browser's own taste when per-recipient objects land (gap G2).
      // Bounded so a hostile client can't stuff megabytes into a row.
      const boundedData = (d) => {
        if (!d || typeof d !== "object" || Array.isArray(d)) return undefined;
        try {
          return JSON.stringify(d).length <= 1024 ? d : undefined;
        } catch {
          return undefined;
        }
      };
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
          const data = boundedData(it.data);
          rows.push({
            userId,
            targetId: sk,
            type,
            target: targetId,
            createdAt: Number(it.createdAt) || Date.now(),
            ...(data ? { data } : {}),
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
      const bounded = boundedData(data);
      if (bounded) item.data = bounded;
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
      // ?giftTypes=product | service | product,service — restrict to one gift
      // type ("only show me services"). Omitted or both -> the default blend.
      const giftTypes = parseList(qs.giftTypes).filter((t) => t === "product" || t === "service");
      const giftTypeOk = (it) =>
        giftTypes.length !== 1 || giftTypes.includes(it.giftType === "service" ? "service" : "product");

      // Vector path: taste = centroid of the user's seed pins -> kNN in S3 Vectors.
      // Seeds come from ?seedKeys=pin-a,pin-b or from the user's interactions.
      const seedKeys = parseList(qs.seedKeys);
      const seeds = seedKeys.length ? seedKeys : [...likedTargets];
      if (s3v && seeds.length && (await aiEnabled())) {
        try {
          // Interaction model: default = fast front-end path (cosine order,
          // instant). ?rank=full = intelligent back-end path — the client
          // calls it AFTER first paint and re-ranks in place when it lands.
          const vitems = await vectorRecommend(seeds, {
            limit,
            sourceUser: qs.sourceUser,
            rank: qs.rank === "full" ? "full" : "fast",
            context: { relationship: qs.relationship, occasion: qs.occasion },
          });
          if (vitems && vitems.length) {
            return json(200, {
              items: interleaveAuthors(vitems.filter(giftTypeOk)),
              cursor: null,
              source: vitems.some((it) => it.mtl) ? "vector+mtl" : "vector",
            });
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
      const items = interleaveAuthors(
        (out.Items ?? [])
          .filter((p) => !likedTargets.has(p.postId) && p.author !== userId)
          .filter(giftTypeOk)
          .map((p) => ({ p, q: feedClassification(p) }))
          .filter((x) => x.q.feedEligible)
          .map(({ p, q }) => ({ ...p, contentType: q.contentType, qualityScore: q.qualityScore, _score: scorePost(p, opts) + q.qualityScore * 0.4 }))
          .sort((a, b) => b._score - a._score)
      ).slice(0, limit);

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
      // Clients update independent profile panels (taste, visibility, account)
      // at different times. Merge their patch so changing visibility cannot
      // erase recipients, events, or taste signals saved elsewhere.
      const existing = await ddb.send(new GetCommand({ TableName: USERS, Key: { userId } }));
      const item = { ...(existing.Item ?? {}), ...profile, userId, updatedAt: Date.now() };
      await ddb.send(new PutCommand({ TableName: USERS, Item: item }));
      // Fan out into the events table + network graph so nothing is missed.
      await captureProfile(userId, profile);
      return json(200, { ok: true, item });
    }

    // DELETE /account?userId=   (or body { userId })  — App Store 5.1.1(v).
    // A signed-in user permanently deletes their account and all the data we
    // hold for them. Irreversible, self-service (no support ticket). Auth-gated
    // like GET/PUT /me: a valid session/provider token must be present, and we
    // delete exactly the userId the caller owns.
    if (method === "DELETE" && path === "/account") {
      const userId = String(qs.userId || body.userId || "").trim();
      if (!userId) return json(400, { error: "userId required" });
      const deleted = await purgeAccount(userId);
      return json(200, { ok: true, deleted });
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
      // Web mints "anon_…" (lib/anon.ts); the iOS InteractionQueue mints
      // "anon-…". Both are claimable — rejecting the dash variant stranded
      // every app-side guest taste profile at signup.
      if (!anonId.startsWith("anon_") && !anonId.startsWith("anon-")) {
        return json(400, { error: "invalid anonId" });
      }
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
      // Also re-key challenges created under the anon id (bySender GSI returns
      // META rows only — they alone carry senderId), so verdicts collected while
      // signed out appear the moment the sender signs in.
      let claimedChallenges = 0;
      if (CHALLENGES) {
        const ch = await ddb.send(
          new QueryCommand({
            TableName: CHALLENGES,
            IndexName: "bySender",
            KeyConditionExpression: "senderId = :s",
            ExpressionAttributeValues: { ":s": anonId },
          })
        );
        for (const row of ch.Items ?? []) {
          await ddb.send(
            new UpdateCommand({
              TableName: CHALLENGES,
              Key: { challengeId: row.challengeId, itemId: "META" },
              UpdateExpression: "SET senderId = :u",
              ExpressionAttributeValues: { ":u": claimUserId },
            })
          );
          claimedChallenges++;
        }
      }
      return json(200, { ok: true, claimed, claimedChallenges });
    }

    // ── Product-seeded swipe challenges ─────────────────────────────────────
    // The funnel: sender shares a product (or an image, e.g. from Instagram) →
    // we build a swipe deck of similar catalog items around it → the friend
    // swipes as a guest → we score their swipes against the seed and tell the
    // sender "they'd love/like/pass on this" without the friend ever knowing
    // which card was the ask.

    // POST /challenges  { senderId, seed: { imageBase64? | postId? | seedKeys? ,
    //   text? }, to?, occasion?, date?, note?, inviterName?, deckSize? }
    // Resolves the seed to a vector, builds the deck, stores the META item.
    if (method === "POST" && path === "/challenges") {
      if (!CHALLENGES) return json(503, { error: "challenges not configured" });
      const senderId = String(body.senderId || "").slice(0, 80);
      if (!senderId) return json(400, { error: "senderId required" });
      if (!s3v || !(await aiEnabled())) {
        return json(503, { error: "temporarily disabled (cost guard)" });
      }
      const seed = body.seed ?? {};
      const deckSize = Math.max(6, Math.min(Number(body.deckSize) || CHALLENGE_DECK_SIZE, 24));
      // "exact" decks (shared swipe lists): the guest swipes EXACTLY the items
      // the sender curated — no lookalike padding, no hidden seed card, no
      // service probes. Their yes/no per card IS the deliverable.
      const exactDeck = body.deckMode === "exact";

      // Resolve the seed vector: an uploaded image (share-extension flow), one
      // catalog pin, or a set of taste keys (centroid).
      let seedVector = null;
      let seedInfo = null;
      let seedCard = null; // the seed itself, slipped into the deck when it's a catalog pin
      let exclude = [];
      let seedVecsByKey = new Map(); // exact decks reuse the fetched vectors as cards
      try {
        if (seed.imageBase64) {
          seedVector = await embedImage(seed.imageBase64, seed.text);
          seedInfo = { kind: "image", text: seed.text ? String(seed.text).slice(0, 200) : null };
        } else if (seed.postId || (Array.isArray(seed.seedKeys) && seed.seedKeys.length)) {
          const keys = seed.postId
            ? [String(seed.postId)]
            : seed.seedKeys.slice(0, exactDeck ? 40 : 8).map(String);
          exclude = keys;
          const vecs = await getVectorsByKeys(keys);
          seedVecsByKey = vecs;
          if (vecs.size) {
            const dim = vecs.values().next().value.data.float32.length;
            const c = new Array(dim).fill(0);
            for (const v of vecs.values()) for (let i = 0; i < dim; i++) c[i] += v.data.float32[i];
            for (let i = 0; i < dim; i++) c[i] /= vecs.size;
            seedVector = c;
            const first = seed.postId ? vecs.get(String(seed.postId)) : null;
            seedInfo = {
              kind: exactDeck ? "list" : seed.postId ? "post" : "keys",
              keys,
              title: first?.metadata?.title || null,
              image: first?.metadata?.imageUrl || null,
            };
            // A pin-seeded challenge hides the seed card IN the deck: a direct
            // swipe on it is the strongest possible signal for the sender.
            if (first && !exactDeck) seedCard = deckSnapshot(vecToItem(first), "seed");
          }
        }
      } catch (e) {
        console.warn("challenge seed resolve failed:", e.message);
      }

      let deck;
      if (exactDeck) {
        // Card sources, in preference order: the vector index (rich metadata),
        // then client-supplied snapshots — swipe lists can hold catalog/feed
        // items that were never embedded, and those must not silently vanish
        // from the deck the recipient sees.
        const sanitizeUrl = (u) =>
          typeof u === "string" && /^https?:\/\//i.test(u) ? u.slice(0, 500) : null;
        const clientCards = new Map();
        for (const c of Array.isArray(body.cards) ? body.cards.slice(0, 40) : []) {
          const id = String(c?.postId || "").slice(0, 120);
          if (!id) continue;
          const price = Number(c.price) || 0;
          clientCards.set(id, {
            postId: id,
            name: String(c.name || "").slice(0, 200),
            image: sanitizeUrl(c.image),
            price,
            priceDisplay: price > 0 ? `$${price}` : null,
            category: String(c.category || "").slice(0, 40),
            domain: String(c.domain || "").slice(0, 120),
            url: sanitizeUrl(c.url) ?? "",
            giftType: c.giftType === "service" ? "service" : "product",
            ...(c.serviceDuration ? { serviceDuration: String(c.serviceDuration).slice(0, 40) } : {}),
            // "list" (not "seed"): every card is the ask, so no single card may
            // trigger the directSeedSwipe verdict override.
            band: "list",
          });
        }
        const keys = exclude.length ? exclude : [...clientCards.keys()];
        deck = keys
          .map((k) => {
            const v = seedVecsByKey.get(k);
            if (v) {
              const snap = deckSnapshot(vecToItem(v), "list");
              // The vector item never carries a price of its own for catalog
              // posts — let a client snapshot fill gaps, not overwrite.
              const c = clientCards.get(k);
              if (c) {
                if (!snap.name && c.name) snap.name = c.name;
                if (!snap.image && c.image) snap.image = c.image;
                if (!snap.price && c.price) {
                  snap.price = c.price;
                  snap.priceDisplay = c.priceDisplay;
                }
                if (!snap.url && c.url) snap.url = c.url;
              }
              return snap;
            }
            return clientCards.get(k) ?? null;
          })
          .filter(Boolean)
          .slice(0, 40);
        if (deck.length < 2) {
          return json(422, { error: "exact deck needs at least 2 resolvable items" });
        }
        if (!seedInfo) seedInfo = { kind: "list", keys: deck.map((d) => d.postId) };
      } else {
        if (!seedVector) {
          return json(400, { error: "seed required: imageBase64, postId, or seedKeys" });
        }
        deck = await buildChallengeDeck(seedVector, {
          size: seedCard ? deckSize - 1 : deckSize,
          excludeKeys: exclude,
        });
        if (seedCard) deck.splice(Math.floor(Math.random() * (deck.length + 1)), 0, seedCard);
        if (deck.length < 4) return json(422, { error: "not enough similar catalog items" });
      }

      const challengeId = `chal_${gid()}`;
      const meta = {
        challengeId,
        itemId: "META",
        senderId,
        createdAt: Date.now(),
        inviterName: body.inviterName ? String(body.inviterName).slice(0, 80) : undefined,
        to: body.to ? String(body.to).slice(0, 80) : undefined,
        occasion: body.occasion ? String(body.occasion).slice(0, 40) : undefined,
        date:
          typeof body.date === "string" && /^\d{4}-\d{2}-\d{2}$/.test(body.date)
            ? body.date
            : undefined,
        note: body.note ? String(body.note).slice(0, 280) : undefined,
        // "group" = friends collaborate on a gift for a third party: every
        // response is shared state (public tally on GET) instead of a private
        // know-me verdict for the sender.
        // "verify" = the concierge double-check: the sender already has a pick
        // (the hidden seed card) and only needs "did they swipe right on it?" —
        // so an aggregate match summary is public to link holders, letting
        // anonymous senders (web consult, no account) read the answer back.
        mode: body.mode === "group" ? "group" : body.mode === "verify" ? "verify" : undefined,
        deckMode: exactDeck ? "exact" : undefined,
        seed: seedInfo,
        // Exact decks may resolve zero index vectors (all-client cards) — the
        // response route already falls back to the facet verdict when seedVec
        // is absent.
        seedVec: seedVector ? packVector(seedVector) : undefined,
        deck,
        responseCount: 0,
      };
      await ddb.send(new PutCommand({ TableName: CHALLENGES, Item: meta }));
      // The sender gets the full deck (bands included) for their own preview.
      return json(200, { ok: true, challengeId, seed: seedInfo, deck });
    }

    // GET /challenges/{id} — the guest's deck (public; sender internals
    // stripped). If the caller authenticates as the SENDER (or admin), the
    // seed, banded deck, and all responses+verdicts ride along.
    if (method === "GET" && /^\/challenges\/[^/]+$/.test(path)) {
      if (!CHALLENGES) return json(503, { error: "challenges not configured" });
      const challengeId = decodeURIComponent(path.split("/")[2] ?? "");
      const out = await ddb.send(
        new GetCommand({ TableName: CHALLENGES, Key: { challengeId, itemId: "META" } })
      );
      const meta = out.Item;
      if (!meta) return json(404, { error: "not found" });
      const base = {
        challengeId,
        inviterName: meta.inviterName ?? null,
        to: meta.to ?? null,
        occasion: meta.occasion ?? null,
        date: meta.date ?? null,
        note: meta.note ?? null,
        mode: meta.mode ?? null,
        createdAt: meta.createdAt,
        responseCount: meta.responseCount ?? 0,
        // Guests must not see which card is the ask: strip band + distance.
        deck: (meta.deck ?? []).map(({ band, distance, ...it }) => it),
      };
      // Group gifting: the tally is the shared prize board — every holder of
      // the link (creator + friends) sees which cards are winning and who
      // voted. There is no hidden seed verdict to protect in this mode.
      if (meta.mode === "group") {
        const resp = await ddb.send(
          new QueryCommand({
            TableName: CHALLENGES,
            KeyConditionExpression: "challengeId = :c AND begins_with(itemId, :r)",
            ExpressionAttributeValues: { ":c": challengeId, ":r": "RESP#" },
          })
        );
        const tally = new Map();
        const responders = [];
        for (const row of resp.Items ?? []) {
          if (row.guestName && !responders.includes(row.guestName)) responders.push(row.guestName);
          for (const s of row.swipes ?? []) {
            if (s.dir !== "yes") continue;
            const t = tally.get(s.id) ?? { yes: 0, guests: [] };
            t.yes += 1;
            if (row.guestName && !t.guests.includes(row.guestName) && t.guests.length < 8) {
              t.guests.push(row.guestName);
            }
            tally.set(s.id, t);
          }
        }
        base.responders = responders.slice(0, 24);
        base.groupPicks = (meta.deck ?? [])
          .filter((it) => tally.has(it.postId))
          .map(({ band, distance, ...it }) => ({
            ...it,
            yes: tally.get(it.postId).yes,
            guests: tally.get(it.postId).guests,
          }))
          .sort((a, b) => b.yes - a.yes)
          .slice(0, 24);
      }
      // Verify mode: expose ONLY the aggregate answer to the sender's real
      // question — "did they swipe right on my pick?" — never the per-card
      // swipes. The unguessable challengeId is the capability, exactly like
      // the group-mode tally above.
      if (meta.mode === "verify") {
        const resp = await ddb.send(
          new QueryCommand({
            TableName: CHALLENGES,
            KeyConditionExpression: "challengeId = :c AND begins_with(itemId, :r)",
            ExpressionAttributeValues: { ":c": challengeId, ":r": "RESP#" },
          })
        );
        let matched = false;
        let best = null;
        let by = null;
        for (const row of resp.Items ?? []) {
          const v = row.verdict;
          if (!v) continue;
          if (v.directSeedSwipe === "yes") {
            matched = true;
            by = row.guestName ?? by;
          }
          if (!best || (v.score ?? 0) > (best.score ?? 0)) best = v;
        }
        base.verify = {
          responses: (resp.Items ?? []).length,
          matched,
          by,
          label: best?.label ?? null,
          score: best?.score ?? null,
        };
      }
      const auth = await authorizeRequest(event, method, path);
      if (auth.ok && (auth.via === "admin" || auth.sub === meta.senderId)) {
        const resp = await ddb.send(
          new QueryCommand({
            TableName: CHALLENGES,
            KeyConditionExpression: "challengeId = :c AND begins_with(itemId, :r)",
            ExpressionAttributeValues: { ":c": challengeId, ":r": "RESP#" },
            ScanIndexForward: false,
          })
        );
        return json(200, {
          ...base,
          senderId: meta.senderId,
          seed: meta.seed,
          deckFull: meta.deck,
          responseCount: meta.responseCount ?? 0,
          responses: resp.Items ?? [],
        });
      }
      return json(200, base);
    }

    // POST /challenges/{id}/response  { guest:{ name?, handle?, birthday?,
    //   genderPref? }, swipes:[{ id, dir, dwellMs? }] }
    // Stores the response + verdict, mirrors a soft-profile connection so the
    // sender's existing Activity/Responses surfaces light up. The GUEST only
    // gets back their own taste summary — never the seed verdict.
    if (method === "POST" && /^\/challenges\/[^/]+\/response$/.test(path)) {
      if (!CHALLENGES) return json(503, { error: "challenges not configured" });
      const challengeId = decodeURIComponent(path.split("/")[2] ?? "");
      const out = await ddb.send(
        new GetCommand({ TableName: CHALLENGES, Key: { challengeId, itemId: "META" } })
      );
      const meta = out.Item;
      if (!meta) return json(404, { error: "not found" });

      const deckByKey = new Map((meta.deck ?? []).map((it) => [it.postId, it]));
      const swipes = (Array.isArray(body.swipes) ? body.swipes : [])
        .slice(0, 60)
        .map((s) => ({
          id: String(s.id || ""),
          dir: s.dir === "yes" ? "yes" : "no",
          dwellMs: Math.max(0, Number(s.dwellMs) || 0),
        }))
        .filter((s) => s.id && deckByKey.has(s.id));
      if (!swipes.length) return json(400, { error: "swipes (on deck items) required" });

      // Verdict: vector-scored when the index is up, facet fallback otherwise.
      let verdict = null;
      const seedVec = unpackVector(meta.seedVec);
      if (seedVec && s3v && (await aiEnabled())) {
        try {
          const vectorsByKey = await getVectorsByKeys(swipes.map((s) => s.id));
          verdict = computeChallengeVerdict({ seedVec, swipes, vectorsByKey, deckByKey });
        } catch (e) {
          console.warn("challenge verdict failed, falling back:", e.message);
        }
      }
      if (!verdict) {
        verdict = computeChallengeVerdict({
          seedVec: seedVec ?? [1],
          swipes,
          vectorsByKey: new Map(),
          deckByKey,
        });
      }

      const guest = body.guest ?? {};
      const guestName = String(guest.name || meta.to || "Friend").trim().slice(0, 80);
      const createdAt = Date.now();
      const respId = gid();
      await ddb.send(
        new PutCommand({
          TableName: CHALLENGES,
          Item: {
            challengeId,
            itemId: `RESP#${createdAt}#${respId}`,
            guestName,
            guestHandle: guest.handle ? String(guest.handle).slice(0, 40) : undefined,
            birthday:
              typeof guest.birthday === "string" && /^\d{4}-\d{2}-\d{2}$/.test(guest.birthday)
                ? guest.birthday
                : undefined,
            genderPref: guest.genderPref ? String(guest.genderPref).slice(0, 12) : undefined,
            swipes,
            verdict,
            createdAt,
          },
        })
      );
      await ddb.send(
        new UpdateCommand({
          TableName: CHALLENGES,
          Key: { challengeId, itemId: "META" },
          UpdateExpression: "ADD responseCount :one",
          ExpressionAttributeValues: { ":one": 1 },
        })
      );

      // Mirror a soft profile so the sender's existing surfaces (Activity,
      // ChallengeView responses, Maxi's list_connections) pick this up as-is.
      if (meta.senderId) {
        const item = {
          userId: meta.senderId,
          connectionId: `conn_${respId}`,
          soft: true,
          kind: "challenge",
          challengeId,
          guestName,
          birthday:
            typeof guest.birthday === "string" && /^\d{4}-\d{2}-\d{2}$/.test(guest.birthday)
              ? guest.birthday
              : undefined,
          genderPref: guest.genderPref ? String(guest.genderPref).slice(0, 12) : undefined,
          vibes: verdict.topCategories,
          seeds: swipes.filter((s) => s.dir === "yes").slice(0, 8).map((s) => s.id),
          giftTypeSplit: verdict.giftTypeSplit,
          yesCount: verdict.yesCount,
          totalSwipes: verdict.swipeCount,
          verdictScore: verdict.score,
          verdictLabel: verdict.label,
          seen: false,
          createdAt,
        };
        await ddb.send(new PutCommand({ TableName: CONNECTIONS, Item: item }));
        await captureConnection(item);
        await sendPushToUser(meta.senderId, {
          title: "Swipe challenge completed 🎁",
          body: `${guestName} swiped on your challenge — verdict: ${verdict.label}`,
          data: { type: "challenge_completed", connectionId: item.connectionId, challengeId },
        });
      }

      // The guest's swipes are THEIR taste, not only the sender's intel. When
      // the guest's browser/app supplies its anon id, persist a self-owned
      // taste row under it — /connections/claim re-keys it into their real
      // account on signup, so a challenge recipient converts with a warm
      // profile instead of a cold start (research doc §9.1, gap G1).
      const guestSeeds = swipes.filter((s) => s.dir === "yes").slice(0, 12).map((s) => s.id);
      const guestNegSeeds = swipes.filter((s) => s.dir === "no").slice(0, 12).map((s) => s.id);
      const anonId =
        typeof guest.anonId === "string" && /^anon[-_][A-Za-z0-9-]{4,64}$/.test(guest.anonId)
          ? guest.anonId
          : null;
      if (anonId && anonId !== meta.senderId) {
        try {
          await ddb.send(
            new PutCommand({
              TableName: CONNECTIONS,
              Item: {
                userId: anonId,
                connectionId: `self_${respId}`,
                soft: true,
                kind: "self-challenge",
                challengeId,
                guestName,
                vibes: verdict.topCategories,
                seeds: guestSeeds,
                negSeeds: guestNegSeeds,
                giftTypeSplit: verdict.giftTypeSplit,
                priceBand: verdict.priceBand ?? undefined,
                yesCount: verdict.yesCount,
                totalSwipes: verdict.swipeCount,
                seen: true, // it's their own — never a sender notification
                createdAt,
              },
            })
          );
          // Mirror into the guest's own subgraph so Maxi + /graph see the
          // swipe-derived taste the moment they sign up and claim the anon id.
          await graphWrite([
            gNode(anonId, "self", "taste", {
              scope: "personal",
              label: "swipe taste",
              data: {
                seeds: guestSeeds,
                negSeeds: guestNegSeeds,
                vibes: verdict.topCategories,
                giftTypeSplit: verdict.giftTypeSplit,
                priceBand: verdict.priceBand ?? null,
              },
            }),
            ...interestItems(anonId, "self", "taste", verdict.topCategories),
          ]);
        } catch (e) {
          console.warn("guest self-taste persist failed:", e.message);
        }
      }

      // The guest's reveal: their own taste only (plus their own yes-list as
      // warm-start seeds). No seed verdict — the ask stays invisible.
      return json(200, {
        ok: true,
        taste: {
          topCategories: verdict.topCategories,
          priceBand: verdict.priceBand,
          giftTypeSplit: verdict.giftTypeSplit,
          seeds: guestSeeds,
        },
      });
    }

    // GET /challenges?senderId= — the sender's challenges, newest first, with
    // response counts + latest verdict. Auth-gated by default-deny.
    if (method === "GET" && path === "/challenges") {
      if (!CHALLENGES) return json(503, { error: "challenges not configured" });
      const senderId = qs.senderId;
      if (!senderId) return json(400, { error: "senderId required" });
      const out = await ddb.send(
        new QueryCommand({
          TableName: CHALLENGES,
          IndexName: "bySender",
          KeyConditionExpression: "senderId = :s",
          ExpressionAttributeValues: { ":s": senderId },
          ScanIndexForward: false,
          Limit: 50,
        })
      );
      const items = await Promise.all(
        (out.Items ?? []).map(async (m) => {
          let latestVerdict = null;
          if ((m.responseCount ?? 0) > 0) {
            const r = await ddb.send(
              new QueryCommand({
                TableName: CHALLENGES,
                KeyConditionExpression: "challengeId = :c AND begins_with(itemId, :r)",
                ExpressionAttributeValues: { ":c": m.challengeId, ":r": "RESP#" },
                ScanIndexForward: false,
                Limit: 1,
              })
            );
            latestVerdict = r.Items?.[0]?.verdict ?? null;
          }
          return {
            challengeId: m.challengeId,
            to: m.to ?? null,
            occasion: m.occasion ?? null,
            date: m.date ?? null,
            seed: m.seed ?? null,
            deckSize: (m.deck ?? []).length,
            responseCount: m.responseCount ?? 0,
            createdAt: m.createdAt,
            latestVerdict,
          };
        })
      );
      return json(200, { items });
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
        // A pledge is real money behind a specific person + occasion — the
        // strongest dyad signal we collect. Mirror it into the pledger's
        // subgraph so recipient rosters/budget priors can read it later
        // (research doc gap G8). Best-effort like every graph write.
        await graphWrite([
          gNode(userId, "pool", poolId, {
            scope: "shared",
            label: meta.Item.title,
            data: {
              occasion: meta.Item.occasion ?? null,
              goal: Number(meta.Item.goal) || null,
            },
          }),
          gEdge(userId, "PLEDGED", "user", userId, "pool", poolId, { amount, at }),
        ]);
        if (meta.Item.organizerId && meta.Item.organizerId !== userId) {
          await sendPushToUser(meta.Item.organizerId, {
            title: "New pledge 💸",
            body: `${name} pledged $${amount} to “${meta.Item.title ?? "your gift pool"}”`,
            data: { type: "pool_contribution", poolId },
          });
        }
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

    // ── Gift circles — shared family/friend groups ────────────────────────
    // One person creates a circle ("Sharma Family"), shares the link, and
    // everyone adds their name + birthday. The circle page shows every
    // member's next birthday and any shared occasions, so nobody misses a
    // gift moment. Stored in the EVENTS table under one CIRCLE# partition:
    //   { userId: CIRCLE#<id>, eventId: "META" }            circle name etc.
    //   { userId: CIRCLE#<id>, eventId: "MEMBER#<mid>" }    name + birthday
    //   { userId: CIRCLE#<id>, eventId: "EVT#<ts>#<id>" }   shared occasion
    // The link is the credential (invite-link trust model): the id is
    // unguessable, and the recipient of a gift never needs to see it.

    // POST /circles  { name, creator: { name, birthday? } }
    if (method === "POST" && path === "/circles") {
      if (!EVENTS) return json(503, { error: "events table not configured" });
      const name = String(body.name ?? "").trim().slice(0, 60);
      if (!name) return json(400, { error: "name required" });
      const circleId = `cir_${gid()}`;
      const pk = `CIRCLE#${circleId}`;
      const now = Date.now();
      const emoji = String(body.emoji ?? "").slice(0, 8) || null;
      await ddb.send(
        new PutCommand({
          TableName: EVENTS,
          Item: { userId: pk, eventId: "META", scope: "circle", circleId, name, emoji, createdAt: now },
        })
      );
      const creator = body.creator ?? {};
      const creatorName = String(creator.name ?? "").trim().slice(0, 40);
      if (creatorName) {
        const birthday =
          typeof creator.birthday === "string" && /^\d{4}-\d{2}-\d{2}$/.test(creator.birthday)
            ? creator.birthday
            : null;
        await ddb.send(
          new PutCommand({
            TableName: EVENTS,
            Item: {
              userId: pk,
              eventId: `MEMBER#${gid()}`,
              scope: "circle",
              name: creatorName,
              birthday,
              role: "creator",
              joinedAt: now,
            },
          })
        );
      }
      return json(200, { ok: true, circleId });
    }

    // GET /circles/{id}  — the whole circle in one query: meta + members + events.
    if (method === "GET" && /^\/circles\/[^/]+$/.test(path)) {
      if (!EVENTS) return json(404, { error: "not found" });
      const circleId = decodeURIComponent(path.split("/")[2]);
      const out = await ddb.send(
        new QueryCommand({
          TableName: EVENTS,
          KeyConditionExpression: "userId = :u",
          ExpressionAttributeValues: { ":u": `CIRCLE#${circleId}` },
        })
      );
      const rows = out.Items ?? [];
      const meta = rows.find((r) => r.eventId === "META");
      if (!meta) return json(404, { error: "circle not found" });
      const members = rows
        .filter((r) => r.eventId.startsWith("MEMBER#"))
        .map((r) => ({
          memberId: r.eventId.slice(7),
          name: r.name,
          birthday: r.birthday ?? null,
          role: r.role ?? "member",
          joinedAt: r.joinedAt ?? 0,
          // Present when this seat is claimed by a signed-in Giftmaxxing account
          // — other members can friend / message / gift them in-app.
          linkedUserId: r.linkedUserId ?? null,
          linkedHandle: r.linkedHandle ?? null,
          linkedName: r.linkedName ?? null,
        }))
        .sort((a, b) => a.joinedAt - b.joinedAt);
      const events = rows
        .filter((r) => r.eventId.startsWith("EVT#"))
        .map((r) => ({
          eventId: r.eventId,
          title: r.title,
          date: r.date,
          type: r.type ?? "occasion",
          forName: r.forName ?? null,
          addedBy: r.addedBy ?? null,
          createdAt: r.createdAt ?? 0,
        }))
        .sort((a, b) => (a.date < b.date ? -1 : 1));
      return json(200, {
        circle: { circleId, name: meta.name, emoji: meta.emoji ?? null, createdAt: meta.createdAt },
        members,
        events,
      });
    }

    // POST /circles/{id}/join  { name, birthday? }  — upsert by name so
    // re-joining from the same link just updates your birthday.
    if (method === "POST" && /^\/circles\/[^/]+\/join$/.test(path)) {
      if (!EVENTS) return json(503, { error: "events table not configured" });
      const circleId = decodeURIComponent(path.split("/")[2]);
      const pk = `CIRCLE#${circleId}`;
      const name = String(body.name ?? "").trim().slice(0, 40);
      if (!name) return json(400, { error: "name required" });
      const birthday =
        typeof body.birthday === "string" && /^\d{4}-\d{2}-\d{2}$/.test(body.birthday)
          ? body.birthday
          : null;
      const out = await ddb.send(
        new QueryCommand({
          TableName: EVENTS,
          KeyConditionExpression: "userId = :u",
          ExpressionAttributeValues: { ":u": pk },
        })
      );
      const rows = out.Items ?? [];
      if (!rows.some((r) => r.eventId === "META")) return json(404, { error: "circle not found" });
      const membersNow = rows.filter((r) => r.eventId.startsWith("MEMBER#"));
      if (membersNow.length >= 100) return json(400, { error: "circle is full" });
      const existing = membersNow.find(
        (r) => String(r.name ?? "").toLowerCase() === name.toLowerCase()
      );
      const item = existing
        ? {
            ...existing,
            birthday: birthday ?? existing.birthday ?? null,
            // Optional: link a signed-in account when rejoining / updating.
            ...(body.userId
              ? {
                  linkedUserId: String(body.userId).slice(0, 128),
                  linkedAt: Date.now(),
                }
              : {}),
          }
        : {
            userId: pk,
            eventId: `MEMBER#${gid()}`,
            scope: "circle",
            name,
            birthday,
            role: "member",
            joinedAt: Date.now(),
            ...(body.userId
              ? {
                  linkedUserId: String(body.userId).slice(0, 128),
                  linkedAt: Date.now(),
                }
              : {}),
          };
      await ddb.send(new PutCommand({ TableName: EVENTS, Item: item }));
      return json(200, {
        ok: true,
        memberId: item.eventId.slice(7),
        linkedUserId: item.linkedUserId ?? null,
      });
    }

    // POST /circles/{id}/events  { title, date, type?, forName?, addedBy? }
    if (method === "POST" && /^\/circles\/[^/]+\/events$/.test(path)) {
      if (!EVENTS) return json(503, { error: "events table not configured" });
      const circleId = decodeURIComponent(path.split("/")[2]);
      const pk = `CIRCLE#${circleId}`;
      const title = String(body.title ?? "").trim().slice(0, 80);
      const date = String(body.date ?? "");
      if (!title || !/^\d{4}-\d{2}-\d{2}$/.test(date)) {
        return json(400, { error: "title and date (YYYY-MM-DD) required" });
      }
      const metaOut = await ddb.send(
        new GetCommand({ TableName: EVENTS, Key: { userId: pk, eventId: "META" } })
      );
      if (!metaOut.Item) return json(404, { error: "circle not found" });
      const item = {
        userId: pk,
        eventId: `EVT#${Date.now()}#${gid()}`,
        scope: "circle",
        title,
        date,
        type: String(body.type ?? "occasion").slice(0, 24),
        forName: body.forName ? String(body.forName).slice(0, 40) : null,
        addedBy: body.addedBy ? String(body.addedBy).slice(0, 40) : null,
        createdAt: Date.now(),
      };
      await ddb.send(new PutCommand({ TableName: EVENTS, Item: item }));
      return json(200, { ok: true, eventId: item.eventId });
    }

    // POST /circles/{id}/events/delete  { eventId }
    if (method === "POST" && /^\/circles\/[^/]+\/events\/delete$/.test(path)) {
      if (!EVENTS) return json(503, { error: "events table not configured" });
      const circleId = decodeURIComponent(path.split("/")[2]);
      const eventId = String(body.eventId ?? "");
      if (!eventId.startsWith("EVT#")) return json(400, { error: "eventId required" });
      await ddb.send(
        new DeleteCommand({ TableName: EVENTS, Key: { userId: `CIRCLE#${circleId}`, eventId } })
      );
      return json(200, { ok: true });
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
      const existing = await ddb.send(new GetCommand({ TableName: USERS, Key: { userId } }));
      await ddb.send(
        new UpdateCommand({
          TableName: USERS,
          Key: { userId },
          UpdateExpression: "SET #id = :id, lastSeenAt = :now, createdAt = if_not_exists(createdAt, :now)",
          ExpressionAttributeNames: { "#id": "identity" },
          ExpressionAttributeValues: {
            ":id": {
              ...(existing.Item?.identity ?? {}),
              email: email ?? existing.Item?.identity?.email ?? null,
              name: name ?? existing.Item?.identity?.name ?? null,
              imageUrl: imageUrl ?? existing.Item?.identity?.imageUrl ?? null,
            },
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
      // Claim the email alias (first-writer-wins) so a later iOS sign-in with
      // the same address adopts THIS account — the web→app sync contract.
      // Web callers arrive Clerk-authenticated; Clerk has verified the email.
      if (email && typeof email === "string" && email.includes("@")) {
        await resolveCanonicalUserId(userId, email);
      }
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
