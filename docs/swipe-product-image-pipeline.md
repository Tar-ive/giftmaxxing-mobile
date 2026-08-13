# Swipe product and feed pipeline

## Why cards previously had one image

The curated manifest stored one editorial crop per product. That image is
evidence for product identity, not product-card media. The enrichment pass now
uses OCR/vision evidence to resolve the exact product, then reads the verified
retailer URL, extracts only listing-owned images and features, archives them in
S3, and publishes the gallery in typed `media[]`. A product remains outside
Swipe until at least one retailer-owned image is verified. Header/listicle
slides are inspiration-only and can never enter the product deck.

```mermaid
flowchart LR
  Guide["Reviewed inspiration carousel"] --> Classify["Header, editorial, or product evidence"]
  Classify -->|"Header or editorial"| HomeOnly["Home inspiration only"]
  Classify -->|"Product evidence"| OCR["OCR and visual product parsing"]
  OCR --> Match["Exact product and variant match"]
  Match --> URL["Official retailer listing URL"]
  URL --> Extract["Official API, JSON-LD, or merchant CDN"]
  Extract --> Validate["Identity, image type, size, dedupe, max 8"]
  Validate -->|"Unverified"| Hold["Hold outside Swipe"]
  Validate --> Archive["Versioned S3 media archive"]
  Archive --> Catalog["Catalog item: verified media[], features[], offer"]
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
  Catalog --> Mixer["Recommender Mixer v2.7"]
  Profile --> Mixer
  Taxonomy["API-owned intent themes; All = child union"] --> Mixer
  Mixer --> Policy["Unique pagination, 1 carousel per 4 cards"]
  Policy --> API["Signed typed recommendation response"]
  API --> Home["For You two-column feed"]
  API --> Search["Search"]
  API --> Challenge["Verified retailer-media Swipe deck"]
  API --> Maxi["Catalog-grounded concierge"]
```

## What changes without an App Store release

Catalog contents, ranking, theme and tag names, prices, features, offers,
galleries, and carousel ordering are server data and propagate after cache
revalidation. New gestures, layouts, local persistence, decoding new required
fields, and native capabilities require an app release. The earlier theme
update failed because the API returned `query` while iOS required `terms`; iOS
then correctly used its bundled offline fallback. The contract is now aligned.
The earlier For You implementation also repeated a local first page, which
starved most API carousels; For You now follows the API cursor and stable IDs.

## Application map

```mermaid
flowchart TD
  Sources["Reviewed guides, retailer listings, and approved UGC"] --> Catalog["Typed catalog graph"]
  Catalog --> Mixer["Unified Recommender Mixer"]
  Events["Impressions, dwell, saves, swipes, reliability, purchases"] --> Profiles["Taste and recipient profiles"]
  Profiles --> Mixer
  Themes["Intent themes and child filters"] --> Mixer
  Mixer --> Home["Home: products plus curated inspiration"]
  Mixer --> Search["Text and image search"]
  Mixer --> Swipe["Product-only taste learning"]
  Mixer --> Challenge["Recipient learning and gift recommendations"]
  Mixer --> Maxi["Catalog-grounded assistant"]
  Home --> Community["Likes, comments, boards, pools"]
  Swipe --> Community
  Swipe --> Retailer["Exact merchant listing"]
  Maxi --> Cart["Cart, dates, memory, and wrapping"]
  Community --> Events
```
