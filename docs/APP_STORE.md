# App Store Submission Guide — Archie Claims

Everything needed to get from Xcode to TestFlight to App Review.

## 1. One-time setup

- [ ] Apple Developer Program membership ($99/yr) — [developer.apple.com](https://developer.apple.com/programs/)
- [ ] In Xcode: Settings → Accounts → add your Apple ID.
- [ ] Pick a unique bundle ID (e.g. `com.yourcompany.archieclaims`) and set it on the ArchieClaims target (and `.tests` suffix for the test target). Set your Team under Signing & Capabilities.
- [ ] Set `contactEmailForAPIs` in `AppSettings.swift` to your support email.
- [ ] Host the privacy policy (`docs/PRIVACY_POLICY.md`) at a public URL — GitHub Pages works fine.

## 2. App Store Connect record

Create the app at [appstoreconnect.apple.com](https://appstoreconnect.apple.com) → My Apps → "+".

| Field | Suggested value |
|---|---|
| Name | Archie Claims — Storm Canvassing |
| Subtitle | NOAA storm reports at the door |
| Category | Business (secondary: Weather) |
| Content rights | Does not contain third-party content |
| Age rating | 4+ (answers: none of the listed content) |
| Privacy policy URL | your hosted copy of `PRIVACY_POLICY.md` |

### Description (paste-ready)

> Knock smarter. Archie Claims puts NOAA storm evidence in your hand while you canvass: tap any house on the map and instantly see nearby hail, wind, and tornado reports from the Storm Prediction Center, plus active National Weather Service alerts for that exact spot.
>
> • Tap-a-house storm reports — hail size, wind speed, distance, and date
> • Free public owner & contact lookups (county records, people search)
> • Lead tracking with statuses, notes, and map pins — stored only on your phone
> • Archie AI claim assistant (bring your own Anthropic API key): door scripts, damage photo checklists, plain-English claim explanations, follow-up messages
>
> Built for roofing sales reps, canvassers, and storm restoration teams.
>
> Storm data is preliminary and unverified — always confirm damage on the roof. AI responses are guidance, not legal or insurance advice. Respect local solicitation laws and do-not-knock lists.

### Keywords

`roofing,storm,hail,canvassing,door knocking,roof claims,insurance claim,leads,wind damage,restoration`

### App Privacy questionnaire

- Data collection: **Data Not Collected** (everything stays on-device; AI chats go directly from the user's device to Anthropic under the user's own key; the developer collects nothing).
- Tracking: **No**.

## 3. Screenshots

Required: 6.9" (iPhone 16 Pro Max or similar) and 6.5" sets. Capture in the simulator (`Cmd+S`):

1. Canvass map with lead pins (satellite view)
2. Property sheet showing hail reports near an address
3. Archie AI answering "Explain ACV vs RCV"
4. Leads list
5. Onboarding "Real Storm Evidence" page

Tip: simulate a location near a recent storm (Features → Location → Custom Location) so real reports appear.

## 4. Build & upload

1. Xcode: select "Any iOS Device (arm64)" → Product → **Archive**.
2. Organizer → Distribute App → **App Store Connect** → Upload (automatic signing).
3. Export compliance is already answered in the binary (`ITSAppUsesNonExemptEncryption = false`) — no extra questions at upload.

## 5. TestFlight

- Internal testers (your team, up to 100): available minutes after processing.
- External testers: add a group + build, fill in "What to Test", submit for Beta App Review (usually < 24h).

Suggested "What to Test": *Tap houses on the map in a storm-hit area and check the storm report; save and edit leads; paste your Anthropic API key in Settings and chat with Archie.*

## 6. App Review notes (paste into "Notes" for the reviewer)

> Archie Claims is a field-sales tool for roofing contractors.
>
> • Storm data comes from free public NOAA/NWS feeds; no login is required for any core feature.
> • The "Archie AI" tab is an optional bring-your-own-key feature: users paste their own Anthropic API key (Settings → AI Assistant), which is stored in the device Keychain and used only to call Anthropic's API directly from the device. Without a key, the tab simply prompts the user to add one — all other features work fully.
> • For testing the AI tab we have included a demo key in the App Review notes field below / or: the feature can be verified by entering any valid Anthropic API key from console.anthropic.com.
> • "Owner & Contact Lookup" buttons open public websites (county assessor directories, people-search sites) in an in-app Safari view; the app does not scrape, collect, or store any data from them.
> • Location is used only to center the canvassing map; it never leaves the device.

(If you have a spare funded Anthropic key, put it in the review notes so the reviewer can exercise the AI tab — revoke it after approval.)

## 7. Common rejection risks & how this app addresses them

| Risk | Mitigation already in place |
|---|---|
| 2.1 App completeness | All features work without accounts; AI tab degrades gracefully without a key |
| 5.1.1 Privacy — permission strings | Location usage string explains exactly why; no other permissions requested |
| 5.1.2 Data use | Privacy manifest declares no collection/tracking; policy matches |
| 4.2 Minimum functionality | Native maps, native storm-data integration, on-device lead CRM — not a web wrapper |
| Export compliance | `ITSAppUsesNonExemptEncryption=false` (standard HTTPS only) |

## 8. After approval

- Phased release recommended (App Store Connect → Version Release options).
- Watch crash reports in Xcode Organizer.
- NOAA endpoints are stable, but if SPC ever changes its CSV layout the storm list will just come back empty — ship a parser update if that happens.
