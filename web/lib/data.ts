// Sample content mirroring the Giftmaxxing prototype (app/data.jsx),
// reused as visual props across the landing page.

export type Grad =
  | "peach"
  | "rose"
  | "butter"
  | "lilac"
  | "sky"
  | "sage"
  | "coral";

export const GRADIENTS: Record<Grad, string> = {
  peach: "linear-gradient(135deg, var(--color-peach-1), var(--color-peach-2))",
  rose: "linear-gradient(135deg, var(--color-rose-1), var(--color-rose-2))",
  butter: "linear-gradient(135deg, var(--color-butter-1), var(--color-butter-2))",
  lilac: "linear-gradient(135deg, var(--color-lilac-1), var(--color-lilac-2))",
  sky: "linear-gradient(135deg, var(--color-sky-1), var(--color-sky-2))",
  sage: "linear-gradient(135deg, var(--color-sage-1), var(--color-sage-2))",
  coral: "linear-gradient(135deg, #ffb5a0, var(--color-coral))",
};

export type Product = {
  id: string;
  name: string;
  brand: string;
  price: number;
  was?: number;
  grad: Grad;
  emoji: string;
  image?: string | null; // real product/preview image (Reddit-sourced posts)
  images?: string[]; // additional carousel slides
};

export const PRODUCTS: Product[] = [
  { id: "camera", name: "Mini Instant Camera", brand: "Halo", price: 79, grad: "sky", emoji: "📷" },
  { id: "matcha", name: "Matcha Starter Kit", brand: "Kettl", price: 54, grad: "sage", emoji: "🍵" },
  { id: "candle", name: "Soy Candle — Fig & Oud", brand: "Ember", price: 24, grad: "peach", emoji: "🕯️" },
  { id: "perfume", name: "Eau de Parfum 50ml", brand: "Dusk", price: 88, was: 110, grad: "rose", emoji: "🌸" },
  { id: "vinyl", name: "Vinyl — Midnight Hours", brand: "Lowtide", price: 32, grad: "lilac", emoji: "🎶" },
  { id: "lamp", name: "Sunset Projector Lamp", brand: "Glow", price: 39, was: 49, grad: "coral", emoji: "🌅" },
  { id: "journal", name: "Linen Daily Journal", brand: "Margin", price: 22, grad: "butter", emoji: "📔" },
  { id: "buds", name: "Wireless Buds Pro", brand: "Aera", price: 149, was: 179, grad: "lilac", emoji: "🎧" },
];

export const FEATURES = [
  {
    tag: "Social feed",
    title: "A feed of gift-worthy finds, from people you trust",
    body: "No more endless tabs. See what friends are loving, save the finds that fit someone you have in mind, and discover curated drops that refresh every 24 hours.",
    accent: "coral" as Grad,
  },
  {
    tag: "Shared wishlists",
    title: "Wishlists nobody double-buys",
    body: "Build a list for any occasion. Friends can quietly claim an item so two people never show up with the same gift — the giver sees it's taken, the recipient stays surprised.",
    accent: "sage" as Grad,
  },
  {
    tag: "Group gifts",
    title: "Pool money for the gift that actually lands",
    body: "Chip in whatever feels right toward one bigger gift. Live progress, a transparent ledger, and a deadline that keeps everyone moving.",
    accent: "sky" as Grad,
  },
  {
    tag: "Never miss it",
    title: "Every birthday, anniversary, and milestone — handled",
    body: "Your calendar of the people who matter. Maxi scans it ahead of time and lines up ideas in your budget before you even remember the date.",
    accent: "butter" as Grad,
  },
];

export const STEPS = [
  {
    n: "01",
    title: "Add the people who matter",
    body: "Birthdays, anniversaries, the friend moving away. Link a Pinterest board or recent saves so Maxi learns each person's taste.",
  },
  {
    n: "02",
    title: "Let Maxi do the searching",
    body: "Tell it the occasion and budget. Maxi matches real products to their aesthetic, builds bundles, and explains why each pick fits.",
  },
  {
    n: "03",
    title: "Give, together",
    body: "Claim from a wishlist, start a group pool, or buy on the spot. Everyone's in the loop, nobody's gift is a duplicate.",
  },
];
