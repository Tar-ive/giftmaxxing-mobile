// Birthday freebies — the TikTok/Reddit-famous "free stuff on your birthday"
// canon (Sephora birthday gift, Starbucks drink, Denny's Grand Slam...) as a
// curated, server-served dataset so new deals ship WITHOUT an app release.
// GET /birthday-freebies → { perks: [...], updatedAt }
//
// Every entry is a stable, well-known rewards-program perk (no scraping, no
// expiring promo codes). `how` is the claim requirement in one line; `window`
// is when the perk is redeemable. The iOS app bundles a fallback copy of this
// list (BirthdayPerksStore.swift) — keep ids in sync when editing.

export const BIRTHDAY_PERKS = [
  // ── Beauty ────────────────────────────────────────────────────────────────
  { id: "sephora", brand: "Sephora", category: "Beauty", gift: "Free birthday gift set (trial-size duo)", how: "Join Beauty Insider (free) — redeem in store or online with any purchase", window: "Your birthday month", url: "https://www.sephora.com/beauty/birthday-gift", emoji: "💄", color: "#D6003C" },
  { id: "ulta", brand: "Ulta Beauty", category: "Beauty", gift: "Free birthday gift + 2x points all month", how: "Join Ulta Rewards (free)", window: "Your birthday month", url: "https://www.ulta.com/rewards", emoji: "✨", color: "#F45C1A" },
  { id: "bodyshop", brand: "The Body Shop", category: "Beauty", gift: "$10 birthday reward", how: "Join Love Your Body Club (free)", window: "Your birthday month", url: "https://www.thebodyshop.com", emoji: "🧴", color: "#004236" },
  { id: "aveda", brand: "Aveda", category: "Beauty", gift: "Free full-size birthday gift", how: "Join Aveda Plus Rewards (free)", window: "Your birthday month", url: "https://www.aveda.com", emoji: "🌿", color: "#20366B" },
  { id: "kiehls", brand: "Kiehl's", category: "Beauty", gift: "Free deluxe sample birthday gift", how: "Join Kiehl's Rewards (free)", window: "Your birthday month", url: "https://www.kiehls.com", emoji: "🧪", color: "#0A3255" },

  // ── Coffee & sweets ───────────────────────────────────────────────────────
  { id: "starbucks", brand: "Starbucks", category: "Coffee & Sweets", gift: "Free handcrafted drink or food item", how: "Starbucks Rewards member (free) — one purchase before your birthday", window: "Birthday only", url: "https://www.starbucks.com/rewards", emoji: "☕️", color: "#00704A" },
  { id: "dunkin", brand: "Dunkin'", category: "Coffee & Sweets", gift: "Free drink reward", how: "Join Dunkin' Rewards (free)", window: "Your birthday week", url: "https://www.dunkindonuts.com/en/dd-perks", emoji: "🍩", color: "#FF6E0C" },
  { id: "krispykreme", brand: "Krispy Kreme", category: "Coffee & Sweets", gift: "Free doughnut + drink", how: "Join Krispy Kreme Rewards (free)", window: "Your birthday month", url: "https://www.krispykreme.com/rewards", emoji: "🍩", color: "#1A6533" },
  { id: "auntieannes", brand: "Auntie Anne's", category: "Coffee & Sweets", gift: "Free pretzel reward", how: "Join Pretzel Perks (free)", window: "Your birthday month", url: "https://www.auntieannes.com/rewards", emoji: "🥨", color: "#0A4E8E" },
  { id: "baskinrobbins", brand: "Baskin-Robbins", category: "Coffee & Sweets", gift: "Free regular scoop", how: "Join the Birthday Club (free)", window: "Your birthday month", url: "https://www.baskinrobbins.com", emoji: "🍨", color: "#E51884" },
  { id: "dairyqueen", brand: "Dairy Queen", category: "Coffee & Sweets", gift: "BOGO Blizzard birthday coupon", how: "DQ Rewards via the app (free)", window: "Your birthday month", url: "https://www.dairyqueen.com", emoji: "🍦", color: "#E4002B" },
  { id: "jamba", brand: "Jamba", category: "Coffee & Sweets", gift: "Free small smoothie or juice", how: "Join Jamba Rewards (free)", window: "Your birthday month", url: "https://www.jamba.com/rewards", emoji: "🥤", color: "#F58220" },
  { id: "nothingbundt", brand: "Nothing Bundt Cakes", category: "Coffee & Sweets", gift: "Free Bundtlet cake", how: "Join NbC Rewards (free)", window: "Your birthday month", url: "https://www.nothingbundtcakes.com", emoji: "🎂", color: "#5C2E91" },
  { id: "panera", brand: "Panera", category: "Coffee & Sweets", gift: "Free pastry or sweet", how: "MyPanera member (free)", window: "Your birthday week", url: "https://www.panerabread.com/en-us/mypanera.html", emoji: "🥐", color: "#6A7F10" },

  // ── Meals ─────────────────────────────────────────────────────────────────
  { id: "dennys", brand: "Denny's", category: "Meals", gift: "Free Original Grand Slam breakfast", how: "Walk in with ID on your birthday — no signup", window: "Birthday only", url: "https://www.dennys.com", emoji: "🥞", color: "#FFC50D" },
  { id: "ihop", brand: "IHOP", category: "Meals", gift: "Free stack of Rooty Tooty pancakes", how: "Join the International Bank of Pancakes (free)", window: "Birthday only", url: "https://www.ihop.com/en/rewards", emoji: "🥞", color: "#2A5CAA" },
  { id: "chipotle", brand: "Chipotle", category: "Meals", gift: "Free chips & guac with purchase", how: "Chipotle Rewards member (free)", window: "Your birthday week", url: "https://www.chipotle.com/rewards", emoji: "🌯", color: "#A81612" },
  { id: "firehouse", brand: "Firehouse Subs", category: "Meals", gift: "Free medium sub with purchase", how: "Firehouse Rewards member (free)", window: "Your birthday week", url: "https://www.firehousesubs.com", emoji: "🥪", color: "#C8102E" },
  { id: "bww", brand: "Buffalo Wild Wings", category: "Meals", gift: "Free birthday wings", how: "Blazin' Rewards member (free)", window: "Your birthday week", url: "https://www.buffalowildwings.com/rewards", emoji: "🍗", color: "#FFB612" },
  { id: "redrobin", brand: "Red Robin", category: "Meals", gift: "Free gourmet burger", how: "Red Robin Royalty member (free)", window: "Your birthday month", url: "https://www.redrobin.com/royalty", emoji: "🍔", color: "#B31B1B" },
  { id: "olivegarden", brand: "Olive Garden", category: "Meals", gift: "Free dessert with your meal", how: "Join eClub (free)", window: "Around your birthday", url: "https://www.olivegarden.com", emoji: "🍰", color: "#5B7233" },
  { id: "texasroadhouse", brand: "Texas Roadhouse", category: "Meals", gift: "Free appetizer or sidekick dessert", how: "Join the VIP Club (free)", window: "Your birthday month", url: "https://www.texasroadhouse.com", emoji: "🤠", color: "#8B1A1A" },
  { id: "benihana", brand: "Benihana", category: "Meals", gift: "$30 birthday certificate", how: "Join The Chef's Table (free)", window: "Your birthday month", url: "https://www.benihana.com/chefs-table/", emoji: "🍤", color: "#C41230" },
  { id: "wafflehouse", brand: "Waffle House", category: "Meals", gift: "Free classic waffle", how: "Join the Regulars Club (free)", window: "Your birthday week", url: "https://www.wafflehouse.com/waffle-house-regulars-club/", emoji: "🧇", color: "#FFDD00" },

  // ── Retail & fun ──────────────────────────────────────────────────────────
  { id: "target", brand: "Target", category: "Retail & Fun", gift: "5% off one shopping trip", how: "Target Circle member (free)", window: "Your birthday month", url: "https://www.target.com/circle", emoji: "🎯", color: "#CC0000" },
  { id: "worldmarket", brand: "World Market", category: "Retail & Fun", gift: "$10 birthday reward", how: "World Market Rewards member (free)", window: "Your birthday month", url: "https://www.worldmarket.com/loyalty/", emoji: "🌍", color: "#B02A30" },
  { id: "dsw", brand: "DSW", category: "Retail & Fun", gift: "$5 birthday reward", how: "DSW VIP member (free)", window: "Your birthday month", url: "https://www.dsw.com/en/us/vip", emoji: "👟", color: "#00263A" },
  { id: "americaneagle", brand: "American Eagle", category: "Retail & Fun", gift: "15% off birthday offer", how: "Real Rewards member (free)", window: "Your birthday month", url: "https://www.ae.com/us/en/myaccount/real-rewards", emoji: "🦅", color: "#00205B" },
  { id: "buildabear", brand: "Build-A-Bear", category: "Retail & Fun", gift: "Pay-your-age Birthday Treat Bear", how: "Bonus Club member (free) — redeem in workshop", window: "Your birthday month", url: "https://www.buildabear.com/birthday-treat-bear.html", emoji: "🧸", color: "#0072BC" },
  { id: "cvs", brand: "CVS", category: "Retail & Fun", gift: "$3 ExtraBucks reward", how: "ExtraCare member (free)", window: "Your birthday month", url: "https://www.cvs.com/extracare", emoji: "💊", color: "#CC0000" },
  { id: "amc", brand: "AMC Theatres", category: "Retail & Fun", gift: "Free large popcorn upgrade + birthday reward", how: "AMC Stubs member (free)", window: "Your birthday month", url: "https://www.amctheatres.com/amcstubs", emoji: "🍿", color: "#D42027" },
  { id: "davebusters", brand: "Dave & Buster's", category: "Retail & Fun", gift: "Free $10 game play", how: "D&B Rewards member (free)", window: "Your birthday week", url: "https://www.daveandbusters.com/rewards", emoji: "🕹️", color: "#003DA5" },
];

const DATASET_UPDATED_AT = "2026-07-07";

// GET /birthday-freebies?category=Beauty — public catalog route.
export function birthdayFreebiesRoute(qs = {}) {
  let perks = BIRTHDAY_PERKS;
  if (qs.category) {
    const want = String(qs.category).toLowerCase();
    perks = perks.filter((p) => p.category.toLowerCase() === want);
  }
  return {
    perks,
    categories: [...new Set(BIRTHDAY_PERKS.map((p) => p.category))],
    updatedAt: DATASET_UPDATED_AT,
  };
}
