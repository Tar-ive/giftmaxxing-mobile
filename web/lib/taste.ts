// ────────────────────────────────────────────────────────────────────────────
// Canonical taste mapping.
//
// The app has three taste vocabularies that never lined up:
//   • onboarding `interests` (InterestTag) + `materialisticCategories`
//   • the bundled pin `category` (lib/pins.ts)
//   • the ranker `vibes` (lib/recommend.ts, infra/src/handler.mjs)
//
// This module is the single source of truth that maps the onboarding signals a
// user actually picks onto the pin `category` vocabulary the home feed is built
// from, so the feed can be biased toward what they chose during onboarding.
// ────────────────────────────────────────────────────────────────────────────

import type { UserProfile, BudgetRange } from "@/lib/onboarding";

// Pin categories that actually exist in lib/pins.ts (the bias targets):
//   plants, home, gifts, jewelry, kitchen, sports, tech, wellness, vintage, travel, art
//
// Onboarding token (InterestTag | MaterialisticCategory, lowercased) → the pin
// categories it implies. The first entry is the strongest association.
const TASTE_TO_CATEGORIES: Record<string, string[]> = {
  // ── InterestTag ──
  cozy: ["home", "plants", "wellness"],
  minimalist: ["home", "tech", "art"],
  vintage: ["vintage", "art", "jewelry"],
  luxury: ["jewelry", "vintage"],
  outdoors: ["sports", "travel", "plants"],
  foodie: ["kitchen"],
  wellness: ["wellness", "plants"],
  photography: ["art", "tech"],
  sustainable: ["plants", "home"],
  diy: ["art", "home", "kitchen"],
  "pop-culture": ["tech", "gifts"],
  plants: ["plants"],
  pets: ["gifts", "home"],
  stationery: ["art"],
  candles: ["home"],
  "coffee-tea": ["kitchen"],
  // ── MaterialisticCategory ──
  tech: ["tech"],
  fashion: ["jewelry", "vintage"],
  beauty: ["wellness", "jewelry", "vintage"],
  home: ["home", "plants"],
  kitchen: ["kitchen"],
  fitness: ["sports", "wellness"],
  travel: ["travel"],
  gaming: ["tech"],
  jewelry: ["jewelry"],
  books: ["art", "gifts"],
  music: ["art", "gifts"],
  art: ["art"],
};

// Mild price band per onboarding budget preference. Used only to gently nudge
// ordering — never to filter pins out.
const BUDGET_BANDS: Record<BudgetRange, [number, number]> = {
  budget: [0, 45],
  mid: [25, 110],
  premium: [80, Number.MAX_SAFE_INTEGER],
  "no-limit": [0, Number.MAX_SAFE_INTEGER],
};

export type Taste = {
  // pin category → weight (higher = stronger preference)
  categories: Record<string, number>;
  priceLo: number;
  priceHi: number;
  hasSignal: boolean; // false on cold start → feed falls back to the neutral shuffle
  topCategory: string | null;
};

// Build a Taste from the saved onboarding profile (null → no signal).
export function tasteFromProfile(profile: UserProfile | null): Taste {
  const categories: Record<string, number> = {};
  if (profile) {
    const tokens = [
      ...(profile.interests ?? []),
      ...(profile.materialisticCategories ?? []),
    ].map((t) => String(t).toLowerCase());
    for (const tok of tokens) {
      const cats = TASTE_TO_CATEGORIES[tok];
      if (!cats) continue;
      // First mapped category counts full; softer associations count half.
      cats.forEach((c, i) => {
        categories[c] = (categories[c] ?? 0) + (i === 0 ? 1 : 0.5);
      });
    }
  }
  const band = profile ? BUDGET_BANDS[profile.dealPreferences.budgetRange] : null;
  const ranked = Object.entries(categories).sort((a, b) => b[1] - a[1]);
  return {
    categories,
    priceLo: band ? band[0] : 0,
    priceHi: band ? band[1] : Number.MAX_SAFE_INTEGER,
    hasSignal: ranked.length > 0,
    topCategory: ranked[0]?.[0] ?? null,
  };
}

// ── Profile → live-feed query params ────────────────────────────────────────
// The bundled feed personalizes via scorePinForTaste; the LIVE API feed needs
// its signals as /feed facets. Interests map onto the server's vibe vocabulary
// (see infra scorePost), genderPref onto a catalog recipient facet.

const INTEREST_TO_VIBE: Record<string, string> = {
  cozy: "cozy",
  minimalist: "minimal",
  vintage: "retro",
  luxury: "luxe",
  outdoors: "outdoors",
  foodie: "foodie",
  wellness: "wellness",
  photography: "tech",
  sustainable: "calm",
  diy: "diy",
  "pop-culture": "retro",
  plants: "home",
  pets: "warm",
  stationery: "stationery",
  candles: "home",
  "coffee-tea": "kitchen",
};

export function feedPersonalization(profile: UserProfile | null): {
  vibes?: string[];
  recipient?: string;
} {
  if (!profile) return {};
  const vibes: string[] = [];
  for (const tag of profile.interests ?? []) {
    const v = INTEREST_TO_VIBE[String(tag).toLowerCase()];
    if (v && !vibes.includes(v)) vibes.push(v);
  }
  // Catalog facets are relationship-flavored; "him" has a direct match.
  const recipient =
    profile.genderPref === "him" ? "men" : profile.genderPref === "her" ? "women" : undefined;
  return {
    vibes: vibes.length ? vibes.slice(0, 6) : undefined,
    recipient,
  };
}

// Affinity of a single pin to the taste. ~[-0.15, 1.5]; 0 when no signal.
export function scorePinForTaste(
  pin: { category: string; price: number },
  taste: Taste
): number {
  if (!taste.hasSignal) return 0;
  let s = taste.categories[pin.category] ?? 0; // category match dominates
  // mild price fit: in-band gets a small bump, far outside a small penalty
  s += pin.price >= taste.priceLo && pin.price <= taste.priceHi ? 0.25 : -0.15;
  return s;
}

// Did the user explicitly express interest in this pin's category?
export function tasteMatchesPin(pin: { category: string }, taste: Taste): boolean {
  return taste.hasSignal && (taste.categories[pin.category] ?? 0) > 0;
}
