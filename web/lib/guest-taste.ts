// ────────────────────────────────────────────────────────────────────────────
// Guest taste — the recipient-entry warm start (research doc §9.1, gap G1).
//
// When someone lands on an invite link and swipes a challenge deck, those
// swipes are THEIR taste, not just the sender's intel. The server persists a
// copy under this browser's anon id (claimed into the account at signup); this
// module keeps the local mirror so the very next page this guest sees — the
// reveal, the feed teaser, onboarding — can seed vector recommendations
// immediately, no account required.
// ────────────────────────────────────────────────────────────────────────────

const KEY = "giftmaxxing_guest_taste";
const SEED_CAP = 24;

export type GuestGiftTypeSplit = {
  productYes?: number;
  productTotal?: number;
  serviceYes?: number;
  serviceTotal?: number;
  productYesRate?: number | null;
  serviceYesRate?: number | null;
};

export type GuestTaste = {
  seeds: string[]; // yes-swiped pin keys, newest first (vector-recs seeds)
  topCategories: string[];
  priceBand?: { min: number; median: number; max: number } | null;
  giftTypeSplit?: GuestGiftTypeSplit | null;
  updatedAt: number;
};

export function loadGuestTaste(): GuestTaste | null {
  if (typeof window === "undefined") return null;
  try {
    const raw = localStorage.getItem(KEY);
    if (!raw) return null;
    const parsed = JSON.parse(raw) as GuestTaste;
    return Array.isArray(parsed?.seeds) ? parsed : null;
  } catch {
    return null;
  }
}

/** Merge a challenge reveal into the stored guest taste (seeds deduped, capped). */
export function mergeGuestTaste(update: {
  seeds?: string[];
  topCategories?: string[];
  priceBand?: GuestTaste["priceBand"];
  giftTypeSplit?: GuestGiftTypeSplit | null;
}): GuestTaste | null {
  if (typeof window === "undefined") return null;
  try {
    const current = loadGuestTaste();
    const seeds = [
      ...(update.seeds ?? []),
      ...(current?.seeds ?? []),
    ].filter((s, i, all) => !!s && all.indexOf(s) === i).slice(0, SEED_CAP);
    const merged: GuestTaste = {
      seeds,
      topCategories: update.topCategories?.length
        ? update.topCategories
        : current?.topCategories ?? [],
      priceBand: update.priceBand ?? current?.priceBand ?? null,
      giftTypeSplit: update.giftTypeSplit ?? current?.giftTypeSplit ?? null,
      updatedAt: Date.now(),
    };
    localStorage.setItem(KEY, JSON.stringify(merged));
    return merged;
  } catch {
    return null;
  }
}

export function clearGuestTaste(): void {
  if (typeof window === "undefined") return;
  try {
    localStorage.removeItem(KEY);
  } catch {
    // ignore
  }
}
