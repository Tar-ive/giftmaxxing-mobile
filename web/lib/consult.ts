// ────────────────────────────────────────────────────────────────────────────
// The Gift Consult — how a friend who's *good at gifts* actually helps you.
//
// You don't hand a friend a settings form; they ask you a handful of sharp
// questions ("who's it for?", "what do they do on a free Sunday?") and then
// say "get them THIS." This module is that consult, as data + pure functions:
//
//   • QUESTIONS      — the conversation script (rendered by <ChatFlow/>)
//   • deriveSignals  — answers → catalog categories, vibes, facets
//   • moveTest       — the quality bar: "if they moved, would they PACK it?"
//   • rankGifts      — merge facet match + budget fit + move-test → shortlist
//
// Framework-free on purpose (mirrors lib/events.ts): the iOS app implements
// this same file 1:1 in Swift. See docs/intentional-gifting.md for the spec.
// ────────────────────────────────────────────────────────────────────────────

import type { Post } from "@/lib/social";
import type { BudgetRange, InterestTag, UserProfile } from "@/lib/onboarding";

// ── Answers collected by the consult ─────────────────────────────────────────

export type ConsultRelation =
  | "partner"
  | "mom"
  | "dad"
  | "sibling"
  | "friend"
  | "coworker"
  | "kid"
  | "other";

export type ConsultAnswers = {
  relation: ConsultRelation;
  name?: string; // what to call them ("Maya") — personalizes every line after
  occasion: string; // occasion facet key ("birthday" … "any")
  budget?: number; // dollars, hard ceiling ×1.15 — absent = "just find the gift"
  worlds: WorldKey[]; // what fills their shelves/time
  sunday?: string; // free text: what they do with a free Sunday
  keeper: KeeperKey; // what they'd never leave behind in a move
};

// ── Q1 relation → the catalog's recipient facet (soft boost server-side) ─────

export const CONSULT_RELATIONS: Record<
  ConsultRelation,
  { label: string; emoji: string; recipientKey: string }
> = {
  partner: { label: "My partner", emoji: "💞", recipientKey: "partner" },
  mom: { label: "My mom", emoji: "🌷", recipientKey: "mom" },
  dad: { label: "My dad", emoji: "🧢", recipientKey: "dad" },
  sibling: { label: "My sibling", emoji: "🧑‍🤝‍🧑", recipientKey: "anyone" },
  friend: { label: "A friend", emoji: "🫂", recipientKey: "friend" },
  coworker: { label: "A coworker", emoji: "💼", recipientKey: "coworker" },
  kid: { label: "A kid", emoji: "🧒", recipientKey: "kids" },
  other: { label: "Someone else", emoji: "🎁", recipientKey: "anyone" },
};

// ── Q3 occasions (occasion facet keys match the posts table) ─────────────────

export const CONSULT_OCCASIONS: { key: string; label: string; emoji: string }[] = [
  { key: "birthday", label: "Birthday", emoji: "🎂" },
  { key: "anniversary", label: "Anniversary", emoji: "💝" },
  { key: "housewarming", label: "Housewarming", emoji: "🏡" },
  { key: "wedding", label: "Wedding", emoji: "💒" },
  { key: "graduation", label: "Graduation", emoji: "🎓" },
  { key: "holiday", label: "Holidays", emoji: "🎄" },
  { key: "any", label: "Just because", emoji: "✨" },
];

// ── Q4 "their world" — multi-select, mapped onto real catalog categories ─────

export type WorldKey =
  | "kitchen"
  | "home"
  | "style"
  | "jewelry"
  | "making"
  | "tech"
  | "outdoors"
  | "wellness"
  | "books"
  | "music"
  | "pets"
  | "games";

export const CONSULT_WORLDS: Record<
  WorldKey,
  { label: string; emoji: string; categories: string[]; vibes: string[] }
> = {
  kitchen: { label: "Cooks & hosts", emoji: "🍳", categories: ["kitchen", "drinkware", "food"], vibes: ["kitchen", "foodie"] },
  home: { label: "Homebody", emoji: "🛋️", categories: ["home", "garden"], vibes: ["cozy", "home"] },
  style: { label: "Fashion & style", emoji: "🧥", categories: ["fashion", "accessories"], vibes: ["minimal", "luxe"] },
  jewelry: { label: "Jewelry & keepsakes", emoji: "💍", categories: ["jewelry"], vibes: ["luxe", "romantic"] },
  making: { label: "Art & making things", emoji: "🎨", categories: ["art", "art_handmade", "stationery"], vibes: ["aesthetic", "diy"] },
  tech: { label: "Tech & gadgets", emoji: "🔌", categories: ["tech", "photography"], vibes: ["tech"] },
  outdoors: { label: "Outdoorsy", emoji: "🏕️", categories: ["outdoors", "fitness", "garden"], vibes: ["outdoors"] },
  wellness: { label: "Wellness & self-care", emoji: "🧘", categories: ["wellness", "beauty"], vibes: ["calm", "wellness", "beauty"] },
  books: { label: "Books & words", emoji: "📚", categories: ["books", "stationery"], vibes: ["calm", "stationery"] },
  music: { label: "Music", emoji: "🎶", categories: ["music"], vibes: ["retro"] },
  pets: { label: "Pet person", emoji: "🐾", categories: ["pets"], vibes: ["warm"] },
  games: { label: "Games & play", emoji: "🎲", categories: ["games", "kids"], vibes: ["retro"] },
};

// ── Q5 free-text "free Sunday" → categories (keyword sweep) ──────────────────

const SUNDAY_HINTS: [RegExp, WorldKey][] = [
  [/cook|bak(e|ing)|recipe|dinner|brunch|host|kitchen|coffee|tea|barista|sourdough/i, "kitchen"],
  [/garden|plant|repot|flower/i, "home"],
  [/thrift|outfit|closet|fashion|shop|style/i, "style"],
  [/paint|draw|sketch|craft|pottery|ceramic|knit|crochet|sew|journal|scrapbook|diy|make/i, "making"],
  [/code|computer|gadget|camera|photo|film|game(?!s? night)|pc|tinker|3d print/i, "tech"],
  [/hik(e|ing)|climb|run|bike|camp|fish|trail|gym|lift|yoga(?! mat)|surf|ski/i, "outdoors"],
  [/spa|skincare|meditat|self.?care|bath|nap|massage/i, "wellness"],
  [/read|book|library|write|poetry|words/i, "books"],
  [/music|vinyl|record|concert|guitar|piano|playlist/i, "music"],
  [/dog|cat|pet|puppy|kitten/i, "pets"],
  [/board game|puzzle|chess|dnd|d&d|games? night|lego/i, "games"],
  [/decorat|candle|cozy|blanket|movie|netflix|home/i, "home"],
];

export function parseSunday(text: string): WorldKey[] {
  const hits = new Set<WorldKey>();
  for (const [re, world] of SUNDAY_HINTS) if (re.test(text)) hits.add(world);
  return [...hits];
}

// ── Q6 the keeper question — calibrates the move-test ────────────────────────
// "Think of the last time they moved. What came with them, no question?"
// Their answer tells us which DURABLE cluster this person actually values.

export type KeeperKey = "kitchen" | "keepsakes" | "shelf" | "setup" | "comfort" | "light";

export const CONSULT_KEEPERS: Record<
  KeeperKey,
  { label: string; emoji: string; boostCategories: string[] }
> = {
  kitchen: { label: "Their kitchen gear", emoji: "🍳", boostCategories: ["kitchen", "drinkware"] },
  keepsakes: { label: "Jewelry & keepsakes", emoji: "💍", boostCategories: ["jewelry", "art_handmade"] },
  shelf: { label: "Books & art", emoji: "🖼️", boostCategories: ["books", "art", "music"] },
  setup: { label: "Their tech setup", emoji: "🖥️", boostCategories: ["tech", "photography", "games"] },
  comfort: { label: "The comfort things", emoji: "🕯️", boostCategories: ["home", "wellness"] },
  light: { label: "Honestly? They travel light", emoji: "🎒", boostCategories: [] },
};

// ── Signals: everything the answers imply, in one derived object ─────────────

export type ConsultSignals = {
  recipientKey: string; // recipient facet for GET /feed (soft boost)
  occasion: string; // occasion facet
  budget?: number;
  categories: string[]; // ordered, deduped — strongest first
  vibes: string[];
  minimalist: boolean; // "travels light" → smaller, quieter, more useful gifts
};

export function deriveSignals(a: ConsultAnswers): ConsultSignals {
  const worlds: WorldKey[] = [...a.worlds, ...parseSunday(a.sunday ?? "")];
  const seen = new Set<string>();
  const categories: string[] = [];
  const vibes = new Set<string>();
  for (const w of worlds) {
    const meta = CONSULT_WORLDS[w];
    if (!meta) continue;
    for (const c of meta.categories) if (!seen.has(c)) { seen.add(c); categories.push(c); }
    for (const v of meta.vibes) vibes.add(v);
  }
  // The keeper answer front-loads what this person provably holds onto.
  const keeper = CONSULT_KEEPERS[a.keeper];
  const ordered = [
    ...keeper.boostCategories.filter((c) => seen.has(c)),
    ...categories.filter((c) => !keeper.boostCategories.includes(c)),
  ];
  return {
    recipientKey: CONSULT_RELATIONS[a.relation]?.recipientKey ?? "anyone",
    occasion: a.occasion,
    budget: a.budget,
    categories: ordered.length ? ordered : keeper.boostCategories,
    vibes: [...vibes],
    minimalist: a.keeper === "light",
  };
}

// ── The move test ─────────────────────────────────────────────────────────────
// The bar for a good gift: "If they were moving, would this make it into the
// box?" Durable, daily-use, personal things pass. Novelty and clutter don't.

export type MoveVerdict = "pack" | "probably" | "clutter";

export type MoveTestResult = {
  score: number; // 0..1
  verdict: MoveVerdict;
  reasons: string[]; // human-readable "why" (surfaced on the card)
};

// How likely a category survives a move, on priors alone.
const CATEGORY_DURABILITY: Record<string, number> = {
  jewelry: 0.9,
  kitchen: 0.8,
  books: 0.8,
  art: 0.75,
  art_handmade: 0.8,
  music: 0.75,
  tech: 0.7,
  photography: 0.7,
  home: 0.68,
  drinkware: 0.65,
  garden: 0.6,
  outdoors: 0.62,
  games: 0.6,
  pets: 0.55,
  fashion: 0.55,
  accessories: 0.55,
  stationery: 0.5,
  fitness: 0.55,
  kids: 0.5,
  wellness: 0.45,
  food: 0.3, // consumable — gone before any move
  beauty: 0.35, // consumable
  gifts: 0.5,
  misc: 0.5,
};

const KEEP_SIGNALS: [RegExp, number, string][] = [
  [/personali[sz]ed|custom|engraved|monogram|initial/i, 0.15, "made for them specifically"],
  [/handmade|hand.?crafted|artisan/i, 0.12, "handmade — has a story"],
  [/solid wood|walnut|oak|leather|ceramic|cast iron|stoneware|brass|copper|linen|marble|wool/i, 0.1, "real materials that age well"],
  [/heirloom|keepsake|forever|lifetime/i, 0.15, "built to be kept"],
  [/\bset\b|kit\b/i, 0.04, "a complete set, not a spare part"],
  [/mug|knife|blanket|throw|lamp|vase|board|journal|tote|necklace|ring|bracelet|watch|frame|print|planter|candle holder|book(?:ends)?/i, 0.06, "something they'd actually use"],
];

const CLUTTER_SIGNALS: [RegExp, number, string][] = [
  [/novelty|gag|prank|funny mug|joke/i, 0.35, "novelty wears off in a week"],
  [/figurine|trinket|knick.?knack|desk toy/i, 0.2, "shelf clutter risk"],
  [/plastic|disposable|single.?use/i, 0.15, "won't survive a year, let alone a move"],
  [/keychain|sticker|magnet/i, 0.15, "too small to register"],
];

export function moveTest(item: {
  name: string;
  category?: string | null;
  price: number;
}): MoveTestResult {
  const reasons: string[] = [];
  let score = CATEGORY_DURABILITY[item.category ?? "misc"] ?? 0.5;

  for (const [re, boost, why] of KEEP_SIGNALS) {
    if (re.test(item.name)) {
      score += boost;
      if (reasons.length < 2) reasons.push(why);
    }
  }
  for (const [re, penalty, why] of CLUTTER_SIGNALS) {
    if (re.test(item.name)) {
      score -= penalty;
      reasons.push(why);
    }
  }
  // Sub-$12 items skew trinket unless the text says otherwise.
  if (item.price > 0 && item.price < 12) {
    score -= 0.1;
    if (!reasons.length) reasons.push("price says trinket");
  }

  score = Math.max(0, Math.min(1, score));
  const verdict: MoveVerdict = score >= 0.7 ? "pack" : score >= 0.5 ? "probably" : "clutter";
  if (!reasons.length) {
    reasons.push(
      verdict === "pack"
        ? "the kind of thing that makes it into the box"
        : verdict === "probably"
          ? "useful enough to keep around"
          : "might not survive their next move",
    );
  }
  return { score, verdict, reasons };
}

export const MOVE_VERDICT_META: Record<MoveVerdict, { label: string; emoji: string }> = {
  pack: { label: "Would pack it", emoji: "📦" },
  probably: { label: "Keeps it", emoji: "👍" },
  clutter: { label: "Clutter risk", emoji: "⚠️" },
};

// ── Ranking: consult signals + move test → the shortlist ────────────────────

export type RankedGift = {
  post: Post;
  score: number;
  move: MoveTestResult;
  why: string; // one personalized line for the card
};

const BUDGET_CEILING = 1.15; // a friend will stretch you 15%, no more

export function rankGifts(posts: Post[], a: ConsultAnswers, n = 9): RankedGift[] {
  const sig = deriveSignals(a);
  const catRank = new Map(sig.categories.map((c, i) => [c, i]));
  const seen = new Set<string>();
  const out: RankedGift[] = [];

  for (const post of posts) {
    if (seen.has(post.id)) continue;
    seen.add(post.id);
    const price = post.product.price;
    if (!price) continue;
    if (a.budget != null && price > a.budget * BUDGET_CEILING) continue;

    const move = moveTest({ name: post.product.name, category: postCategory(post), price });
    // A consult never recommends something failing its own bar.
    if (move.verdict === "clutter") continue;

    // Interest match: earlier in the derived category order = closer to who
    // they are. No category signal at all still competes on the move test.
    const rank = catRank.get(postCategory(post) ?? "");
    const interest = rank == null ? 0.25 : Math.max(0.4, 1 - rank * 0.15);

    // Budget fit: spending real budget beats a token spend on big budgets.
    // No budget given → neutral fit; the move test + interests decide alone.
    const fit =
      a.budget == null
        ? 0.7
        : price <= a.budget
          ? 0.7 + 0.3 * Math.min(1, price / (a.budget * 0.45))
          : 0.55; // inside the stretch zone

    // Minimalists ("travels light") get extra move-test weight — the gift has
    // to EARN space in their life.
    const wMove = sig.minimalist ? 0.55 : 0.45;
    const score = wMove * move.score + 0.35 * interest + (1 - wMove - 0.35) * fit;

    out.push({ post, score, move, why: whyLine(post, a, rank != null) });
  }

  out.sort((x, y) => y.score - x.score);
  // Variety pass: max 3 per category so one strong facet can't fill the page.
  const byCat: Record<string, number> = {};
  const picked: RankedGift[] = [];
  for (const g of out) {
    const c = postCategory(g.post) ?? "misc";
    if ((byCat[c] ?? 0) >= 3) continue;
    byCat[c] = (byCat[c] ?? 0) + 1;
    picked.push(g);
    if (picked.length >= n) break;
  }
  return picked;
}

function postCategory(p: Post): string | null {
  if (p.category) return p.category;
  // Older cached pages predate the category field — sniff the reason string.
  const m = /in (\w+)/.exec(p.reason ?? "");
  return m ? m[1] : null;
}

function whyLine(post: Post, a: ConsultAnswers, matchedWorld: boolean): string {
  const who = a.name?.trim() || CONSULT_RELATIONS[a.relation].label.replace(/^my /i, "your ").toLowerCase();
  const price = post.product.price;
  if (matchedWorld && a.budget != null && price <= a.budget * 0.6) {
    return `Right in ${who}'s world, with budget left for the card`;
  }
  if (matchedWorld) return `Squarely ${who}'s thing — and it passes the move test`;
  if (a.budget != null && price <= a.budget * 0.5) return `A keeper at half your budget`;
  return `Not the obvious pick — that's why it lands`;
}

// ── Consult → GET /feed query params ─────────────────────────────────────────
// The backend treats every facet as a soft boost (see infra/src/handler.mjs
// scorePost), so we can pass everything and still get a full page back.

export function consultFeedOpts(a: ConsultAnswers): {
  recipient?: string;
  occasion?: string;
  category?: string;
  budget?: number;
  vibes?: string[];
  limit: number;
} {
  const sig = deriveSignals(a);
  return {
    recipient: sig.recipientKey !== "anyone" ? sig.recipientKey : undefined,
    occasion: sig.occasion !== "any" ? sig.occasion : undefined,
    category: sig.categories[0],
    budget: sig.budget,
    vibes: sig.vibes.length ? sig.vibes : undefined,
    limit: 50,
  };
}

// ── Consult → UserProfile (the concierge IS onboarding) ─────────────────────
// The consult replaces the profile wizard, so its answers must produce a
// profile the rest of the app accepts (isUserProfile: ≥3 interests, full
// dealPreferences). Worlds map onto the interest tags the feed already
// understands; missing signals fall back to broad, safe defaults.

const WORLD_INTERESTS: Record<WorldKey, InterestTag[]> = {
  kitchen: ["foodie", "coffee-tea"],
  home: ["cozy", "plants", "candles"],
  style: ["minimalist", "vintage"],
  jewelry: ["luxury"],
  making: ["diy", "stationery"],
  tech: ["photography", "pop-culture"],
  outdoors: ["outdoors", "sustainable"],
  wellness: ["wellness"],
  books: ["stationery", "cozy"],
  music: ["vintage", "pop-culture"],
  pets: ["pets"],
  games: ["pop-culture"],
};

export function deriveProfileFromConsult(
  a: ConsultAnswers,
  userName?: string,
  genderPref?: "him" | "her" | "any",
): UserProfile {
  const interests: InterestTag[] = [];
  for (const w of [...a.worlds, ...parseSunday(a.sunday ?? "")]) {
    for (const tag of WORLD_INTERESTS[w] ?? []) {
      if (!interests.includes(tag)) interests.push(tag);
    }
  }
  // isUserProfile requires ≥3 — pad with evergreen tags.
  for (const tag of ["cozy", "foodie", "wellness"] as InterestTag[]) {
    if (interests.length >= 3) break;
    if (!interests.includes(tag)) interests.push(tag);
  }
  const budgetRange: BudgetRange =
    a.budget == null ? "no-limit" : a.budget <= 40 ? "budget" : a.budget <= 120 ? "mid" : "premium";
  return {
    name: userName?.trim() || "Gifter",
    role: "giver",
    difficulty: "moderate",
    style: "thoughtful",
    materialisticCategories: [],
    interests,
    dealPreferences: {
      sensitivity: "value-conscious",
      budgetRange,
      dealTypes: ["price-drops"],
      priceAlerts: false,
    },
    pinterestLinks: [],
    genderPref,
    completedAt: Date.now(),
  };
}

// ── Budget parsing for free-text answers ("around 80 bucks", "$50") ──────────

export function parseBudgetText(text: string): number | null {
  const m =
    text.match(/\$\s?(\d{1,5})/) ||
    text.match(/(?:under|below|around|about|max|up to|roughly|~)\s*\$?(\d{1,5})/i) ||
    text.match(/^(\d{1,5})$/) ||
    text.match(/(\d{1,5})\s?(?:dollars|bucks|usd)/i);
  if (!m) return null;
  const n = parseInt(m[1], 10);
  return Number.isFinite(n) && n > 0 ? n : null;
}
