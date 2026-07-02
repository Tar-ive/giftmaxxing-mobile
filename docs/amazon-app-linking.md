# Routing Amazon affiliate links to the Amazon iOS app

Research for: tapping an affiliate link/post in Giftmaxxing should open the
product **in the Amazon iOS app** when it's installed, and fall back to our
in-app browser (`SafariView`) when it isn't — without losing the associate tag.

Status: research only, verified 2026-07-02. No code changes yet.

---

## TL;DR — where the boundary sits

| Concern | Who handles it |
|---|---|
| Deciding "is the Amazon app installed?" | **iOS** (universal links + AASA) |
| Routing an `https://www.amazon.com/...` URL into the Amazon app | **iOS**, but ONLY when the URL is opened through the system (`UIApplication.open` / SwiftUI `Link`) |
| Passing the full URL (incl. `?tag=`) into the Amazon app | **iOS** (delivers it via `NSUserActivity.webpageURL`) |
| Fallback to browser when app is missing | **us** (one `completionHandler` branch) |
| NOT sending Amazon links into `SFSafariViewController` in the first place | **us** — this is the actual bug today; SFSVC/WKWebView **never** trigger universal links |
| Making sure the tag is on the URL before opening | **us** (`Affiliate.swift`) |
| Expanding `amzn.to` shortlinks (not app-associated) | **us** (optional) |
| Attribution inside the Amazon app after handoff | **Amazon** (standard 24h window) |

The OS does the heavy lifting. Our part is a small **outbound router** (~40
lines) that every product tap funnels through, replacing today's direct
`browserTarget = BrowserTarget(url:)` calls.

## Why links don't open the app today

All product taps present `SafariView` (`SFSafariViewController`) via
`.sheet` — see `PostDetailView`, `MaxiProductCard`. Apple deliberately does
**not** trigger universal links for navigations inside `SFSafariViewController`
or `WKWebView`; that privilege is reserved for system-level opens. So as long
as we hand Amazon URLs straight to the in-app browser, iOS never gets a chance
to route to the Amazon app.

Interesting accident: `ShopView`'s "Buy on Amazon" uses SwiftUI
`Link(destination:)`, which IS a system open — that one button already opens
the Amazon app on devices that have it. The rest of the app doesn't. That
inconsistency is the clearest proof of the mechanism.

## The mechanism we should use

```
UIApplication.shared.open(url, options: [.universalLinksOnly: true]) { opened in
    if !opened { /* present SafariView as today */ }
}
```

- `universalLinksOnly: true` (iOS 10+) means: open ONLY if an installed app
  claims this URL as a universal link. Amazon app present → opens natively,
  tag intact. Absent → completion fires with `false` and we present our
  existing `SafariView`. No `canOpenURL`, no `LSApplicationQueriesSchemes`,
  no custom scheme needed.
- If the user has explicitly disabled "open in app" for Amazon (long-press →
  "Open in Safari" memory), `opened == false` → we fall back gracefully.
  Correct behavior for free.

### Why not Amazon's custom URL scheme

`com.amazon.mobile.shopping://` exists but is undocumented/unstable, needs
`LSApplicationQueriesSchemes` for detection, and tag attribution through it is
unverified. Universal links carry the canonical tagged https URL — strictly
better. Don't use the scheme.

## Verified: which URLs the Amazon app actually claims

Fetched 2026-07-02 from `https://www.amazon.com/.well-known/apple-app-site-association`
(app ID `94KV3E626L.com.amazon.Amazon` + international variants):

| Our link shape | AASA pattern | Opens in app? |
|---|---|---|
| `/dp/{ASIN}?tag=…` (product) | `/dp/??????????` (+ `/ref=*`) | **Yes** |
| `/s?k=…&tag=…` (search fallback) | `/s` | **Yes** |
| `/gp/product/{ASIN}` | `/gp/product/??????????` | Yes |
| `https://a.co/d/XXXXXXX` (share shortlink) | a.co AASA: `/d/???????`, `/d/????????` | **Yes** |
| `https://amzn.to/…` (Bitly-managed) | no AASA on amzn.to | **No** — 302s to amazon.com inside whatever browser loads it |
| Any URL with `?nodl=1` or `ref=nodl_*` | explicit AASA excludes | No (Amazon's own opt-out convention) |

Notes:
- Query strings are unconstrained in the `/dp` and `/s` patterns, so `?tag=`
  never blocks matching.
- ASIN wildcards are exactly-10-char (`??????????`) — matches our validated
  `/dp/{10-char ASIN}` output from `Affiliate.amazonUrl`.
- `nodl` gives us a free kill-switch: append `nodl=1` to force-stay-in-browser
  if we ever need it (e.g. a debug toggle).

## Affiliate attribution — what survives the handoff

- iOS hands the **complete URL** to the Amazon app; `tag=giftmaxxingde-20`
  arrives intact. Amazon Associates counts in-app purchases from tagged links
  the same as web (standard 24-hour attribution window).
- **Compliance prerequisite**: the Associates program requires registering a
  mobile app that displays affiliate links (Associates Central → Account →
  "Mobile apps"). We already show the required "As an Amazon Associate…"
  disclosure (`ShopView`). Register the iOS app before shipping this, or
  attribution can be disqualified.
- Amazon PA-API is still gated (needs 3 qualifying sales) — unchanged; we only
  construct links from ASINs, never scrape prices.

## Gaps in current code the implementation must fix

1. **Tag parity bug**: web `outboundAffiliateUrl` re-tags raw Amazon URLs
   (extracts ASIN → rebuilds `/dp/{asin}?tag=…`). The iOS port
   `Affiliate.productUrl` passes raw retailer URLs through **untagged** — an
   Amazon URL from server enrichment without `tag=` earns nothing, in app or
   browser. Port `extractAsin` + re-tag into `Affiliate.swift` first.
2. **No single choke point**: `PostDetailView`, `MaxiProductCard`, `ShopView`
   each open links their own way. Add one `OutboundRouter.open(url, source:)`
   (needs `UIApplication` access, so a small non-View helper + a
   `browserTarget` binding or an injected presenter) and route all three
   through it.
3. **Analytics blind spot**: `trackAffiliateClick` fires before open; add the
   resolved destination (`amazon_app` vs `in_app_browser`) so we can measure
   app-open rate and conversion lift. The completion handler gives us this
   for free.

## Recommended design (for the implementing agent)

1. `Affiliate.retag(_ url:) -> URL` — ASIN extraction + `/dp` rebuild parity
   with web; leave non-Amazon URLs untouched.
2. `OutboundRouter.open(_ url: URL, source: String, fallback: (URL) -> Void)`:
   - retag → if `Affiliate.isAmazonUrl` and host is app-associated
     (`amazon.*` or `a.co`; NOT `amzn.to`) → `UIApplication.shared.open`
     with `.universalLinksOnly: true`
   - `opened == false` (or non-Amazon) → `fallback(url)` presents `SafariView`
   - fire `trackAffiliateClick` with the actual destination in both branches
3. Call sites: replace direct `browserTarget = BrowserTarget(url:)` in
   `PostDetailView` / `MaxiProductCard`; replace `Link` in `ShopView` with a
   `Button` through the router (also fixes its missing analytics).
4. `amzn.to`: don't special-case v1. They're rare in our data (ingest emits
   `/dp` URLs). Optional v2: async HEAD to expand, then route.

No entitlement, Info.plist, or `project.yml` changes required — universal
links into OTHER apps need zero configuration on our side.

## Test plan (device matrix)

Simulator has no Amazon app, so the app-open path needs a physical device.

| Case | Device state | Expect |
|---|---|---|
| Tap post product (`/dp` + tag) | Amazon app installed | Amazon app opens on product page; Associates dashboard later shows tagged click |
| Same | Amazon app NOT installed | `SafariView` sheet, tagged URL (today's behavior) |
| Search-fallback link (`/s?k=`) | installed | Amazon app opens search results |
| User disabled UL for Amazon (long-press → Open in Safari) | installed | falls back to `SafariView`, no dead tap |
| Non-Amazon retailer URL | any | `SafariView` (unchanged) |
| Analytics | both | `destination` field distinguishes app vs browser |

Attribution smoke test: use the real tag, tap through on device, check
Associates Central → Reports → clicks within ~24h.

## Open questions for product

- Keep search-fallback links routing to the app too, or browser-only? (App
  search results page is a stronger buy context; recommend app.)
- Should the guest/web invite flow get the same treatment via Smart App
  Banner deep-through? (Separate workstream — web already has OneLink notes.)
