// Turn the bundled Pinterest pins (real i.pinimg.com photos + synthesized
// prices) into an Instagram-style social feed: each pin is attributed to a demo
// user with a caption, likes, and a couple of comments. This guarantees the
// feed always renders real photos (unlike the Reddit API feed, whose
// preview.redd.it images 403 on cross-origin hotlinks).
import { PINS, type Pin } from "@/lib/pins";
import type { Comment, Post } from "@/lib/social";
import type { Product } from "@/lib/data";
import { hiResImage } from "@/lib/images";
import { type Taste, scorePinForTaste, tasteMatchesPin } from "@/lib/taste";

const AUTHORS = ["maya", "theo", "jules", "noor", "ivy", "sam", "remy"];

const CAPTIONS = [
  "found this and immediately thought of you 🎁",
  "adding straight to the gift list",
  "ok this is the one. saving for later 🤌",
  "Maxi surfaced this from my taste board — obsessed",
  "the aesthetic >>> need it",
  "perfect little gift under budget",
  "this would make someone's whole week",
  "been eyeing this for a birthday coming up",
  "curated drop material fr",
  "tell me this isn't the cutest thing",
];

const COMMENTS = [
  "obsessed with this 😍",
  "adding to my list rn",
  "where is this from??",
  "this is so them",
  "Maxi was right again",
  "need x2",
  "the perfect gift honestly",
];

function hash(s: string): number {
  let h = 0;
  for (let i = 0; i < s.length; i++) h = (h * 31 + s.charCodeAt(i)) >>> 0;
  return h;
}

// Trim a long pin title down to a clean product-style name.
export function shortTitle(title: string): string {
  const firstSentence = title.split(/[.!?]/)[0].trim();
  const base = firstSentence.length >= 18 ? firstSentence : title.trim();
  return base.length > 60 ? base.slice(0, 57).trimEnd() + "…" : base;
}

export function pinToProduct(pin: Pin): Product {
  return {
    id: pin.id,
    name: shortTitle(pin.title),
    brand: pin.brand,
    price: pin.price,
    grad: pin.grad,
    emoji: pin.emoji,
    image: hiResImage(pin.image),
  };
}

export function pinToPost(pin: Pin, idx: number, taste?: Taste): Post {
  const h = hash(pin.id);
  const author = AUTHORS[h % AUTHORS.length];
  const likes = 40 + (h % 1860);
  // Keep bundled fallback posts on the same timestamp path as API posts.
  const createdAt = Date.now() - (3 + (h % 72)) * 60 * 60 * 1000;
  const nComments = h % 3; // 0..2
  const comments: Comment[] = Array.from({ length: nComments }, (_, i) => {
    const cu = AUTHORS[(h + i + 1) % AUTHORS.length];
    return { id: `${pin.id}-c${i}`, user: cu, text: COMMENTS[(h + i) % COMMENTS.length] };
  });
  // A pin is flagged as a personalized rec when its category matches the user's
  // onboarding taste; otherwise keep the original cosmetic every-4th cadence.
  const matched = taste ? tasteMatchesPin(pin, taste) : false;
  const isRec = matched || idx % 4 === 1;
  return {
    id: pin.id,
    user: author,
    createdAt,
    time: "",
    product: pinToProduct(pin),
    caption: CAPTIONS[h % CAPTIONS.length],
    likes,
    liked: false,
    saved: false,
    comments,
    commentCount: comments.length + (h % 12),
    source: pin.brand,
    url: pin.url,
    productUrl: pin.url,
    rec: isRec,
    reason: matched
      ? `matches your ${pin.category} taste`
      : isRec
        ? "matches your saved taste"
        : undefined,
  };
}

// Deterministic per-cycle shuffle so repeated passes over the 72 pins feel
// fresh without RNG nondeterminism across renders.
function cycleOrder(cycle: number, taste?: Taste): Pin[] {
  const arr = [...PINS];
  const seed = (cycle + 1) * 2654435761;
  return arr
    .map((p, i) => {
      const base = hash(p.id + ":" + ((seed + i) >>> 0));
      // No taste signal → original deterministic shuffle (key = hash).
      if (!taste || !taste.hasSignal) return { p, k: base };
      // Taste signal → pins matching the user's categories sort first; per-cycle
      // noise keeps each pass varied. Lower key = earlier, so negate affinity.
      const noise = (base % 1000) / 1000;
      return { p, k: -(scorePinForTaste(p, taste) * 2 + noise * 0.6) };
    })
    .sort((a, b) => a.k - b.k)
    .map((x) => x.p);
}

// Return `limit` feed posts starting at a flat offset, cycling (and reshuffling)
// through the pin set so the feed scrolls effectively forever.
export function buildPinFeed(offset: number, limit: number, taste?: Taste): Post[] {
  const out: Post[] = [];
  const n = PINS.length;
  for (let i = 0; i < limit; i++) {
    const flat = offset + i;
    const cycle = Math.floor(flat / n);
    const order = cycleOrder(cycle, taste);
    const pin = order[flat % n];
    out.push(pinToPost(pin, flat, taste));
  }
  return out;
}
