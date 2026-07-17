# Giftmaxxing launch page design QA

- Source visual truth: `design-audit/getlimits/01-hero.png`
- Implementation: `design-audit/02-launch-desktop.png`
- Combined comparison: `design-audit/07-reference-vs-launch.png`
- Responsive evidence: `design-audit/03-launch-mobile.png`,
  `design-audit/04-launch-mobile-features.png`,
  `design-audit/06-launch-mobile-phone.png`
- Viewports: desktop reference and implementation normalized to 720px height;
  mobile at 390×844
- State: launch-page hero and primary screen-story flow

## Full-view comparison

The implementation matches the reference rhythm: quiet navigation, oversized
two-tone headline, short supporting copy, pill CTA, and overlapping authentic
iPhone captures. Giftmaxxing intentionally keeps its cream/coral product tokens
instead of copying Limits' blue-white palette.

## Focused comparison

- Hero: headline and device cluster have separate readable columns; no copy is
  hidden by the phones after the first QA adjustment.
- Mobile: hero, brand circles, feature pills, and screen stories fit 390px with
  no horizontal overflow.
- Product imagery: every phone contains a real 1320×2868 Simulator capture.
  Brand marks use local SVG assets; there are no placeholder screens.

## Required fidelity surfaces

- Typography: Hanken Grotesk preserves the source's dense geometric headline
  feel; weights, wrapping, and muted second-line hierarchy are consistent.
- Spacing: the large quiet hero, bordered brand strip, and alternating story
  cards keep the source's slow vertical rhythm.
- Colors: cream, ink, warm gray, white, and coral map directly to the existing
  Giftmaxxing design tokens.
- Image quality: source captures are full-resolution App Store screenshots,
  rendered through `next/image`; crops remain sharp and undistorted.
- Copy: all claims describe shipped product surfaces. Launch language says
  "launching soon" and "currently in App Store review."

## Interaction and accessibility checks

- "See the iPhone app" scrolls to `#screens`.
- Web-app CTA resolves to `/feed`.
- Privacy and Support remain `/privacy` and `/support`.
- Browser console: no errors.
- Mobile document width: 390px; no overflow.
- Semantic headings, navigation labels, image alt text, and visible focusable
  links are present.

## Comparison history

1. P1: the first desktop hero let the phone cluster overlap the last headline
   word. Reduced the responsive display size and recaptured.
2. Post-fix: no actionable P0/P1/P2 issues remain.

## Follow-up polish

- P3: replace "App Store soon" with the live product-page link after approval.

final result: passed
