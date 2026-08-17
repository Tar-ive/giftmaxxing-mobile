// Client data layer for the AWS HTTP API (infra/). Fetches the cursor-paginated
// feed + recommendations and maps DynamoDB post items into the UI's Post type.
import type { Grad } from "@/lib/data";
import type { Post } from "@/lib/social";
import { SEED_PINS } from "@/lib/seed-pins";
import { ADMIN_BYPASS } from "@/lib/admin";
import { getOrCreateAnonId } from "@/lib/anon";
import { hiResImage } from "@/lib/images";

export const API_BASE = process.env.NEXT_PUBLIC_API_URL ?? "";
export const isApiConfigured = () => API_BASE.length > 0;

// Auth for the AWS API. Real users send a short-lived Clerk session JWT; the
// local admin-dev bypass sends the x-admin-token shared secret (that whole
// branch is tree-shaken out of production builds, so the token never ships to
// prod). Public catalog endpoints work without either.
async function authHeaders(): Promise<Record<string, string>> {
  if (typeof window === "undefined") return {};
  if (ADMIN_BYPASS) {
    const t = process.env.NEXT_PUBLIC_ADMIN_API_TOKEN;
    if (t) return { "x-admin-token": t };
  }
  try {
    const clerk = (window as unknown as {
      Clerk?: { session?: { getToken?: () => Promise<string | null> } };
    }).Clerk;
    const token = await clerk?.session?.getToken?.();
    if (token) return { Authorization: `Bearer ${token}` };
  } catch {
    /* not signed in / Clerk not loaded yet */
  }
  return {};
}

// fetch() wrapper that targets the API and attaches auth headers. ALL API calls
// go through this so a single place controls authentication.
//
// Resilience: the dev AWS account's Lambda concurrency is capped low, so API
// Gateway can return 503/429 — a pre-invocation throttle (rejected before the
// Lambda ran, so the request had no side effect). We ONLY retry writes here:
// retrying a throttled write is safe and avoids losing a user action (e.g.
// creating a pool), with jittered backoff so many clients don't resend in
// lockstep. GETs are NOT retried — they go through cachedGetJson() + the
// CloudFront edge cache, so retrying them only amplifies the throttle storm
// (that loop resending throttled feed reads WAS most of the storm).
export async function apiFetch(path: string, init: RequestInit = {}): Promise<Response> {
  const auth = await authHeaders();
  const headers = { ...(init.headers as Record<string, string> | undefined), ...auth };
  const url = API_BASE + path;
  let res = await fetch(url, { ...init, headers });
  const method = (init.method ?? "GET").toUpperCase();
  const maxRetries = method === "GET" ? 0 : 2;
  for (let attempt = 1; attempt <= maxRetries && (res.status === 503 || res.status === 429); attempt++) {
    await new Promise((r) => setTimeout(r, 250 * attempt + Math.random() * 250));
    res = await fetch(url, { ...init, headers });
  }
  return res;
}

// ── Client-side cache + in-flight dedup for the public, cacheable GET routes ──
// Repeated/identical feed reads (remounts, retries, multiple components) must not
// each hit the origin while the Lambda concurrency is tiny. We cache successful
// JSON in memory for a short TTL, share in-flight requests (N callers -> 1 fetch),
// and serve the last-good response if a refresh fails. These routes are public,
// so we issue a plain "simple" CORS GET (no Authorization header => no preflight),
// which also maximizes the CloudFront edge-cache hit rate.
const FEED_CACHE_TTL_MS = 45_000;
type GetCacheEntry<T> = { at: number; data: T };
const _getCache = new Map<string, GetCacheEntry<unknown>>();
const _getInflight = new Map<string, Promise<unknown>>();

async function cachedGetJson<T>(path: string, ttlMs = FEED_CACHE_TTL_MS): Promise<T> {
  const now = Date.now();
  const cached = _getCache.get(path) as GetCacheEntry<T> | undefined;
  if (cached && now - cached.at < ttlMs) return cached.data;

  const inflight = _getInflight.get(path) as Promise<T> | undefined;
  if (inflight) return inflight;

  const p = (async (): Promise<T> => {
    try {
      const res = await fetch(API_BASE + path, { headers: { accept: "application/json" } });
      if (!res.ok) {
        if (cached) return cached.data; // serve stale rather than fail
        throw new Error(`${path} -> HTTP ${res.status}`);
      }
      const data = (await res.json()) as T;
      _getCache.set(path, { at: Date.now(), data });
      return data;
    } catch (err) {
      if (cached) return cached.data; // network error -> serve stale
      throw err;
    } finally {
      _getInflight.delete(path);
    }
  })();
  _getInflight.set(path, p);
  return p;
}

const GRADS: Grad[] = ["peach", "rose", "butter", "lilac", "sky", "sage", "coral"];
const asGrad = (g: unknown): Grad =>
  GRADS.includes(g as Grad) ? (g as Grad) : "peach";

// Shape returned by GET /feed and /recommendations (see infra/src/handler.mjs).
type ApiPost = {
  postId: string;
  author?: string;
  createdAt?: number;
  likes?: number;
  comments?: number;
  caption?: string;
  source?: string;
  url?: string;
  productUrl?: string | null;
  rec?: boolean;
  reason?: string;
  recipient?: string;
  occasion?: string;
  category?: string;
  status?: string;
  product?: {
    id?: string;
    name?: string;
    brand?: string;
    price?: number;
    grad?: string;
    emoji?: string;
    image?: string | null;
    images?: string[];
  };
};

export type FeedPage = { posts: Post[]; cursor: string | null };

// Compact relative time from an epoch-ms timestamp ("5d", "3h", "12m").
export function relativeTime(ms?: number): string {
  if (!ms) return "";
  const s = Math.max(1, Math.floor((Date.now() - ms) / 1000));
  if (s < 60) return `${s}s`;
  const m = Math.floor(s / 60);
  if (m < 60) return `${m}m`;
  const h = Math.floor(m / 60);
  if (h < 24) return `${h}h`;
  const d = Math.floor(h / 24);
  if (d < 365) return `${d}d`;
  return `${Math.floor(d / 365)}y`;
}

export function mapApiPost(api: ApiPost): Post {
  const p = api.product ?? {};
  return {
    id: api.postId,
    user: api.author ?? "reddit",
    createdAt: api.createdAt,
    time: relativeTime(api.createdAt),
    product: {
      id: p.id ?? api.postId,
      name: p.name ?? api.caption ?? "Gift find",
      brand: p.brand ?? api.source ?? "Reddit",
      price: Number(p.price) || 0,
      grad: asGrad(p.grad),
      emoji: p.emoji ?? "🎁",
      image: hiResImage(p.image) || null,
      images: (p.images ?? []).map(hiResImage).filter(Boolean),
    },
    caption: api.caption ?? "",
    likes: Number(api.likes) || 0,
    liked: false,
    saved: false,
    comments: [],
    commentCount: Number(api.comments) || 0,
    source: api.source,
    url: api.url,
    productUrl: api.productUrl ?? null,
    rec: api.rec ?? true,
    reason: api.reason,
    category: api.category,
  };
}

type FeedOpts = {
  cursor?: string | null;
  limit?: number;
  vibes?: string[];
  recipient?: string;
  occasion?: string;
  category?: string;
  budget?: number;
  eventBoost?: number;
  // Viewer id (from getMyUserId). When present the backend excludes everything
  // this user has already seen/liked/saved, so the feed never repeats.
  userId?: string | null;
};

async function getPage(path: string, opts: FeedOpts): Promise<FeedPage> {
  const q = new URLSearchParams();
  if (opts.cursor) q.set("cursor", opts.cursor);
  if (opts.limit) q.set("limit", String(opts.limit));
  if (opts.vibes?.length) q.set("vibes", opts.vibes.join(","));
  if (opts.recipient) q.set("recipient", opts.recipient);
  if (opts.occasion) q.set("occasion", opts.occasion);
  if (opts.category) q.set("category", opts.category);
  if (opts.budget) q.set("budget", String(opts.budget));
  if (opts.eventBoost) q.set("eventBoost", String(opts.eventBoost));
  if (opts.userId) q.set("userId", opts.userId);

  const data = await cachedGetJson<{ items?: ApiPost[]; cursor?: string | null }>(
    `${path}?${q.toString()}`
  );
  return {
    posts: (data.items ?? []).map(mapApiPost),
    cursor: data.cursor ?? null,
  };
}

export const fetchFeed = (opts: FeedOpts = {}) => getPage("/feed", opts);
export const fetchRecommendations = (opts: FeedOpts = {}) =>
  getPage("/recommendations", opts);

// Fire-and-forget interaction logging (POST /interactions). Powers two things:
//  1. Feed freshness — the backend excludes every target a user has interacted
//     with, so "seen" impressions stop items from reappearing on the next load.
//  2. Personalized recs — likes/saves become vector seeds for /recommendations.
// Idempotent per session: each (user,type,target) is sent at most once, so the
// impression observer can call this freely without spamming the API.
// Comments are NOT de-duped (many per post).
const _sentInteractions = new Set<string>();
export function recordInteraction(
  userId: string | null | undefined,
  targetId: string,
  type: "seen" | "like" | "save" | "comment",
  data?: { text?: string }
): void {
  if (!isApiConfigured() || !userId || !targetId) return;
  // Comments are never de-duped; likes/saves/seen are idempotent.
  if (type !== "comment") {
    const key = `${userId}#${type}#${targetId}`;
    if (_sentInteractions.has(key)) return;
    _sentInteractions.add(key);
    void apiFetch(`/interactions`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ userId, targetId, type }),
    }).catch(() => {
      _sentInteractions.delete(key); // allow a retry after a transient failure
    });
  } else {
    void apiFetch(`/interactions`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ userId, targetId, type, data }),
    }).catch(() => {});
  }
}

// ── Fetch persisted interactions (GET /interactions) ──────────────────────────
// Returns the user's likes, saves, and comments from the backend so state can be
// restored on page load (cross-device sync). Falls back gracefully to null when
// the API is unreachable so callers use localStorage instead.
export type PersistedInteraction = {
  targetId: string;
  type: "like" | "save" | "comment" | "seen";
  createdAt?: number;
  data?: { text?: string };
};

export async function fetchInteractions(
  userId: string,
  types?: string[]
): Promise<PersistedInteraction[] | null> {
  if (!isApiConfigured() || !userId) return null;
  try {
    const q = new URLSearchParams({ userId });
    if (types?.length) q.set("types", types.join(","));
    const res = await apiFetch(`/interactions?${q.toString()}`, {
      headers: { accept: "application/json" },
    });
    if (!res.ok) return null;
    const data = (await res.json()) as { items?: PersistedInteraction[] };
    return data.items ?? [];
  } catch {
    return null;
  }
}

// Fetch the set of post IDs a user has saved (via GET /interactions?type=save).
// Used on mount to restore cross-device save state. Returns an empty set on any
// failure (endpoint not deployed, network error) so localStorage stays the fallback.
export async function fetchSavedIds(userId: string): Promise<Set<string>> {
  if (!isApiConfigured() || !userId) return new Set();
  try {
    const res = await fetch(
      `${API_BASE}/interactions?userId=${encodeURIComponent(userId)}&type=save`,
      { headers: { accept: "application/json" } }
    );
    if (!res.ok) return new Set();
    const data = (await res.json()) as { items?: { target: string }[] };
    return new Set((data.items ?? []).map((i) => i.target).filter(Boolean));
  } catch {
    return new Set();
  }
}

// ── Vector recommendations (S3 Vectors) ──────────────────────────────────────
// Raw item shape returned by GET /pins and the vector path of /recommendations.
export type VectorItem = {
  postId: string;
  author?: string;
  image?: string;
  name?: string;
  source?: string;
  reason?: string;
  // Real shoppable fields returned by vecToItem (infra/src/handler.mjs): the
  // outbound retailer link, price, and merchant — used to make results buyable.
  url?: string;
  productUrl?: string | null;
  price?: number;
  merchant?: string;
  domain?: string;
  _score?: number | null;
  _distance?: number | null;
};

export type VectorResponse = { items: VectorItem[]; source: string | null };

// List embedded pins (key + metadata) to use as seed vectors. Prefers the live
// GET /pins endpoint; falls back to the bundled SEED_PINS list when /pins isn't
// reachable (e.g. not deployed yet) so the UI keeps working offline of it.
export async function fetchPins(limit = 60): Promise<VectorItem[]> {
  if (isApiConfigured()) {
    try {
      const data = await cachedGetJson<{ items?: VectorItem[] }>(`/pins?limit=${limit}`);
      if (data.items && data.items.length) return data.items;
    } catch {
      // fall through to the bundled list
    }
  }
  return SEED_PINS.slice(0, limit).map((p) => ({
    postId: p.k,
    name: p.t,
    author: `pinterest_${p.u}`,
  }));
}

// Call the vector path of /recommendations: seedKeys -> taste centroid -> kNN.
// Returns the raw items plus the `source` tag ("vector" | "facet").
export async function fetchVectorRecommendations(
  opts: { seedKeys?: string[]; vibes?: string[]; sourceUser?: string; limit?: number } = {}
): Promise<VectorResponse> {
  const q = new URLSearchParams();
  if (opts.seedKeys?.length) q.set("seedKeys", opts.seedKeys.join(","));
  if (opts.vibes?.length) q.set("vibes", opts.vibes.join(","));
  if (opts.sourceUser) q.set("sourceUser", opts.sourceUser);
  q.set("limit", String(opts.limit ?? 12));

  const data = await cachedGetJson<{ items?: VectorItem[]; source?: string }>(
    `/recommendations?${q.toString()}`
  );
  return { items: data.items ?? [], source: data.source ?? null };
}

// Visual search: POST a base64 image -> Titan Multimodal embed -> S3 Vectors kNN
// (see infra/src/handler.mjs POST /visual-search). Throws if the endpoint isn't
// reachable so callers can fall back to a local taste match.
export async function fetchVisualSearch(opts: {
  imageBase64: string;
  text?: string;
  limit?: number;
  sourceUser?: string;
}): Promise<VectorResponse> {
  if (!isApiConfigured()) throw new Error("API not configured");
  const res = await apiFetch(`/visual-search`, {
    method: "POST",
    headers: { "content-type": "application/json", accept: "application/json" },
    body: JSON.stringify({
      imageBase64: opts.imageBase64,
      text: opts.text,
      limit: opts.limit ?? 12,
      sourceUser: opts.sourceUser,
    }),
  });
  if (!res.ok) throw new Error(`/visual-search -> HTTP ${res.status}`);
  const data = (await res.json()) as { items?: VectorItem[]; source?: string };
  return { items: data.items ?? [], source: data.source ?? "visual" };
}

// ── User profile persistence (DynamoDB `users` table via /me) ─────────────────
// The signed-in user's whole profile (incl. recipients + events) is stored as a
// single item keyed by the Clerk userId, so it hydrates in one read on login.
// Wired up by AccountSync (web/components/app/account-sync.tsx).
export type UpcomingEvent = {
  id: string;
  recipientId: string;
  type: string;
  date: string;
  recurrence: string;
  reminderLeadDays: number;
  budget?: number;
  daysUntil: number;
  recipient: { id: string; name: string; relation: string; sourceUser?: string } | null;
};

export async function fetchMe<T = Record<string, unknown>>(userId: string): Promise<T | null> {
  if (!isApiConfigured() || !userId) return null;
  try {
    const res = await apiFetch(`/me?userId=${encodeURIComponent(userId)}`, {
      headers: { accept: "application/json" },
    });
    if (!res.ok) return null;
    const data = (await res.json()) as { item?: T | null };
    return data.item ?? null;
  } catch {
    return null;
  }
}

export async function saveMe(userId: string, profile: unknown): Promise<boolean> {
  if (!isApiConfigured() || !userId) return false;
  try {
    const res = await apiFetch(`/me`, {
      method: "PUT",
      headers: { "content-type": "application/json", accept: "application/json" },
      body: JSON.stringify({ userId, profile }),
    });
    return res.ok;
  } catch {
    return false;
  }
}

export async function fetchUpcomingEvents(
  userId: string,
  withinDays = 90
): Promise<UpcomingEvent[]> {
  if (!isApiConfigured() || !userId) return [];
  try {
    const res = await fetch(
      `${API_BASE}/events/upcoming?userId=${encodeURIComponent(userId)}&withinDays=${withinDays}`,
      { headers: { accept: "application/json" } }
    );
    if (!res.ok) return [];
    const data = (await res.json()) as { items?: UpcomingEvent[] };
    return data.items ?? [];
  } catch {
    return [];
  }
}

// ── Soft profiles / viral swipe-challenge connections ────────────────────────
// When a guest finishes a shared swipe challenge, a "soft profile" is created on
// the sender's account (POST /connections, keyed by the sender's Clerk userId).
// The sender reads them back (GET /connections) as notifications + connections.

const UID_KEY = "giftmaxxing_uid";

// The signed-in user's Clerk userId, stashed to localStorage by AccountSync so
// non-Clerk client code (e.g. the swipe share link) can read it synchronously.
export function getMyUserId(): string | null {
  if (typeof window === "undefined") return null;
  try {
    return localStorage.getItem(UID_KEY) || null;
  } catch {
    return null;
  }
}

export function setMyUserId(userId: string | null): void {
  if (typeof window === "undefined") return;
  try {
    if (userId) localStorage.setItem(UID_KEY, userId);
    else localStorage.removeItem(UID_KEY);
  } catch {
    /* ignore quota / disabled storage */
  }
}

// The id to attribute a shared challenge to: the signed-in Clerk userId if we
// have one, otherwise a persistent anonymous id (claimed into the account on
// sign-in). Lets a signed-out user share a challenge and still collect results.
export function getShareSenderId(): string {
  return getMyUserId() ?? getOrCreateAnonId();
}

// Taste + identity captured from a guest's completed swipe challenge.
export type GuestSoftProfile = {
  name: string;
  handle?: string;
  birthday?: string;
  genderPref?: string;
  vibes?: string[];
  seeds?: string[];
  interests?: string[];
  yesCount?: number;
  totalSwipes?: number;
  dwellSignals?: { id: string; dir: string; dwellMs: number }[];
};

// A soft profile as stored under the sender (GET /connections).
export type SoftConnection = {
  userId: string;
  connectionId: string;
  soft?: boolean;
  kind?: string;
  guestName: string;
  guestHandle?: string;
  birthday?: string;
  genderPref?: string;
  vibes?: string[];
  seeds?: string[];
  interests?: string[];
  yesCount?: number;
  totalSwipes?: number;
  seen?: boolean;
  createdAt?: number;
};

// ── Server-side challenges (deck + verdict in the Lambda) ────────────────────
// POST /challenges (sender, iOS/web) builds a banded deck around a seed; the
// invite link carries challengeId; the guest page fetches the deck and posts
// swipes back — the verdict is computed server-side and mirrored into
// connections, so no separate createConnection call is needed on this path.

export type ChallengeDeckItem = {
  postId: string;
  name?: string;
  image?: string;
  price?: number;
  priceDisplay?: string | null;
  category?: string;
  domain?: string;
  url?: string;
  // Products vs gift-able services (a year of Netflix, a Costco membership…):
  // the deck mixes ~20% service probes so a guest's swipes also reveal whether
  // they'd rather receive a membership than a thing (verdict.giftTypeSplit).
  giftType?: "product" | "service";
  serviceDuration?: string;
};

export type ChallengePublic = {
  challengeId: string;
  inviterName?: string | null;
  to?: string | null;
  occasion?: string | null;
  date?: string | null;
  note?: string | null;
  // "group" = friends swipe FOR a third-party recipient; the tally is shared.
  // "verify" = concierge double-check; aggregate match summary is public.
  mode?: string | null;
  responseCount?: number;
  deck: ChallengeDeckItem[];
  // Verify mode only: did they swipe right on the hidden pick?
  verify?: {
    responses: number;
    matched: boolean;
    by?: string | null;
    label?: string | null;
    score?: number | null;
  };
};

// Sender-side: build the deck in the Lambda around a seed (taste keys on the
// web — the image path is the iOS share-extension flow). Returns the
// challengeId to embed in the invite link, or null → caller keeps the legacy
// local-deck link so sharing never blocks.
export async function createChallenge(opts: {
  senderId: string;
  seedKeys?: string[];
  imageBase64?: string;
  postId?: string;
  inviterName?: string;
  to?: string;
  occasion?: string;
  date?: string;
  mode?: "group" | "verify";
}): Promise<string | null> {
  if (!isApiConfigured() || !opts.senderId) return null;
  const seed: Record<string, unknown> = {};
  if (opts.imageBase64) seed.imageBase64 = opts.imageBase64;
  if (opts.postId) seed.postId = opts.postId;
  if (opts.seedKeys?.length) seed.seedKeys = opts.seedKeys.slice(0, 8);
  if (Object.keys(seed).length === 0) return null;
  try {
    const res = await apiFetch(`/challenges`, {
      method: "POST",
      headers: { "content-type": "application/json", accept: "application/json" },
      body: JSON.stringify({
        senderId: opts.senderId,
        seed,
        ...(opts.inviterName ? { inviterName: opts.inviterName } : {}),
        ...(opts.to?.trim() ? { to: opts.to.trim() } : {}),
        ...(opts.occasion ? { occasion: opts.occasion } : {}),
        ...(opts.date ? { date: opts.date } : {}),
        ...(opts.mode ? { mode: opts.mode } : {}),
      }),
    });
    if (!res.ok) return null;
    const data = (await res.json()) as { challengeId?: string };
    return typeof data?.challengeId === "string" && data.challengeId ? data.challengeId : null;
  } catch {
    return null;
  }
}

// Guest-side: the pre-built deck (band/distance stripped by the server).
export async function fetchChallenge(challengeId: string): Promise<ChallengePublic | null> {
  if (!isApiConfigured() || !challengeId) return null;
  try {
    const res = await apiFetch(`/challenges/${encodeURIComponent(challengeId)}`, {
      headers: { accept: "application/json" },
    });
    if (!res.ok) return null;
    const data = (await res.json()) as ChallengePublic;
    return Array.isArray(data?.deck) && data.deck.length ? data : null;
  } catch {
    return null;
  }
}

export type ChallengeSwipe = { id: string; dir: "yes" | "no"; dwellMs?: number };

// The guest's own reveal payload (never the sender's seed verdict): their top
// categories, price band, product-vs-service split, and yes-seeds for warm-
// starting vector recommendations before they have an account.
export type ChallengeGuestTaste = {
  topCategories?: string[];
  priceBand?: { min: number; median: number; max: number } | null;
  giftTypeSplit?: {
    productYes?: number;
    productTotal?: number;
    serviceYes?: number;
    serviceTotal?: number;
    productYesRate?: number | null;
    serviceYesRate?: number | null;
  } | null;
  seeds?: string[];
};

// Guest-side: submit swipes; the server scores the verdict against the hidden
// seed and mirrors a soft-profile connection for the sender. Passing
// guest.anonId additionally persists the swiper's OWN taste under that id
// server-side (claimed into their account at signup — the recipient-entry
// warm start), and the response echoes that taste back for local seeding.
export async function submitChallengeResponse(
  challengeId: string,
  guest: { name?: string; handle?: string; birthday?: string; genderPref?: string; anonId?: string },
  swipes: ChallengeSwipe[]
): Promise<{ ok: boolean; taste: ChallengeGuestTaste | null }> {
  if (!isApiConfigured() || !challengeId || !swipes.length) return { ok: false, taste: null };
  try {
    const res = await apiFetch(`/challenges/${encodeURIComponent(challengeId)}/response`, {
      method: "POST",
      headers: { "content-type": "application/json", accept: "application/json" },
      body: JSON.stringify({ guest, swipes }),
    });
    if (!res.ok) return { ok: false, taste: null };
    const data = (await res.json().catch(() => null)) as { taste?: ChallengeGuestTaste } | null;
    return { ok: true, taste: data?.taste ?? null };
  } catch {
    return { ok: false, taste: null };
  }
}

// Called by the (anonymous) guest's browser on challenge completion.
export async function createConnection(
  senderId: string,
  guest: GuestSoftProfile
): Promise<boolean> {
  if (!isApiConfigured() || !senderId || !guest?.name) return false;
  try {
    const res = await apiFetch(`/connections`, {
      method: "POST",
      headers: { "content-type": "application/json", accept: "application/json" },
      body: JSON.stringify({ senderId, guest }),
    });
    return res.ok;
  } catch {
    return false;
  }
}

// Called by the sender's app to list collected soft profiles (newest first).
export async function fetchConnections(
  userId: string,
  opts: { unseenOnly?: boolean } = {}
): Promise<{ items: SoftConnection[]; unseen: number }> {
  if (!isApiConfigured() || !userId) return { items: [], unseen: 0 };
  try {
    const q = new URLSearchParams({ userId });
    if (opts.unseenOnly) q.set("unseenOnly", "1");
    const res = await apiFetch(`/connections?${q.toString()}`, {
      headers: { accept: "application/json" },
    });
    if (!res.ok) return { items: [], unseen: 0 };
    const data = (await res.json()) as { items?: SoftConnection[]; unseen?: number };
    return { items: data.items ?? [], unseen: data.unseen ?? 0 };
  } catch {
    return { items: [], unseen: 0 };
  }
}

// Clear the sender's notification state. Omit ids to mark all unseen as seen.
export async function markConnectionsSeen(
  userId: string,
  connectionIds?: string[]
): Promise<boolean> {
  if (!isApiConfigured() || !userId) return false;
  try {
    const res = await apiFetch(`/connections/seen`, {
      method: "POST",
      headers: { "content-type": "application/json", accept: "application/json" },
      body: JSON.stringify({ userId, connectionIds }),
    });
    return res.ok;
  } catch {
    return false;
  }
}

// Re-key every soft profile collected under a signed-out creator's anon id onto
// their real account. Called by AccountSync on sign-in. Returns the number of
// claimed connections, or null if the request failed (so the caller can retry
// next sign-in instead of dropping the anon id).
export async function claimConnections(
  anonId: string,
  userId: string
): Promise<number | null> {
  if (!isApiConfigured() || !anonId || !userId) return null;
  try {
    const res = await apiFetch(`/connections/claim`, {
      method: "POST",
      headers: { "content-type": "application/json", accept: "application/json" },
      body: JSON.stringify({ anonId, userId }),
    });
    if (!res.ok) return null;
    const data = (await res.json()) as { claimed?: number };
    return data.claimed ?? 0;
  } catch {
    return null;
  }
}

// ── Identity (ensure a users row exists from the FIRST sign-in) ───────────────
// Upserts identity fields keyed by the Clerk userId WITHOUT clobbering a profile
// written later by /me. Called by AccountSync on every sign-in.
export async function identifyMe(
  userId: string,
  identity: { email?: string | null; name?: string | null; imageUrl?: string | null }
): Promise<boolean> {
  if (!isApiConfigured() || !userId) return false;
  try {
    const res = await apiFetch(`/me/identity`, {
      method: "POST",
      headers: { "content-type": "application/json", accept: "application/json" },
      body: JSON.stringify({ userId, ...identity }),
    });
    return res.ok;
  } catch {
    return false;
  }
}

// ── Unified events (personal milestones + shared occasions/soft profiles) ─────
// Backed by the DynamoDB `events` table (scope-tagged) + mirrored into the graph.
export type EventScope = "personal" | "shared";
export type ApiEvent = {
  userId: string;
  eventId: string;
  scope: EventScope;
  kind?: string;
  type?: string;
  title?: string;
  date?: string;
  createdAt?: number;
  [k: string]: unknown;
};

export async function fetchEvents(userId: string, scope?: EventScope): Promise<ApiEvent[]> {
  if (!isApiConfigured() || !userId) return [];
  try {
    const q = new URLSearchParams({ userId });
    if (scope) q.set("scope", scope);
    const res = await apiFetch(`/events?${q.toString()}`, { headers: { accept: "application/json" } });
    if (!res.ok) return [];
    const data = (await res.json()) as { items?: ApiEvent[] };
    return data.items ?? [];
  } catch {
    return [];
  }
}

export async function saveEvent(userId: string, event: Record<string, unknown>): Promise<boolean> {
  if (!isApiConfigured() || !userId) return false;
  try {
    const res = await apiFetch(`/events`, {
      method: "POST",
      headers: { "content-type": "application/json", accept: "application/json" },
      body: JSON.stringify({ userId, event }),
    });
    return res.ok;
  } catch {
    return false;
  }
}

export async function patchEvent(
  userId: string,
  eventId: string,
  patch: Record<string, unknown>
): Promise<boolean> {
  if (!isApiConfigured() || !userId) return false;
  try {
    const res = await apiFetch(`/events`, {
      method: "PUT",
      headers: { "content-type": "application/json", accept: "application/json" },
      body: JSON.stringify({ userId, eventId, patch }),
    });
    return res.ok;
  } catch {
    return false;
  }
}

export async function deleteEvent(userId: string, eventId: string): Promise<boolean> {
  if (!isApiConfigured() || !userId) return false;
  try {
    const res = await apiFetch(`/events/delete`, {
      method: "POST",
      headers: { "content-type": "application/json", accept: "application/json" },
      body: JSON.stringify({ userId, eventId }),
    });
    return res.ok;
  } catch {
    return false;
  }
}

// Bulk import (e.g. local milestones -> events, scope "personal"). Idempotent.
export async function migrateEvents(userId: string, items: Record<string, unknown>[]): Promise<number> {
  if (!isApiConfigured() || !userId || items.length === 0) return 0;
  try {
    const res = await apiFetch(`/events/migrate`, {
      method: "POST",
      headers: { "content-type": "application/json", accept: "application/json" },
      body: JSON.stringify({ userId, items }),
    });
    if (!res.ok) return 0;
    const data = (await res.json()) as { migrated?: number };
    return data.migrated ?? 0;
  } catch {
    return 0;
  }
}

// ── Network graph (read the signed-in user's nodes + edges) ───────────────────
export type GraphNode = { id: string; type: string; scope?: string; label?: string; data?: Record<string, unknown> };
export type GraphEdge = { rel: string; from: string; to: string; data?: Record<string, unknown> };

export async function fetchGraph(
  userId: string
): Promise<{ nodes: GraphNode[]; edges: GraphEdge[]; counts: { nodes: number; edges: number } }> {
  const empty = { nodes: [], edges: [], counts: { nodes: 0, edges: 0 } };
  if (!isApiConfigured() || !userId) return empty;
  try {
    const res = await apiFetch(`/graph?userId=${encodeURIComponent(userId)}`, {
      headers: { accept: "application/json" },
    });
    if (!res.ok) return empty;
    return (await res.json()) as { nodes: GraphNode[]; edges: GraphEdge[]; counts: { nodes: number; edges: number } };
  } catch {
    return empty;
  }
}

// ── Maxi agent (Claude Haiku 4.5 via POST /maxi) ─────────────────────────────
export type MaxiAgentProduct = {
  postId: string;
  title: string;
  price: number | null;
  brand: string | null;
  image: string | null;
  category: string | null;
  // Optional Alexa-style commerce metadata (present on find_deals results).
  listPrice?: number;
  discountPct?: number;
  rating?: number;
  reviews?: number;
  boughtPastMonth?: string;
  delivery?: string;
  onDeal?: boolean;
};
export type MaxiAction = { type: string; postIds?: string[] };
// One surfaced "layer" of the agent's tool-use loop (e.g. "Scanned your past orders").
export type MaxiStep = { tool: string; label: string; detail?: string };
export type MaxiAgentReply = {
  say: string;
  pins: MaxiAgentProduct[];
  actions: MaxiAction[];
  steps: MaxiStep[];
  source: string;
};

// Calls the real LLM agent (Bedrock Converse + tools, server-side). Returns null
// on ANY failure (not configured, 5xx, cost-guard, network) so callers can fall
// back to the offline rule-based responder in web/lib/maxi.ts.
export async function askMaxi(input: {
  userId?: string | null;
  name?: string;
  message: string;
  messages?: { role: "user" | "assistant"; text: string }[];
}): Promise<MaxiAgentReply | null> {
  if (!isApiConfigured()) return null;
  try {
    const res = await apiFetch(`/maxi`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        userId: input.userId ?? undefined,
        name: input.name,
        message: input.message,
        messages: (input.messages ?? []).slice(-12),
      }),
    });
    if (!res.ok) return null;
    const data = (await res.json()) as Partial<MaxiAgentReply>;
    if (!data || typeof data.say !== "string") return null;
    return {
      say: data.say,
      pins: Array.isArray(data.pins) ? data.pins : [],
      actions: Array.isArray(data.actions) ? data.actions : [],
      steps: Array.isArray(data.steps) ? data.steps : [],
      source: typeof data.source === "string" ? data.source : "agent",
    };
  } catch {
    return null;
  }
}
