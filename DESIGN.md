---
name: Giftmaxxing iOS
version: alpha
description: >
  Design system for the Giftmaxxing SwiftUI iOS app. Warm, editorial,
  gift-boutique feel — one coral accent over cream/ink neutrals, generous
  whitespace, soft continuous corners, spring motion with haptics.
  This file is the single source of truth for all UI work: coding agents
  MUST resolve every color, font, radius, spacing, and shadow through the
  tokens below (exposed in Swift via Giftmaxxing/Extensions/Theme.swift).
colors:
  # Light values below are the reference; each token also has a dark
  # variant resolved by Color.dynamic(light:dark:) in Theme.swift.
  primary: "#FB6F52"        # coral — the ONLY accent. Interactivity signal. (dark #FF7F63)
  primary-emphasis: "#E85A3D" # pressed/darkened coral (dark #FF9A80)
  primary-soft: "#FFF0ED"    # coral tint fill (selected chips, soft badges) (dark #3A2620)
  gradient-start: "#FB6F52"  # brand gradient = primary → gradient-end, topLeading→bottomTrailing
  gradient-end: "#FF9A76"
  background: "#F7F2EB"      # cream — app/screen background (dark #141210)
  surface: "#FFFFFF"         # cards, sheets, rows (dark #1E1B18)
  surface-sunken: "#F1EAE0"  # inset wells, skeleton base (dark #2A2620)
  text-primary: "#1A1A1A"    # ink (dark #F5F1EA)
  text-secondary: "#6B6560"  # warm gray — metadata, subtitles (dark #B3ABA1)
  text-tertiary: "#9B948C"   # timestamps, placeholders (dark #867E75)
  border: "#E5E0D8"          # hairlines only (0.5–1pt). Never decorative heavy borders. (dark #332E28)
  success: "#3E8E5A"         # (dark #5FB77F)
  danger: "#D64545"          # (dark #F06B6B)
  on-primary: "#FFFFFF"      # text/icons on coral
  scrim: "#1A1A1ACC"         # image overlays (80% ink), price badges
typography:
  display:                   # hero numbers, splash — SF Pro Rounded
    fontFamily: "SF Pro Rounded"
    fontSize: 34pt
    fontWeight: 700
  title:                     # screen titles — maps to .title2 + .fontDesign(.rounded)
    fontFamily: "SF Pro Rounded"
    fontSize: 22pt
    fontWeight: 700
  section:                   # section headers — maps to .title3 rounded
    fontFamily: "SF Pro Rounded"
    fontSize: 20pt
    fontWeight: 600
  headline:                  # card titles, row titles — maps to .headline
    fontFamily: "SF Pro"
    fontSize: 17pt
    fontWeight: 600
  body:                      # maps to .body
    fontFamily: "SF Pro"
    fontSize: 17pt
    fontWeight: 400
  subheadline:               # secondary row text — maps to .subheadline
    fontFamily: "SF Pro"
    fontSize: 15pt
    fontWeight: 400
  footnote:                  # metadata — maps to .footnote
    fontFamily: "SF Pro"
    fontSize: 13pt
    fontWeight: 400
  caption:                   # badges, overlines — maps to .caption, +0.5pt tracking when uppercased
    fontFamily: "SF Pro"
    fontSize: 12pt
    fontWeight: 500
rounded:
  sm: 8px      # thumbnails, small controls
  md: 12px     # buttons (non-capsule), inputs, nested images inside cards
  lg: 16px     # cards, sheets-inner
  xl: 24px     # hero cards, modal covers
  full: 999px  # capsule — pills, chips, primary CTA
spacing:
  xxs: 4px
  xs: 8px
  sm: 12px
  md: 16px    # default gutter + default intra-card padding
  lg: 20px
  xl: 24px
  xxl: 32px
  xxxl: 48px
components:
  button-primary:
    backgroundColor: "{colors.primary}"
    textColor: "{colors.on-primary}"
    typography: "{typography.headline}"
    rounded: "{rounded.full}"
    padding: "14px 20px"
    height: 50px
  button-primary-pressed:
    backgroundColor: "{colors.primary-emphasis}"
    textColor: "{colors.on-primary}"
    typography: "{typography.headline}"
    rounded: "{rounded.full}"
    padding: "14px 20px"
    height: 50px
  button-secondary:
    backgroundColor: "{colors.primary-soft}"
    textColor: "{colors.primary}"
    typography: "{typography.headline}"
    rounded: "{rounded.full}"
    padding: "14px 20px"
    height: 50px
  button-quiet:
    backgroundColor: "{colors.surface}"
    textColor: "{colors.text-primary}"
    typography: "{typography.subheadline}"
    rounded: "{rounded.full}"
    padding: "10px 16px"
  chip:
    backgroundColor: "{colors.surface}"
    textColor: "{colors.text-primary}"
    typography: "{typography.subheadline}"
    rounded: "{rounded.full}"
    padding: "8px 14px"
  chip-selected:
    backgroundColor: "{colors.primary-soft}"
    textColor: "{colors.primary}"
    typography: "{typography.subheadline}"
    rounded: "{rounded.full}"
    padding: "8px 14px"
  card:
    backgroundColor: "{colors.surface}"
    textColor: "{colors.text-primary}"
    rounded: "{rounded.lg}"
    padding: "{spacing.md}"
  section-header:
    textColor: "{colors.text-primary}"
    typography: "{typography.section}"
    padding: "24px 16px 8px 16px"
  badge:
    backgroundColor: "{colors.primary-soft}"
    textColor: "{colors.primary}"
    typography: "{typography.caption}"
    rounded: "{rounded.full}"
    padding: "4px 10px"
  list-row:
    backgroundColor: "{colors.surface}"
    textColor: "{colors.text-primary}"
    typography: "{typography.body}"
    padding: "12px 16px"
    height: 52px
---

# Giftmaxxing iOS Design System

## Overview

Giftmaxxing is a gifting companion — the feel is a **warm, curated gift
boutique**, not a marketplace. Think editorial calm (Airbnb, Notion,
Aesop) rather than promotional density (Temu, Wish). Three words govern
every screen: **warm, calm, intentional**.

The visual identity is built from restraint:

- **One accent.** Coral (`{colors.primary}`) is the only saturated color on
  any screen, and it always means "you can act here." Everything else is
  cream, white, ink, and warm gray. If a screen has coral in more than
  ~10% of its pixels, remove some.
- **Whitespace is the luxury signal.** Fewer items per viewport, larger
  imagery, more breathing room. Density is the single biggest driver of
  the "cheap catalog" look — when in doubt, show less.
- **Motion is feedback, not decoration.** Springs + haptics on state
  changes; nothing loops or pulses idly (the Maxi FAB is the sole
  exception).
- **Follow Apple HIG defaults** (hierarchy, harmony, consistency; see
  <https://developer.apple.com/design/human-interface-guidelines>).
  Deviate only where this file explicitly says so.

**Agent contract (read before touching any view):**

1. Never write a literal color, font size, corner radius, spacing value,
   or shadow in a view. Use the tokens above via `Theme.swift`
   (`Color.*`, `Font.*`, `Spacing.*`, `Radius.*`, `CardShadow.*`). If a
   token is missing, add it to `Theme.swift` **and** to this file in the
   same PR.
2. Never use `.font(.system(size:))`. Use Dynamic Type text styles
   (mapping in **Typography** below) so text scales with accessibility
   settings.
3. Never restyle a button inline. Use the shared `ButtonStyle`s
   (**Components** below).
4. All rounded corners use `style: .continuous`.
5. Every new interactive element gets: ≥44×44pt tap target, an
   `accessibilityLabel`, a pressed state, and (if it commits an action)
   `sensoryFeedback`.
6. Respect `@Environment(\.accessibilityReduceMotion)` — swap springs
   and loops for opacity crossfades when it is set.

## Colors

**Roles, not hues.** Every color has exactly one job:

| Token | Job |
|---|---|
| `primary` | Interactivity. Buttons, selected states, links, tab tint. Nothing decorative. |
| `primary-soft` | Selected-chip fill, soft badges, tinted secondary buttons. |
| `background` | Screen background (cream). Screens are never pure white. |
| `surface` | Cards, rows, sheets sit on cream as white surfaces. |
| `text-primary` / `text-secondary` / `text-tertiary` | Three-step text hierarchy. Never use opacity to fake hierarchy (`.opacity(0.6)` on text is banned — use the token). |
| `border` | 0.5–1pt hairlines only. |
| `scrim` | The only permitted overlay on photos (price badges, story chrome). |
| `success` / `danger` | Semantic status only — never decorative. |

**Rules:**

- **Retire the 7-pastel `GradientStyle` palette as UI.** Avatars use a
  single system: `primary-soft` background + coral initials, or the brand
  gradient for the current user. Product placeholders use
  `surface-sunken`, never random pastels. (The pastel enum may survive in
  data models for legacy decode, but no view may render it.)
- **One gradient.** The brand gradient (`gradient-start → gradient-end`,
  topLeading → bottomTrailing) is the only fill gradient in the product
  UI. Onboarding/splash may additionally use the ambient mesh treatment
  (see Components → Onboarding).
- Text on photos always sits on `scrim`, never raw.
- **Dark mode is live.** Every token in `Theme.swift` resolves per trait
  collection via `Color.dynamic(light:dark:)`, and the user picks
  System / Light / Dark in Settings (`AppearanceStore`). Dark is a
  **warm** dark (brown-black `#141210`, never blue-black) so the
  boutique feel survives the switch; coral lightens slightly
  (`#FF7F63`) to hold contrast on dark surfaces.
- **Never hardcode `.white` / `.black` as a surface or text color** —
  they don't invert, and a white card on a dark screen is the classic
  tell. `Color.surface`, `Color.cream`, and `Color.ink` already flip.
  White is only correct for content sitting ON coral or on `scrim`.

## Typography

System fonts only: **SF Pro** for text, **SF Pro Rounded** for display
(the brand voice lives in rounded weights ≥ semibold at ≥ 20pt).

**Hard rule: semantic Dynamic Type styles only.** The YAML sizes above
are the *reference* (Large) sizes — in Swift, always map to text styles
so Dynamic Type works:

| Token | SwiftUI |
|---|---|
| `display` | `.font(.largeTitle.weight(.bold)).fontDesign(.rounded)` |
| `title` | `.font(.title2.weight(.bold)).fontDesign(.rounded)` |
| `section` | `.font(.title3.weight(.semibold)).fontDesign(.rounded)` |
| `headline` | `.font(.headline)` |
| `body` | `.font(.body)` |
| `subheadline` | `.font(.subheadline)` |
| `footnote` | `.font(.footnote)` |
| `caption` | `.font(.caption.weight(.medium))` |

- Max **two** type sizes per card; hierarchy comes from weight and the
  three text-color steps, not from a zoo of sizes.
- Prices and counters use `.monospacedDigit()`.
- Uppercased overlines (`caption` + `.tracking(0.5)`) are the only
  tracked text.
- Minimum text size anywhere: `caption2` (11pt). The current 8–10pt
  literals are banned.

**Copy rules (text density).** Too much text is the fastest way to lose
warm/calm/intentional:

- Screen intros are **one fragment, not a paragraph**. No multi-sentence
  subtitles or "why this tab exists" manifestos on primary tabs.
- Row/card subtitles are ≤ 4 words or absent. Empty states get one short
  sentence, never two.
- Explain a feature at the moment of failure or first use (an error, a
  tooltip), not pre-emptively in standing copy. Size limits, screening
  notices, and mechanics ("they swipe, you see answers") belong behind
  the interaction, not in front of it.

## Layout

- **4pt base grid**; all spacing from the `spacing` scale. Screen gutter
  is `md` (16pt) **everywhere** — the current 14/16/20 mix is why rows
  don't align across tabs.
- Section rhythm: `xl` (24pt) between sections, `sm` (12pt) between cards
  in a section, `md` (16pt) intra-card padding.
- **Tap targets ≥ 44×44pt**, no exceptions.
- Feed/list density: one dominant image per viewport-height on Home;
  Shop grid is 2-up with `sm` gaps, never 3-up.
- Let text containers grow (no fixed heights around text) — Dynamic Type
  will expand them.
- Respect safe areas; content scrolls under bars with
  `.scrollEdgeEffect`/material, never under opaque hand-drawn headers.

## Elevation & Depth

Exactly **three** levels. The current 9 ad-hoc shadow recipes (up to
45% black) are the "sticker on a page" tell — depth must be barely
perceptible:

| Level | Use | Recipe |
|---|---|---|
| 0 — flat | Rows, chips, inline elements | No shadow. Optional `border` hairline. |
| 1 — card | Cards, rails | `black 6%, radius 12, y 4` |
| 2 — floating | FAB, sheets, swipe deck top card | `black 10%, radius 24, y 8` |

- Never exceed 12% shadow opacity. Never colored shadows except the
  coral glow on splash/FAB (part of the brand mark treatment).
- Materials (`.ultraThinMaterial`/`.regularMaterial`) are for **chrome
  floating over content** (headers over scrolling feeds, story-viewer
  controls, the FAB backing) — the Liquid Glass rule. Never stack
  material on material; never use material as a card background.

## Shapes

- Every corner is `RoundedRectangle(cornerRadius:, style: .continuous)`
  or `Capsule()`. The default-style (circular) corner is banned.
- Scale: `sm` 8 · `md` 12 · `lg` 16 · `xl` 24 · capsule. Nothing else.
- **Concentric nesting** (HIG "harmony"): inner radius = outer radius −
  padding. Card `lg` (16) with `md` padding (16) → image inside gets
  effectively flush-safe `md`… in practice: images inside `lg` cards use
  `md` (12). The current 2pt product-image corners next to 16–20pt cards
  are the clearest single "cheap" artifact — fix on sight.
- Custom shapes (logo mark, decorative arcs) are implemented as a
  generic `Shape`-conforming type that scales an SVG path into
  `path(in rect:)` (M→`move`, L→`addLine`, C→`addCurve`,
  Q→`addQuadCurve`, Z→`closeSubpath`, coordinates scaled by
  `rect.width / viewBoxWidth`). Convert with
  <https://svg-to-swiftui.quassum.com/>. Shapes can then be filled,
  gradient-stroked, and `.trim`-animated — never bundle static SVG/PNG
  icons when an SF Symbol or Shape exists.

## Components

All shared components live in `Giftmaxxing/Views/Components/` and
styles in `Theme.swift`. **If two screens need it, it's a component.**

- **Buttons** — shared `ButtonStyle`s only: `PrimaryButtonStyle` (coral
  capsule, `on-primary` text, pressed = `primary-emphasis` +
  `scaleEffect(0.97)` spring), `SecondaryButtonStyle` (`primary-soft`
  fill, coral text), `QuietButtonStyle` (surface pill). Generalize the
  existing `FriendPillStyle` (`FriendsView.swift`) into these; delete
  every inline coral-pill rebuild.
- **Chip** — capsule, `surface` + hairline default; `chip-selected` =
  `primary-soft` fill + coral text + `sensoryFeedback(.selection)` +
  `.snappy` spring on toggle. Chips are text-first; at most one emoji,
  prefer SF Symbols.
- **Card** — `lg` continuous corners, `surface`, elevation 1, `md`
  padding, nested imagery `md` corners. One `.cardStyle()` ViewModifier.
- **Section header** — one shared view: `section` type + optional
  "See all" quiet button. Delete the three inline variants.
- **List row** — one shared row (icon, title, detail, chevron) reused by
  More/Circles/Pools; 52pt min height.
- **Avatar** — single treatment (see Colors); ring for stories = brand
  gradient stroke, 2pt.
- **Badge/price** — `scrim` capsule with white `caption` text on photos;
  `badge` token elsewhere.
- **Skeletons** — `surface-sunken` shapes with a shimmer sweep (the one
  approved decorative animation).
- **Maxi (assistant) surfaces** — Maxi owns the expressive budget: brand
  gradient, mesh-gradient ambient background allowed, `sparkles` symbol
  with `.symbolEffect(.pulse)` while thinking.
- **Onboarding/Splash** — the glass treatment (materials + mesh/radial
  glow) is Maxi's/onboarding's; the product body stays flat-calm. Bridge
  the two by reusing the brand gradient and rounded display type, and
  keep a glass echo on chrome (headers/FAB) so first-run doesn't feel
  like a different app. Replace the 🎁-emoji orb with the real logo mark
  (Shape-based) when available.

**Motion & haptics catalog** (the polished-feel toolkit — use these, not
`repeatForever`):

| Moment | Idiom |
|---|---|
| Default state change | `.snappy` (or `.spring(duration: 0.35, bounce: 0.15)`) |
| Reward (pledge, match, gift sent) | `.bouncy` + `.sensoryFeedback(.success, trigger:)` |
| Selection (chips, segmented, tabs) | `.snappy` + `.sensoryFeedback(.selection, trigger:)` |
| Swipe commit | `.sensoryFeedback(.impact(weight: .medium), trigger:)` |
| Icon feedback | `.symbolEffect(.bounce, value:)` on the changed symbol (e.g. heart, `sun.max`-style state icons); swap symbols with `.contentTransition(.symbolEffect(.replace))` |
| Changing numbers (totals, counts) | `.contentTransition(.numericText())` |
| Feed items entering | `.scrollTransition { c, phase in c.opacity(phase.isIdentity ? 1 : 0.6).scaleEffect(phase.isIdentity ? 1 : 0.96) }` |
| Hero (card → detail) | `matchedGeometryEffect` / iOS 18 `.navigationTransition(.zoom(sourceID:in:))` |
| Progress/celebration strokes | `shape.trim(from: 0, to: p).stroke(brandGradient, style: .init(lineWidth: 3, lineCap: .round))`, animate `p` |
| Premium border accent (Maxi/featured only) | `AngularGradient` stroke, slow rotation, blurred duplicate underneath for glow |

## Do's and Don'ts

**Do**

- Use coral for exactly one primary action per viewport.
- Use whitespace and imagery scale to signal quality; cut items before
  cutting padding.
- Pair every visual state change with a spring, and commits with a
  haptic.
- Use SF Symbols (filled = active/selected) sized by `imageScale`/text
  style, animated with `symbolEffect`.
- Add `accessibilityLabel`s to every interactive element you touch.
- Check Reduce Motion and Reduce Transparency for loops and materials.

**Don't**

- Don't hardcode any size, color, radius, or shadow in a view file.
- Don't use `.font(.system(size:))` — ever.
- Don't render UI from the pastel `GradientStyle` palette.
- Don't use emoji as icons, logos, or category art (chips may keep at
  most one leading emoji; prefer symbols). The 🎁 logo-as-Text is
  deprecated.
- Don't add borders heavier than 1pt or shadows darker than 12%.
- Don't introduce a second accent hue, a new gradient, or a new radius —
  extend this file first, in the same PR.
- Don't use `repeatForever` animations outside skeleton shimmer and the
  Maxi FAB pulse.
- Don't use `.opacity()` on text for hierarchy — use the three text
  tokens.
- Don't ship placeholder hacks (e.g. onboarding auto-advance timers
  marked `TEMP`).

---

### References for downstream agents

- Apple HIG (canonical): <https://developer.apple.com/design/human-interface-guidelines> — color, typography, materials, motion, SF Symbols pages.
- Liquid Glass: <https://developer.apple.com/documentation/TechnologyOverviews/liquid-glass>
- Apple Design Awards (the quality bar): <https://developer.apple.com/design/awards/>
- Real-app pattern galleries: Mobbin <https://mobbin.com> · Page Flows <https://pageflows.com> · Appshots (motion) <https://appshots.design> · Pttrns <https://pttrns.com> · UI Sources <https://uisources.com>
- SwiftUI recipes: Hacking with Swift <https://www.hackingwithswift.com/quick-start/swiftui> · Design+Code handbook <https://designcode.io/swiftui-handbook> · Create with Swift <https://www.createwithswift.com>
- SVG → SwiftUI Shape converter: <https://svg-to-swiftui.quassum.com/>
- Token-architecture reference (structure, not values): Material 3 <https://m3.material.io> · SAP Fiori for iOS <https://www.sap.com/design-system/fiori-design-ios/>
- This file follows the Stitch design-md spec: <https://stitch.withgoogle.com/docs/design-md/specification/> (repo: <https://github.com/google-labs-code/design.md>)

*Companion document: `docs/design-gap-analysis.md` — the audited current
state, the gap to this system, and the prioritized migration plan.*
