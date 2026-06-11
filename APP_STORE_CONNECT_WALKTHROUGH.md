# App Store Connect Walkthrough — Archie Canvass

**For:** A Claude agent with browser access (Claude for Chrome / Cowork), working with James (he handles 2FA).
**Goal:** Take the existing app record from empty to "Waiting for Review."
**State when written (2026-06-10):** App record created (iOS, name Archie Canvass, bundle `com.archieclaims.app`, SKU `archie-canvass-ios`). Build 1.0 (1) uploaded from Xcode (if not visible yet, it's still processing — continue with other steps; the build is selected in Step 8). All code work is done; do NOT ask for code changes.

Work top-to-bottom. Every value you need is in this doc — never invent values.

---

## Step 0 — Sign in
https://appstoreconnect.apple.com — James signs in (2FA). Team: the one containing Archie Canvass.

## Step 1 — Agreements gate (do first, it has processing lag)
Business (or "Agreements, Tax, and Banking") → confirm **Paid Apps / Paid Applications agreement = Active**, with bank account and tax forms complete.
- If not Active: James must accept the agreement and fill banking/tax now. **IAP creation (Step 4) works while pending, but nothing is purchasable until Active.** Don't block on it — continue.

## Step 2 — App Information (My Apps → Archie Canvass → App Information)
- **Subtitle** (30 chars max): `Roofing canvassing + leads`
- **Category:** Primary **Business**; Secondary **Productivity**
- **Content Rights:** does not contain third-party content
- **Age Rating:** click Edit → answer **None/No to everything** → results in **4+**
- Record the **Apple ID** number shown on this page (numeric, ~10 digits) — James needs it later for Render (`APPLE_APP_APPLE_ID`).

## Step 3 — App Privacy (left sidebar → App Privacy)
Click Get Started. Answers (these MUST match the app's privacy manifest and policy — do not improvise):
1. **Privacy Policy URL:** `https://app.archie.now/privacy.html`
2. **Do you collect data?** → **Yes**
3. Data types collected — select exactly these three:
   - **Contact Info → Name** — used for App Functionality; **linked to identity**; NOT used for tracking
   - **Contact Info → Email Address** — App Functionality; **linked**; NOT tracking
   - **Purchases → Purchase History** — App Functionality; **linked**; NOT tracking
4. **Location:** NOT collected (it never leaves the device — do not select it)
5. **Tracking:** No data used for tracking.
6. Publish the answers.

## Step 4 — In-App Purchases (the exact product IDs are hardcoded in app + backend — typos break purchases)

### 4a. Consumables — Features → In-App Purchases → "+" → **Consumable**
Create three. For each: Reference Name + Product ID below, then availability (all countries), price, en-US localization, and a review screenshot (Step 7 note).

| Reference Name | Product ID | Price | Display Name | Description |
|---|---|---|---|---|
| Credits Pack 100 | `now.archie.credits.pack100` | **$79.00** | 100 Credits | 100 data credits for verified property owner lookups. |
| Credits Pack 250 | `now.archie.credits.pack250` | **$149.00** | 250 Credits | 250 data credits for verified property owner lookups. |
| Credits Pack 1000 | `now.archie.credits.pack1000` | **$499.00** | 1,000 Credits | 1,000 data credits for verified property owner lookups. |

### 4b. Subscriptions — Features → Subscriptions → Create **Subscription Group** named `Archie Pro` → add two subscriptions:

| Reference Name | Product ID | Duration | Price | Display Name | Description |
|---|---|---|---|---|---|
| Archie Pro Monthly | `now.archie.credits.sub.monthly` | 1 Month | **$29.99** | Archie Pro — Monthly | 100 data credits every month for owner lookups. |
| Archie Pro Annual | `now.archie.credits.sub.annual` | 1 Year | **$299.99** | Archie Pro — Annual | 1,200 data credits per year (100/month) for owner lookups. |

Subscription group localization (en-US): group display name `Archie Pro`.

Each of the 5 IAPs must reach **"Ready to Submit"** (needs: localization + price + screenshot). They get attached to the version in Step 9.

## Step 5 — App Store Server Notifications
App Information → App Store Server Notifications:
- **Production Server URL:** `https://roofy-backend.onrender.com/api/property/apple-notifications`
- **Sandbox Server URL:** same URL
- **Version 2** notifications.

## Step 6 — Version page metadata (left sidebar → 1.0 Prepare for Submission)

**Promotional Text** (170 max):
> Knock smarter. See storm history for any house, pull verified owner contacts in seconds, and send every door you work straight to your CRM.

**Description** (paste as-is):
> Archie Canvass turns door-to-door roofing canvassing into a data-driven operation.
>
> TAP ANY HOUSE, KNOW THE STORM STORY
> See NOAA storm reports and hail history around any property — sized, dated, and mapped — so you can speak to real damage, not guesses.
>
> VERIFIED OWNER LOOKUPS
> One tap pulls the property owner's name, phones (with do-not-call flags), and email, plus property details. Each lookup costs one data credit; buy packs or subscribe for monthly credits.
>
> EVERY DOOR LOGGED, EVERY LEAD SYNCED
> Log each knock with status and notes. Qualified doors become leads in your Archie CRM automatically — no end-of-day data entry.
>
> AI ASSISTANT FOR CLAIMS
> Attach inspection docs or insurer emails and get plain-English summaries, next steps, and drafted responses — connected to your client's CRM record.
>
> BUILT FOR THE TRUCK, NOT THE OFFICE
> Works one-handed on the street. Your location stays on your device. Storm data caches offline.
>
> Archie Canvass requires a free Archie account. Owner lookups consume data credits, available by subscription (Archie Pro) or one-time packs.
>
> Terms: https://app.archie.now/terms.html · Privacy: https://app.archie.now/privacy.html

**Keywords** (100 chars max, no spaces after commas):
`roofing,canvassing,door knocking,storm,hail,leads,crm,roof sales,claims,owner lookup`

**Support URL:** `https://app.archie.now/support.html`
**Marketing URL:** (leave blank or `https://archie.now`)
**Copyright:** `2026 SellMore Solutions LLC dba Kynex`

## Step 7 — Screenshots
Required: **6.9" iPhone** set (1320×2868) — Apple auto-scales for smaller sizes. iPhone-only app, so NO iPad set needed.
James (or Claude Code locally, not the browser agent) captures from the simulator: canvassing map, property sheet w/ storm data, owner report, AI assistant, credit store. 3–5 screenshots, in that order.
**Also grab one paywall screenshot (CreditStoreView)** — every IAP in Step 4 needs it as its review screenshot.

## Step 8 — Build + App Review info (same version page)
- **Build:** click "+" and select **1.0 (1)** (if absent, it's still processing or export-compliance is being computed — encryption is pre-declared in the binary, so no questions should appear).
- **App Review Information:**
  - Sign-in required: **YES** — Demo account: `james+appreview@bestroofingnow.com` / `ArchieReview#2026`
  - Notes (paste):
    > Sign in with the provided demo account (it has data credits preloaded). To test: tap any house on the map → "Property" sheet shows storm history; "Owner lookup" spends 1 credit and returns the owner record. In-app purchases grant additional credits. The AI assistant requires the same sign-in.
  - Contact: James Turner, james@bestroofingnow.com, +1 (his phone — ask James).
- **Pricing:** app price **Free** (Pricing and Availability page).
- **Release option:** "Manually release this version" (recommended — James controls launch day).

## Step 9 — Attach IAPs & submit
On the 1.0 version page, **In-App Purchases and Subscriptions section** → Add → select **all 5 IAPs** (first-ever IAPs must ride along with a version review).
Click **Add for Review → Submit to App Review**.

## Step 10 — Tell James what's left outside ASC (after submit)
1. Render env vars (James): `APPLE_BUNDLE_ID=com.archieclaims.app`, `APPLE_APP_APPLE_ID=<numeric id from Step 2>`, `APPLE_ENV=production`. Leave `APPLE_IAP_VERIFY` off until the sandbox test passes, then set `on`.
2. Sandbox test before (or in parallel with) review: create a Sandbox Tester (Users and Access → Sandbox), run the app from Xcode, buy pack100, confirm credits arrive. The backend auto-falls-back to sandbox verification.
3. After approval: release manually, make one real purchase to verify production notifications, then consider `APPLE_ALLOW_SANDBOX=off` in Render.

---

### Hard rules for the executing agent
- Product IDs, URLs, prices, and the demo credentials are EXACT — copy-paste, never retype from memory.
- If ASC's UI shows different field names than this doc (Apple moves things), match by meaning, not position.
- If something requires a decision not covered here (e.g., name "Archie Canvass" taken), STOP and ask James.
- Never change the bundle ID. The uploaded binary is `com.archieclaims.app`.
