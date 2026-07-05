// ────────────────────────────────────────────────────────────────────────────
// Event logging — recipients + important dates (birthdays, anniversaries, …).
//
// This is the "who do you shop for, and when" layer. It is intentionally
// framework-free (pure types + functions) so it can be used in:
//   • the onboarding wizard (collect dates)                  — web/app/onboarding
//   • the recommendation feed (bias toward the next event)   — web/components/app/store
//   • Maxi / drops / bundles (recipient + occasion + budget) — web/lib/*
//   • the server reminder job (X days before)                — infra/src/reminders.mjs
//
// Persistence today: stored on the UserProfile in localStorage (lib/onboarding.ts)
// and mirrored to the `users` DynamoDB table once signed in (lib/api.ts saveMe()).
// The DynamoDB item shape is exactly { userId, ...UserProfile }, so `recipients`
// and `events` ride along with the rest of the profile — no schema migration.
// ────────────────────────────────────────────────────────────────────────────

export type RelationType =
  | "partner"
  | "spouse"
  | "parent"
  | "child"
  | "sibling"
  | "friend"
  | "coworker"
  | "self"
  | "other";

export type EventType =
  | "birthday"
  | "anniversary"
  | "wedding"
  | "valentines"
  | "mothers-day"
  | "fathers-day"
  | "graduation"
  | "housewarming"
  | "holiday"
  | "baby-shower"
  | "other";

export type Recurrence = "annual" | "once";

// A person the user gives gifts to. `sourceUser` / `pinSeeds` link this person's
// taste into the vector recommender (handler.mjs filters kNN by `sourceUser`).
export type Recipient = {
  id: string;
  name: string;
  relation: RelationType;
  sourceUser?: string; // e.g. a linked Pinterest handle representing their taste
  pinSeeds?: string[]; // seed pin keys that represent their taste
  interests?: string[]; // interest tags (mirrors onboarding InterestTag)
};

// An important date tied to a recipient. `date` is ISO "YYYY-MM-DD"; for annual
// recurrence the year is ignored when computing the next occurrence.
export type ImportantEvent = {
  id: string;
  recipientId: string; // FK → Recipient.id
  type: EventType;
  date: string; // "YYYY-MM-DD"
  recurrence: Recurrence;
  reminderLeadDays: number; // notify this many days before
  budget?: number; // optional target spend for this gift
  note?: string;
};

// ── Display metadata for the dropdowns ───────────────────────────────────────
// `recipientKey` maps our relation onto the Reddit-mined `knowledge` table /
// `scorePost` recipient facet; `occasion` maps an event type onto the occasion
// facet. Unknown/none → "anyone"/"any", which the ranker treats as a no-op.

export const RELATION_META: Record<
  RelationType,
  { label: string; emoji: string; recipientKey: string }
> = {
  partner: { label: "Partner / Girlfriend / Boyfriend", emoji: "💞", recipientKey: "partner" },
  spouse: { label: "Spouse (wife / husband)", emoji: "💍", recipientKey: "partner" },
  parent: { label: "Parent (mom / dad)", emoji: "👪", recipientKey: "parent" },
  child: { label: "Child / Kid", emoji: "🧒", recipientKey: "kids" },
  sibling: { label: "Sibling", emoji: "🧑‍🤝‍🧑", recipientKey: "sibling" },
  friend: { label: "Friend", emoji: "🫂", recipientKey: "friend" },
  coworker: { label: "Coworker", emoji: "💼", recipientKey: "coworker" },
  self: { label: "Myself", emoji: "🙋", recipientKey: "self" },
  other: { label: "Someone else", emoji: "🎁", recipientKey: "anyone" },
};

export const EVENT_TYPE_META: Record<
  EventType,
  { label: string; emoji: string; occasion: string }
> = {
  birthday: { label: "Birthday", emoji: "🎂", occasion: "birthday" },
  anniversary: { label: "Anniversary", emoji: "💝", occasion: "anniversary" },
  wedding: { label: "Wedding", emoji: "💒", occasion: "wedding" },
  valentines: { label: "Valentine's Day", emoji: "🌹", occasion: "valentines-day" },
  "mothers-day": { label: "Mother's Day", emoji: "🌷", occasion: "mothers-day" },
  "fathers-day": { label: "Father's Day", emoji: "🧔", occasion: "fathers-day" },
  graduation: { label: "Graduation", emoji: "🎓", occasion: "graduation" },
  housewarming: { label: "Housewarming", emoji: "🏡", occasion: "housewarming" },
  holiday: { label: "Holiday / Christmas", emoji: "🎄", occasion: "holiday" },
  "baby-shower": { label: "Baby shower", emoji: "🍼", occasion: "baby-shower" },
  other: { label: "Other occasion", emoji: "✨", occasion: "any" },
};

export const RECURRENCE_META: Record<Recurrence, { label: string; emoji: string }> = {
  annual: { label: "Every year", emoji: "🔁" },
  once: { label: "One time", emoji: "📌" },
};

// ── ID helper ────────────────────────────────────────────────────────────────
export function genId(prefix = "id"): string {
  try {
    if (typeof crypto !== "undefined" && "randomUUID" in crypto) {
      return `${prefix}_${crypto.randomUUID()}`;
    }
  } catch {
    /* fall through */
  }
  return `${prefix}_${Date.now().toString(36)}${Math.random().toString(36).slice(2, 8)}`;
}

// ── Date math (timezone-safe; operates on local calendar days) ────────────────
function startOfDay(from: Date): Date {
  return new Date(from.getFullYear(), from.getMonth(), from.getDate());
}

// ── Natural-language date entry ("3/14", "March 14", "14 march 1998") ────────
// Used by the conversational onboarding's events loop. Bare dates and past
// years (birth years) roll forward to the next occurrence; an explicit
// current/future year is preserved and reported via futureYearGiven so the
// caller can decide between annual and one-off recurrence.

const MONTH_ABBR = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"];
const MONTH_FULL = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"];

export type ParsedDateText = { iso: string; label: string; futureYearGiven: boolean };

export function parseEventDateText(raw: string, now = new Date()): ParsedDateText | null {
  const t = raw.trim().toLowerCase();
  let m: number | null = null;
  let d: number | null = null;
  let y: number | null = null;

  let match = /^(\d{4})-(\d{1,2})-(\d{1,2})$/.exec(t); // ISO
  if (match) [y, m, d] = [Number(match[1]), Number(match[2]), Number(match[3])];
  if (m == null) {
    match = /^(\d{1,2})[/.-](\d{1,2})(?:[/.-](\d{2,4}))?$/.exec(t); // 3/14[/1998]
    if (match) {
      m = Number(match[1]);
      d = Number(match[2]);
      y = match[3] && match[3].length === 4 ? Number(match[3]) : null;
    }
  }
  if (m == null) {
    // "march 14 [1998]" or "14 march [1998]"
    match = /^([a-z]+)\s+(\d{1,2})(?:\s*,?\s*(\d{4}))?$/.exec(t) ?? null;
    let monthToken: string | undefined;
    let dayToken: string | undefined;
    let yearToken: string | undefined;
    if (match) [monthToken, dayToken, yearToken] = [match[1], match[2], match[3]];
    else {
      match = /^(\d{1,2})(?:st|nd|rd|th)?\s+(?:of\s+)?([a-z]+)(?:\s*,?\s*(\d{4}))?$/.exec(t);
      if (match) [dayToken, monthToken, yearToken] = [match[1], match[2], match[3]];
    }
    if (monthToken && dayToken) {
      const mi = MONTH_ABBR.findIndex((mn) => monthToken.startsWith(mn));
      if (mi >= 0) {
        m = mi + 1;
        d = Number(dayToken);
        y = yearToken ? Number(yearToken) : null;
      }
    }
  }

  if (m == null || d == null || m < 1 || m > 12 || d < 1 || d > 31) return null;
  const futureYearGiven = y != null && y >= now.getFullYear();
  if (y == null || y < now.getFullYear()) {
    const today = startOfDay(now);
    y =
      new Date(now.getFullYear(), m - 1, d).getTime() < today.getTime()
        ? now.getFullYear() + 1
        : now.getFullYear();
  }
  const iso = `${y}-${String(m).padStart(2, "0")}-${String(d).padStart(2, "0")}`;
  const label = `${MONTH_FULL[m - 1]} ${d}${futureYearGiven ? `, ${y}` : ""}`;
  return { iso, label, futureYearGiven };
}

export function parseISODate(iso: string): { y: number; m: number; d: number } | null {
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec((iso ?? "").trim());
  if (!match) return null;
  const y = Number(match[1]);
  const m = Number(match[2]);
  const d = Number(match[3]);
  if (m < 1 || m > 12 || d < 1 || d > 31) return null;
  return { y, m, d };
}

// The next calendar date this event lands on (annual → roll forward a year if
// it already passed this year). Returns null on a malformed date.
export function nextOccurrence(event: ImportantEvent, from = new Date()): Date | null {
  const p = parseISODate(event.date);
  if (!p) return null;
  if (event.recurrence === "once") return new Date(p.y, p.m - 1, p.d);

  const today = startOfDay(from);
  let candidate = new Date(today.getFullYear(), p.m - 1, p.d);
  if (candidate.getTime() < today.getTime()) {
    candidate = new Date(today.getFullYear() + 1, p.m - 1, p.d);
  }
  return candidate;
}

// Whole days from today until the next occurrence (0 = today). For a one-time
// event already in the past this is negative.
export function daysUntil(event: ImportantEvent, from = new Date()): number | null {
  const next = nextOccurrence(event, from);
  if (!next) return null;
  const today = startOfDay(from);
  return Math.round((next.getTime() - today.getTime()) / 86_400_000);
}

export type DatedEvent = { event: ImportantEvent; days: number };

// Upcoming events sorted soonest-first. `withinDays <= 0` removes the upper bound.
export function upcomingEvents(
  events: ImportantEvent[],
  withinDays = 90,
  from = new Date()
): DatedEvent[] {
  return (events ?? [])
    .map((event) => ({ event, days: daysUntil(event, from) }))
    .filter(
      (x): x is DatedEvent =>
        x.days != null && x.days >= 0 && (withinDays <= 0 || x.days <= withinDays)
    )
    .sort((a, b) => a.days - b.days);
}

export function nextUpcomingEvent(
  events: ImportantEvent[],
  from = new Date()
): ImportantEvent | null {
  const up = upcomingEvents(events, 0, from);
  return up.length ? up[0].event : null;
}

const MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];

export function formatEventDate(event: ImportantEvent): string {
  const p = parseISODate(event.date);
  if (!p) return "";
  const base = `${MONTHS[p.m - 1]} ${p.d}`;
  return event.recurrence === "once" ? `${base}, ${p.y}` : base;
}

export function relationFor(
  event: ImportantEvent,
  recipients: Recipient[]
): Recipient | undefined {
  return (recipients ?? []).find((r) => r.id === event.recipientId);
}

// ── Feed bridge ──────────────────────────────────────────────────────────────
// Resolve the next upcoming event into the params the recommender already
// understands (recipient / occasion / sourceUser / budget). `eventBoost` rises
// as the event nears so the ranker can weight recipient+occasion matches harder.
export type FeedEventContext = {
  recipient?: string;
  occasion?: string;
  sourceUser?: string;
  budget?: number;
  eventInDays?: number;
  eventBoost?: number; // 0..1, 1 = imminent
  recipientName?: string;
  recipientId?: string; // the saved Recipient.id (deep-links Shop gifts to them)
  interests?: string[]; // the recipient's interest tags (for personalized picks)
  eventType?: EventType;
};

export function feedContextFromEvents(
  events: ImportantEvent[],
  recipients: Recipient[],
  from = new Date()
): FeedEventContext | null {
  const next = nextUpcomingEvent(events, from);
  if (!next) return null;
  const r = relationFor(next, recipients);
  const days = daysUntil(next, from) ?? undefined;
  // Boost ramps from 0 (≥45 days out) to 1 (today). Linear, clamped.
  const eventBoost =
    days == null ? 0 : Math.max(0, Math.min(1, 1 - days / 45));

  const recipientKey = r ? RELATION_META[r.relation]?.recipientKey : undefined;
  const occasion = EVENT_TYPE_META[next.type]?.occasion;
  return {
    recipient: recipientKey && recipientKey !== "anyone" ? recipientKey : undefined,
    occasion: occasion && occasion !== "any" ? occasion : undefined,
    sourceUser: r?.sourceUser,
    budget: next.budget,
    eventInDays: days,
    eventBoost,
    recipientName: r?.name,
    recipientId: r?.id,
    interests: r?.interests,
    eventType: next.type,
  };
}
