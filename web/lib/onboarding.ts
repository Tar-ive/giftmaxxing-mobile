// ────────────────────────────────────────────────────────────────────────────
// Onboarding — user profile + preferences persisted in localStorage.
//
// The onboarding wizard collects taste signals that feed into the
// recommendation engine (lib/recommend.ts, infra/src/handler.mjs).
// When a real auth backend exists, migrate this to the users DynamoDB table
// and hydrate on login instead of reading localStorage.
// ────────────────────────────────────────────────────────────────────────────

import type { ImportantEvent, Recipient } from "@/lib/events";
import { ADMIN_BYPASS, ADMIN_PROFILE } from "@/lib/admin";

export type GiftRole = "giver" | "taker" | "both";
export type GiftDifficulty = "easy" | "moderate" | "hard";
export type GiftStyle = "thoughtful" | "materialistic" | "mix";
export type ProfileVisibility = "public" | "private";

export type MaterialisticCategory =
  | "tech"
  | "fashion"
  | "beauty"
  | "home"
  | "kitchen"
  | "fitness"
  | "travel"
  | "gaming"
  | "jewelry"
  | "books"
  | "music"
  | "art";

export type InterestTag =
  | "cozy"
  | "minimalist"
  | "vintage"
  | "luxury"
  | "outdoors"
  | "foodie"
  | "wellness"
  | "photography"
  | "sustainable"
  | "diy"
  | "pop-culture"
  | "plants"
  | "pets"
  | "stationery"
  | "candles"
  | "coffee-tea";

export type BudgetRange = "budget" | "mid" | "premium" | "no-limit";

export type DealType =
  | "clearance"
  | "flash-sales"
  | "coupons"
  | "price-drops"
  | "bundle-deals"
  | "seasonal"
  | "refurbished"
  | "outlet";

export type DealSensitivity = "deal-hunter" | "value-conscious" | "quality-first" | "splurge";

export type DealPreferences = {
  sensitivity: DealSensitivity;
  budgetRange: BudgetRange;
  dealTypes: DealType[];
  priceAlerts: boolean;
};

export type PinterestLink = {
  profileUrl: string;
  linkedAt: number;
  // TODO(next-agent): after Pinterest OAuth is approved, store tokens here:
  // accessToken?: string;
  // refreshToken?: string;
  // scopes?: string[];
};

export type UserProfile = {
  name: string;
  role: GiftRole;
  difficulty: GiftDifficulty;
  style: GiftStyle;
  materialisticCategories: MaterialisticCategory[];
  interests: InterestTag[];
  dealPreferences: DealPreferences;
  pinterestLinks: PinterestLink[];
  // Event logging (opt-in): recipients the user gives to + their important dates.
  // Drives reminders and biases the feed toward the next upcoming occasion.
  eventLoggingEnabled?: boolean;
  recipients?: Recipient[];
  events?: ImportantEvent[];
  // Profile visibility (public/private). Absent on older saved profiles →
  // treated as "public" by the UI.
  visibility?: ProfileVisibility;
  // Who their feed should lean toward ("show me gifts for him/her/mix") —
  // asked by the concierge onboarding, mapped to a recipient facet on /feed.
  genderPref?: "him" | "her" | "any";
  completedAt: number;
};

const STORAGE_KEY = "giftmaxxing_onboarding";

function isUserProfile(value: unknown): value is UserProfile {
  if (!value || typeof value !== "object") return false;
  const p = value as Partial<UserProfile>;
  return (
    typeof p.name === "string" &&
    p.name.trim().length > 0 &&
    (p.role === "giver" || p.role === "taker" || p.role === "both") &&
    (p.difficulty === "easy" || p.difficulty === "moderate" || p.difficulty === "hard") &&
    (p.style === "thoughtful" || p.style === "materialistic" || p.style === "mix") &&
    Array.isArray(p.interests) &&
    p.interests.length >= 3 &&
    Array.isArray(p.pinterestLinks) &&
    typeof p.completedAt === "number" &&
    !!p.dealPreferences &&
    typeof p.dealPreferences === "object" &&
    ((p.dealPreferences as DealPreferences).sensitivity === "deal-hunter" || (p.dealPreferences as DealPreferences).sensitivity === "value-conscious" || (p.dealPreferences as DealPreferences).sensitivity === "quality-first" || (p.dealPreferences as DealPreferences).sensitivity === "splurge") &&
    ((p.dealPreferences as DealPreferences).budgetRange === "budget" || (p.dealPreferences as DealPreferences).budgetRange === "mid" || (p.dealPreferences as DealPreferences).budgetRange === "premium" || (p.dealPreferences as DealPreferences).budgetRange === "no-limit") &&
    Array.isArray((p.dealPreferences as DealPreferences).dealTypes) &&
    (p.dealPreferences as DealPreferences).dealTypes.every(
      (t: string) => t === "clearance" || t === "flash-sales" || t === "coupons" || t === "price-drops" || t === "bundle-deals" || t === "seasonal" || t === "refurbished" || t === "outlet",
    ) &&
    typeof (p.dealPreferences as DealPreferences).priceAlerts === "boolean"
  );
}

export function loadProfile(): UserProfile | null {
  if (typeof window === "undefined") return null;
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    if (raw) {
      const parsed: unknown = JSON.parse(raw);
      if (isUserProfile(parsed)) return parsed;
    }
  } catch {
    // fall through to the bypass / null below
  }
  // Local dev-only admin session: synthesize a valid profile so the gates pass
  // without onboarding. ADMIN_BYPASS is a compile-time `false` in production.
  return ADMIN_BYPASS ? ADMIN_PROFILE : null;
}

export function saveProfile(profile: UserProfile): boolean {
  if (typeof window === "undefined") return false;
  try {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(profile));
    return true;
  } catch {
    return false;
  }
}

export function clearProfile(): void {
  if (typeof window === "undefined") return;
  localStorage.removeItem(STORAGE_KEY);
}

// Update just the profile's visibility (public/private) and notify listeners
// (the identity hook + AccountSync) via the shared profile event.
export function setProfileVisibility(visibility: ProfileVisibility): boolean {
  const current = loadProfile();
  if (!current) return false;
  const ok = saveProfile({ ...current, visibility });
  if (ok && typeof window !== "undefined") {
    window.dispatchEvent(new Event("giftmaxxing:profile"));
  }
  return ok;
}

export function isOnboardingComplete(): boolean {
  return ADMIN_BYPASS || loadProfile() !== null;
}

// ────────────────────────────────────────────────────────────────────────────
// Display metadata for the interest/category picker chips (Pinterest-style).
// ────────────────────────────────────────────────────────────────────────────

export const INTEREST_META: Record<InterestTag, { label: string; emoji: string }> = {
  cozy: { label: "Cozy vibes", emoji: "🧸" },
  minimalist: { label: "Minimalist", emoji: "◻️" },
  vintage: { label: "Vintage & retro", emoji: "📻" },
  luxury: { label: "Luxury", emoji: "💎" },
  outdoors: { label: "Outdoors", emoji: "🏕️" },
  foodie: { label: "Foodie", emoji: "🍽️" },
  wellness: { label: "Wellness", emoji: "🧘" },
  photography: { label: "Photography", emoji: "📸" },
  sustainable: { label: "Sustainable", emoji: "♻️" },
  diy: { label: "DIY & crafts", emoji: "🎨" },
  "pop-culture": { label: "Pop culture", emoji: "🎬" },
  plants: { label: "Plants", emoji: "🌿" },
  pets: { label: "Pet lover", emoji: "🐾" },
  stationery: { label: "Stationery", emoji: "✏️" },
  candles: { label: "Candles & scents", emoji: "🕯️" },
  "coffee-tea": { label: "Coffee & tea", emoji: "☕" },
};

export const DEAL_SENSITIVITY_META: Record<DealSensitivity, { label: string; desc: string; emoji: string }> = {
  "deal-hunter": { label: "Deal hunter", desc: "I'll wait for the perfect price", emoji: "🏷️" },
  "value-conscious": { label: "Value-conscious", desc: "I want good value, but don't obsess", emoji: "💡" },
  "quality-first": { label: "Quality first", desc: "I'll pay more for the right gift", emoji: "⭐" },
  splurge: { label: "Splurge", desc: "Price isn't a factor for me", emoji: "💳" },
};

export const BUDGET_RANGE_META: Record<BudgetRange, { label: string; emoji: string }> = {
  budget: { label: "Under $25", emoji: "🪙" },
  mid: { label: "$25 – $100", emoji: "💵" },
  premium: { label: "$100 – $300", emoji: "💰" },
  "no-limit": { label: "No limit", emoji: "💎" },
};

export const DEAL_TYPE_META: Record<DealType, { label: string; emoji: string }> = {
  clearance: { label: "Clearance", emoji: "🔥" },
  "flash-sales": { label: "Flash sales", emoji: "⚡" },
  coupons: { label: "Coupons & codes", emoji: "🎟️" },
  "price-drops": { label: "Price drops", emoji: "📉" },
  "bundle-deals": { label: "Bundle deals", emoji: "📦" },
  seasonal: { label: "Seasonal sales", emoji: "🎄" },
  refurbished: { label: "Refurbished", emoji: "♻️" },
  outlet: { label: "Outlet stores", emoji: "🏬" },
};

export const MATERIALISTIC_META: Record<MaterialisticCategory, { label: string; emoji: string }> = {
  tech: { label: "Tech & gadgets", emoji: "💻" },
  fashion: { label: "Fashion", emoji: "👗" },
  beauty: { label: "Beauty & skincare", emoji: "💄" },
  home: { label: "Home decor", emoji: "🏡" },
  kitchen: { label: "Kitchen & cooking", emoji: "🍳" },
  fitness: { label: "Fitness & sports", emoji: "🏋️" },
  travel: { label: "Travel gear", emoji: "✈️" },
  gaming: { label: "Gaming", emoji: "🎮" },
  jewelry: { label: "Jewelry & watches", emoji: "💍" },
  books: { label: "Books", emoji: "📚" },
  music: { label: "Music & vinyl", emoji: "🎵" },
  art: { label: "Art & prints", emoji: "🖼️" },
};
