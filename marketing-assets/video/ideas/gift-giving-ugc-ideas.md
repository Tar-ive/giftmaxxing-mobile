# Gift-giving UGC content ideas

Framework: [fal-ai-community/skills/storytelling](https://github.com/fal-ai-community/skills/tree/main/skills/storytelling) —
every piece is structured as **Hook → Setup → Development → Turn → Close**, held together by
**continuity anchors** (character, product, wardrobe, environment, color) so a multi-shot sequence
reads as one coherent short film instead of disconnected clips.

Recurring creator (continuity anchor across every concept below): the identity-locked woman
established in `marketing-assets/video/gift-rules-ugc-v2/stills/01-forgettable-gifts.png` —
warm olive skin, shoulder-length dark brown hair, small gold hoops, generated once via
YouCam text-to-image and re-used as the `image-to-image` reference for every subsequent shot,
across every piece, so she reads as the same person in a content series rather than a one-off actor.

Central premise every concept works from: **the story behind a gift is what makes it good** — not
price. Each hook sets up a bad-default expectation; the turn is the recipient's genuine reaction;
the close ties back to the specific thoughtfulness mechanism (not a generic "buy this").

---

## Produced

### 1. "Stop buying forgettable gifts" — `gift-rules-ugc-v2`
- **Hook:** she stands in a cluttered gift closet, unimpressed, holding an untouched candle + blank gift card.
- **Setup → Development:** five story beats, one rule each — micro-friction fix, upgrade-the-everyday,
  inside-joke callback, guilt-free permission, keep-the-notes.
- **Turn:** each beat's own small reveal (genuine delight pouring syrup, friends laughing over a chess set, a facial, a quietly saved note).
- **Close:** "What friction or desire can I solve?" — reframes gift-picking as a question, not a purchase.
- Delivered as the 47.7s composite + 5 standalone rule clips.

### 2. "Skip generic romance" — `partner-gifts-ugc-v1`
- **Hook:** she holds up a generic bouquet + heart-shaped chocolate box, visibly unmoved.
- **Development:** two contrasting mechanisms — build around their daily ritual (pour-over coffee gift
  mid-morning-routine) vs. build around a shared memory (personalized photo frame).
- **Turn:** partner's genuine surprised/touched reaction in each.
- **Close:** the memory-frame beat — "that's what makes it unforgettable."
- Delivered as an 18.3s composite + 3 standalone clips.

### 3. "The gift basket nobody returns" — `gift-basket-ugc-v1` (from `build-a-better-gift-basket`)
- **Hook:** she holds a random drugstore gift basket at arm's length, unconvinced.
- **Development:** she assembles an intentional basket on camera — comfort item, treat, handwritten
  note placed last.
- **Turn:** a friend opens it, reads the note, genuinely moved.
- **Close:** "Random isn't thoughtful. Intentional is."
- Delivered as a 21.6s composite + 3 standalone clips.

### 4. "Wrapping IS the gift" — `gift-wrapping-ugc-v1` (from `gift-wrapping-worth-keeping`)
- **Hook:** a plain kraft-paper bag with generic tissue paper, she's unimpressed.
- **Development:** close-up hands adding texture — twine, a dried flower, a wax seal.
- **Turn:** a friend slowly unties the bow, savoring the reveal instead of tearing in.
- **Close:** "Make opening part of the gift."
- Delivered as a 17.0s composite + 3 standalone clips.

### 5. "What actually says 'I see you,' for parents" — `parent-gifts-ugc-v1` (from `meaningful-gifts-for-parents`)
- **Hook:** she stands in a store aisle of "World's Best Mom/Dad" mugs, unimpressed.
- **Development:** she frames a handwritten family recipe card instead.
- **Turn:** her mother's quiet, teary, genuinely moved reaction.
- **Close:** "That's what they remember. Not the mug. The story."
- Delivered as an 18.9s composite + 3 standalone clips.

---

## Unproduced — scoped, ready to run through `scripts/video-agent/`

Maps to a curated Pinterest carousel already sitting in `giftmaxxing-dev-media/ugc/public/editorial/pinterest/ukK6yxJmbvEyK5aNV/` (source data in `infra/ingest/reports/apify-pinterest-2026-08-04.json`), so the premise and specific gift ideas are pre-validated rather than invented from scratch.

### 6. "Six birthday gifts that prove you noticed" (→ `birthday-gifts-that-feel-personal`)
- **Hook:** she scrolls a "gifts under $50" listicle, unconvinced, then closes the tab.
- **Development:** rapid-fire montage of inside-joke-driven gifts — a flower bouquet with tags
  referencing shared memories, a scrapbook frame of the two of them, a matchbook keepsake.
- **Turn:** best friend's reaction lands on "wait, you remembered that?"
- **Close:** "The best birthday gifts prove you noticed."

---

## How to produce one

```
node scripts/video-agent/run.mjs --brief scripts/video-agent/briefs/<new-brief>.json
```

Write the brief JSON per the shape in `scripts/video-agent/briefs/partner-gifts-ugc-v1.json`
(identity anchor reused from the existing still keeps the recurring-creator continuity anchor
intact), draft each scene as one shot using the fal skill's template — `SHOT [n], [duration]:
[story purpose]. [subject/action]. [location/time]. [framing]. [movement]. [lighting].
[continuity anchor].` — and run the graph. All local; no AWS.
