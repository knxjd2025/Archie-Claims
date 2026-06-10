# Archie Claims — Master Improvement Plan

**Version**: 1.0.0 · **Date**: 2026-06-09 · **Owner**: Product Owner / Developer (James Turner)
**Goal (owner's words)**: "best-in-class canvassing tool" with "better and more user friendly UX and UI"
**Executes against**: `docs/product/PRD.md` (v1.0.0) and `docs/product/architecture.md` (v1.0.0, incl. §8 tech-debt register)

> **Sourcing note**: `competitive-analysis.md`, `market-research.md`, and `ux-spec.md` were not present in
> `docs/product/` when this plan was written. Competitive and market citations therefore reference
> **PRD §8 (Competitive Context)** and **PRD §9 (Market Context)**, which embed that research; engineering
> citations reference the **architecture.md §8 tech-debt register** (items `TD-1`…`TD-18`); every UX critique
> item below was verified first-hand against the Swift source (file:line cited). Nothing in this plan
> depends on a doc that doesn't exist.

---

## 1. Strategy Summary

### Where Archie Claims wins today

1. **Free, official storm evidence at per-address granularity.** Every competitor charges for the
   thing we give away: SalesRabbit sells weather as a paid add-on, HailTrace/Interactive Hail Maps
   *are* the paid subscription, Hail Recon gates its data (PRD §8). Our NOAA SPC + NWS pipeline costs
   $0/user (`StormDataService.swift`) and is already cached, debounced, and attributed correctly.
2. **The only canvassing app wired into the contractor's own CRM + a claims-trained AI.** Client
   attachment, claim-document filing from the kitchen table, and adjuster-email logging
   (`ArchieCRMService.swift`, `AssistantView.swift`) have no equivalent in SalesRabbit, Spotio, or any
   hail-map product (PRD §8). This is the moat — nobody else can copy it without owning a roofing CRM.
3. **Genuinely fast door logging.** Quick Log's instant-pin + background-enrichment design
   (`CanvassMapView.quickLog`, line 217) is architecturally right; it just needs the last tap removed
   and feedback added (see UX-1/UX-2).

### Where we lose today

- **Leads die on the phone.** Device-only `LeadStore` (TD-3, PRD Open Question 1) breaks the
  "field companion to Archie CRM" promise for both the manager (Dana) and owner (Marcus) personas, and
  severs the only monetization funnel the app has (PRD §9: success = CRM accounts + linkage depth).
- **We're flying blind.** Zero analytics (PRD §11.3) — none of the PRD's activation/engagement targets
  can be measured. Verified by grep: no analytics, telemetry, or event code anywhere in the target.
- **Speed-of-UI details are below SalesRabbit's bar**: no haptics, no undo, no one-tap disposition,
  inconsistent storm colors, a "for testing" Charlotte default, no offline signal (all verified in
  source; details in §2).

### The three bets that matter

| Bet | What | Why it wins | Risk if skipped |
|---|---|---|---|
| **B1 — Close the CRM loop** | One-way lead push (`POST /api/leads`) on milestone statuses + "Send to Archie CRM"; later two-way | The entire positioning and revenue model (PRD §1.1, §9) hinge on doors becoming CRM pipeline. Data model already maps 1:1 (`Lead` ↔ CRM lead, architecture §10.2) | App stays a toy; CRM acquisition story collapses; Dana/Marcus never adopt |
| **B2 — Be the fastest knock-logger in the category** | Sticky-status one-tap logging, haptics, undo, offline hardening, follow-up reminders | We can't out-feature SalesRabbit's 10-year team suite this year (PRD §8), but we *can* beat everyone on per-door speed — the thing the commission rep (Tyler, 80–120 doors/day, PRD §2.1) actually feels | Reps churn back to SalesRabbit despite our free data |
| **B3 — Own the storm moment** | Storm event filters → saved territories → **storm push notifications** → (v2) swath polygons | DAU is storm-driven (PRD §11.2 targets 3× DAU in 72h post-event). Being the app that *tells you* a storm hit your turf converts seasonality from headwind (PRD §9) into our growth engine | HailTrace stays the storm-day default; we're only opened after someone else told the rep where to go |

Everything in this plan ladders to B1, B2, or B3. Instrumentation (§2 UX-23) is the precondition for all three.

---

## 2. UX/UI Improvements

Effort: **S** = ≤1 dev-day · **M** = 1–3 days · **L** = 1–2 weeks. "Why" cites PRD/architecture/source.

### A. Canvass map & Quick Log (Bet B2)

**UX-1 · Sticky-status Quick Log ("paint mode") — the single biggest UX upgrade** · **M**
- **What**: When Quick Log is armed, show a horizontal status palette (Not Home / Interested / Appt /
  Not Interested / Signed) pinned above the bottom bar. The selected status is "loaded"; every roof tap
  logs **one tap, zero dialogs**. Long-press a roof for the full dialog; "Not Home" pre-selected by
  default (it's ~70% of knocks).
- **Why**: The current flow is tap → reach to bottom `confirmationDialog` → pick from 7 buttons
  (`CanvassMapView.swift:175–194`). At Tyler's 80–120 doors/day (PRD §2.1) that's 100+ avoidable
  reaches. One-tap disposition is the table-stakes interaction in SalesRabbit/Spotio (PRD §8) — we should
  beat it, not trail it. Directly serves PRD F2's "log in under 5 seconds" promise.
- **Where**: `CanvassMapView.swift` — replace the `confirmationDialog` path in `handleTap`/`quickLog`;
  new `quickLogStatus: Lead.Status?` state; palette view next to `statusChips`.

**UX-2 · Haptic + undo toast on every door log** · **S**
- **What**: `.sensoryFeedback(.success, trigger:)` on lead save; transient toast "Logged: Not Home — Undo"
  (4 s) that deletes/reverts. Distinct haptic (`.impact(weight: .heavy)`) for Signed.
- **Why**: Grep confirms **zero haptic or feedback code in the app**. Reps log while walking in sun glare;
  eyes-free confirmation is a field requirement, and mis-taps currently create junk leads with no recovery
  except hunting them down in the Leads tab. Supports PRD F2 success metric (median 2 taps/door — now 1).
- **Where**: `CanvassMapView.quickLog` (line 217) + a small `ToastView` overlay; `LeadStore` already has
  `delete(_:)` for undo.

**UX-3 · Unify storm colors + add a map legend** · **S**
- **What**: Move kind colors to a single `StormReport.Kind.color` extension; add a collapsible legend
  capsule (hail ●, wind ●, tornado ●) anchored bottom-leading.
- **Why**: **Bug-level inconsistency found in source**: hail is orange/wind blue on the map
  (`CanvassMapView.swift:287–293`) but cyan/indigo in the property sheet (`PropertySheetView.swift:281–287`).
  PRD §5.3 explicitly flags the missing non-color legend as the app's accessibility gap.
- **Where**: `Models/StormReport.swift` (new extension), `CanvassMapView.stormMarker`,
  `PropertySheetView.StormReportRow.iconColor`, new legend in `CanvassMapView` overlays.

**UX-4 · Kill the Charlotte "for testing" default region** · **S**
- **What**: First launch → `.userLocation(fallback: .region(charlotte))` after permission; subsequent
  launches → persist/restore last camera region via `@AppStorage` (two doubles + span).
- **Why**: Source comment literally says "the default canvassing area for testing"
  (`CanvassMapView.swift:19–20`); PRD Open Question 4; TD-12. A rep in Oklahoma opening to Charlotte is a
  first-session activation killer (PRD activation target: first door logged in session 1 > 50%).
- **Where**: `CanvassMapView.swift` initial `cameraPosition` + `.onMapCameraChange` persistence;
  `AppSettings.swift` keys.

**UX-5 · Render the storm-overlay loading state** · **S**
- **What**: Small capsule "Checking storms…" (progress spinner) while the overlay fetch runs; brief
  "N reports" confirmation on completion.
- **Why**: `isLoadingStorms` is set but never rendered — dead state (TD-14, `CanvassMapView.swift:42,273,283`).
  On a 2-year lookback first fetch (up to 730 files, PRD F1 edge case) the map silently shows nothing for
  many seconds — users will conclude "no storms" and leave.
- **Where**: `CanvassMapView` overlay, reusing existing state.

**UX-6 · Storm kind + date filtering on the overlay** · **M**
- **What**: Tapping the storm toolbar icon opens a small popover: kind toggles (hail/wind/tornado) and a
  session date range ("Last 7d / 30d / custom / a specific event date") that narrows the overlay without
  touching the global Settings lookback.
- **Why**: Hail-map competitors organize the world by *storm event* (PRD §8 — HailTrace's core mental
  model); reps canvass "the May 14 storm," not "30 days." Today the only control is buried in Settings and
  is global. Stepping stone to B3 (saved territories + push).
- **Where**: `CanvassMapView` (new popover + filter state applied in `scheduleStormOverlayRefresh`);
  `StormDataService.reports` already returns kind+date — filtering is client-side and cheap.

**UX-7 · Cluster dense storm markers instead of silently capping at 80** · **M**
- **What**: At wide zoom, grid-bucket reports into count badges ("23 ⚡"); tap zooms in. Keep individual
  markers under ~0.2° span.
- **Why**: PRD F1 edge case: "marker cap of 80 means dense regions undercount visually" — in a major
  outbreak (exactly when the app matters most) the map lies about storm density. PRD §12 Phase 3 lists
  clustering; pulling it forward because it's a trust issue on the hero surface.
- **Where**: `CanvassMapView.stormMarkers` pipeline (bucket before `prefix(80)`).

**UX-8 · Lead pins deserve lead actions** · **S/M**
- **What**: Tapping a saved-lead pin shows a compact action sheet: cycle status, open Lead detail,
  open Property sheet. Today it routes to the generic property sheet (`CanvassMapView.swift:93–95`),
  which re-geocodes and only *mentions* the saved lead.
- **Why**: Working callbacks from the map is the PRD §4.2 core loop step 3; currently editing a pin
  requires leaving the map for the Leads tab. Direct manipulation of pins is standard in every D2D app
  (PRD §8).
- **Where**: `CanvassMapView.handleTap` + new lead action sheet; navigation into `LeadDetailView`.

**UX-9 · Fix the "Today" tally definition** · **S**
- **What**: Count doors by a new `lastKnockAt` (set on create and on status change), not `updatedAt`.
- **Why**: `todayStats` filters `updatedAt` is-today (`CanvassMapView.swift:350`) — editing notes on last
  week's lead inflates today's door count. The tally is the rep's scoreboard and the PRD's engagement
  metric (doors/day ≥ 40, §11.2); it must not be gameable by accident.
- **Where**: `Models/Lead.swift` (+ field, defaulted for migration), `LeadStore.update`, `CanvassMapView.todayStats`.

### B. Property sheet

**UX-10 · "Log this door" status row inside the property sheet** · **S**
- **What**: A segmented row of the five quick statuses at the top of `actionSection` — logging a knock
  from the evidence view without round-tripping through Quick Log mode.
- **Why**: PRD F4 actions today are only Save/Ask/Share (`PropertySheetView.swift:157–176`). The natural
  flow at the door is: tap house → show homeowner the evidence → log the outcome. Removing the mode
  dependency makes the sheet a complete door tool.
- **Where**: `PropertySheetView.actionSection` + reuse `saveLead()` with a status parameter.

**UX-11 · Distinguish offline from "no storms"** · **M**
- **What**: `StormDataService` returns per-day fetch failures (e.g. `(reports, failedDays)` or a thrown
  error when *all* network days fail and no cache exists); property sheet and overlay show
  "Couldn't reach NOAA — showing cached data" instead of the no-reports empty state.
- **Why**: TD-10: "offline looks identical to 'no storms'" — the single worst trust failure possible for
  an evidence product. A rep told "No reports in range" in a hail-damaged neighborhood (because LTE
  dropped) stops believing the app. PRD §4.4 error table currently codifies the silent behavior.
- **Where**: `StormDataService.reports/reportsForDay` (stop swallowing in `catch { return [] }`,
  lines 86–88), `PropertySheetView.stormSection`, `CanvassMapView` overlay state.

**UX-12 · People-search link kill-switch + "Open in Maps"** · **S/M**
- **What**: (a) Gate TruePeopleSearch/FastPeopleSearch rows behind a remote config flag fetched from the
  Archie backend (e.g. `GET /api/app-config`, cached, default **on**; assessor/NETR links always shown).
  (b) Add "Open in Apple Maps" to the address section (drive-to-appointment).
- **Why**: PRD Open Question 5 flags App Store review risk of people-search link-outs; a remote flag means
  a rejection becomes a config change, not a resubmission. Maps handoff is a free win for the appointment
  flow (PRD §4.2).
- **Where**: `PublicRecordsLinks.swift` (flag-aware `links(...)`), small config fetch in
  `ArchieBackendService`, `PropertySheetView.addressSection`.

### C. Archie AI chat

**UX-13 · Persist chat history with a conversation list** · **M**
- **What**: JSON-file store (mirror `LeadStore` pattern) for conversations; toolbar history button; store
  the attached client's id/summary so reopening restores the banner.
- **Why**: TD-8 / PRD Open Question 7 — a rep who got a great door script yesterday cannot retrieve it
  today; relaunch wipes everything (`AssistantView.swift:18`, in-memory `@State`). Retention surface for
  the conversion metrics in PRD §11.2.
- **Where**: new `Services/ChatStore.swift`, `AssistantView` load/save, `Models/ChatMessage.swift`
  (already `Codable`-friendly).

**UX-14 · True SSE streaming from the Archie backend** · **M (backend) + S (app)**
- **What**: Add SSE to `POST /api/ai-assistant`; the app's `AsyncThrowingStream` facade
  (`ArchieBackendService.streamReply`) already isolates the change — only the transport swaps.
- **Why**: TD-15 / PRD Open Question 11: today users stare at a spinner then get a wall of text; the
  legacy Anthropic mode already streams, so the default mode *feels worse than the deprecated one*.
  Perceived speed is the cheapest "AI quality" lever there is.
- **Where**: roofy-backend (`/api/ai-assistant`); `ArchieBackendService.swift` chat call.

**UX-15 · Real Markdown rendering in assistant bubbles** · **S**
- **What**: Replace `Text(LocalizedStringKey(message.text))` with `AttributedString(markdown:options:)`
  using `.full` interpretation (or split into paragraph blocks) so lists, headings, and multi-line
  structure render.
- **Why**: TD-18 — claim explanations and photo checklists are exactly the list-shaped content the
  current renderer flattens (`AssistantView.swift:549`).
- **Where**: `AssistantView.MessageBubble`.

**UX-16 · Chat ergonomics: keyboard + scroll** · **S**
- **What**: `.scrollDismissesKeyboard(.interactively)` on the chat `ScrollView` (grep confirms absent);
  scroll-to-bottom floating button when scrolled up; keep composer visible above keyboard.
- **Where**: `AssistantView` ScrollView block (lines 68–92).

**UX-17 · Context-aware quick prompts** · **S**
- **What**: Swap the static 4 prompts when context is attached — property attached → "Summarize this
  storm evidence for the homeowner", "Is this hail size claim-worthy?"; client attached → "Where does this
  claim stand?", "Draft a follow-up to the adjuster".
- **Why**: The Ask Archie handoff (PRD F4/F9) lands the user on generic prompts that ignore what they
  just attached; first-message friction is the conversion moment for the >25% linkage target (PRD §11.2).
- **Where**: `AssistantView.quickPrompts` → computed property keyed off `appState.pendingPropertyContext`
  / `attachedClient`.

### D. Leads tab

**UX-18 · Status-colored rows, recency sort, and sections** · **S**
- **What**: Color the status icon with the canonical status color (today it's flat `accentColor`,
  `LeadsView.swift:70`); sort by `updatedAt` descending (today: insertion order — `LeadStore.add` inserts
  at 0 but `update` doesn't re-rank, so today's hottest lead can sit mid-list); optional grouping
  "Today / This week / Earlier". Move `color(for: Lead.Status)` out of `CanvassMapView` (line 517) into a
  `Lead.Status.color` extension shared with the map.
- **Where**: `Models/Lead.swift`, `LeadsView.swift`, `CanvassMapView.swift`.

**UX-19 · Text action + smarter call action** · **S**
- **What**: Add "Text Homeowner" (`sms:` URL) beside Call in lead detail; pair with "Draft with Archie"
  so the AI-written follow-up is one copy-paste from sending.
- **Why**: Tyler "follows up with texts in the evening" (PRD §2.1) and the app has a follow-up-text quick
  prompt — yet no SMS affordance exists (`LeadDetailView.swift:48` is tel-only; grep confirms no `sms:`).
- **Where**: `LeadDetailView.swift` quick-actions section.

**UX-20 · Follow-up reminders (local notifications)** · **M**
- **What**: `followUpAt: Date?` on `Lead`; date picker in detail; smart defaults ("Not Home → in 2 days,
  6 pm"); `UNUserNotificationCenter` local notification deep-linking to the lead; "Due today" section
  atop `LeadsView`.
- **Why**: PRD pain point #3 ("lost callbacks") is unsolved as-built; SalesRabbit/Spotio both ship
  follow-up scheduling (PRD §8). This is the feature that makes the lead book a *system* instead of a list,
  and it drives non-storm-day retention (PRD §11.2 week-4 retention > 30%). Grep confirms zero
  notification code today.
- **Where**: `Models/Lead.swift`, `LeadDetailView`, `LeadsView`, new `Services/ReminderService.swift`,
  Info.plist permission string, permission priming (UX-22).

### E. Onboarding & system

**UX-21 · Surface lead-save failures; stop swallowing them** · **S**
- **What**: `LeadStore.save()` currently `try?`-ignores write errors (`LeadStore.swift:57–60`) — a full
  disk silently loses a day of knocks (TD-10). Track `lastSaveError`, surface a persistent banner.
- **Where**: `LeadStore.swift`, banner in `RootView` or `CanvassMapView`.

**UX-22 · Onboarding: permission priming + Quick Log demo + activation CTA** · **S/M**
- **What**: Add a pre-permission page ("We use your location to center the map on your turf — it never
  leaves your phone") before the system prompt fires on map appear; show the ⚡ Quick Log gesture on
  page 1 (it's the activation event, PRD §11.2, yet onboarding never mentions it); end with
  "Find my turf" (locate-me) instead of generic "Start Canvassing".
- **Why**: PRD targets: location grant > 70%, onboarding completion > 85%, first door in session 1 > 50%.
  Current onboarding (`OnboardingView.swift`) is three static value-prop pages with no priming and no
  gesture teaching.
- **Where**: `OnboardingView.swift`, `CanvassMapView.onAppear` (defer permission until after priming).

**UX-23 · Minimal privacy-friendly analytics (the measurement foundation)** · **M**
- **What**: A tiny in-house event logger (no third-party SDK, consistent with the zero-dependency
  architecture, architecture §1.3): batched JSON events → a new `POST /api/app-events` on the Archie
  backend (the auth plumbing already exists). Core events: `onboarding_done`, `location_granted`,
  `door_logged{status,mode}`, `property_sheet_opened`, `storm_overlay_refreshed{count}`, `lead_saved`,
  `sign_in`/`account_created`, `client_attached`, `doc_filed`, `ask_archie_handoff`, `chat_sent`,
  `crm_lead_pushed`. Anonymous device id; opt-out toggle in Settings; disclosed in privacy policy.
- **Why**: PRD §11.3: "The app currently ships no analytics… targets above [are unmeasurable]."
  Open Question 3. Every other item in this plan needs this to be judged.
- **Where**: new `Services/EventLogger.swift`, call sites across views, backend endpoint,
  `docs/PRIVACY_POLICY.md` update.

**UX-24 · Kill the stored password (auth refresh tokens)** · **M (backend) + S (app)**
- **What**: Backend `POST /api/auth/refresh`; app stores access+refresh tokens, deletes the
  `archie-backend-password` Keychain entry on first launch after update.
- **Why**: TD-1/TD-2 — the only high-severity security item; architecture §10.1 says it "should precede
  App Store launch marketing to CRM customers." Plaintext credentials are also an App Store review and
  trust liability for a CRM vendor.
- **Where**: roofy-backend; `ArchieBackendService.authenticate/refreshSession`, `KeychainStore.swift`.

---

## 3. Feature Roadmap

### Tier 1 — Quick wins (days; ship as v1.0.1 alongside App Store submission)

| # | Item | Effort | Bet |
|---|------|--------|-----|
| QW-1 | Replace `support@example.com` with real address (`AppSettings.swift:9`) — **release blocker** (PRD §7.4, TD-9) | XS | — |
| QW-2 | Default region from user location / last camera (UX-4) | S | B2 |
| QW-3 | Storm color unification + legend (UX-3) | S | B3 |
| QW-4 | Quick Log haptics + undo toast (UX-2) | S | B2 |
| QW-5 | Storm loading indicator (UX-5) | S | B3 |
| QW-6 | Today-tally accuracy via `lastKnockAt` (UX-9) | S | B2 |
| QW-7 | Leads list: status colors, recency sort (UX-18) | S | B2 |
| QW-8 | SMS quick action in lead detail (UX-19) | S | B2 |
| QW-9 | Property-sheet "Log this door" row (UX-10) | S | B2 |
| QW-10 | Chat Markdown + keyboard polish (UX-15, UX-16) | S | — |
| QW-11 | Context-aware quick prompts (UX-17) | S | B1 |
| QW-12 | Lead-save failure banner (UX-21) | S | B2 |
| QW-13 | Onboarding priming + Quick Log demo (UX-22) | S/M | B2 |
| QW-14 | People-search remote kill-switch + Open in Maps (UX-12) | S/M | — |
| QW-15 | Event logger + core events (UX-23) | M | all |

### Tier 2 — v1.1 (weeks; the "companion app becomes real" release)

| # | Item | Effort | Bet | Notes |
|---|------|--------|-----|-------|
| V1-1 | **Lead → CRM one-way sync** | L | B1 | `syncedCRMLeadID: String?` on `Lead`; "Send to Archie CRM" in `LeadDetailView`; auto-prompt on Appointment/Signed/Inspected; bulk "Push N leads" in `LeadsView`; synced badge on rows/pins. Backend: accept storm summary + coordinates on `POST /api/leads`. Offline-safe: queue + retry (pairs with V1-5). PRD Open Question 1 Option A; architecture §10.2. The monetization hook: pushed leads land in the CRM free tier → upgrade path. |
| V1-2 | **Sticky-status Quick Log** (UX-1) + lead-pin actions (UX-8) | M | B2 | The speed headline for App Store screenshots. |
| V1-3 | **Follow-up reminders** (UX-20) | M | B2 | Local notifications; no backend needed. |
| V1-4 | **Chat persistence + conversation list** (UX-13) and **SSE streaming** (UX-14) | M+M | B1 | Streaming requires one backend change; facade already isolates it. |
| V1-5 | **Offline hardening** | M | B2 | UX-11 (offline vs no-reports) + queued CRM pushes (V1-1) + pre-fetch SPC days for the visible region on Wi-Fi ("Download this market"). Canvassing happens on rural LTE; PRD §4.4 currently codifies silent failure. |
| V1-6 | Storm kind/date filter popover (UX-6) + marker clustering (UX-7) | M+M | B3 | Sets up event-centric model for territories/push. |
| V1-7 | Auth refresh tokens; delete stored password (UX-24) | M | — | TD-1/2; do in the same backend release as V1-1's endpoint work. Add server-side `?lead_id=/job_id=` claim filters (TD-4/5) while in there. |
| V1-8 | Address-based lead dedupe (TD-13) | S | B2 | Dedupe on reverse-geocoded address once available; today two townhomes 22 m apart collide. |
| V1-9 | Extract `CanvassSession`/`ChatSession` @Observable objects (TD-7) | M | — | Pay this down *while* touching the two big views for V1-2/V1-4, not as a separate project. Unlocks tests for quick-log and chat pipelines (currently 0% coverage, architecture §3). |

### Tier 3 — v2 bets (quarters; each gates on Tier-2 measurement)

1. **Storm push notifications + saved territories (the DAU engine — biggest v2 bet, do first).**
   Rep saves territories (map regions); server-side job watches SPC feeds and pushes "1.75-inch hail
   reported in your Concord territory 2h ago — 41 homes you've knocked are inside it." Converts storm
   seasonality (PRD §9 headwind) into the 3× storm-DAU target (PRD §11.2). Needs: APNs, backend cron +
   territory store, deep link to region. PRD §12 Phase 3.
2. **Team canvassing on the CRM team tier (Dana persona).** Shared door map, rep daily tallies, simple
   leaderboard, territory assignment. This is the first feature that should be **tier-gated** (PRD Open
   Question 2): free for individuals forever; team visibility = CRM team-tier seat. Direct counter to
   SalesRabbit's stronghold (PRD §8) — sold through companies already on Archie CRM, not head-to-head.
3. **Hail swath visualization.** SPC point reports are honest but coarse (PRD §8 "known gap"). Evaluate:
   (a) derive swaths from NOAA MRMS MESH grids (free, engineering-heavy), vs (b) license (HailTrace
   et al., per-seat cost kills the free model). Recommendation: prototype (a) server-side as raster tiles;
   ship as the first paid-tier *data* differentiator only if pilots demand it (PRD Open Question 8).
4. **Route assist (not full route planning — stay out of dispatch, PRD non-goal 4).** "Knock order"
   suggestion along the current street from un-knocked addresses between logged pins; Apple Maps handoff
   for appointment driving. Lightweight, on-device, no territory engine needed.
5. **Branded homeowner storm report.** Today's share is plain text (`PropertySheetView.shareText`).
   Generate a one-page branded PDF/image (company logo via CRM profile) — the credibility artifact for
   the kitchen table, and a viral surface ("Generated with Archie Claims"). Reuses the CRM's
   roof-report/R2 plumbing.
6. **Live Activity / widget for the daily tally** (architecture §10.8) + iPad/landscape once team
   features exist.

---

## 4. "Do First" Sprint (2 weeks, ordered)

One developer, full codebase access. Order respects dependencies (measure before optimize; backend asks
filed on day 1 so server work overlaps client work).

| # | Item | Size | Justification |
|---|------|------|---------------|
| 1 | **QW-1 real NOAA/NWS contact email** (`AppSettings.swift:9`) | XS | Release blocker (PRD §7.4); 5 minutes; do it before anything else gets forgotten. |
| 2 | **File backend tickets**: `POST /api/leads` push contract, SSE on `/api/ai-assistant`, `POST /api/auth/refresh`, `POST /api/app-events`, `/api/app-config` flag | S | Everything in B1 waits on server lead-time; unblock it on day 1 (same owner, but context-switch cost is real). |
| 3 | **UX-23 event logger + core events** | M | The PRD's metrics are unmeasurable today (§11.3). Every later item's success criteria (§5) depends on this landing *first* so the pilot generates baselines. |
| 4 | **UX-4 default region fix** | S | First-session activation killer; trivially small; comment says "for testing." |
| 5 | **UX-2 haptics + undo** | S | Field feel; prerequisite polish for the sticky-status mode that follows. |
| 6 | **UX-1 sticky-status Quick Log** | M | The bet-B2 headline. Cuts logging to one tap/door; do after #5 so feedback ships with it. |
| 7 | **UX-3 color unification + legend** + **UX-5 loading state** | S | Trust + accessibility on the hero surface; both are tiny once `Kind.color` exists. |
| 8 | **UX-11 offline vs no-reports distinction** | M | Worst trust failure in the app for an evidence product; pilots will hit rural LTE on day one. |
| 9 | **UX-9 tally fix + UX-18 leads sort/colors + UX-19 SMS action** | S | Three small lead-book wins, one PR; makes evening follow-up workflow credible for pilots. |
| 10 | **UX-12 people-search kill-switch** | S/M | Submission insurance — must be in the binary *before* first App Store review (PRD Open Question 5). |
| 11 | **V1-1 lead → CRM push MVP** ("Send to Archie CRM" button + auto-prompt on Appointment/Signed; queue offline) | M/L | Bet B1's first slice; start as soon as the backend endpoint from #2 is live; OK if it lands in week 3 — the contract work in week 1 is what matters. |
| 12 | **QW-10/11 chat Markdown, keyboard, context prompts** | S | Round out the sprint; cheap perceived-quality wins for the AI surface while backend SSE bakes. |

**Explicitly deferred from this sprint**: chat persistence, reminders, clustering, refresh tokens
(all v1.1) — they're valuable but none gates the TestFlight pilot (PRD §12 Phase 1), and the sprint's
purpose is: *submittable, measurable, fast-at-the-door, with the CRM loop opened.*

---

## 5. Metrics to Watch (per improvement)

All client metrics come from UX-23 events; backend metrics from roofy-backend logs; store metrics from
App Store Connect. Baselines = first 2 pilot weeks; targets from PRD §11.

| Improvement | Primary metric | Target / expectation |
|---|---|---|
| Sticky-status Quick Log (UX-1) | Median taps per logged door; `door_logged` events/user/field-day | 2 → 1 tap; doors/day toward ≥ 40 (PRD §11.2) |
| Haptics + undo (UX-2) | Undo rate; lead deletions within 5 min of creation | Undo < 5% of logs; junk-lead deletions trend to ~0 |
| Default region (UX-4) | % sessions whose first map interaction is in-region; time-to-first `door_logged` | First-door-in-session-1 > 50% (PRD activation) |
| Legend/colors + loading (UX-3/5) | `storm_overlay_refreshed` retention (overlay stays on) | > 80% sessions keep overlay on (PRD §11.2) |
| Offline distinction (UX-11) | "couldn't reach NOAA" impressions vs empty-state impressions; support complaints | Zero "app says no storms but there were" reports from pilots |
| Tally fix (UX-9) | Doors/day distribution sanity (no spikes from edits) | Trustworthy denominator for all engagement metrics |
| Property-sheet log row (UX-10) | Share of `door_logged` with `mode=sheet` | > 15% of logs — validates non-mode logging |
| Leads sort/SMS (UX-18/19) | `sms_opened` per WAU; evening-session (5–9 pm) lead-detail opens | Evening engagement uptick; callbacks worked in-app |
| Follow-up reminders (UX-20) | Reminders set per rep-week; notification→app open rate; Not Home→Interested conversion | Week-4 retention of activated users > 30% (PRD) |
| Onboarding priming (UX-22) | Location grant rate; onboarding completion | > 70% grants; > 85% completion (PRD) |
| Lead → CRM push (V1-1) | `crm_lead_pushed` per signed-in WAU; % of Appointment/Signed leads pushed; app-originated CRM accounts that later upgrade | > 50% of milestone leads pushed; this is **the** B1 number |
| Chat persistence + streaming (V1-4) | Chat sends per WAU; conversation reopen rate; p50 time-to-first-token | TTFT < 1.5 s with SSE; reopens > 20% of conversations |
| Context prompts (UX-17) | Ask-Archie handoff → first-message conversion | > 60% of handoffs result in a sent message |
| People-search flag (UX-12) | App Store review outcome; lookup-link CTR | Approval without rejection cycle; CTR informs Open Question 5 |
| Kill-switch on password (UX-24) | % installs migrated off stored password; silent re-login success | 100% migration in 2 releases; re-login success > 95% (PRD quality) |
| Storm push + territories (v2-1) | Storm-event DAU multiple; push opt-in; push→`door_logged` within 24 h | ≥ 3× baseline DAU within 72 h of a covered event (PRD §11.2) |
| Team tier (v2-2) | Team-tier seats attributable to app; reps per company active | First gated-revenue line for the app |

**North star (PRD §11.1)**: storm-verified doors logged per week, all users. Every sprint review starts
with that number and its three drivers: active canvassers × doors/day × storm coverage.

---

## 6. Standing Guidance for the Implementing Developer

- **Don't break the zero-dependency rule** (architecture §1.3) — the event logger, toasts, clustering,
  and reminders are all achievable with Apple frameworks. It keeps review risk and binary size down.
- **Touch `CanvassMapView`/`AssistantView` through extraction** (TD-7): when implementing UX-1 and V1-4,
  move logic into `CanvassSession`/`ChatSession` observables and add unit tests — these two files are
  already 528/602 lines and every Tier-2 feature lands in them.
- **Migration discipline on `Lead`**: UX-9 (`lastKnockAt`), UX-20 (`followUpAt`), V1-1
  (`syncedCRMLeadID`) all change the on-disk JSON — add them as optionals/defaults in one release so
  existing pilots' lead books decode cleanly (`LeadStore.load` currently fails silently to an empty
  array, which would *erase* a rep's book on a bad decode — guard that first; see UX-21).
- **Sequence backend asks in two batches**: Batch 1 (sprint): `/api/leads` push, `/api/app-events`,
  `/api/app-config`. Batch 2 (v1.1): SSE chat, `/api/auth/refresh`, claim FK filters. One deploy each.

---

**Document History**

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0.0 | 2026-06-09 | Improvement-plan agent (Claude) | Initial plan from PRD v1.0.0, architecture v1.0.0, and full source verification |
