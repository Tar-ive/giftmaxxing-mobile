# iOS Information Architecture

The July 2026 restructure. Problem it solves: the app's best features (group
gifting, challenges, the concierge) were invisible — buried two taps deep in a
"More" screen — while the tab bar spent slots on modes (Search) instead of
journeys. New users also never learned what the app IS: onboarding was four
marketing slides, not the product.

## The conventions we follow (Apple HIG + platform norms)

- **3–5 tabs, journeys not modes.** The tab bar is the app's table of
  contents; every top-level journey must be one tap away. A "More" tab is an
  admission the IA failed — apps that win (Instagram, Airbnb, Amazon) put
  their signature act IN the bar.
- **The signature action gets a permanent slot.** Airbnb = Search, Instagram
  = Create, Spotify = Home. For Giftmaxxing the signature act is *"tell Maxi
  about a person, get THE gift"* — the Concierge.
- **Search is a mode, not a place.** HIG treats search as an overlay you
  summon (App Store is the exception because search IS its product). Ours
  now presents as a full-screen cover from the Home search bar / camera.
- **Push vs. sheet.** Drill-downs push within a tab's NavigationStack;
  self-contained tasks (create a pool, run a challenge, chat with Maxi)
  present as sheets so the user never loses their place.
- **SF Symbols everywhere,** filled variants for selected state.
- **Onboarding = doing, not touring.** Contextual first-run that delivers
  value in under a minute and is skippable. Ours runs a real consult; the
  answers double as the taste profile.
- **Progressive disclosure.** Primary journeys: 1 tap. Secondary (settings,
  orders): 2 taps under You.

## The tab bar

| Tab | What lives there | Why it earns the slot |
| --- | --- | --- |
| **Home** | Personalized feed, search bar (→ modal), activity/messages | Daily habit loop; personalization shows off here |
| **Swipe** | Taste-training decks, events context | Feeds the ranker; fun retention loop |
| **Concierge** | The Maxi consult (ConsultView) → real pick → buy or verify-by-swipe | The product thesis in one screen |
| **Circles** | Your circles (shared groups: members + birthdays + occasions), events & reminders, group gifts, pools, challenges | Gifting is social AND date-driven; the people and their moments live together |
| **You** | Profile, shop, Maxi chat, settings, sign-in | Everything about ME, in one predictable place |

Removed from the bar: **Search** (modal via `AppState.showSearch`),
**Events** (folded INTO Circles — a date only matters because of the person
it belongs to, so the people and their dates share one home), **More**
(dissolved: its features got real homes).

## Circles = people + dates + gifting together

The July 2026 iteration: the tab stopped being a grab-bag of social plays
and became the hub it claimed to be.

- **Circles** are real server entities (`POST /circles`, web parity with
  `web/lib/circles.ts`): create "Sharma Family", share the `/circle/<id>`
  link, members add name + birthday in the browser — no account. The circle
  page (`CircleDetailView`) shows whose moment is next and jumps straight
  into a prefilled group gift.
- **Events & reminders** live in the same tab (`EventsViewModel` +
  `AddEventSheet`): add a date, pick a lead time, and `ReminderScheduler`
  posts local notifications (lead-day + day-of, 9am) — no server needed,
  mirroring `infra/src/reminders.mjs` semantics (default lead 7 days).
- **Group gifts / pools / challenges** stay as the "gift together" actions,
  now reachable FROM a moment (event detail and circle moments prefill
  `GroupGiftCreateView`).

The floating Maxi button stays on Home/Swipe/Circles (agent always one tap
away), hides on Concierge (that IS Maxi) and You.

## Onboarding & personalization contract

- Onboarding = the Concierge consult (`ConsultView(isOnboarding: true)`),
  including "whose gifts should your feed lean toward?" (him/her/mix).
- Gating is **per identity** (`PersonalizationStore.hasOnboarded`), not a
  device-global bool: a new sign-in on a used device still gets its first
  consult, after a `/me` check so cross-platform users are never re-gated.
- Consult output feeds personalization instantly: genderPref → recipient
  facet, worlds → vibe facets on `GET /feed` (`FeedViewModel`), plus the
  web-compatible profile PUT to `/me` for cross-device restore.
- Identity pings use `POST /me/identity` (merge) — never `PUT /me`, which
  replaces the row and used to wipe web-created profiles on iOS sign-in.

## File map

- Tabs/routing: `App/AppState.swift`, `App/ContentView.swift`
- Concierge: `Views/Consult/ConsultView.swift` (shared by onboarding wrapper
  `Views/Onboarding/OnboardingView.swift`)
- Circles hub: `Views/Circles/CirclesView.swift` (coming-up dates + circles +
  group gifts push; pools/challenges sheet), `Views/Circles/CircleStore.swift`
  (memberships), `Views/Circles/CircleDetailView.swift` (one circle: members,
  moments, occasions, invite link)
- Events & reminders: `Views/Swipe/EventsView.swift` (list + AddEventSheet),
  `Views/Swipe/EventDetailView.swift`, `Services/ReminderScheduler.swift`
  (local notifications)
- You: `Views/More/MoreView.swift`
- Personalization: `Services/PersonalizationStore.swift`,
  `Services/FeedViewModel.swift`
