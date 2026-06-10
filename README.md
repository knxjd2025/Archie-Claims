# Archie Claims

**The storm canvassing app for roofers.** Tap any house on the map → instant NOAA storm report for that address, free public owner/contact lookups, lead tracking, and an AI roofing claim assistant powered by **Claude Opus 4.8**.

| Tab | What it does |
|---|---|
| **Canvass** | Live map (standard/satellite) starting over Charlotte, NC with a **storm overlay** — NOAA SPC hail/wind/tornado reports drawn on the map for the visible area. **Quick Log mode** (⚡️): tap a roof, pick a status, done — address + storm evidence save automatically. Status filter chips, a live "today" door tally, address/city search, and +/− zoom. |
| **Archie AI** | Claim assistant chat: door scripts, ACV/RCV explanations, photo checklists, follow-up texts. Attach a property's storm data ("Ask Archie"), attach a CRM client (claim profile, docs, communications pulled from app.archie.now), or attach insurance estimates/PDFs/photos/emails — files get text-extracted on-device for the chat and filed to the client's claim in the CRM. |
| **Leads** | Every door you've knocked: status (Not Home → Signed), homeowner info, notes, call & share. Stored 100% on-device. |
| **Settings** | Archie account sign-in (Keychain), storm search radius & lookback, data attribution. |

## Data sources (all free, no API keys)

- **NOAA Storm Prediction Center** daily storm reports — hail size, wind speed, tornadoes with lat/lon (`spc.noaa.gov/climo/reports/`). Cached on-device per day.
- **National Weather Service API** — active alerts for the exact point (`api.weather.gov`).
- **Public records links** — county assessor directories (NETR), free people-search sites, and web search, opened in an in-app browser. Nothing is scraped or stored.

> Storm reports are *preliminary and unverified* — great for canvassing conversations, but always verify damage on the roof.

## AI assistant

Archie chat runs on the **main Archie CRM backend** at [app.archie.now](https://app.archie.now/) (Vercel proxies `/api/*` to the Render service `roofy-backend`) — the same accounts as the web app. Sign in **or create a free account** right in the app (Settings → AI Assistant, or the prompt on the Archie AI tab); the session JWT and credentials live in the iOS Keychain, auth uses `Authorization: Bearer` against `POST /api/ai-assistant` (`action: "chat"`), and the server supplies the roofing-expert system prompt plus your company profile from the CRM. Everything else in the app works without signing in.

A legacy **bring-your-own-key** mode (direct Anthropic Messages API, `claude-opus-4-8`, streaming) is still available under Settings → AI Assistant → Advanced → AI backend.

## Build & run

Requirements: **macOS with Xcode 16+** (App Store submissions require the iOS 18 SDK or later), iOS 17+ device or simulator.

1. Clone the repo and open `ArchieClaims.xcodeproj`.
2. Select the **ArchieClaims** target → *Signing & Capabilities* → choose your **Team** and change the **bundle identifier** (`com.archieclaims.app`) to one in your account.
3. In `ArchieClaims/Services/AppSettings.swift`, set `contactEmailForAPIs` to your real support email (NOAA/NWS ask API users to identify themselves).
4. Run on a simulator or device. To test the map tap flow in the simulator, use *Features → Location → Custom Location* and pick somewhere with recent storms (e.g. 35.34, -97.49 — Moore, OK).

If the project file ever gives you trouble, regenerate it with [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen && xcodegen generate` (spec in `project.yml`).

### Run the tests

Product → Test in Xcode, or:

```sh
xcodebuild test -project ArchieClaims.xcodeproj -scheme ArchieClaims \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

## Ship it: TestFlight & App Store

The full submission checklist (metadata, screenshots, review notes, export compliance) lives in [`docs/APP_STORE.md`](docs/APP_STORE.md). Short version:

1. Create the app record in App Store Connect with your bundle ID.
2. Host [`docs/PRIVACY_POLICY.md`](docs/PRIVACY_POLICY.md) at a public URL (App Store requirement) and review it.
3. Product → Archive in Xcode → Distribute → App Store Connect.
4. Add testers in TestFlight; submit for review with the provided review notes.

Export compliance is pre-answered: `ITSAppUsesNonExemptEncryption = false` (HTTPS only). A privacy manifest (`PrivacyInfo.xcprivacy`) and the required location-usage string are already included.

## Repository layout

```
ArchieClaims/            App source (SwiftUI, iOS 17+)
  Models/                StormReport, Lead, NWSAlert, ChatMessage
  Services/              SPC parser, storm data, Claude streaming client,
                         Keychain, lead store, geocoding, public-records links
  Views/                 Map, property sheet, AI chat, leads, settings, onboarding
  Support/               SafariView wrapper
ArchieClaimsTests/       Unit tests (parser, date math, lead store)
docs/                    App Store guide, privacy policy, testing guide
project.yml              XcodeGen fallback spec
```

## Compliance notes for canvassers

- Honor **no-soliciting signs, local permit rules, and do-not-knock lists**.
- Contact info from public sources may be outdated — **verify before use** and follow **TCPA/do-not-call** rules for calls and texts.
- Archie's AI output is guidance, **not legal or insurance advice**; insurance regulations vary by state.
