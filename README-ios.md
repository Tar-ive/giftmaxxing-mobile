# Giftmaxxing Mobile

Native SwiftUI iOS app for [giftmaxxing](https://github.com/Tar-ive/giftmaxxing) — the social gifting platform.

## Requirements

- iOS 17.0+
- Xcode 15.0+
- Swift 5.9+

## Architecture

- **SwiftUI** with MVVM pattern
- **async/await** networking via `APIClient`
- Same backend API as the web app (`tvyu8gqmki.execute-api.us-east-1.amazonaws.com`)

## Screens

| Tab | Screen | Description |
|-----|--------|-------------|
| Home | Feed | Instagram-style feed with gift posts, stories tray, infinite scroll |
| Search | Search | Browse by occasion, search gifts/vibes |
| Swipe | Swipe | Tinder-style swipe deck for gift discovery |
| Events | Events | Birthday/anniversary countdown tracker |
| More | Hub | Feature grid: Maxi AI, Pools, Shop, Ideas, Settings |

### Additional Screens

- **Ask Maxi** — AI gift concierge chat (Bedrock Claude via `/maxi` endpoint)
- **Gift Pools** — Crowdfund gifts with friends
- **Shop** — Amazon affiliate product grid
- **Settings** — Account preferences
- **Onboarding** — 4-page intro flow

## Project Structure

```
Giftmaxxing/
├── App/              # App entry point, state, tab router
├── Models/           # Data models (Post, Product, Pool, etc.)
├── Services/         # API client, view models
├── Views/
│   ├── Feed/         # Feed, stories, search
│   ├── Swipe/        # Swipe deck, events
│   ├── Maxi/         # AI chat
│   ├── Pools/        # Gift pools
│   ├── Shop/         # Amazon picks
│   ├── More/         # Feature hub, settings, privacy
│   ├── Onboarding/   # First-launch flow
│   └── Components/   # Shared UI (avatars, cards, search bar)
├── Extensions/       # Theme colors, fonts
└── Resources/        # Assets (add via Xcode)
```

## Getting Started

### Option A: XcodeGen (recommended)

```bash
brew install xcodegen
cd giftmaxxing-mobile
xcodegen generate
open Giftmaxxing.xcodeproj
```

### Option B: Manual Xcode project

1. Open Xcode → File → New → Project → iOS App (SwiftUI, Swift)
2. Name it "Giftmaxxing", set deployment target to iOS 17.0
3. Delete the generated source files
4. Drag the `Giftmaxxing/` folder into the project navigator
5. Build and run (Cmd+R)

The app connects to the live API by default — no local backend needed.

## Brand

- Coral: `#FB6F52`
- Cream: `#F7F2EB`
- Font: SF Rounded (system)
