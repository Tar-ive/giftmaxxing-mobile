# Wishwave guide pilot

Fourteen internal carousel prototypes using Wishwave and GiftOffList guides only
as human discovery signals. Product availability, destination URLs, prices, and
images were checked against merchant pages on 2026-08-11. All copy is original.

Wishwave's terms prohibit scraping/copying. Do not bulk ingest its article text or
media, and do not publish these prototypes until image usage rights are confirmed.
For production, use licensed affiliate/product feeds or obtain permission.

```bash
node marketing-assets/carousels/wishwave-pilot-2026-08-11/render.mjs
node marketing-assets/carousels/wishwave-pilot-2026-08-11/sync-to-ios.mjs
```

Each output folder contains six 1080x1350 slides, a contact sheet, caption,
source analysis, and an app-ready review manifest. Manifests remain
`prototype_review_required`; nothing is uploaded automatically.

The current set covers fourteen gift genres across four layout families: 84
slides and 70 verified merchant products. The sync command copies reviewed
slides into the iOS bundle and adds their journeys/products to the same manifest
used by the AWS curation publisher.
