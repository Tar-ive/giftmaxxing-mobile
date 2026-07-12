# Design Gap Analysis — current UI vs. the DESIGN.md system

> Companion to the root **`DESIGN.md`** (the design system + agent
> contract). This file answers: what does the app look like today, why
> does it read as unpolished ("Temu"), what does polished look like, how
> much of the fix is visual vs. structural, and what agents can take
> from `DESIGN.md` alone vs. what needs per-screen direction.
> Audited July 2026 across all 36 view files. The `/screenshots` folder
> is **outdated web-design material — do not use it as a reference.**

## 1. The current design flow (as coded)

Cold launch → `SplashView` (spring logo, 1.15s) → sign-in gate
(`SignInView`, full-screen cover) → onboarding
(`GlassmorphismOnboardingView` glass intro → `ConsultView` chip-based
consult) → main `TabView` with 5 tabs — **Home** (`FeedView`,
Instagram-style feed + pledge rail + stories), **Swipe** (`SwipeView`,
Tinder-style deck), **Shop** (`ShopView`, product grid), **Circles**
(`CirclesView` hub → `CircleDetailView`, group gifts, pools, challenge),
**You** (`MoreView`). Global overlays: Maxi FAB (pulsing), search as
`fullScreenCover`, Maxi sheet, offline banner. Navigation is sound
(per-tab `NavigationStack`, sheets for tasks) — **the IA is not the
problem; the surface treatment is.**

## 2. Why it reads "Temu" — the audit numbers

The app has a theme file (`Extensions/Theme.swift`: 6 colors, 8 fonts,
7 gradients) that the codebase almost entirely bypasses:

| Symptom | Measured |
|---|---|
| Hardcoded `.font(.system(size:))` | **462 calls, 29 distinct sizes (8–80pt)** vs ~143 token uses |
| Inline color styling | **548** `.foregroundColor/Style/tint` calls; 34 raw `Color(hex:)` in views |
| Corner radii | **135 declarations, 11 distinct values** (2,4,8,10,12,14,16,18,20,24,28) — product images at 2pt sit next to 16–20pt cards |
| Shadows | 16 shadows, **9 recipes**, up to **45% black** (`CompactPledgeRail`) |
| Competing accents | **7 pastel gradients** (`GradientStyle` in `Models/Product.swift`) sprayed across avatars/tiles/story rings → "marketplace confetti" |
| Shared button styles | **1** (`FriendPillStyle`, private to Friends); the coral CTA is hand-rebuilt on ≥6 screens with drifting padding/radius |
| Spacing | No scale; gutters alternate 14/16/20 across tabs so nothing aligns |
| Haptics | **0** anywhere (in a swipe-centric app) |
| Modern motion APIs | **0** uses of `symbolEffect`, `scrollTransition`, `matchedGeometryEffect`, `contentTransition`, `sensoryFeedback`; 23 total animation call-sites, mostly splash/onboarding |
| Dynamic Type | Unsupported (all fixed point sizes); 184 of 462 sizes are ≤13pt → cramped-catalog density |
| Dark mode | Hard-disabled (`GiftmaxxingApp.swift:24`); no asset-catalog color sets |
| Accessibility | 11 labels app-wide; Reduce Motion/Transparency never checked |
| Emoji as UI | 🎁 *is* the logo (rendered as `Text`); chips and product placeholders are emoji |
| First-run whiplash | Premium glassmorphism onboarding → flat solid-fill app; onboarding also auto-dismisses after 3s (a leftover `// TEMP: for screenshot capture` hack) |

**The one-sentence diagnosis:** the app doesn't have a bad design — it
has *eleven accidental micro-designs*, one per screen, because nothing
forces consistency. "Temu look" = many saturated accents + dense small
type + inconsistent radii/shadows + emoji-as-artwork. Every one of those
is present and countable.

## 3. What polished looks like (the target)

Defined normatively in `DESIGN.md`. In one paragraph: **cream canvas,
white cards with 16pt continuous corners and a barely-there shadow, ink
text in three gray steps, coral used only where you can act, SF
Rounded display type, 16pt gutters everywhere, springs + haptics on
every state change, and the expressive budget (gradients, mesh, glass,
symbol effects) spent only on Maxi and onboarding.** The brand
(coral/cream/gift-boutique warmth) is already good — polish is
subtraction and consistency, not a rebrand.

## 4. How much is "visual" vs. structural — and what agents need to be told

**≈70% of the perceived cheapness is structural**, fixable mechanically
with zero taste required: adopt the token scales (type, spacing, radius,
elevation), unify the CTA into shared `ButtonStyle`s, demote the pastel
palette, replace scattered sizes with Dynamic Type styles. This is
codemod-grade work agents can do from `DESIGN.md` alone.

**≈30% is genuine visual/motion craft** needing judgment or per-screen
direction:

| Can be established once in DESIGN.md (done) | Needs fine-grained, per-task instruction |
|---|---|
| All tokens (color/type/spacing/radius/shadow) | A real logo mark to replace the 🎁 emoji (SVG → `Shape`) |
| Component specs (buttons, chips, cards, rows, headers, badges) | Per-screen density/layout calls (what to *remove* from Feed cards, Circles hub hierarchy) |
| Motion & haptics catalog (which idiom for which moment) | Choreography of hero moments (swipe-match celebration, pledge-complete, story ring) |
| Do/Don't rules (one accent, no emoji-as-UI, shadow caps) | Copy/tone and empty-state illustrations |
| Accessibility & Reduce-Motion baseline | Photography/product-image curation quality |

**Practical instruction to give downstream agents** (paste into any UI
task):

> Before any UI change, read `/DESIGN.md` and follow its Agent contract.
> Resolve every color/font/spacing/radius/shadow through `Theme.swift`
> tokens; use the shared ButtonStyles and components; no
> `.system(size:)`, no new hues/radii/shadows. If the task needs a value
> the system lacks, extend `Theme.swift` + `DESIGN.md` in the same PR.

## 5. Animation: now vs. target

| | Now | Target (per DESIGN.md catalog) |
|---|---|---|
| Buttons | No pressed feedback (`.plain` everywhere) | ButtonStyle scale-down 0.97 + spring |
| Chips/selection | Instant state swap | `.snappy` + `.sensoryFeedback(.selection)` |
| Swipe deck | Drag + spring reset (decent) | + impact haptic on commit, `.bouncy` match celebration |
| Feed/lists | Static | `.scrollTransition` fade/scale on entry |
| Icons | Static | `.symbolEffect(.bounce, value:)`, `.contentTransition(.symbolEffect(.replace))` |
| Numbers (pool totals, counts) | Hard swap | `.contentTransition(.numericText())` |
| Card → detail | Sheet pop | `matchedGeometryEffect` / `.navigationTransition(.zoom)` hero |
| Progress (pools) | Static bar | Gradient `trim` stroke animation |
| Idle loops | FAB pulse + onboarding shimmer, ignore Reduce Motion | Keep only FAB pulse + skeleton shimmer, gated on Reduce Motion |
| Haptics | None | Success/selection/impact tied to the same triggers as springs |

## 6. Gradients: now vs. target techniques

**Now:** 7 pastel linear gradients used as random decoration; the coral
brand gradient copy-pasted in 3 files; a 4-stop linear + radial glows in
onboarding only; 13 inline one-off gradients.

**Target:** one tokenized brand gradient (`coral → #FF9A76`) for
identity moments; pastels retired from UI. Then *technique*, not
quantity, supplies the premium feel:

- **Gradient-stroked shapes** — progress rings/celebrations: `.trim` +
  `stroke(brandGradient, lineCap: .round)` animated 0→1.
- **Angular-gradient animated borders** with a blurred duplicate for
  glow — reserved for Maxi/featured cards.
- **`MeshGradient` (iOS 18)** — slow ambient motion via
  `TimelineView(.animation)` for onboarding/Maxi backgrounds, replacing
  the static 4-stop linear.
- **Shimmer** — only on skeletons (`surface-sunken` base).
- **Scrim gradients** (ink → clear) under text on photos, replacing flat
  black-55% badges.

## 7. Resources (the "v0 gallery" equivalents for iOS)

Galleries agents/designers can pull patterns from:

- **Mobbin** — <https://mobbin.com> — 100k+ real iOS screens by app/flow/element; the default reference ("how do the best apps do onboarding/paywall/empty states").
- **Page Flows** — <https://pageflows.com> — recorded video flows (sequencing, transitions).
- **Appshots** — <https://appshots.design> — motion/micro-interaction clips.
- **Pttrns** — <https://pttrns.com> — iOS patterns by type.
- **UI Sources** — <https://uisources.com> — component-level breakdowns with interaction zoom-ins.
- **Apple Design Awards** — <https://developer.apple.com/design/awards/> — the polish bar.
- **Apple Design Resources** (Figma/Sketch UI kits) — <https://developer.apple.com/design/resources/>.
- SwiftUI implementation recipes: Hacking with Swift, Design+Code handbook, Create with Swift (URLs in `DESIGN.md`).
- Design-system structure references: Material 3 (<https://m3.material.io>), SAP Fiori for iOS (<https://www.sap.com/design-system/fiori-design-ios/>) — steal documentation *structure*, keep HIG values.

## 8. Migration plan (priority order)

1. **P0 — Token layer.** Rewrite `Theme.swift`: semantic colors (incl.
   `textSecondary/Tertiary`, `surfaceSunken`, `scrim`, `success/danger`),
   `Spacing`/`Radius`/`CardShadow` enums, Dynamic-Type font mapping,
   tokenized brand gradient. Add asset-catalog color sets. (~1 file +
   catalog; unblocks everything.)
2. **P0 — Shared styles.** `PrimaryButtonStyle` / `SecondaryButtonStyle`
   / `QuietButtonStyle` / `.cardStyle()` / `SectionHeader` / shared list
   row; generalize `FriendPillStyle`. Remove the onboarding `TEMP`
   auto-advance (`GlassmorphismOnboardingView.swift:77-82`).
3. **P1 — Sweep the worst offenders** onto tokens+styles, one screen per
   PR: `CircleDetailView`, `GroupGiftViews`, `ConsultView`,
   `SearchTabsView`, `CirclesView`, `SwipeView`, then Feed/Shop/More.
   Kill pastel-`GradientStyle` rendering, 2pt image corners, ≤10pt text,
   >12% shadows, emoji placeholders.
4. **P1 — Motion & haptics pass.** Apply the DESIGN.md catalog: button
   press states, chip selection feedback, swipe-commit impact,
   `scrollTransition` on Feed/Shop, `numericText` on pool totals,
   Reduce-Motion gates on the FAB pulse/shimmer.
5. **P2 — Hero moments.** Logo mark as `Shape` (replace 🎁), mesh-gradient
   onboarding/Maxi ambient, match/pledge celebrations (gradient trim
   strokes, `.bouncy`), card→detail hero transitions.
6. **P2 — Accessibility & dark-mode readiness.** Labels on all
   interactive elements, Dynamic Type verification pass, then remove the
   light-mode lock once asset-catalog dark variants exist.

Each step is independently shippable; P0+P1 alone remove the "Temu"
signal since they eliminate every countable symptom in §2.
