// ────────────────────────────────────────────────────────────────────────────
// Invite links — zero-friction sharing for the swipe challenge.
//
// An invite code is a base64url-encoded JSON payload containing the inviter's
// name (and, eventually, their userId / Pinterest handle once real auth exists).
// The invited user never needs to sign up and never fills in a form — they just
// swipe. The sender can pre-set the recipient's name and the occasion/date, so
// the guest goes straight from swiping to seeing their gift set.
// ────────────────────────────────────────────────────────────────────────────

/** Compact, URL-embeddable snapshot of a group-gift pool. Group-gift invites
 *  carry their own copy of the pool because the pool store is client-side
 *  (localStorage), so an external recipient's browser has no record of it until
 *  they join. Keep this small — it lives inside the invite code in the URL. */
export type PoolInviteSnapshot = {
  id: string;
  title: string;
  occasion: string;
  goal: number;
  blurb?: string;
  emoji?: string;
  grad?: string;
  image?: string | null;
};

export type InvitePayload = {
  /** Display name of the person who sent the invite. */
  name: string;
  /** Optional handle (derived from name for now). */
  handle?: string;
  /** Clerk userId of the inviter, so a completed challenge can notify them and
   *  attach the resulting soft profile to their account. Absent when the sender
   *  is signed out (the link still works, it just can't report back). */
  senderId?: string;
  /** Recipient's name, chosen by the sender — so the guest never types it. */
  to?: string;
  /** Occasion the sender wants to remember (an events EventType, e.g. "birthday"). */
  occasion?: string;
  /** Event date (YYYY-MM-DD) the sender set for the recipient. */
  date?: string;
  /** Group-gift invite: when present, the link invites the recipient to JOIN a
   *  group gift (chip in) rather than run the swipe challenge. /invite/[code]
   *  routes these through sign-in + consent before they can contribute. */
  pool?: PoolInviteSnapshot;
  /** Server-side challenge (POST /challenges): when present, the guest page
   *  fetches the pre-built seeded deck from GET /challenges/{id} and posts
   *  swipes to /challenges/{id}/response — deck + verdict fully server-side.
   *  Absent → the legacy local-deck flow (old links keep working). */
  challengeId?: string;
};

// ── Encoding / decoding ──────────────────────────────────────────────────────

function toBase64Url(s: string): string {
  if (typeof btoa === "function") {
    const bytes = new TextEncoder().encode(s);
    const binary = Array.from(bytes, (b) => String.fromCharCode(b)).join("");
    return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
  }
  return Buffer.from(s, "utf-8").toString("base64url");
}

function fromBase64Url(s: string): string {
  const padded = s.replace(/-/g, "+").replace(/_/g, "/");
  if (typeof atob === "function") {
    const binary = atob(padded);
    const bytes = Uint8Array.from(binary, (c) => c.charCodeAt(0));
    return new TextDecoder().decode(bytes);
  }
  return Buffer.from(padded, "base64").toString("utf-8");
}

export function encodeInvite(payload: InvitePayload): string {
  return toBase64Url(JSON.stringify(payload));
}

export function decodeInvite(code: string): InvitePayload | null {
  try {
    const raw: unknown = JSON.parse(fromBase64Url(code));
    if (
      raw &&
      typeof raw === "object" &&
      typeof (raw as InvitePayload).name === "string" &&
      (raw as InvitePayload).name.trim().length > 0
    ) {
      return raw as InvitePayload;
    }
    return null;
  } catch {
    return null;
  }
}

// ── Invite-link builder (used in the share button) ───────────────────────────

export function buildInviteUrl(
  inviterName: string,
  opts: {
    senderId?: string;
    origin?: string;
    to?: string;
    occasion?: string;
    date?: string;
    /** Server-side challenge id (POST /challenges) — guest page fetches the
     *  pre-built deck instead of running the legacy local one. */
    challengeId?: string;
  } = {}
): string {
  // Prefer the canonical public site URL so a shared link never points at a
  // Vercel *preview* deployment — those sit behind Vercel Authentication and
  // would prompt the recipient to "log in to Vercel". Falls back to the current
  // origin (fine for local dev / the production origin itself).
  const envSite = process.env.NEXT_PUBLIC_SITE_URL?.replace(/\/+$/, "");
  const base =
    opts.origin ||
    envSite ||
    (typeof window !== "undefined" ? window.location.origin : "");
  const payload: InvitePayload = { name: inviterName.trim() };
  if (opts.senderId) payload.senderId = opts.senderId;
  if (opts.to?.trim()) payload.to = opts.to.trim();
  if (opts.occasion?.trim()) payload.occasion = opts.occasion.trim();
  if (opts.date?.trim()) payload.date = opts.date.trim();
  if (opts.challengeId) payload.challengeId = opts.challengeId;
  const code = encodeInvite(payload);
  return `${base}/invite/${code}`;
}

// ── Group-gift invite-link builder ───────────────────────────────────────────
// Builds an /invite/<code> link that invites someone to JOIN a group gift. The
// recipient must sign in (and agree to the terms) before they can chip in — see
// the PoolInvite landing. The pool snapshot rides along in the code so the link
// renders the pool even on a device that has never seen it.
export function buildPoolInviteUrl(
  inviterName: string,
  pool: PoolInviteSnapshot,
  opts: { senderId?: string; origin?: string } = {}
): string {
  const envSite = process.env.NEXT_PUBLIC_SITE_URL?.replace(/\/+$/, "");
  const base =
    opts.origin ||
    envSite ||
    (typeof window !== "undefined" ? window.location.origin : "");
  const payload: InvitePayload = { name: inviterName.trim() || "A friend", pool };
  if (opts.senderId) payload.senderId = opts.senderId;
  const code = encodeInvite(payload);
  return `${base}/invite/${code}`;
}

// ── Session persistence ──────────────────────────────────────────────────────
// Tracks the invite context across the swipe → birthday flow so we know who
// invited this user even if they navigate away mid-flow.

const INVITE_SESSION_KEY = "giftmaxxing_invite_session";

export type InviteSession = {
  inviterName: string;
  code: string;
  startedAt: number;
};

export function loadInviteSession(): InviteSession | null {
  if (typeof window === "undefined") return null;
  try {
    const raw = localStorage.getItem(INVITE_SESSION_KEY);
    if (!raw) return null;
    const parsed: unknown = JSON.parse(raw);
    if (
      parsed &&
      typeof parsed === "object" &&
      typeof (parsed as InviteSession).inviterName === "string"
    ) {
      return parsed as InviteSession;
    }
    return null;
  } catch {
    return null;
  }
}

export function saveInviteSession(session: InviteSession): void {
  if (typeof window === "undefined") return;
  try {
    localStorage.setItem(INVITE_SESSION_KEY, JSON.stringify(session));
  } catch {
    // quota exceeded — non-critical
  }
}

export function clearInviteSession(): void {
  if (typeof window === "undefined") return;
  try {
    localStorage.removeItem(INVITE_SESSION_KEY);
  } catch {
    // ignore
  }
}
