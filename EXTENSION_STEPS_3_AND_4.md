# Archie Canvass — App Store Connect: App Privacy + In-App Purchases ONLY

Everything else on the listing (description, keywords, pricing, age rating, build, review notes) is ALREADY DONE via API. You only need to do these two sections. App: **Archie Canvass**, https://appstoreconnect.apple.com → My Apps → Archie Canvass. James handles 2FA. Copy-paste exact values — never retype product IDs from memory.

---

## TASK A — App Privacy (left sidebar → App Privacy → "Get Started" / Edit)

Answer exactly (these must match the app; do not improvise):

1. **Privacy Policy URL** (if asked): `https://app.archie.now/privacy.html`
2. **Do you or your partners collect data from this app?** → **Yes, we collect data from this app**
3. Add these **three data types**, each with the SAME settings (Used for **App Functionality** only; **Linked to the user's identity = Yes**; **Used for tracking = No**):
   - **Contact Info → Name**
   - **Contact Info → Email Address**
   - **Purchases → Purchase History**
4. Do NOT add Location (it never leaves the device).
5. Do NOT add any other categories.
6. **Publish** the privacy answers.

---

## TASK B — Create 5 In-App Purchases (Features tab)

Product IDs are hardcoded in the app + backend. A typo = broken purchases. Copy-paste each.

### B1 — Three Consumables: Features → In-App Purchases → "+" → **Consumable**
For each: enter Reference Name + Product ID → create → then set Price → add English (U.S.) display name + description → upload the paywall review screenshot (James provides; if not ready, create them anyway and add the screenshot before submit).

| Reference Name | Product ID | Price | Display Name | Description |
|---|---|---|---|---|
| Credits Pack 100 | `now.archie.credits.pack100` | **$79.00** (Tier) | 100 Credits | 100 data credits for verified property owner lookups. |
| Credits Pack 250 | `now.archie.credits.pack250` | **$149.00** | 250 Credits | 250 data credits for verified property owner lookups. |
| Credits Pack 1000 | `now.archie.credits.pack1000` | **$499.00** | 1,000 Credits | 1,000 data credits for verified property owner lookups. |

### B2 — Subscription group + two auto-renewable subs: Features → Subscriptions
1. Create a **Subscription Group** named: `Archie Pro`
2. Inside it, add two subscriptions:

| Reference Name | Product ID | Duration | Price | Display Name | Description |
|---|---|---|---|---|---|
| Archie Pro Monthly | `now.archie.credits.sub.monthly` | 1 Month | **$29.99** | Archie Pro — Monthly | 100 data credits every month for owner lookups. |
| Archie Pro Annual | `now.archie.credits.sub.annual` | 1 Year | **$299.99** | Archie Pro — Annual | 1,200 data credits per year (100/month) for owner lookups. |

3. Subscription group **localization** (English U.S.): display name `Archie Pro`.

### Goal state
All 5 reach **"Ready to Submit."** Each needs: price + English localization + a review screenshot. (James's desktop Claude will attach them to the app version and submit via API — you do NOT need to submit.)

---

## When done
Tell James: "Privacy published, 5 IAPs created." He'll have his desktop Claude attach the IAPs to the version and submit. If any product ID won't save or a price tier is missing, STOP and tell James — don't substitute values.
