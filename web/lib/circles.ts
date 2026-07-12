"use client";

// ────────────────────────────────────────────────────────────────────────────
// Gift circles — shared family/friend groups.
//
// One person creates a circle ("Sharma Family"), shares the /circle/<id> link
// in the group chat, and every member adds their name + birthday — no account,
// no app. The circle page becomes the group's gift calendar: whose birthday is
// next, what occasions are coming, and a jumping-off point for group gifts.
//
// The link is the credential (same trust model as invite/challenge links).
// This browser remembers which circles it belongs to (and as whom) in
// localStorage, so "your circles" persists across visits device-locally.
// ────────────────────────────────────────────────────────────────────────────

import { API_BASE, isApiConfigured } from "@/lib/api";

export type CircleMember = {
  memberId: string;
  name: string;
  birthday: string | null; // YYYY-MM-DD
  role: "creator" | "member";
  joinedAt: number;
  /** Signed-in Giftmaxxing account linked to this seat (when claimed). */
  linkedUserId?: string | null;
  linkedHandle?: string | null;
  linkedName?: string | null;
};

export type CircleEvent = {
  eventId: string;
  title: string;
  date: string; // YYYY-MM-DD
  type: string;
  forName: string | null;
  addedBy: string | null;
  createdAt: number;
};

export type Circle = {
  circleId: string;
  name: string;
  emoji: string | null;
  createdAt: number;
};

export type CircleData = {
  circle: Circle;
  members: CircleMember[];
  events: CircleEvent[];
};

// ── API calls ────────────────────────────────────────────────────────────────

export async function createCircle(opts: {
  name: string;
  emoji?: string;
  creator?: { name: string; birthday?: string };
}): Promise<string | null> {
  if (!isApiConfigured()) return null;
  try {
    const res = await fetch(`${API_BASE}/circles`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify(opts),
    });
    if (!res.ok) return null;
    const data = (await res.json()) as { ok?: boolean; circleId?: string };
    return data.circleId ?? null;
  } catch {
    return null;
  }
}

export async function fetchCircle(circleId: string): Promise<CircleData | null> {
  if (!isApiConfigured() || !circleId) return null;
  try {
    const res = await fetch(`${API_BASE}/circles/${encodeURIComponent(circleId)}`, {
      headers: { accept: "application/json" },
    });
    if (!res.ok) return null;
    return (await res.json()) as CircleData;
  } catch {
    return null;
  }
}

export async function joinCircle(
  circleId: string,
  member: { name: string; birthday?: string; userId?: string }
): Promise<boolean> {
  if (!isApiConfigured()) return false;
  try {
    const res = await fetch(`${API_BASE}/circles/${encodeURIComponent(circleId)}/join`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify(member),
    });
    return res.ok;
  } catch {
    return false;
  }
}

export async function addCircleEvent(
  circleId: string,
  event: { title: string; date: string; type?: string; forName?: string; addedBy?: string }
): Promise<boolean> {
  if (!isApiConfigured()) return false;
  try {
    const res = await fetch(`${API_BASE}/circles/${encodeURIComponent(circleId)}/events`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify(event),
    });
    return res.ok;
  } catch {
    return false;
  }
}

export async function deleteCircleEvent(circleId: string, eventId: string): Promise<boolean> {
  if (!isApiConfigured()) return false;
  try {
    const res = await fetch(
      `${API_BASE}/circles/${encodeURIComponent(circleId)}/events/delete`,
      {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ eventId }),
      }
    );
    return res.ok;
  } catch {
    return false;
  }
}

// ── "My circles" — this browser's memberships ───────────────────────────────

const MY_CIRCLES_KEY = "giftmaxxing_my_circles";

export type MyCircle = {
  circleId: string;
  name: string;
  emoji: string | null;
  joinedAs: string | null; // the name you entered when joining
  savedAt: number;
};

export function loadMyCircles(): MyCircle[] {
  if (typeof window === "undefined") return [];
  try {
    const raw = localStorage.getItem(MY_CIRCLES_KEY);
    const list = raw ? (JSON.parse(raw) as MyCircle[]) : [];
    return Array.isArray(list) ? list : [];
  } catch {
    return [];
  }
}

export function rememberCircle(entry: Omit<MyCircle, "savedAt">): void {
  if (typeof window === "undefined") return;
  try {
    const list = loadMyCircles().filter((c) => c.circleId !== entry.circleId);
    list.unshift({ ...entry, savedAt: Date.now() });
    localStorage.setItem(MY_CIRCLES_KEY, JSON.stringify(list.slice(0, 20)));
  } catch {
    // storage full/blocked — the share link still works
  }
}

export function forgetCircle(circleId: string): void {
  if (typeof window === "undefined") return;
  try {
    localStorage.setItem(
      MY_CIRCLES_KEY,
      JSON.stringify(loadMyCircles().filter((c) => c.circleId !== circleId))
    );
  } catch {
    // ignore
  }
}

// ── Date math — "whose gift moment is next?" ────────────────────────────────

/** Next occurrence of a MM-DD (from a full YYYY-MM-DD) on or after today. */
export function nextOccurrence(dateStr: string, from = new Date()): Date | null {
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(dateStr);
  if (!m) return null;
  const [, , mm, dd] = m;
  const month = Number(mm) - 1;
  const day = Number(dd);
  const today = new Date(from.getFullYear(), from.getMonth(), from.getDate());
  let candidate = new Date(from.getFullYear(), month, day);
  // Feb 29 in a non-leap year rolls to Mar 1 (Date handles the overflow).
  if (candidate < today) {
    candidate = new Date(from.getFullYear() + 1, month, day);
  }
  return candidate;
}

export function daysUntil(date: Date, from = new Date()): number {
  const a = new Date(from.getFullYear(), from.getMonth(), from.getDate());
  return Math.round((date.getTime() - a.getTime()) / 86_400_000);
}

/** Age they'll turn on their next birthday, when the year looks real. */
export function turningAge(birthday: string): number | null {
  const m = /^(\d{4})-\d{2}-\d{2}$/.exec(birthday);
  if (!m) return null;
  const year = Number(m[1]);
  if (year < 1900 || year > new Date().getFullYear()) return null;
  const next = nextOccurrence(birthday);
  return next ? next.getFullYear() - year : null;
}

export type UpcomingMoment = {
  key: string;
  kind: "birthday" | "occasion";
  title: string; // "Mom's birthday" / "Parents' anniversary"
  who: string | null;
  date: Date;
  days: number;
  turning: number | null;
  emoji: string;
};

const OCCASION_EMOJI: Record<string, string> = {
  birthday: "🎂",
  anniversary: "💝",
  wedding: "💒",
  graduation: "🎓",
  holiday: "🎄",
  "baby-shower": "🍼",
  farewell: "👋",
  occasion: "✨",
};

/** Every member birthday + shared occasion, as one sorted countdown list. */
export function upcomingMoments(data: CircleData, from = new Date()): UpcomingMoment[] {
  const out: UpcomingMoment[] = [];
  for (const member of data.members) {
    if (!member.birthday) continue;
    const date = nextOccurrence(member.birthday, from);
    if (!date) continue;
    out.push({
      key: `bday-${member.memberId}`,
      kind: "birthday",
      title: `${member.name}'s birthday`,
      who: member.name,
      date,
      days: daysUntil(date, from),
      turning: turningAge(member.birthday),
      emoji: "🎂",
    });
  }
  for (const ev of data.events) {
    const date = nextOccurrence(ev.date, from);
    if (!date) continue;
    out.push({
      key: ev.eventId,
      kind: "occasion",
      title: ev.title,
      who: ev.forName,
      date,
      days: daysUntil(date, from),
      turning: null,
      emoji: OCCASION_EMOJI[ev.type] ?? "✨",
    });
  }
  return out.sort((a, b) => a.days - b.days);
}

export function circleShareUrl(circleId: string): string {
  const base =
    typeof window !== "undefined"
      ? window.location.origin
      : process.env.NEXT_PUBLIC_SITE_URL ?? "";
  return `${base}/circle/${circleId}`;
}
