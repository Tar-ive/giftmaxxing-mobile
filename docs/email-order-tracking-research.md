# Email order tracking — dedicated forward-to address (research + cheapest design)

> **Status: research + design, Jul 2026.** Nothing built yet. This doc is the spec for the
> "dedicated email address" order-tracking feature: every user gets a unique address like
> `u-7f3k2m9q@orders.giftmaxxing.com`; they forward (or auto-forward) order-confirmation /
> shipping emails from Amazon, Walmart, Target, SHEIN, Etsy, etc. to it; we parse order
> number, merchant, items, dates, tracking numbers — including PDF confirmations — and
> surface order/delivery status in the app, tied to Gift Boards ("you shared the list,
> they confirmed, now you're ordering — track it all in one place").
>
> **Verdict: viable, cheap, and a great fit for the existing stack.** The whole thing runs
> on infra we already have (SES, Lambda, DynamoDB, Bedrock, S3) at **≈ $1–5/month at
> 5k emails/month, effectively $0 at current scale**. The ONLY hard prerequisite is one
> we don't have yet: **a custom domain** (repo-wide search confirms no `giftmaxxing.com`
> or Route53/ACM resources exist anywhere) — ~$10–14/yr, the sole fixed cost.

---

## 1. Viability — is forward-to-address a proven pattern?

Yes. It is the classic low-friction alternative to full inbox OAuth:

- **TripIt** (`plans@tripit.com`, since 2007) — the canonical example: forward any travel
  confirmation, get a parsed itinerary. Users learned this behavior 18 years ago.
- **Manus AI "Mail Manus"** (what the user referenced as "Manas AI") — each user gets a
  unique bot address; forwarding an email triggers an agent task on its contents.
- **ShipShow** (AI package tracker) — forward order confirmations, it extracts tracking
  across 1000+ carriers. Purpose-built proof that LLM parsing of retail emails works.
- Historical: Slice, Shop (Arrive), Route, Parcel — all built businesses on parsing
  order/shipping emails (mostly via inbox OAuth; the forward model gets ~the same data
  without the privacy problem).

### Why forward-to-address beats Gmail/Outlook OAuth (the "Option 1" it simplifies)

| | Dedicated address (this doc) | Inbox OAuth (Gmail API etc.) |
|---|---|---|
| Dev cost | Low — receive + parse | High — OAuth, sync, token refresh, per-provider APIs |
| **Hidden cost** | none | Gmail *restricted scopes* require an annual **CASA security assessment** (thousands of $/yr) + Google app review; Outlook has its own review |
| Privacy story | User hands over nothing; address only ever sees what they forward | "Give us read access to your entire inbox" — churn + App Review scrutiny |
| Data purity | ~100% shopping emails → high parse accuracy | Must classify the whole inbox first |
| Friction | User must forward (or set up auto-forward) per email/retailer | Zero after consent |

The friction disadvantage is real but mitigable (§6): a good onboarding screen, one-tap
copy/add-to-contacts, per-retailer "use this as your notification email" tips, and Gmail
auto-forward setup (with the verification-code gotcha handled — see §6.3).

---

## 2. Receiving options compared — cheapest first

All prices verified Jul 2026 (links in §9). A domain is required for every option.

| Option | Cost | Notes |
|---|---|---|
| **AWS SES inbound receiving** ✅ recommended | **$0.10 / 1,000 emails + $0.09 / 1,000 chunks** (1 chunk = 256 KB incl. attachments). Free tier: 3,000 msgs/mo for the first 12 months of SES use (shared with outbound — we already send lockout emails, so the clock may already be running/expired; check the console). | Native to our account/region (receiving IS supported in us-east-1, where everything already lives). Receipt rule → S3 (raw MIME) + Lambda. Max inbound message size 40 MB with the S3 action *(verify)*. Spam/virus/SPF/DKIM verdicts included free. |
| **Cloudflare Email Routing + Email Worker** | **$0** for routing (no message limits); Worker CPU limits apply on the free plan (big MIME/PDF parses may need the $5/mo Workers Paid plan) | Genuinely free, but: DNS must move to Cloudflare, it's a second platform to operate, and the Worker would call back into AWS anyway. Right choice only if we refuse SES's ~$1/mo. |
| **Postmark inbound** | $15/mo (100 emails/mo free dev tier) | Best DX (JSON webhook, 45-day retention). Not cheapest. |
| **Mailgun inbound routes** | $15/mo Basic (Flex pay-as-you-go was killed Dec 2025) | Best-in-class routing rules; fixed cost we don't need. |
| **SendGrid Inbound Parse** | $19.95/mo (permanent free plan eliminated May 2025) | No. |

**Decision: SES inbound.** It keeps everything in the account we already run, reuses the
existing Lambda/IAM/Terraform patterns, costs ~$1/mo at 5k emails, and its S3 action gives
us durable raw-MIME storage (replayable when we improve the parser) for free.

---

## 3. Cheapest architecture (all existing building blocks)

```
retailer / user forwards
        │
        ▼
MX orders.giftmaxxing.com ──▶ SES inbound (us-east-1)
        │  receipt rule: domain catch-all, spam/virus verdict drop
        ├──▶ S3 giftmaxxing-dev-media  key: inbound/<messageId>.eml   (raw MIME, 90-day lifecycle)
        └──▶ Lambda "order-parser"  (S3 event or SES Lambda action)
                │ 1. mailparser/postal-mime → text/HTML + attachments
                │ 2. alias local-part → userId  (GRAPH emailAlias# row)
                │ 3. Tier-1 deterministic extractors (regex, free)
                │ 4. Tier-2 Bedrock structured extraction (Nova Lite / Haiku)
                │ 5. PDF attachments → same Bedrock call (Converse document block)
                ▼
        DynamoDB GRAPH table — ORDER# rows (extend the existing model)
                ▲
   handler.mjs: GET /orders · GET /me returns orderEmail · match → Gift Board items
                ▲
   iOS: Orders screen + status chips on Gift Board items ("Ordered · arrives Fri")
```

### 3.1 Address scheme + provisioning (no new table)

- `orderEmail = "u-" + base32(hmacSHA256(ORDERS_ALIAS_SECRET, userId)).slice(0,10) + "@orders.giftmaxxing.com"` —
  deterministic, non-guessable, non-enumerable (don't use raw userIds; they appear in URLs).
- HMAC isn't reversible, so on first read of `GET /me` write a reverse-lookup row to the
  existing **GRAPH** table: `{ pk: "emailAlias#u-7f3k2m9q", sk: "owner", userId }`. Parser
  Lambda resolves recipient → userId with one Get. Unknown alias → drop silently.
- SES receipt rule matches the whole `orders.` subdomain (catch-all), so no per-user SES
  config ever.

### 3.2 Receiving (net-new Terraform, small)

1. Register `giftmaxxing.com` (Route53 ~$14/yr, or Cloudflare Registrar at-cost ~$10/yr —
   cheapest; DNS can stay wherever the domain lives, we only need records).
2. Route53 hosted zone ($0.50/mo) *or* free DNS at the registrar. Records:
   `MX orders.giftmaxxing.com → 10 inbound-smtp.us-east-1.amazonaws.com`.
3. SES: verify domain identity `orders.giftmaxxing.com`; receipt rule set (activate — the
   account has none today) with one rule: recipients `orders.giftmaxxing.com` →
   S3 action (`${prefix}-media`, prefix `inbound/`) + Lambda action (async) → drop.
   Enable spam/virus scanning; bounce/ignore on `spamVerdict: FAIL`.
4. New Lambda `${prefix}-order-parser` — reuse the `reminders.tf` pattern (same zip, same
   role, different handler entry). IAM adds: S3 `GetObject` on `inbound/*` (the API role
   currently has **no** media-bucket policy at all — net-new statement), `bedrock:InvokeModel`
   (already granted), DynamoDB on GRAPH (already granted).

### 3.3 Parsing — the two-tier cost trick

**Tier 1 — deterministic (free, covers most volume).** Retailer confirmation emails are
templated; the high-value fields are regex-able:

- Amazon order numbers: `\b\d{3}-\d{7}-\d{7}\b`; Target: `\b10\d{8,}\b`; generic
  `Order (#|No\.?|Number:?)\s*([A-Z0-9-]{5,})`.
- Tracking numbers: UPS `1Z[A-Z0-9]{16}`, FedEx `\b\d{12,15}\b`, USPS `\b9[234]\d{20,24}\b`.
- Merchant from `From:` domain (amazon.com, ship-confirm@…), date from the `Date` header,
  totals from `\$\d+\.\d{2}` near "total".
- Email type from subject: "Ordered:" / "Your order has shipped" / "Delivered:".

**Tier 2 — Bedrock structured extraction (only when Tier 1 is incomplete).** One Converse
call with a JSON schema (same pattern as Maxi's tool use in `handler.mjs`):

```json
{ "merchant": "", "orderNumber": "", "orderDate": "", "items": [{"name":"","qty":1,"price":0}],
  "total": 0, "currency": "USD", "trackingNumbers": [{"carrier":"","number":""}],
  "estimatedDelivery": "", "status": "ordered|shipped|out_for_delivery|delivered|cancelled",
  "recipientAddressCity": "", "confidence": 0.0 }
```

Model choice (Bedrock, on-demand, per-1M tokens): **Nova Lite $0.06 in / $0.24 out** —
the cheapest thing that reliably does structured extraction; **Claude Haiku 4.5 $1 / $5**
as the accuracy escalation when Nova returns low `confidence` or fails schema validation.
Make it an env var (`ORDERS_PARSE_MODEL_ID`, `ORDERS_PARSE_FALLBACK_MODEL_ID`) like the
existing `MAXI_*` vars. A stripped order email is ~2–5k tokens → **Nova ≈ $0.0002–0.0004
/email; Haiku ≈ $0.005/email**. HTML → text first (strip tags/CSS) to cut tokens ~5–10×.

**PDFs (the SHEIN/airline-style confirmation attachment case).** Bedrock **Converse
document blocks** accept PDFs natively — for Claude models each page is processed as
text+image, up to 100 pages; the old 4.5 MB/doc cap is documented as lifted for PDF on
Claude 4+ models *(verify at build time; keep a 4.5 MB guard + "download too-large PDFs
skipped" fallback either way)*. So a PDF attachment is just another content block in the
same extraction call — no Textract needed (Textract would be $1.50/1k pages; skip unless
PDFs prove hostile). Non-PDF attachments (images of receipts) also work via image blocks.

**Multi-email lifecycle.** Retailers send 2–4 emails per order (confirm → shipped →
delivered). Upsert by `(userId, merchant, orderNumber)`: the shipped email adds tracking
+ ETA to the existing row; the delivered email flips status. This is how "track
everything" happens with zero carrier-API spend.

### 3.4 Storage — extend the existing ORDER# model (zero new tables)

`handler.mjs` already has an orders concept: `saveOrder()` writes
`{ pk: userId, sk: "ORDER#<ts>#<id>", kind: "order", items[], total }` to **GRAPH**
(Maxi's purchase-history tool, incl. `synthStarterOrders` fakes). Cheapest + most
consistent move: **make parsed emails write the same row shape, extended**:

```
sk: "ORDER#<orderDate>#<merchant>#<orderNumber>"
+ merchant, orderNumber, status, trackingNumbers[], estimatedDelivery, deliveredAt,
+ source: "email" (vs "synthetic"/"maxi"), rawEmailKeys[] (S3 pointers), emailCount
```

- Maxi's `toolOrderHistory` instantly gets REAL purchase history (better gift
  recommendations for free).
- `DELETE /account` → `purgeByPartition(GRAPH, userId)` already wipes these rows — account
  deletion compliance holds with no extra work. Add: delete `inbound/*` S3 objects listed
  in `rawEmailKeys` during purge, and the `emailAlias#` row.
- A dedicated `${prefix}-orders` table (PK userId, SK orderId, GSI byTracking) is the
  scale-up option only if GRAPH gets hot — not needed now.

### 3.5 API + app surface

- `GET /me` response gains `orderEmail` (computed + alias row write-through).
- `GET /orders?userId=` — list parsed orders (auth-gated like `/me`; prefer `auth.sub`
  over the query param, per the known handler.mjs scoping quirk).
- `POST /orders/{id}/dismiss`, `DELETE /orders/{id}`.
- **Gift Board tie-in (the point of the feature):** when a new order lands, fuzzy-match
  item names against the user's Gift Board posts (client can do this too — boards are in
  the `/me` profile as `giftBoards`). Matches set a per-board-item
  `orderStatus: ordered|shipped|delivered` → iOS shows status chips on
  `SwipeListDetailView` items and a "Gifts on the way" rail. The existing share→confirm
  flow (board → `deckMode:"exact"` challenge → recipient swipes) is unchanged; this adds
  the *after* — "confirmed → ordered → arriving Friday" — completing the loop the user
  described.
- Push: order-delivered → APNs via the existing `${prefix}-devices` + SNS platform app.

---

## 4. Cost summary (the "cheapest solution" numbers)

Assume a generous 1,000 active users × 5 forwarded emails/mo = **5,000 emails/mo**, avg
300 KB (2 chunks), 10% with PDFs, Tier 1 regex resolving ~50% without an LLM call:

| Item | Math | $/mo |
|---|---|---|
| Domain (only fixed cost) | ~$12/yr | **$1.00** |
| Route53 hosted zone (skippable w/ registrar DNS) | $0.50 | $0.50 |
| SES receiving | 5k msgs = $0.50 + 10k chunks = $0.90 | $1.40 |
| S3 raw MIME (90-day lifecycle) | ~1.5 GB rolling | $0.04 |
| Lambda parser | ~5k × 2s × 256 MB | ~$0.05 |
| Bedrock Nova Lite (2.5k LLM-parsed × ~4k tokens) | 10M in × $0.06 + out | ~$0.65 |
| Bedrock Haiku 4.5 escalations (5%) | 250 × $0.005 | ~$1.25 |
| DynamoDB writes | ~15k upserts | ~$0.02 |
| **Total at 5k emails/mo** | | **≈ $5/mo** |
| **Total at current scale (~40 users)** | | **≈ $1/mo (the domain)** |

No idle cost anywhere; every line scales to zero. The SES free tier (3k msgs/mo, first
12 months of SES use) may cover receiving entirely at launch.

For contrast: the fixed-fee SaaS route (Postmark/Mailgun) starts at $15–20/mo before a
single email, and inbox OAuth carries a recurring 4-figure CASA assessment.

---

## 5. Risks / gotchas (build these in from day 1)

1. **Spam + spoofing.** The addresses are public-ish once users paste them into retailer
   accounts. Mitigate: SES spam/virus verdict drop (free), unknown-alias drop, per-alias
   rate limit (e.g. 50/day via a CONFIG counter), and never render email HTML in-app —
   only parsed fields.
2. **Prompt injection via email content.** The email body is untrusted input flowing into
   an LLM. The parser prompt must be extraction-only with a strict JSON schema, no tools,
   and outputs validated/coerced before storage. Never let email text reach Maxi's
   tool-using agent loop directly.
3. **PII.** Order emails contain names + home addresses. Store only what we surface
   (city-level at most), lifecycle-expire raw MIME at 90 days, and wire S3 cleanup into
   `DELETE /account` (§3.4).
4. **Gmail auto-forward verification.** When a user sets up auto-forwarding, Gmail first
   sends a confirmation code TO the dedicated address. The parser must detect
   `forwarding-noreply@google.com`, extract the code/link, and surface it in-app
   ("Confirm your Gmail auto-forward: 482913") — otherwise auto-forward setup silently
   dead-ends. TripIt et al. all handle this. Same for Outlook rules.
5. **Forwarded-email mangling.** "Fwd:" emails wrap the original (sometimes as an
   attachment, sometimes inline-quoted). mailparser handles `message/rfc822` attachments;
   the LLM tier is robust to inline-quoted noise — another reason not to go regex-only.
6. **SES account state.** Receiving needs no production-access request (that's for
   sending), but verify the receipt-rule-set activation and the 40 MB inbound size limit
   during build. Region must be us-east-1/…-west-2/eu-west-1 — we're already us-east-1. ✅

---

## 6. Onboarding UX (the churn mitigation)

1. **Reveal the address** on an "Track your gift orders" screen (You tab + post-share
   nudge on Gift Boards): big copy button, "Add to Contacts" (`CNContact` with our icon so
   it autocompletes in Mail), QR for the desktop.
2. **Two usage modes, pitched in order of effort:**
   - *Zero-setup:* "Just forward any order confirmation to this address." (works today,
     every retailer, every inbox)
   - *Set-and-forget:* per-retailer "add as your notification email" tips + Gmail/Outlook
     auto-forward filter recipes (`from:(amazon.com OR walmart.com OR target.com …)`),
     with the §5.4 verification-code flow handled in-app.
3. **Instant gratification:** first parsed email triggers a push + the order appears with
   a confetti moment; a "send yourself a test email" button makes the demo self-serve.
4. Board tie-in nudge: after a recipient confirms a shared list ("3 yeses on Mom's
   board"), prompt: "Ordering these? Forward the confirmations and I'll track them."

---

## 7. Phased build plan

- **Phase 1 — receive + parse + list (the MVP).** Domain + MX + SES receipt rule → S3 +
  parser Lambda (mailparser, Tier-1 regex, Nova Lite fallback, PDF via Converse) → GRAPH
  ORDER# upserts → `GET /orders` + `orderEmail` in `/me` → iOS Orders list + onboarding
  screen. *(All net-new code; Terraform: ~1 zone, 1 SES identity, 1 rule set, 1 Lambda,
  2 IAM statements, S3 lifecycle rule.)*
- **Phase 2 — lifecycle + boards.** Shipped/delivered upserts, Gift Board item matching +
  status chips, delivered push, Gmail-verification-code handling, Maxi reads real orders.
- **Phase 3 — polish/scale (only if usage demands).** Carrier tracking polls for
  merchants that don't email delivery notices (17track/AfterShip are paid; USPS/UPS/FedEx
  direct APIs have free keys), Haiku escalation tuning, dedicated orders table,
  price-drop cross-link into the deal-monitoring backlog item.

---

## 8. What already exists to reuse (from the Jul 2026 repo audit)

| Piece | Where | Reuse |
|---|---|---|
| ORDER# rows + order tools | `infra/src/handler.mjs` (`saveOrder`, `toolOrderHistory`, GRAPH table) | The storage model + Maxi integration, as-is |
| SES client + outbound IAM | `handler.mjs` (lockout email), `infra/iam.tf` | Account is SES-active; add receiving side |
| Second-Lambda pattern | `infra/reminders.tf` (same zip, different handler, EventBridge) | Template for the parser Lambda |
| Bedrock IAM + model env-var pattern | `MAXI_*` vars, existing `bedrock:InvokeModel` | Parser model config |
| Private media bucket | `infra/s3.tf` (`${prefix}-media`) | `inbound/` prefix + lifecycle rule |
| Gift Boards (client + `/me` sync) | `SwipeListStore.swift`, `giftBoards` in profile | Order↔board matching, status chips |
| Push | `sns-apns.tf`, `${prefix}-devices` | Delivered notifications |
| Account deletion | `DELETE /account` → `purgeByPartition` | Orders purge rides along; add S3 + alias cleanup |

**Net-new:** the domain (user action: register it), SES receiving Terraform, the parser
Lambda code (`mailparser` + prompt), `/orders` routes, iOS Orders UI. No new tables, no
new vendors, no fixed fees beyond the domain.

---

## 9. Sources

- [Amazon SES pricing](https://aws.amazon.com/ses/pricing/) — $0.10/1k inbound emails + $0.09/1k 256KB chunks; 3k msgs/mo free first 12 months; Mail Manager alternative ($0.15/1k + $50/mo ingress endpoint — not worth it here).
- [Amazon Bedrock pricing](https://aws.amazon.com/bedrock/pricing/) — Nova Lite $0.06/$0.24 per 1M tokens; Claude Haiku 4.5 $1/$5; Nova Micro $0.035 in.
- [Bedrock Converse API restrictions](https://docs.aws.amazon.com/bedrock/latest/userguide/inference-api-restrictions.html) + [Claude PDF support on Bedrock](https://builder.aws.com/content/2yuuUoj0uthPd6M3GR7t2SZ4r8E/claude-pdf-support-on-amazon-bedrock) — PDF document blocks, ≤100 pages; 4.5 MB/doc cap documented as lifted for PDFs on Claude 4+ *(verify)*.
- [Cloudflare Email Routing](https://www.cloudflare.com/products/email-routing/) + [Email Workers](https://developers.cloudflare.com/email-routing/email-workers/) — free routing, Worker CPU limits on free plan.
- [Postmark pricing/restructure](https://postmarkapp.com/compare/sendgrid-alternative) ($15–18/mo, inbound at Pro tier), Mailgun Flex removal → $15/mo Basic (Dec 2025), SendGrid free plan eliminated (May 2025) — via [pingram.io comparison](https://www.pingram.io/blog/best-inbound-email-notification-apis) and [buildmvpfast](https://www.buildmvpfast.com/api-costs/email).
- [Mail Manus](https://manus.im/docs/features/mail-manus) (the "Manas AI" reference) and [ShipShow](https://apps.apple.com/us/app/shipshow-ai-package-tracker/id6741838725) — forward-to-address precedents.
