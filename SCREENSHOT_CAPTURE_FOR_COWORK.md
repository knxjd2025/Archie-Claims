# Capture App Store Screenshots — Archie Canvass (for Cowork)

**For:** Claude Cowork (controls James's Mac).
**Goal:** Capture 4–5 clean App Store screenshots of Archie Canvass and save them to `~/Archie-Claims/screenshots/`.

## Already set up (don't redo)
- The **iPhone 17 Pro Max** simulator (iOS 26.4, UDID `33FC60BB-37B8-4302-9295-37212F090B12`) is **booted**, with the app **installed and launched**.
- This is the required App Store size: **6.9" / 1320×2868**.
- Location permission is granted; simulated location is **Charlotte, NC** (35.2271, -80.8431).
- The app opens on a 4-page onboarding flow ("Canvass Smarter").

## How to capture each shot (clean, correct resolution)
With the Simulator window focused, press **⌘S** (File → Save Screen). It saves a 1320×2868 PNG to the Desktop. OR run in Terminal:
```
xcrun simctl io 33FC60BB-37B8-4302-9295-37212F090B12 screenshot ~/Archie-Claims/screenshots/NN-name.png
```
The `simctl` command is preferred (exact filename + folder). Take each shot, then **move/rename all into `~/Archie-Claims/screenshots/`** numbered in the order below.

## Demo account (for the signed-in screens)
- Email: `james+appreview@bestroofingnow.com`
- Password: `ArchieReview#2026`
(Sign in via Settings tab → Account, or when the app prompts.)

## Screens to capture, in order

1. **`01-onboarding.png`** — the first onboarding page ("Canvass Smarter", orange map icon). Already on screen — capture it now.
2. **`02-map.png`** — tap **Next** through the 3 remaining onboarding pages, then **Get Started**. Allow location if prompted ("Allow While Using App"). You'll land on the canvassing **map**, centered on Charlotte. Capture it.
3. **`03-property-storm.png`** — **tap any house/pin on the map** to open the Property sheet. Wait for the storm section to load (NOAA reports / "Checking NOAA storm reports…" resolves to data). Capture the sheet showing the address + storm data.
4. **`04-assistant.png`** — go to the **AI assistant** tab (sign in with the demo account first if prompted). Type a short prompt like `What should I look for on a hail-damaged roof?` and send; once a reply appears, capture it.
5. **`05-credit-store.png`** — open the **Data Credits** store (from the Property sheet's owner-lookup section, tap the credits/buy button, or wherever the credit store opens). It shows the subscription + credit packs with Apple/Web prices. Capture it.

### SKIP — do NOT capture
- The **owner-report result** screen (real homeowner name/phone/email). James wants this excluded — it's real PII and Apple discourages it. Capture the **credit store** instead (step 5), not the owner result.

## When done
- Confirm 4–5 PNGs are in `~/Archie-Claims/screenshots/`, each **1320×2868**.
- Tell James they're ready; he (or the App Store Connect browser agent) uploads them on the version page (Step 7 of the App Store Connect walkthrough). Apple auto-scales this 6.9" set to smaller iPhones — no other sizes needed.

## If something blocks you
- Map blank/not centered: it may need a moment to load tiles; the location is already Charlotte.
- Sign-in fails: the account is real on production — double-check the email/password above exactly.
- Don't change any app code or settings; this is capture-only.
