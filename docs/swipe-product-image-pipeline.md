# Swipe product and feed pipeline

## Why cards previously had one image

The curated manifest stored one editorial crop per product. The API normalized
that single value correctly, so the client could not invent a product gallery.
The new enrichment pass reads the exact verified retailer URL, extracts only
listing-owned images, archives them in S3, and publishes the gallery in the
typed `media[]` field. If a retailer exposes one image, the card stays
single-image. No unrelated fallback images are added.

```mermaid
flowchart LR
  Guide["Reviewed inspiration carousel"] --> Match["Human-verified product match"]
  Match --> URL["Exact retailer listing URL"]
  URL --> Extract["JSON-LD or official retailer API"]
  Extract --> Validate["Image type, size, dedupe, max 8"]
  Validate --> Archive["Versioned S3 media archive"]
  Archive --> Catalog["Catalog item: media[], features[], offer"]
  Catalog --> Mixer["POST /v2/recommendations"]
  Mixer --> Swipe["Swipe product gallery"]
  Swipe --> Detail["Swipe up: features and why it fits"]
  Detail --> Shop["Open exact retailer listing"]
```

## API-authoritative feed

```mermaid
flowchart TD
  Curated["35 reviewed carousels + 86 verified products"] --> Catalog["Typed catalog graph"]
  Events["Views, dwell, saves, swipes, reliability votes"] --> Profile["Taste and quality signals"]
  Catalog --> Mixer["Recommender Mixer v2.6"]
  Profile --> Mixer
  Taxonomy["API-owned intent themes"] --> Mixer
  Mixer --> Policy["Unique pagination, 1 carousel per 4 cards"]
  Policy --> API["Signed typed recommendation response"]
  API --> Home["For You two-column feed"]
  API --> Search["Search"]
  API --> Challenge["Product-only swipe challenge"]
  API --> Maxi["Catalog-grounded concierge"]
```

## What changes without an App Store release

Catalog contents, ranking, theme and tag names, prices, features, offers,
galleries, and carousel ordering are server data and propagate after cache
revalidation. New gestures, layouts, local persistence, decoding new required
fields, and native capabilities require an app release. The earlier theme
update failed because the API returned `query` while iOS required `terms`; iOS
then correctly used its bundled offline fallback. The contract is now aligned.
