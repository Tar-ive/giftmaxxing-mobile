import assert from "node:assert/strict";
import test from "node:test";

import {
  classifyMedia, imagesOf, intentOf, occasionOf, recipientOf, scorePost, titleOf,
} from "./ingest-apify-instagram.mjs";

import {
  amazonQuery, bucketFor, contentWords, lexicalOverlap, specificOverlap,
  SIMILARITY_FLOOR, STRONG_OVERLAP,
} from "./inspo-gap.mjs";

const reel = (over = {}) => ({
  type: "Video", shortCode: "abc", displayUrl: "https://cdn/cover.jpg",
  videoUrl: "https://cdn/v.mp4", caption: "Birthday gift for my bestie 🎀",
  likesCount: 1700, url: "https://instagram.com/p/abc/", ...over,
});

// ── Media classification ─────────────────────────────────────────────────────

test("classifyMedia separates reels, carousels and stills", () => {
  assert.equal(classifyMedia(reel()), "video");
  assert.equal(classifyMedia({ type: "Sidecar", childPosts: [{}, {}] }), "carousel");
  assert.equal(classifyMedia({ type: "Image", displayUrl: "https://x/a.jpg" }), "image");
  assert.equal(classifyMedia({}), "unknown");
});

// This is the finding that shaped the whole ingest: 806 of 999 posts on the
// source account are reels, and every one carries a usable cover frame.
// Dropping video would have discarded four fifths of the corpus.
test("a reel still yields its cover frame", () => {
  assert.deepEqual(imagesOf(reel()), ["https://cdn/cover.jpg"]);
});

test("carousel collects child stills and skips child videos", () => {
  const images = imagesOf({
    type: "Sidecar",
    displayUrl: "https://cdn/0.jpg",
    childPosts: [
      { type: "Image", displayUrl: "https://cdn/1.jpg" },
      { type: "Video", displayUrl: "https://cdn/2.jpg", videoUrl: "https://cdn/2.mp4" },
      { type: "Image", displayUrl: "https://cdn/3.jpg" },
    ],
  });
  assert.deepEqual(images, ["https://cdn/0.jpg", "https://cdn/1.jpg", "https://cdn/3.jpg"]);
});

test("imagesOf dedupes and rejects non-https", () => {
  const images = imagesOf({ displayUrl: "https://cdn/a.jpg", images: ["https://cdn/a.jpg", "http://cdn/b.jpg", ""] });
  assert.deepEqual(images, ["https://cdn/a.jpg"]);
});

// ── Acceptance ───────────────────────────────────────────────────────────────

test("a captioned gift reel is accepted", () => {
  const result = scorePost(reel());
  assert.equal(result.accepted, true);
  assert.ok(result.reasons.includes("gift_intent"));
  assert.ok(result.reasons.includes("recipient"));
});

test("hashtag-only captions are rejected", () => {
  // Measured: the source account's top hashtags are trend/fyp/viral/relatable —
  // pure reach bait that carries no gift information at all.
  const result = scorePost(reel({ caption: "#fyp #trending #viral #relatable #insta" }));
  assert.equal(result.accepted, false);
  assert.ok(result.reasons.includes("hashtags_only"));
});

test("affiliate bait is rejected", () => {
  const result = scorePost(reel({ caption: "Promise necklace, DM for order details, gift for her" }));
  assert.equal(result.accepted, false);
  assert.ok(result.reasons.includes("engagement_bait"));
});

test("a post with no image can never be accepted", () => {
  const result = scorePost({ type: "Video", caption: "Birthday gift for mom", likesCount: 99999 });
  assert.equal(result.accepted, false);
  assert.deepEqual(result.reasons, ["no_image"]);
});

// ── DIY intent — the distinction that keeps the gap report honest ────────────

test("handmade posts are tagged make, not buy", () => {
  // 26% of this corpus is DIY. Reporting these as "we don't sell this" would
  // send someone shopping for products that do not exist.
  for (const caption of [
    "one year anniversary book that I made, he loved it",
    "Personalized Bestie Magazine — template link",
    "DIY scrapbook for my boyfriend",
    "how to make an interactive card",
  ]) {
    assert.equal(intentOf({ caption }), "make", caption);
  }
});

test("product posts stay buy", () => {
  for (const caption of [
    "Promise necklace for her",
    "These AirPods are the perfect birthday gift",
    "Cutest candle set for mom",
  ]) {
    assert.equal(intentOf({ caption }), "buy", caption);
  }
});

// ── Metadata extraction ──────────────────────────────────────────────────────

test("recipient and occasion come out of the caption", () => {
  const item = reel({ caption: "Anniversary gift for my boyfriend 🥹" });
  assert.equal(recipientOf(item), "boyfriend");
  assert.equal(occasionOf(item), "anniversary");
});

test("titleOf strips hashtags and truncates", () => {
  assert.equal(
    titleOf({ caption: "Personalized bestie magazine ✨ #fyp #trending" }),
    "Personalized bestie magazine ✨"
  );
  assert.ok(titleOf({ caption: "x".repeat(200) }).length <= 90);
});

// ── Gap analysis ─────────────────────────────────────────────────────────────

// Calibrated against the real corpus: image→image similarity here spans
// ~0.38–0.58, and a HIGHER score is regularly the WRONG item. Overlap decides.
test("bucketing is lexical-first, not similarity-first", () => {
  // The measured failure case: junk at 0.486 with no shared words must lose to
  // a correct match at 0.467 with three.
  assert.equal(bucketFor(0.486, []), "unmatched");
  assert.equal(bucketFor(0.467, ["matcha", "whisk", "ceramic"]), "matched");

  assert.equal(bucketFor(0.55, ["candle", "soy"]), "matched");
  assert.equal(bucketFor(0.55, ["candle"]), "near");
  assert.equal(bucketFor(0.55, []), "unmatched");
  // Below the floor nothing is a match, however many words agree.
  assert.equal(bucketFor(SIMILARITY_FLOOR - 0.01, ["matcha", "whisk"]), "unmatched");
});

// Measured coincidences from the first calibrated run.
test("generic words alone never earn a match", () => {
  assert.equal(bucketFor(0.55, ["year"]), "unmatched");        // 10 year olds vs 10 Year Anniversary
  assert.equal(bucketFor(0.55, ["easy"]), "unmatched");        // Easy snack vs Easy Sunkissed Set
  assert.equal(bucketFor(0.55, ["birthday", "year"]), "unmatched");
  // One specific word rescues it.
  assert.equal(bucketFor(0.55, ["birthday", "spiderman"]), "matched");
  assert.deepEqual(specificOverlap(["birthday", "spiderman", "year"]), ["spiderman"]);
});

test("contentWords strips hashtags and @mentions", () => {
  // Otherwise the Amazon query becomes "save bdayy giftideas foryou foryoupage".
  const words = contentWords("Spiderman room decor #foryou #fypage @lyft0gt");
  assert.ok(words.includes("spiderman"));
  assert.ok(words.includes("decor"));
  assert.ok(!words.some((w) => ["foryou", "fypage", "lyft0gt"].includes(w)));
});

test("contentWords drops stopwords and gift-generic filler", () => {
  const words = contentWords("The perfect gift ideas for your matcha loving bestie");
  assert.ok(words.includes("matcha"));
  assert.ok(words.includes("loving"));
  // "gift"/"ideas"/"perfect" are in every caption — they match everything and
  // therefore discriminate nothing.
  assert.ok(!words.includes("gift"));
  assert.ok(!words.includes("ideas"));
  assert.ok(!words.includes("perfect"));
});

// The lexical gate exists because kNN distance is NOT a relevance signal for
// this index — measured: a wrong neighbour at 0.428 outranked the correct one
// at 0.438. Word-boundary matching, never bare `includes`.
test("lexicalOverlap uses word boundaries, not substrings", () => {
  assert.deepEqual(lexicalOverlap(["matcha"], "Matcha Whisk Set"), ["matcha"]);
  assert.deepEqual(lexicalOverlap(["mug"], "Ceramic Mugs"), ["mug"]);   // trailing s
  // "art" must NOT match "Easter Party" — the exact false positive that made
  // the age-pack build produce junk.
  assert.deepEqual(lexicalOverlap(["art"], "Easter Party Decorations"), []);
  assert.deepEqual(lexicalOverlap(["candle"], "Scandal Perfume"), []);
});

test("amazonQuery builds a searchable phrase from the caption", () => {
  const query = amazonQuery({
    product: { name: "Personalized star map" },
    caption: "The perfect gift for your boyfriend — a custom star map of your first date",
  });
  assert.ok(query.includes("personalized"));
  assert.ok(query.includes("star"));
  assert.ok(!query.includes("perfect"));
  assert.ok(query.split(" ").length <= 5);
});
