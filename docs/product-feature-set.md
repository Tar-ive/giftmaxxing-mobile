# Giftmaxxing product and intended use

Giftmaxxing is a shared gift-discovery and planning app. It shortens the path
from inspiration, to a relevant product, to the merchant listing, while helping
people remember recipients, dates, budgets, and what each person actually likes.

## Core experience

- **Home:** a server-ranked, near-infinite two-column feed of approved products
  and editorial carousels. Theme and tag pills refine the same recommender.
- **Swipe:** product-only taste learning for yourself or a recipient. Cards show
  verified listing imagery, product features, price, merchant, and a direct shop
  link. Decisions update the taste profile and community recipient rankings.
- **Search:** text and photo search over the approved catalog, with personalized
  ranking and direct retailer links.
- **Maxi:** an AI gifting concierge that can read and write gifting memory, refer
  to and update dates, read the catalog and cart, and add items to the cart.
- **Circles:** people, important dates, collaborative Gift Boards, swipe
  challenges, reminders, and group gift pools.
- **You:** profile and taste controls, Gift Boards, cart, purchase tracking,
  birthday perks, account settings, privacy controls, and account deletion.

## Content and shopping

- Approved inspiration carousels connect ideas to verified product records.
- Every recommended product can carry merchant, price, availability, features,
  offer URL, and provenance; uncertain matches are withheld instead of padded
  with unrelated products.
- Product links open the merchant listing. The app records the outbound click
  for attribution but does not claim to process the merchant's checkout.
- Users can publish UGC with photos and captions and are strongly encouraged to
  attach the products shown. Uploads are identity-bound and moderated before
  becoming feed-eligible.
- Boards organize possibilities; the cart represents committed choices. Gift
  pools let friends coordinate contributions without duplicating gifts.
- Packaging guidance turns the selected cart into wrapping materials, palette,
  steps, and a note idea.

## Personalization and learning

- Immediate event learning covers impressions, dwell, search taps, likes,
  saves, hides, product clicks, purchases, and challenge answers.
- The mixer uses the same catalog and taste primitives for Home, pills, search,
  challenge learning, and final recipient recommendations.
- Model training runs every three days. Candidates are evaluated and remain
  pending manual approval; training never promotes over the production champion
  automatically.
- A ten-person synthetic evaluation checks relevance, diversity, shoppability,
  content mix, duplication, personalization lift, and challenge improvement.

## Delivery and control boundary

Approved inventory, carousel membership, prices, links, features, ranking,
mixing cadence, and taxonomy are server-controlled and can change without a new
iOS build. The installed app still owns screen layout, gestures, navigation,
local caching, and the set of API fields it understands; changing those requires
an App Store update. Bundled catalog data exists only as an offline fallback.

Authenticated mobile recommendation and event requests use a signed protobuf
envelope. The server binds recommendations to the authenticated actor and
rejects invalid signatures when signature enforcement is enabled.
