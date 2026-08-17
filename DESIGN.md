---
name: Giftmaxxing iOS
version: 1.1
description: >
  Design system for the Giftmaxxing SwiftUI iOS app. Warm, editorial,
  gift-boutique feel — one accent over neutral grounds, generous whitespace,
  soft continuous corners, spring motion with haptics. This file is the single
  source of truth for all UI work: coding agents MUST resolve every color, font,
  radius, spacing and shadow through the tokens below, which are exposed in
  Swift by Giftmaxxing/Extensions/Theme.swift and Extensions/ThemePalette.swift.
  Values here are the SHIPPED palette (warmBoutique); seven alternates exist and
  every token resolves through whichever palette is active at draw time.
colors:
  # Each entry is the warmBoutique light value, with its dark pair in the
  # comment. Do NOT hardcode these hexes — read the Swift token.
  coral: "#C63F24"           # the ONLY accent; interactivity signal (dark #FF7F63)
  coralEmphasis: "#A8321B"   # pressed/darkened accent (dark #FF9A80)
  coralSoft: "#FFF0ED"       # accent tint fill: selected chips, soft badges (dark #3A2620)
  cream: "#F7F2EB"           # app/screen background (dark #141210 — a WARM brown-black)
  surface: "#FFFFFF"         # cards, sheets, rows (dark #1E1B18)
  surfaceSunken: "#F1EAE0"   # inset wells, skeleton base (dark #2A2620)
  ink: "#1A1A1A"             # primary text (dark #F5F1EA)
  inkSecondary: "#6B6560"    # metadata, subtitles (dark #B3ABA1)
  inkTertiary: "#7D7670"     # timestamps, placeholders (dark #867E75)
  line: "#E5E0D8"            # hairlines only, 0.5–1pt (dark #332E28)
  gradientEnd: "#FF9A76"     # brandGradient = coral → gradientEnd, topLeading→bottomTrailing
  onboardingGlow: "#FFC5A0"  # onboarding/splash glow only (dark #7A4A33)
  onboardingWash: "#FFF9F5"  # onboarding/splash wash only (dark #1A1613)
  success: "#3E8E5A"         # (dark #5FB77F)
  danger: "#D64545"          # (dark #F06B6B)
  onPrimary: "#FFFFFF"       # text/icons on the accent — a plain static white
typography:
  # The real scale is Font extension in Theme.swift. SF Pro Rounded for display,
  # SF Pro for everything else. There are exactly eight tokens.
  displayLarge:  { size: 28pt, weight: heavy,   design: rounded }
  displayMedium: { size: 22pt, weight: bold,    design: rounded }
  displaySmall:  { size: 18pt, weight: bold,    design: rounded }
  bodyLarge:     { size: 16pt, weight: regular }
  bodyMedium:    { size: 14pt, weight: regular }
  bodySmall:     { size: 12pt, weight: regular }
  caption:       { size: 11pt, weight: medium }
  labelBold:     { size: 14pt, weight: bold }
rounded:          # ThemeRadius
  sm: 8px         # thumbnails, small controls
  md: 12px        # buttons (non-capsule), inputs, nested images inside cards
  lg: 16px        # cards, sheets-inner
  xl: 24px        # hero cards, modal covers
  full: 999px     # capsule — pills, chips, primary CTA
spacing:          # ThemeSpacing
  xxs: 4px
  xs: 8px
  sm: 12px
  md: 16px        # default gutter + default intra-card padding
  lg: 20px
  xl: 24px
  xxl: 32px
elevation:        # ThemeElevation
  card:     { color: "black 6%",  radius: 12px, y: 4px }   # .cardElevation()
  floating: { color: "black 10%", radius: 24px, y: 8px }
---

# Giftmaxxing iOS Design System

## Agent contract

Four rules. They are the reason this file exists.

1. **Never hardcode a value.** No hex strings, no `.font(.system(size:))`, no
   magic radii, spacings or shadows in a view file. Resolve through the tokens.
2. **A missing token is a PR to this file.** Need a colour, size or radius that
   isn't here? Extend `Theme.swift` (and `ThemePalette.swift` if it's a colour)
   **and** this document in the same PR. Never inline the one-off.
3. **A new colour must ship light AND dark, in all eight palettes, and clear
   WCAG AA (4.5:1)** against the surface it sits on in both appearances. That
   contract is stated in `ThemePalette.swift` and is not negotiable.
4. **Shared components only.** If two screens need it, it belongs in
   `Giftmaxxing/Views/Components/` or as a `ButtonStyle` in `Theme.swift`.

## How a colour actually resolves

This is the part most agents get wrong. `Color.coral` is not a constant — it is
a two-stage lookup performed at **draw time**:

```
Color.coral
  → ThemeManager.current          the selected AppTheme's Palette (8 available)
  → traits.userInterfaceStyle     the light or dark half of that token's pair
  → UIColor provider              resolved during rendering, so a theme switch
                                  repaints without recreating any view's colors
```

Two consequences worth internalising:

- The tokens are declared `static var`, not `static let`. A stored constant
  would bake in whichever palette was selected at first access and never change
  again. **Don't "optimise" them into `let`.**
- `DebugSessionManager.active.accentHex` can override the accent — and only the
  accent. A variant that repainted surfaces would stop being a card-layout
  comparison and become a second theme system.

`Color.dynamic(light:dark:)` exists for genuinely one-off pairs that aren't part
of the palette. Reach for it rarely; a colour used twice is a token.

## The palette system

Eight complete palettes, each with a light and dark value for all 15 tokens,
selectable at runtime from **You → Settings → Appearance**:

| AppTheme | Character |
|---|---|
| `warmBoutique` | **The shipped look.** Warm brown-black dark, coral accent |
| `midnightPlum` | Deep violet-black, punchy pink coral, ivory text (≈15:1) |
| `editorialMono` | Near-black and paper white, one saturated accent |
| `forestLuxe` | Deep green-black with warm gold |
| `paperCoral` | Bright paper white, soft shadows, the original coral |
| `oceanSlate` | Cool blue-grey with a teal accent |
| `terracotta` | Clay and sand, burnt-orange accent |
| `nordicIce` | Very light and airy, icy blue accent |

`ThemeManager.shared` holds the selection (persisted under
`giftmaxxing_app_theme`, defaulting to `warmBoutique`) and the root view
observes it, so switching re-renders the whole app instantly — which is the
entire point of making it swappable rather than a build flag.

**Appearance (light / dark / system) is a separate axis**, owned by
`AppearanceStore`. A palette defines *what* the colours are; the appearance
decides *which half* of each pair is used.

### Why light-mode coral is #C63F24

The original `#FB6F52` failed AA badly: white-on-coral measured 2.80:1 and
coral-as-text-on-cream 2.51:1. The deepened value clears the floor everywhere it
is used — fill 5.08, on cream 4.56, on surface 5.08, on coralSoft 4.58 — while
staying unmistakably the same coral. Dark mode already passed and is unchanged.
If you introduce a palette, measure the same four ratios.

## Other token surfaces

- **`AvatarPalette.gradient(for: String)`** — deterministic gradient per name,
  so a person's avatar is the same colour everywhere in the app.
- **`Color.gradient(for: GradientStyle)`** — product artwork placeholders only.
  Never render chrome or UI from this pastel palette.
- **`MediaAspect`** — the only aspect ratios in the app: `vertical` 9:16,
  `square` 1:1, `product` 4:5 (the editorial crop for catalog imagery),
  `recommendationCard` 3:4 (discovery cards, so an item doesn't change shape
  between feed and detail). Widescreen uploads keep their real shape rather than
  being snapped square, which used to slice the top and bottom off collages.
- **`AppIcons`** — the app-icon set; not a UI token surface.

## Components

Shared components live in `Giftmaxxing/Views/Components/`; styles live in
`Theme.swift`. **If two screens need it, it's a component.**

**Built and in use:**

- `PrimaryButtonStyle` — coral capsule, white text, pressed state swaps to
  `coralEmphasis` with `scaleEffect(0.97)` and a `.spring(duration: 0.35,
  bounce: 0.15)`.
- `SecondaryButtonStyle` — `coralSoft` fill, coral text, same press behaviour.
- `.cardElevation()` — the one approved card shadow. Anything heavier is a
  custom shadow and shouldn't exist.
- `SearchBar` / `HomeSearchBar`, `GradientCard`, `MasonryFeedGrid`, `MaxiIcon`,
  `MaxiFloatingButton`, `SplashView`, `CameraPicker`, `SafariView`,
  `RegionSearchImage` — all free of app-state coupling, and therefore the first
  candidates for the future DesignSystem module.

**Specified but NOT built** (don't cite these as if they exist):
`QuietButtonStyle`, a shared `.cardStyle()` modifier, and a single shared
list-row. `FriendPillStyle` in `FriendsView.swift` is the inline ancestor of
`QuietButtonStyle` and should be generalised when someone needs it twice.

**Conventions for the ones that do exist:**

- **Chip** — capsule, `surface` + hairline by default; selected is `coralSoft`
  fill + coral text + `sensoryFeedback(.selection)` + a `.snappy` spring.
  Text-first; at most one leading emoji, prefer SF Symbols.
- **Card** — `lg` continuous corners, `surface`, `cardElevation()`, `md`
  padding, nested imagery at `md` corners.
- **Avatar** — one treatment via `AvatarPalette`; story ring is the brand
  gradient at 2pt.
- **Skeletons** — `surfaceSunken` shapes with a shimmer sweep. This is the one
  approved decorative loop.
- **Maxi surfaces** — Maxi owns the expressive budget: brand gradient, ambient
  mesh gradient, `sparkles` with `.symbolEffect(.pulse)` while thinking.
- **Onboarding / Splash** — the glass treatment (materials, mesh/radial glow)
  belongs to onboarding and Maxi; the product body stays flat-calm. Bridge them
  with the brand gradient and rounded display type.

## Motion & haptics catalog

Use these idioms, not `repeatForever`.

| Moment | Idiom |
|---|---|
| Default state change | `.snappy` (or `.spring(duration: 0.35, bounce: 0.15)`) |
| Reward (pledge, match, gift sent) | `.bouncy` + `.sensoryFeedback(.success, trigger:)` |
| Selection (chips, segmented, tabs) | `.snappy` + `.sensoryFeedback(.selection, trigger:)` |
| Swipe commit | `.sensoryFeedback(.impact(weight: .medium), trigger:)` |
| Icon feedback | `.symbolEffect(.bounce, value:)`; swap symbols with `.contentTransition(.symbolEffect(.replace))` |
| Changing numbers | `.contentTransition(.numericText())` |
| Feed items entering | `.scrollTransition { c, phase in c.opacity(phase.isIdentity ? 1 : 0.6).scaleEffect(phase.isIdentity ? 1 : 0.96) }` |
| Hero (card → detail) | `matchedGeometryEffect` / `.navigationTransition(.zoom(sourceID:in:))` |
| Progress / celebration strokes | `shape.trim(from: 0, to: p).stroke(brandGradient, style: .init(lineWidth: 3, lineCap: .round))`, animate `p` |
| Premium border accent (Maxi/featured only) | `AngularGradient` stroke, slow rotation, blurred duplicate underneath |

## Do's and Don'ts

**Do**

- Use the accent for exactly one primary action per viewport.
- Use whitespace and imagery scale to signal quality; cut items before cutting
  padding.
- Pair every visual state change with a spring, and every commit with a haptic.
- Use SF Symbols (filled = active/selected), sized by `imageScale` or text
  style, animated with `symbolEffect`.
- Add `accessibilityLabel`s to every interactive element you touch.
- Check Reduce Motion and Reduce Transparency for loops and materials.

**Don't**

- Don't hardcode any size, colour, radius or shadow in a view file.
- Don't use `.font(.system(size:))` — ever.
- Don't turn the colour tokens into `static let` (see "How a colour resolves").
- Don't render UI from the pastel `GradientStyle` palette.
- Don't use emoji as icons, logos or category art.
- Don't add borders heavier than 1pt or shadows darker than 12%.
- Don't introduce a second accent hue, a new gradient or a new radius — extend
  this file first, in the same PR.
- Don't use `repeatForever` outside skeleton shimmer and the Maxi pulse.
- Don't use `.opacity()` on text for hierarchy — use the three ink tokens.
- Don't add a palette without light + dark for all 15 tokens and the four AA
  measurements.

## Copy rules

Words are design material. Screen intros are one fragment, not a paragraph.
Subtitles run four words or fewer. Explain a mechanic at the point of use, never
pre-emptively. A control says exactly what happens ("Send", then "Sent").

---

### References for downstream agents

- Apple HIG: <https://developer.apple.com/design/human-interface-guidelines>
- Liquid Glass: <https://developer.apple.com/documentation/TechnologyOverviews/liquid-glass>
- Apple Design Awards (the quality bar): <https://developer.apple.com/design/awards/>
- Pattern galleries: Mobbin <https://mobbin.com> · Page Flows <https://pageflows.com> · Appshots <https://appshots.design>
- SwiftUI recipes: Hacking with Swift <https://www.hackingwithswift.com/quick-start/swiftui> · Design+Code <https://designcode.io/swiftui-handbook>
- SVG → SwiftUI Shape: <https://svg-to-swiftui.quassum.com/>
- Token-architecture reference (structure, not values): Material 3 <https://m3.material.io>
- This file follows the Stitch design-md spec: <https://stitch.withgoogle.com/docs/design-md/specification/>

*Companion: `docs/design-gap-analysis.md` — audited current state and migration
plan. Note it predates the palette system and is itself due a refresh.*
