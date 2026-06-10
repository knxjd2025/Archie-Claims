# Archie Canvass — App Store Launch Plan

**Purpose:** Execute this plan to take the Archie Claims iOS app from its current state to "Submitted for App Review."
**Executor:** A Claude agent with browser access (Claude for Chrome / Cowork / computer use) working alongside James.
**Date written:** 2026-06-10. Verify nothing has drifted if executing much later.

---

## Context (read first)

- **App:** Archie Canvass (Xcode project folder is still named Archie-Claims) — iOS app for roofing canvassing/claims. Xcode project at `~/Archie-Claims` (scheme `ArchieClaims`). Builds and tests pass as of 2026-06-10.
- **Bundle ID:** `com.archieclaims.app` (already set in the project; use EXACTLY this in App Store Connect).
- **Version:** 1.0 (build 1).
- **Backend:** `https://roofy-backend.onrender.com` (Render). Stripe billing is live on it; Apple IAP verification code is deployed but **fails closed** until env vars are set (intentional — prevents a free-credit exploit).
- **Monetization:** 5 in-app purchases (3 consumable credit packs + 2 auto-renewable subscriptions). The app also sells the same credits via Stripe on the web at a 10% discount — that path is independent of this launch.
- **Apple Developer account:** James already has one. The Claude agent CANNOT log in alone — Apple uses 2FA. James must be present for every App Store Connect session.

### Inputs — ALL RESOLVED 2026-06-10 except 2FA
| Input | Value |
|---|---|
| Privacy Policy URL | `https://app.archie.now/privacy.html` (live) |
| Terms of Use / EULA URL | `https://app.archie.now/terms.html` (live) |
| Support URL | `https://app.archie.now/support.html` (live) |
| Demo account | `james+appreview@bestroofingnow.com` / `ArchieReview#2026` — 25 credits loaded, login verified |
| 2FA codes during ASC sessions | Still James, in person |

---

## Phase 1 — Code fixes ✅ ALL DONE 2026-06-10 (skip to Phase 2)

All four fixes are implemented, built, tested, and pushed (iOS `Archie-Claims@5234357`, backend `roof-report-ai@eb69885`). Kept below for reference. Demo/legal inputs are also done: privacy/terms/support pages live at `https://app.archie.now/privacy.html` / `terms.html` / `support.html`; App Review demo account `james+appreview@bestroofingnow.com` / `ArchieReview#2026` with 25 credits.

### 1.1 Restore Purchases button — `ArchieClaims/Views/CreditStoreView.swift`
- Add a visible "Restore Purchases" button to the credit store / paywall.
- Implementation: `try await AppStore.sync()` then refresh entitlements/credits. (Guideline 3.1.1.)

### 1.2 Privacy Policy + Terms of Use links on the paywall — `CreditStoreView.swift`
- Add tappable "Privacy Policy" and "Terms of Use" links (open in Safari) near the subscription buttons, plus the standard auto-renew disclosure text (renews unless cancelled ≥24h before period end; manage in Settings). (Guideline 3.1.2.)

### 1.3 In-app account deletion — backend + app
The app has in-app sign-UP (`ArchieBackendService.signUp`), so Apple requires in-app account DELETION (Guideline 5.1.1(v)).
- **Backend** (`~/roof-report-ai/server`): add an authenticated `DELETE /api/auth/account` (or equivalent) that deletes/deactivates the user and associated personal data. Deploy to Render.
- **App:** add "Delete Account" in `ArchieClaims/Views/SettingsView.swift` (red, confirmation dialog, calls the endpoint, then signs out locally like `ArchieBackendService.signOut()`).

### 1.4 Dual-environment Apple verification — `~/roof-report-ai/server/src/lib/apple-iap.ts`
App Review tests IAP in the **sandbox** environment even for production submissions. The verifier currently honors a single `APPLE_ENV`. Change it to: try **production first, fall back to sandbox** when the signed data indicates sandbox (Apple's recommended pattern). This prevents a guaranteed review-time rejection.

**Commit and push all of the above; confirm the Render deploy goes live before Phase 4.**

---

## Phase 2 — App Store Connect setup (browser, with James for 2FA)

Log in at https://appstoreconnect.apple.com.

### 2.1 Agreements (gate for everything else)
- Business → Agreements, Tax, and Banking: confirm the **Paid Apps agreement is Active**, with banking and tax info complete. If not, James must complete it (IAPs won't work even in sandbox until Active). This can take Apple time to process — do it FIRST.

### 2.2 Identifier + app record
- developer.apple.com → Certificates, IDs & Profiles → Identifiers: ensure an App ID exists for `com.archieclaims.app` with the **In-App Purchase** capability (usually automatic).
- App Store Connect → My Apps → "+" → New App:
  - Platform: iOS · Name: **Archie Canvass** (if taken, ask James for an alternative) · Language: English (U.S.) · Bundle ID: `com.archieclaims.app` · SKU: `archie-canvass-ios`
- After creation, open App Information and **record the numeric Apple ID** — needed in Phase 3 as `APPLE_APP_APPLE_ID`.

### 2.3 Create the 5 in-app purchases (EXACT product IDs — the app and backend both hardcode them)

**Consumables** (Features → In-App Purchases → "+" → Consumable):
| Product ID | Reference name | Price | Display name | Description |
|---|---|---|---|---|
| `now.archie.credits.pack100` | Credits Pack 100 | $79 | 100 Credits | 100 credits for property owner lookups |
| `now.archie.credits.pack250` | Credits Pack 250 | $149 | 250 Credits | 250 credits for property owner lookups |
| `now.archie.credits.pack1000` | Credits Pack 1000 | $499 | 1,000 Credits | 1,000 credits for property owner lookups |

**Subscriptions** (Features → Subscriptions → create group named **Archie Pro**, then two subscriptions in it):
| Product ID | Reference name | Duration | Price | Display name |
|---|---|---|---|---|
| `now.archie.credits.sub.monthly` | Archie Pro Monthly | 1 month | $29.99 | Archie Pro — Monthly (100 credits/mo) |
| `now.archie.credits.sub.annual` | Archie Pro Annual | 1 year | $299.99 | Archie Pro — Annual (1,200 credits/yr) |

For ALL five: add the en-US localization, and attach a **review screenshot** of the paywall (any current simulator screenshot of CreditStoreView is acceptable; take it during Phase 1 testing). Each IAP must reach "Ready to Submit."

### 2.4 App Store Server Notifications
- App → App Information → App Store Server Notifications:
  - **Production URL:** `https://roofy-backend.onrender.com/api/property/apple-notifications`
  - **Sandbox URL:** same URL
  - Version: **2 (V2)**.

---

## Phase 3 — Render environment variables (James sets these; agent provides values)

In the Render dashboard for the `roofy-backend` service:
| Var | Value |
|---|---|
| `APPLE_BUNDLE_ID` | `com.archieclaims.app` |
| `APPLE_APP_APPLE_ID` | numeric Apple ID from step 2.2 |
| `APPLE_ENV` | `production` (with the 1.4 fix, sandbox falls back automatically) |
| `APPLE_IAP_VERIFY` | leave **unset/off** until Phase 4 passes, then set to `on` |

Each save triggers a redeploy (~1–2 min). Watch deploy logs: with verify off in production, the backend intentionally logs a loud `[apple-iap]` startup error — expected until the final flip.

---

## Phase 4 — Sandbox end-to-end test (do NOT skip)

1. App Store Connect → Users and Access → Sandbox Testers: create a sandbox tester (fresh email alias, e.g. `james+sandbox1@bestroofingnow.com`).
2. On a real iPhone or simulator: Settings → App Store → Sandbox Account → sign in with the tester. Build & run from Xcode.
3. Set `APPLE_IAP_VERIFY=on` in Render (sandbox verification now active via the 1.4 fallback).
4. Test matrix — all must pass:
   - [ ] Buy `pack100` → credits balance +100 in the app.
   - [ ] Re-launch app → no duplicate grant (idempotency).
   - [ ] Subscribe monthly → +100 credits.
   - [ ] Kill the app immediately after Apple's payment sheet confirms, before the success UI → relaunch → recovery listener redeems the purchase and credits appear.
   - [ ] Restore Purchases button runs without error.
   - [ ] Owner lookup spends a credit correctly.
5. If anything fails: check Render logs (`[apple-iap]` and `/credits/iap` lines) before touching code.

---

## Phase 5 — Listing metadata (browser)

- **Screenshots:** 6.7" iPhone set required (6.9" if current Apple specs demand — check the upload UI). Capture from simulator: map/canvassing view, property sheet, assistant, credit store. iPad screenshots only if the app targets iPad — check Xcode target; if iPhone-only, skip.
- **Description, keywords, promotional text:** draft from the app's actual features (canvassing map, owner lookup, AI assistant, claims tools). James approves copy.
- **URLs:** Support URL + Privacy Policy URL (from inputs), Terms of Use → paste the EULA URL into the App License Agreement field or the description per current ASC UI.
- **Age rating questionnaire:** all "No" → 4+ (nothing objectionable in the app).
- **App Privacy (questionnaire):** declare —
  - Contact info (name, email) — account creation, linked to identity.
  - Purchases — linked to identity.
  - Location: the app uses location ONLY on-device (usage string says it never leaves the device). If that's still true, declare location as **not collected**. Verify with James/code before answering.
- **Pricing:** app itself is **Free**.
- **App Review notes:** include demo account credentials and: "Sign in with the provided demo account. In-app purchases grant lookup credits; the demo account already has credits to demonstrate the owner-lookup feature."

---

## Phase 6 — Build upload + submission

1. Xcode: bump nothing (1.0/build 1 is fine for first submission). Product → Archive (Any iOS Device).
2. Distribute → App Store Connect → Upload (requires James's signing identity; automatic signing should handle it).
3. Wait for processing (~15–60 min), fix any post-processing emails from Apple (e.g., missing usage strings — none expected).
4. In ASC: select the build, **attach all 5 IAPs to the version submission** (first IAPs must ride with a version review), answer export compliance (already `ITSAppUsesNonExemptEncryption=false`), submit for review.
5. Typical review: 1–3 days. If rejected, the rejection reason maps to a phase above — fix and resubmit.

---

## Post-approval checklist
- [ ] Confirm `APPLE_IAP_VERIFY=on` in Render (production).
- [ ] Make one real $79 pack purchase, confirm credits, then refund via ASC if desired.
- [ ] Verify a production App Store Server Notification arrives (Render logs) after the purchase.
- [ ] Stripe web path: confirm webhook endpoint subscribes to `checkout.session.completed` + `invoice.payment_succeeded` (Dashboard → Developers → Webhooks) — last unverified Stripe item.

## Known-good state (don't redo)
- Backend credits system hardened + deployed (migrations 114–117 run; balance ≥ 0 constraint live).
- iOS redeem-before-finish + interrupted-purchase recovery committed (`Archie-Claims@18df061`).
- Stripe billing live on the same backend; no Stripe products needed (prices created on the fly).
