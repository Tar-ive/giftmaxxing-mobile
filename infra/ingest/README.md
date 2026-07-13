# Reddit → DynamoDB ingestion pipeline

Loads scraped Reddit gift finds into the `posts` DynamoDB table created by the
Terraform stack in `../`.

## Flow

```
web/scripts/scrape-reddit.mjs  ->  web/lib/reddit-gifts.json
                                          │
                                   infra/ingest/ingest.mjs  (transform.mjs)
                                          │
                                   DynamoDB  giftmaxxing-dev-posts
                                          │
                                   API Lambda  GET /feed, /recommendations
```

## 1. Scrape (no credentials needed — uses PullPush)

```bash
cd ../../web && npm run scrape:reddit
```

## 2. Dry run (validate transform, no AWS needed)

```bash
node ingest.mjs --dry-run
# writes posts.ingest.json + prints a sample item
```

## 3. Ingest (once AWS resources exist)

Requires valid AWS credentials and the table to exist. Load creds from the repo
root `.env` (SSO/temporary creds), then run:

```bash
set -a; source ../../.env; set +a   # AWS_*  +  optional POSTS_TABLE
npm install                          # installs @aws-sdk/* (first run only)
node ingest.mjs                      # -> $POSTS_TABLE (default giftmaxxing-dev-posts)
```

## Options

| Flag         | Default                          | Purpose                              |
|--------------|----------------------------------|--------------------------------------|
| `--dry-run`  | off                              | Write payload to JSON, skip AWS      |
| `--table`    | `$POSTS_TABLE` / `giftmaxxing-dev-posts` | Target DynamoDB table        |
| `--limit N`  | all                              | Cap number of posts ingested         |
| `--file P`   | `../../web/lib/reddit-gifts.json`| Input file                           |
| `--out P`    | `posts.ingest.json`              | Dry-run output path                  |

Writes use `BatchWrite` (25/request) and retry `UnprocessedItems` with backoff,
so re-running is safe (idempotent upsert by `postId`).

---

# Pinterest pin-page scraper (`pinterest-scrape.mjs`)

The real, shoppable pin catalog. Unlike the RSS feeds (~25 recent pins/feed, **no
outbound product link**), this uses Pinterest's own SPA resource endpoints — which
work without auth — to pull pins **with real prices, real product links, real
names, ratings, and board/category metadata**.

## Why these endpoints

| Endpoint              | Role                                                      |
|-----------------------|----------------------------------------------------------|
| `PinResource`         | Full pin: `link` (outbound URL), price, `board.id`, …    |
| `BoardFeedResource`   | A whole board, paginated by bookmark — **the volume engine** (every pin already carries link + price) |
| `BaseSearchResource`  | Gift queries → diverse pins + board discovery            |

> ⚠️ This reads Pinterest's internal JSON. It is ToS-gray and markup/endpoint
> names can change. The crawler throttles, backs off, and is **resumable**, but
> run it politely (default ~1.5 s/request).

## Flow

```
seed-boards.json (users + queries)
   │  RSS user pins ─► PinResource ─► board.id   (brand boards, crawled first)
   │  search queries ─► pins + more board.ids
   ▼
BoardFeedResource (paginate each board) ─► filter / dedup / diversity-cap
   ▼
pins.manifest.json   (+ optional S3 image upload with --bucket)
   ▼
embed.mjs ─► S3 Vectors      ingest-pins.mjs ─► DynamoDB posts (real link/price/facets)
```

## Run

```bash
npm run scrape:dry          # 200-pin dry run -> ./pins.manifest.json, no S3
npm run scrape              # full 10k crawl  -> ./pins.manifest.json
npm run scrape:resume       # continue after a stop/block (uses .scrape-state.json)

# crawl + upload originals to the media bucket in one pass:
set -a; source ../../.env; set +a
node pinterest-scrape.mjs --target 10000 --bucket "$MEDIA_BUCKET" --skip-existing
```

## Options

| Flag                | Default            | Purpose                                   |
|---------------------|--------------------|-------------------------------------------|
| `--target N`        | `10000`            | Stop after N unique quality pins          |
| `--seeds P`         | `seed-boards.json` | Curated users / queries (facet-tagged)    |
| `--out P`           | `pins.manifest.json` | Manifest output                         |
| `--bucket NAME`     | —                  | Also upload originals to this S3 bucket    |
| `--skip-existing`   | off                | Skip S3 objects that already exist        |
| `--resume`          | off                | Resume from `.scrape-state.json`          |
| `--dry-run`         | off                | Skip S3 upload (manifest only)            |
| `--max-per-board`   | `250`              | Diversity cap per board                    |
| `--max-per-domain`  | `1500`             | Diversity cap per merchant                 |
| `--min-interval`    | `1200` (ms)        | Throttle between requests                  |
| `--no-search` / `--no-rss` | both on     | Disable a seeding path                     |
| `--retailers`       | off                | Keep only real retailer **product** pages (built-in `RETAILER_DOMAINS` allowlist) + drop blog/gift-guide URLs |
| `--allow-domains a,b` | —                | Keep only outbound links on these domains (subdomains ok) |
| `--require-price`   | off                | Drop pins with no real price — i.e. links **and** prices  |
| `--block-listicles` / `--keep-listicles` | off | Drop / keep blog & gift-guide URLs                |

Quality filter drops pins with no image, no outbound link, off-Pinterest social
domains (`facebook.com`, …), and out-of-stock/stale products; dedup is by pin id
**and** image signature. Diversity comes from facet-tagged seeds + per-board /
per-merchant caps.

## Real retailer products (Sephora, Urban Outfitters, …) — end to end

To pull only **actual product pages with links and prices** from trusted stores
(Sephora, Ulta, Urban Outfitters, Anthropologie, Nordstrom, West Elm, Etsy, … —
see `RETAILER_DOMAINS` in `pinterest-scrape.mjs`) and load them into BOTH the
vector index (powers visual search) and the feed DB:

```bash
set -a; source ../../.env; set +a    # AWS creds + MEDIA_BUCKET + ADMIN_API_SECRET

# 1. Validate: tiny dry run -> ./pins.retailers.json (no AWS; prints a sample +
#    a "with real price" ratio so you can confirm links + prices came through)
npm run scrape:retailers:dry

# 2. Crawl real products + upload their images to the media bucket. Writes a
#    SEPARATE pins.retailers.json, so your existing pins.manifest.json is untouched.
node pinterest-scrape.mjs --target 3000 --retailers --require-price \
  --out pins.retailers.json --state .scrape-retailers.state.json \
  --bucket "$MEDIA_BUCKET" --skip-existing

# 3. Embed images -> S3 Vectors (UPSERTS — adds to the index, never clobbers it)
node embed.mjs --manifest pins.retailers.json

# 4. Ingest -> DynamoDB posts (the feed) via the admin-only /seed endpoint
node ingest-pins.mjs --manifest pins.retailers.json --dry-run   # preview items
node ingest-pins.mjs --manifest pins.retailers.json             # POST (needs ADMIN_API_SECRET)
```

`--retailers` narrows the crawl to the allowlist and drops gift-guide/blog URLs;
`--require-price` keeps only pins Pinterest exposes a real price for. Widen the
net with `--allow-domains store1.com,store2.com`, or relax with `--keep-listicles`
/ by dropping `--require-price` if a run comes back too sparse.

---

# Clean trash posts (`clean-posts.mjs`)

Removes low-quality Pinterest imports from the `posts` table (the `/feed` store):
dead/non-shoppable links (Pinterest-only, social), bare landing pages, and
blog/recipe/spam domains. **Reddit posts and user-generated content are never
touched** — only items with author `pinterest_*` / source `Pinterest/*` are
considered. Classification reuses `../src/quality.mjs` (`classifyPin`).

```bash
set -a; source ../../.env; set +a   # AWS creds (refresh SSO if expired)

npm run clean:posts:dry             # DRY RUN: scan, print breakdown, write backup
npm run clean:posts                 # APPLY: backup first, then BatchWrite-delete
```

## Trash buckets

| Bucket          | What it catches                                   | Default  |
|-----------------|---------------------------------------------------|----------|
| `dead-link`     | No usable http(s) product link                    | delete   |
| `non-shoppable` | Link goes to pinterest/instagram/facebook/tiktok/… | delete   |
| `landing`       | Bare homepage / root path (no product page)       | delete   |
| `content`       | Blog / recipe / spam domain                       | delete   |
| `non-gift`      | Replacement auto/plumbing parts, digital PDF/SVG pattern files | delete   |
| `guide`         | Listicle / gift-guide / editorial / seasonal      | opt-in   |
| `no-price`      | Real shoppable deep link but missing a price      | opt-in   |

## Options

| Flag                  | Purpose                                                   |
|-----------------------|----------------------------------------------------------|
| (none)                | Dry run — scan, report, and write a backup; no deletes    |
| `--apply`             | Actually delete (a timestamped backup is written first)   |
| `--include-guides`    | Also delete the `guide` bucket                            |
| `--include-no-price`  | Also delete the `no-price` bucket                         |
| `--keep a,b`          | Exclude buckets from deletion (e.g. `--keep content`)     |
| `--only a,b`          | Delete ONLY these buckets                                 |
| `--table` / `--region`| Override `$POSTS_TABLE` / `$AWS_REGION`                   |
| `--limit N`           | Cap how many posts are scanned (testing)                  |
| `--out P`             | Backup path (default `clean-posts.backup.<ts>.json`)      |
| `--verbose`           | Print every `postId` slated for deletion                  |

Deletes are `BatchWrite` (25/req) by `postId` with `UnprocessedItems` retry. The
posts table has point-in-time recovery enabled, and the backup JSON is restorable
via a `BatchWrite` Put, so the operation is reversible.

---

# Product-page image galleries (`enrich-images.mjs`)

Our pins carry ONE image, but the retailer listing behind them (eBay/Etsy/…)
usually has 5-10 shots. This crawls each shoppable `productUrl`, extracts the
gallery (JSON-LD `Product.image` → eBay/Etsy CDN references → `og:image`),
and writes it to `product.images` on the posts row. `/feed` passes the field
through untouched and the iOS detail sheet renders a swipeable carousel.

```bash
# Verify extraction on one page — no AWS needed:
node enrich-images.mjs --url "https://www.ebay.com/itm/..."

set -a; source ../../.env; set +a
npm run enrich:images:dry        # scan + fetch 20, print galleries, no writes
npm run enrich:images            # enrich every un-enriched post (throttled ~1.5s/page)
```

| Flag | Purpose |
|------|---------|
| `--url U` | Offline single-page mode: print the extracted gallery |
| `--dry-run` | Fetch + report, write nothing |
| `--limit N` / `--only-domain a,b` | Bound the crawl |
| `--force` | Re-fetch rows that already have `product.images` |
| `--min-interval MS` | Politeness throttle (default 1500) |

Idempotent (rows with `product.images` skip unless `--force`); thumbnails are
upgraded to the largest CDN rendition (`s-l1600`, `il_1588xN`); capped at 8.

---

# Amazon affiliate catalog (`import-asins.mjs` + `paapi-enrich.mjs`)

Powers `/feed/shop`. The catalog lives in `web/lib/amazon-picks.json` and is the
single source of truth. **We never scrape Amazon** — product images/titles/prices
may come ONLY from the Product Advertising API (PA-API), per the Associates
Operating Agreement.

## 1. Add ASINs (`import-asins.mjs`)

```bash
node import-asins.mjs asins.seed.txt        # from a file (ASINs or full URLs)
node import-asins.mjs B00ABCDEFG B00HIJKLMN # inline
pbpaste | node import-asins.mjs             # from the clipboard
```

Re-running merges — it never drops existing picks. To curate by hand, add a
**tab-separated** record (tabs beat commas, since titles contain commas):

```
ASIN<TAB>Title<TAB>Brand<TAB>Category<TAB>Description
```

Use only your OWN words for Title/Description without PA-API. `Category` drives
the section grouping and the fallback emoji on each tile.

## 2. Enrich with official data (`paapi-enrich.mjs`) — needs PA-API access

PA-API access is granted after ~3 qualifying sales within 180 days. Until then,
preview requests with `--dry-run`. Credentials go in the repo-root `.env`
(SECRET — never `NEXT_PUBLIC_`, never in Vercel):

```bash
set -a; source ../../.env; set +a   # AMAZON_PAAPI_ACCESS_KEY / _SECRET_KEY / AMAZON_PARTNER_TAG
node paapi-enrich.mjs --dry-run     # preview only (no credentials needed)
node paapi-enrich.mjs               # fill picks missing a title/image
node paapi-enrich.mjs --force       # re-fetch everything (e.g. refresh prices)
```

| Flag        | Purpose                                                      |
|-------------|-------------------------------------------------------------|
| `--dry-run` | Print the batched requests; make no API call, write nothing |
| `--force`   | Overwrite all fields, not just empty ones                   |
| `--limit N` | Only the first N target ASINs (handy while testing quotas)  |

GetItems runs in batches of 10, throttled (~1 TPS) with retry/backoff. It fills
`title/brand/category/blurb` only when empty (preserving manual curation) and
always refreshes the PA-API-owned `image/price`. **Prices are stored but not yet
shown** in the UI — the Operating Agreement requires displayed prices be ≤24h
old, so schedule enrichment (or fetch at request time) before surfacing them.
