# Product Requirements Document: Archie Claims

**Version**: 1.0.0
**Last Updated**: 2026-06-09
**Status**: Approved (documents the app as built) + Draft (near-term direction)
**Owner**: Product Manager
**Platform**: iOS (SwiftUI, iOS 17+), App Store distribution
**Relationship**: Field companion to the Archie CRM web platform (app.archie.now)

> This PRD documents Archie Claims **as built** (verified against the Swift source in
> `ArchieClaims/` on 2026-06-09) and defines near-term direction. Every feature claim in
> Section 3 maps to shipped code; Section 12 covers what comes next.

---

## 1. Product Overview

### 1.1 Vision Statement

Archie Claims is the fastest door-to-door storm canvassing tool for residential roofing
contractors. Standing in front of any house, a rep can pull official NOAA storm evidence
for that exact address in seconds, log the knock with two taps, look up the owner through
free public records, and get AI help with scripts, claims, and insurance paperwork — all
from one app. It is the **field companion to the Archie CRM** (app.archie.now): the same
account, the same backend, the same clients and claims, extended to the street where
roofing sales actually happens.

**Positioning**: "Canvass where the storm actually hit." Competing canvassing apps
(SalesRabbit, Spotio, Lead Scout) sell territory management to sales managers; hail-map
products (HailTrace, Interactive Hail Maps) sell weather data subscriptions. Archie Claims
combines free, official storm evidence + door logging + an AI claim assistant wired into
the contractor's own CRM — at zero marginal data cost (NOAA SPC, NWS, and Apple geocoding
are all free), making it a natural acquisition and retention surface for Archie CRM.

### 1.2 Target Audience

**Primary**: Door-to-door storm canvassers and roofing sales reps chasing recent
hail/wind damage in US markets (Southeast, Midwest, Plains).

**Secondary**: Roofing company owners and sales managers — existing or prospective
Archie CRM customers — who want their reps producing documented, storm-backed leads and
who handle insurance claims through the CRM.

### 1.3 Success Metrics (summary — detail in Section 11)

- **Activation**: % of new installs that log their first door (Quick Log or Save as Lead) in session 1 — target > 50%
- **Engagement**: doors logged per active canvasser per field day — target ≥ 40; DAU spike ≥ 3x baseline within 72h of a major SPC storm event in a covered metro
- **Conversion**: % of installs signing in / creating an Archie account — target > 35%; % of signed-in users who attach a CRM client or document in chat — target > 25%

---

## 2. User Personas

### 2.1 Primary Persona: "Storm Canvasser" — Tyler, the D2D Rep

**Demographics**:
- Age: 21–35
- Occupation: Commission-only door-to-door roofing sales rep; often travels market-to-market following storms
- Tech savviness: Medium — lives on an iPhone, hates typing in the field
- Location: Charlotte NC metro and other storm-prone US markets

**Pain Points**:
1. Doesn't know which streets actually took hail — wastes hours knocking unaffected blocks
2. Homeowners ask "what storm?" and he has no credible evidence to show at the door
3. Tracking knocks in notes apps or paper means lost callbacks and re-knocked doors
4. Looking up an absentee owner means juggling county sites and people-search tabs
5. Freezes on objections about deductibles, ACV vs RCV, and the claim process

**Goals**:
1. Knock only where storm evidence supports a claim conversation
2. Log every door in under 5 seconds and never lose a callback
3. Show the homeowner official NOAA data for *their* address
4. Get instant, credible answers to insurance questions mid-conversation

**Typical Day**: Checks where yesterday's storm tracked, drives to a neighborhood, knocks
80–120 doors, logs outcomes, sets 2–4 inspection appointments, follows up with texts in
the evening.

**Quote**: *"If I can show them the hail report for their own street, the conversation
changes completely."*

### 2.2 Secondary Persona: "Sales Manager" — Dana

- Runs a 5–15 rep canvassing team for a roofing company on Archie CRM (team tier)
- **Pain points**: no visibility into rep activity (doors, appointments) without nagging;
  reps' leads live in personal notebooks; inconsistent door scripts and claim explanations
- **Goals**: every rep knocking storm-verified streets; standardized scripts via Archie AI;
  eventually, rep-logged doors flowing into the CRM pipeline she already manages
- **Current gap (as built)**: leads are on-device only and there is no team visibility —
  Dana's needs drive the near-term roadmap (Sections 10, 12), not the current release.

### 2.3 Secondary Persona: "Owner" — Marcus

- Owns a 10–50 employee residential roofing company; an Archie CRM customer handling
  insurance restoration work
- **Pain points**: paying per-seat for canvassing software *and* hail-map data on top of a
  CRM; claim documents scattered across reps' phones and email
- **Goals**: one vendor (Archie) covering office + field; insurance docs reps collect at
  the kitchen table landing on the claim record automatically; defensible, compliant
  canvassing (TCPA, do-not-knock)
- **What the app gives him today**: free field tool for his reps; document/email capture
  that files to claims in his CRM; compliance disclaimers baked into the product.

### 2.4 User Journey Map

**Current State (before Archie Claims)**:
1. Rep guesses storm-hit streets from Facebook posts or a paid hail-map subscription
2. Knocks doors with no per-address evidence; tracks outcomes on paper/notes app
3. Owner lookups via multiple browser tabs; claim questions answered by texting the manager
4. Insurance estimates photographed and texted; never reach the CRM claim record

**Future State (with Archie Claims)**:
1. Opens the Canvass map → storm overlay shows exactly which blocks took hail (up to 2 years back)
2. Quick Log mode: tap roof → status → next door; address + storm evidence saved automatically
3. Property sheet shows NOAA reports + active NWS alerts + free owner lookup links for any tapped house
4. "Ask Archie" answers claim questions with the property's storm data attached; estimates and adjuster emails get OCR'd into the chat **and** filed to the client's claim in the CRM

---

## 3. Features & Requirements (As Built)

All features below are **shipped** in the current build. Priorities reflect their role in
the product; complexity reflects the implementation as found in source.

### Feature 1: Canvass Map with NOAA Storm Overlay

**Priority**: P0 (core) · **Complexity**: High · **Source**: `Views/CanvassMapView.swift`, `Services/StormDataService.swift`, `Services/SPCReportParser.swift`

**User Story**:
As a storm canvasser, I want recent NOAA hail/wind/tornado reports drawn directly on the
map I'm canvassing from, so that I knock only the streets where a storm actually hit.

**Description**:
MapKit map (hybrid/satellite by default, toggle to standard) defaulting to Charlotte, NC
(35.2271, -80.8431). A storm overlay (toggleable, on by default) draws NOAA SPC severe
weather reports for the visible region: hail (orange), wind (blue), tornado (red) markers,
capped at 80, refreshed 450 ms after the camera settles. Fetch radius adapts to the
visible span (clamped 2–60 mi); lookback comes from Settings (default 30 days, up to 2
years). SPC daily CSVs (`spc.noaa.gov/climo/reports/yymmdd_rpts_filtered.csv`) are cached
in memory and on disk per convective day (today's file intentionally not frozen on disk).
The map also shows the user's location (when-in-use permission requested on appear),
status-colored lead pins, a compass, +/− zoom buttons, a locate-me button, and an
empty-state hint capsule.

**Acceptance Criteria**:
```gherkin
Given the app launches with the storm overlay enabled
When the map camera settles on a region
Then SPC reports for the visible area and configured lookback render as colored markers (≤ 80)
And panning/zooming re-queries after a 450 ms debounce, cancelling stale requests

Given a storm marker is visible
When the user taps it
Then the Property sheet opens at the marker's coordinate

Given the same convective day was fetched earlier
When its reports are needed again
Then they are served from the memory or disk cache without re-downloading

Given the SPC fetch fails (offline, missing file)
Then the overlay shows no markers for that day and the app does not error
```

**Dependencies**: NOAA SPC CSV feed (free, no key); User-Agent identifies the app per NOAA guidance.

**Edge Cases**: lookback of 730 days triggers up to 730 daily-file fetches on first use
(then cached); marker cap of 80 means dense regions undercount visually; SPC convective
days are 12Z–12Z so "yesterday's storm" can appear under today's date.

---

### Feature 2: Quick Log Mode (Two-Tap Door Logging)

**Priority**: P0 (core — the activation moment) · **Complexity**: Medium · **Source**: `CanvassMapView.swift` (`quickLog`), `Services/GeocodingService.swift`, `Services/LeadStore.swift`

**User Story**:
As a storm canvasser walking a street, I want to log each knock in two taps without
typing, so that I keep moving and never lose track of a door.

**Description**:
A bolt (⚡️) toolbar toggle arms Quick Log mode (banner confirms it's on). Tapping a roof
opens a confirmation dialog — Not Home / Interested / Appointment Set / Not Interested /
Signed! / Full Details… — and saving creates a lead instantly with placeholder address
"Locating address…". Reverse geocoding (Apple `CLGeocoder`) and a storm-evidence snapshot
(`StormDataService.summary`) fill in via a background task while the rep walks to the
next door. Tapping within ~0.0002° (~22 m) of an existing lead updates that lead's status
instead of duplicating. "Full Details…" opens the Property sheet instead.

**Acceptance Criteria**:
```gherkin
Given Quick Log mode is on
When the user taps a rooftop and picks "Interested"
Then a lead is saved immediately and a status-colored pin appears at that spot
And the address and storm summary populate in the background without blocking the UI

Given a lead already exists within ~22 m of the tap
When the user picks a new status
Then the existing lead's status is updated (no duplicate is created)

Given reverse geocoding fails
Then the lead's address falls back to its lat/long coordinates

Given Quick Log mode is off
When the user taps the map
Then the Property sheet opens instead of the log dialog
```

**Success Metrics**: median taps per logged door = 2; doors/day per active canvasser.

**Edge Cases**: airplane mode → coordinates-only address, empty storm summary retried
never (acceptable for v1); rapid tapping creates multiple background tasks (each updates
its own lead).

---

### Feature 3: Status Filters, Today Tally, Search, and Map Controls

**Priority**: P1 · **Complexity**: Low–Medium · **Source**: `CanvassMapView.swift`

**User Story**:
As a canvasser, I want to filter pins by status, see today's door count at a glance, and
jump to any address or city, so that I can work callbacks and relocate to new storm
markets quickly.

**Description**:
(a) Horizontally scrolling status chips ("All (n)" + one chip per status with count > 0)
filter map pins; (b) a bottom capsule shows "Today: N doors · X interested · Y appts ·
Z signed 🎉" computed from leads updated today; (c) a search field forward-geocodes any
address or city (Apple geocoding), shows up to 5 disambiguation results, auto-selects a
single match, animates the camera with an address-tight or city-wide span, and drops a
tappable pin that opens the Property sheet; (d) zoom in/out buttons (0.45x / 2.2x span)
and a locate-me button.

**Acceptance Criteria**:
```gherkin
Given leads with mixed statuses exist
When the user taps the "Interested" chip
Then only Interested pins remain on the map; tapping the chip again clears the filter

Given the user logged 12 doors today and 30 last week
Then the tally capsule reads "Today: 12 doors" plus interested/appointment/signed counts

Given the user searches "Moore, OK"
When a single match resolves
Then the camera animates there with a city-scale span and a pin appears
And tapping that pin opens the Property sheet (storm report for that spot)

Given a search has no matches
Then "No matches — try adding a city or state." is shown
```

---

### Feature 4: Property Sheet (Tap Any House)

**Priority**: P0 (core) · **Complexity**: Medium · **Source**: `Views/PropertySheetView.swift`, `Services/PublicRecordsLinks.swift`, `Models/NWSAlert.swift`

**User Story**:
As a canvasser at the door, I want one sheet with the address, the storm evidence, owner
lookup links, and actions (save / ask AI / share), so that I have everything for the
conversation without leaving the map.

**Description**:
Tapping a house (Quick Log off) opens a medium/large-detent sheet that concurrently:
reverse-geocodes the address (falls back to coordinates with an explanatory note, and
flags an existing saved lead); loads **Storm Evidence** — active NWS alerts for the exact
point (`api.weather.gov/alerts/active?point=`) shown in red, plus up to 12 SPC reports
within the configured radius/lookback (magnitude like `1.75" hail` / `70 mph wind` /
`EF2 tornado`, town/county, date, distance), with a NOAA/NWS "preliminary, unverified"
attribution footer and an empty state pointing at Settings; lists **Owner & Contact
Lookup** links — NETR county records directory, a targeted assessor web search,
TruePeopleSearch, FastPeopleSearch, and a quoted-address web search — opened in an
in-app `SFSafariViewController` with a compliance footer (verify info; TCPA/do-not-knock).
Actions: **Save as Lead / Update Lead Snapshot**, **Ask Archie** (queues a property
context block and switches to the AI tab), and **Share Storm Report** (plain-text
summary with attribution via ShareLink).

**Acceptance Criteria**:
```gherkin
Given the user taps a house with SPC reports in range
Then the sheet shows the street address and up to 12 reports sorted newest-then-closest
And each row shows magnitude, location, county, date, and distance in miles

Given an active NWS alert covers the point
Then the alert event and headline render above the SPC reports in red

Given no reports are in range
Then a "No reports in range" empty state suggests widening radius/lookback in Settings

Given the user taps "Save as Lead" for a new address
Then a lead is created with the address and current storm summary snapshot
And for an already-saved address the button reads "Update Lead Snapshot" and refreshes the snapshot

Given the user taps "Ask Archie"
Then the app switches to the Archie AI tab with a property-context banner attached
And the next message includes address, coordinates, storm summary, and any active alerts

Given the user taps a lookup link
Then the public site opens in an in-app browser (nothing is scraped or stored)
```

**Edge Cases**: ocean/rural taps with no address still show storm data; people-search
sites may rate-limit or change URL formats (links are best-effort).

---

### Feature 5: Archie AI Chat (CRM-Backed Assistant)

**Priority**: P0 (core differentiator + conversion driver) · **Complexity**: High · **Source**: `Views/AssistantView.swift`, `Services/ArchieBackendService.swift`

**User Story**:
As a roofing rep, I want an AI sidekick that knows roofing claims and my company, so that
I get door scripts, ACV/RCV explanations, photo checklists, and follow-up texts on demand
in the field.

**Description**:
Default mode talks to the production Archie CRM backend (`https://app.archie.now`,
Vercel-proxied to the Render `roofy-backend` service): `POST /api/ai-assistant` with
`action: "chat"`, the last user turn as `question`, prior turns as
`conversation_history`. The server owns the roofing-expert system prompt and enriches it
with the user's company profile from the CRM (Groq-powered server-side). The reply is
non-streaming but delivered through a stream-shaped interface so the UI stays
backend-agnostic. UX: empty state with four quick prompts (door script, ACV vs RCV,
photo checklist, follow-up text) and an "AI guidance only" disclaimer; Markdown rendering
of replies; stop button to cancel; new-conversation button; error surface. Chat history is
in-memory only (cleared on relaunch). 401s trigger one silent re-login before surfacing
"session expired"; 429 shows a rate-limit message.

**Acceptance Criteria**:
```gherkin
Given a signed-in user sends "Write a 20-second door script for a neighborhood that just took hail"
Then the request posts to /api/ai-assistant with action "chat" and Bearer auth
And the reply renders as Markdown in an assistant bubble

Given the user is not signed in (Archie mode)
When they try to send a message
Then the sign-in/create-account sheet opens instead of sending

Given the stored JWT has expired (server returns 401)
Then the app silently re-logs-in once with Keychain credentials and retries
And only if that fails shows "Your Archie session expired…"

Given a reply is in flight
When the user taps the stop button
Then the request is cancelled and an empty assistant bubble is removed
```

**Dependencies**: Archie CRM backend availability; Archie account.

---

### Feature 6: Archie Account — In-App Sign In / Sign Up

**Priority**: P0 (conversion) · **Complexity**: Medium · **Source**: `Views/ArchieAccountView.swift`, `ArchieBackendService.swift`, `Services/KeychainStore.swift`

**User Story**:
As a new user, I want to create or sign in to my Archie account without leaving the app,
so that the AI assistant and CRM features light up immediately.

**Description**:
A segmented Sign In / Create Account form (in Settings and as a sheet on the AI tab).
Sign-up mirrors server validation client-side (name ≥ 2 chars; password ≥ 8 with upper,
lower, digit) — accounts are the same as app.archie.now and new accounts start on the
CRM's free tier. Auth: `POST /api/auth/login` / `api/auth/signup`; the JWT arrives only
in the `Set-Cookie` header (`roof_report_token`) and is extracted directly (fallback:
cookie-jar-backed `GET /api/auth/token`), then stored in the iOS Keychain alongside the
email and password (used solely for silent 7-day-token refresh). All API calls use
`Authorization: Bearer`. Sign Out clears Keychain entries and cookies for both hosts.
Everything outside the AI/CRM features works without an account.

**Acceptance Criteria**:
```gherkin
Given a user enters a weak password during sign-up
Then a specific local validation message appears before any network call

Given a successful sign-in
Then the JWT, email, and password are stored in the Keychain (never UserDefaults)
And Settings shows "Signed in to Archie" with the account email

Given the user taps Sign Out
Then Keychain credentials and backend cookies are removed and the AI tab prompts sign-in again

Given the user never signs in
Then the map, storm data, property sheet, and leads features remain fully functional
```

---

### Feature 7: Attach a CRM Client to the Chat

**Priority**: P0 (the CRM-companion moat) · **Complexity**: High · **Source**: `Views/ClientPickerSheet.swift`, `Services/ArchieCRMService.swift`

**User Story**:
As a rep working a claim, I want to attach one of our CRM clients to the conversation, so
that Archie answers with their actual claim, documents, and communication history in mind.

**Description**:
The person toolbar button opens a debounced (350 ms) search against
`GET /api/crm-dashboard/search` (min 2 chars, limit 20, leads + jobs/customers only).
Picking a hit assembles a compact context object: lead detail (`/api/leads/:id` — contact,
address, status, damage, insurance flags) or job detail
(`/api/crm-jobs/:id?include=projects,invoices,activities` — pipeline stage, carrier,
lifetime value); a linked insurance claim found via `/api/claims?search=` and matched
client-side on `lead_id`/`job_id` (claim number, carrier, adjuster, amounts, deductible);
up to 10 claim documents on file; and up to 8 recent communications. This is forwarded as
`context.current_project`, which the server injects into the system prompt. A banner shows
the attached client ("name · address · claim #") with one-tap detach.

**Acceptance Criteria**:
```gherkin
Given a signed-in user types "smi" in the client picker
Then matching CRM leads and customers appear within ~350 ms of the last keystroke

Given the user picks a customer with a linked claim
Then the attachment context includes the claim profile, documents on file, and recent communications
And a banner confirms "Client attached — Archie can use their CRM data"

Given the user is not signed in
When they tap the attach-client button
Then the sign-in sheet opens first

Given a client is attached
When the user asks "What's the status of their claim?"
Then the request carries context.current_project so the server can answer from CRM data
```

---

### Feature 8: Document & Email Attachments (On-Device Extraction → CRM Filing)

**Priority**: P0 · **Complexity**: High · **Source**: `AssistantView.swift`, `Services/DocumentTextExtractor.swift`, `ArchieCRMService.swift`

**User Story**:
As a rep handed an insurance estimate at the kitchen table, I want to attach it (PDF or
photo) or paste the adjuster's email, so that Archie can analyze it with me **and** it
gets filed to the client's claim in the CRM automatically.

**Description**:
Paperclip menu → file importer (PDF, image, plain text, .eml) or "Paste email". Text
extraction is 100% on-device: PDFKit for PDFs (up to 40 pages; scanned PDFs without a
text layer are rejected with a clear error), Vision OCR (accurate mode + language
correction) for photos, UTF-8/Latin-1 decode for text — capped at 15,000 chars with a
truncation marker. Attachments stage as removable chips; on send they are wrapped in
tagged blocks (`<attached_document>`, `<email_communication>`, plus `<property_context>`
from Ask Archie) ahead of the question; sending with no typed question auto-asks for a
summary of key points and amounts. Chat bubbles collapse the raw blocks into chips
(📎/✉️/🏠). **CRM side-effects**: when a client with a claim is attached, the original
file uploads via the backend's presigned R2 flow (`POST /api/r2/upload` → `PUT` →
`POST /api/claims/:id/documents`) with an inferred document type
(photo / denial_letter / estimate / correspondence) and live status on the chip
("Saving to claim…" → "Saved to claim ✓" / "Claim upload failed — still used in chat").
Pasted emails log to the client's CRM communication history
(`POST /api/communications/log`, inbound, title ≤ 200 / body ≤ 8,000 chars) when a lead
or job is attached.

**Acceptance Criteria**:
```gherkin
Given the user attaches a photographed insurance estimate
Then Vision OCR extracts its text on-device (no bytes leave the phone for extraction)
And the text rides into the next message inside an <attached_document> block

Given a client with a linked claim is attached
When a document is attached
Then the original file uploads to R2 and registers on the claim
And the chip status progresses to "Saved to claim ✓" (or a non-blocking failure note)

Given a client is attached and the user pastes an adjuster email
Then it is logged to that client's CRM communication history and usable in the chat

Given a scanned PDF has no text layer
Then the user sees "No readable text found in that document." and nothing is sent

Given a 60-page estimate
Then extraction stops at 40 pages / 15,000 characters with a visible truncation marker
```

---

### Feature 9: Leads Tab (On-Device Lead Book)

**Priority**: P0 · **Complexity**: Medium · **Source**: `Views/LeadsView.swift`, `Views/LeadDetailView.swift`, `Models/Lead.swift`, `Services/LeadStore.swift`

**User Story**:
As a canvasser, I want every door I've knocked in one searchable list with full detail
editing, so that I can work callbacks and appointments without a separate CRM seat.

**Description**:
Leads persist to a JSON file in Application Support — 100% on-device, no account needed.
Statuses: New / Not Home / Interested / Appointment / Inspected / Signed / Not Interested,
each with its own SF Symbol and pin color. List: search by address or homeowner name,
status filter menu, swipe-to-delete, empty state pointing to the map. Detail view:
status picker, address + storm-evidence snapshot (read-only), homeowner name/phone,
multiline notes — auto-saved on change (`updatedAt` bumps, which feeds the today tally) —
plus quick actions: Call (tel: link when a phone exists), **Ask Archie about this lead**
(address, homeowner, status, storm data, notes as context), Share Lead, and Delete with
confirmation.

**Acceptance Criteria**:
```gherkin
Given saved leads exist
When the user searches "Maple"
Then only leads whose address or homeowner name contains "Maple" remain

Given the user edits a lead's status or notes
Then the change persists immediately and survives app relaunch

Given a lead has a phone number
Then a "Call" row launches the dialer via tel:

Given the user taps "Ask Archie about this lead"
Then the AI tab opens with the lead's full context attached to the next message

Given the user deletes a lead (swipe or detail)
Then it disappears from the list and the map after a confirmation (detail flow)
```

---

### Feature 10: Settings & First-Run Onboarding

**Priority**: P1 · **Complexity**: Low–Medium · **Source**: `Views/SettingsView.swift`, `Views/OnboardingView.swift`, `Services/AppSettings.swift`, `Views/RootView.swift`

**User Story**:
As a user, I want to control how wide and how far back storm searches go, manage my
Archie account, and understand the data sources, so that the evidence matches my market
and I trust what I'm showing homeowners.

**Description**:
**Storm Data**: radius slider 1–25 mi (default 10) and lookback picker — 7/14/30/60/90
days, 6 months, 1 year, 2 years (default 30 days) — both applied app-wide via AppStorage.
**AI Assistant**: Archie account rows (sign in/out) by default; an Advanced disclosure
holds the backend picker (Archie account vs **legacy bring-your-own Anthropic API key**),
an Archie backend URL override (https-only), and — in legacy mode — model
(default `claude-opus-4-8`, direct SSE streaming with an on-device roofing system prompt)
and proxy URL overrides; the API key lives in the Keychain with save/remove controls.
**About**: version/build, active AI backend, NOAA SPC and NWS links, and a combined
data/compliance footer (preliminary data, verify lookups, AI ≠ legal/insurance advice,
TCPA/do-not-knock). **Onboarding**: a three-page first-run cover (Canvass Smarter / Real
Storm Evidence / Archie AI sidekick) ending in "Start Canvassing" with a solicitation-law
reminder; shown once via an AppStorage flag.

**Acceptance Criteria**:
```gherkin
Given the user sets radius 25 mi and lookback 1 year
Then the property sheet header reads "Storm Evidence — 25 mi / 1 year" and queries match

Given a fresh install
Then the onboarding cover appears once and never again after "Start Canvassing"

Given the user switches the AI backend to "Anthropic API key" and saves a key
Then the key is stored in the Keychain and chat streams directly from the Anthropic API

Given an invalid (non-https) backend URL override
Then the app falls back to the default backend URL
```

---

## 4. User Flows

### 4.1 Onboarding → Activation Flow

**Goal**: first door logged in session 1.

1. **Launch** → 3-page onboarding (value, data sources, AI) → "Start Canvassing"
2. **Map** appears (Charlotte default; location permission requested; storm overlay already on)
3. Empty-state capsule: "Tap a rooftop to pull its storm report" (or Quick Log variant)
4. User taps a roof → Property sheet shows real storm evidence → "Save as Lead" **or**
   arms ⚡️ Quick Log → taps roof → picks status → **activated**

**Success Criteria**: first lead saved within the first session; no sign-in required.

### 4.2 Core Loop: Storm → Knock → Log → Follow Up

1. Search a storm market (or locate-me) → overlay confirms hit streets
2. Quick Log doors all day; tally capsule tracks the day
3. Hot doors: Property sheet → owner lookup links → Save as Lead → add name/phone/notes in Lead detail
4. Evening: Leads tab → filter Interested/Appointment → Call / Ask Archie for follow-up text → send

### 4.3 Claim Desk Flow (CRM-Connected)

1. Sign in (Settings or AI-tab prompt) → attach CRM client (search ≥ 2 chars)
2. Attach insurance estimate PDF/photo → OCR on device → chip "Saving to claim…" → "Saved to claim ✓"
3. Paste adjuster email → logged to CRM history
4. Ask Archie to analyze → reply grounded in claim profile + attached docs

### 4.4 Error States & Edge Cases

| Scenario | User Experience | System Behavior |
|----------|----------------|-----------------|
| Offline / SPC fetch fails | Overlay/sheet show no reports; empty state suggests widening range | Per-day fetches fail silently; cached days still render |
| Reverse geocode fails | "Couldn't resolve a street address — storm data still applies." | Lead address falls back to coordinates |
| Not signed in, sends AI message | Sign-in sheet opens | Message not sent until authenticated |
| JWT expired (401) | Invisible on success | One silent re-login with Keychain credentials, then retry |
| Backend 429 | "Archie is rate limited right now…" | No retry storm |
| Scanned PDF, no text layer | "No readable text found in that document." | Attachment rejected |
| Claim upload fails | Chip: "Claim upload failed — still used in chat" | Chat proceeds; CRM filing is best-effort |
| Geocode search no match | "No matches — try adding a city or state." | No camera move |

---

## 5. Non-Functional Requirements

### 5.1 Performance
- Map tap → Property sheet visible: instant (data sections load concurrently with progress states)
- Quick Log save: synchronous insert (< 100 ms perceived); enrichment fully backgrounded
- Storm overlay refresh debounce: 450 ms; overlay marker cap: 80; SPC day files cached memory + disk
- Timeouts as built: SPC 20 s, NWS 15 s, auth 90 s, chat 120 s, CRM 60 s, R2 upload 300 s

### 5.2 Security & Privacy (as built)
- JWT, email, password, and Anthropic key stored **only** in the iOS Keychain (`KeychainStore`)
- All network traffic HTTPS; URL overrides rejected unless https; `ITSAppUsesNonExemptEncryption = false`
- Leads stored on-device only (Application Support JSON); never uploaded
- Document text extraction is fully on-device (PDFKit/Vision); original files upload only when the user attaches them with a claim-linked client
- Public-records links open in an in-app browser; nothing scraped or stored
- `PrivacyInfo.xcprivacy` included; location is when-in-use only, used solely to position the map
- **Known trade-off**: the account password is kept in the Keychain to enable silent re-login (documented in Settings footer) — revisit if the backend adds refresh tokens

### 5.3 Accessibility
- Custom map controls, toggles, and attachment chips carry accessibility labels (verified in source)
- Dynamic-type-friendly SwiftUI text styles throughout; selectable text for addresses/replies
- Gap: storm marker color-coding lacks a non-color legend — candidate improvement

### 5.4 Compliance (product-level)
- "Preliminary, unverified" NOAA attribution on every storm surface
- TCPA / do-not-knock / solicitation-permit reminders in onboarding, property sheet, README, and Settings
- AI disclaimer ("guidance only — not legal or insurance advice") in chat empty state and Settings; system prompts forbid inventing storm data or suggesting claim misrepresentation

### 5.5 Platform Requirements
- iOS 17.0+ (iOS 17-era APIs: `MapReader`, `ContentUnavailableView`, `onChange` two-param); built with Xcode 26.5; XcodeGen spec (`project.yml`) as project fallback
- iPhone-first, portrait-first; bundle `com.archieclaims.app`; App Store distribution (checklist in `docs/APP_STORE.md`)
- Unit tests ship for SPC parsing, convective-day math, and the lead store (`ArchieClaimsTests/`)

---

## 6. Non-Goals (Explicitly Out of Scope for the Current Release)

1. **Two-way lead sync with the CRM** — canvass leads are on-device only; CRM data flows *into* chat, and only documents/emails flow back. (Top candidate to change — see Section 10.)
2. **Team features** — no rosters, territories, leaderboards, or manager dashboards.
3. **Hail swath polygons / forensic weather verification** — point reports from SPC only; no paid radar-derived swaths, no per-address damage probability.
4. **Route planning / turf assignment** — the map is evidence-first, not dispatch.
5. **In-app photo capture & inspection reports** — the CRM's roof-report pipeline owns report generation; the app attaches documents, it doesn't author them.
6. **Estimating / measurements / e-signing** — out of scope; CRM territory.
7. **Background location tracking or knock-path recording** — when-in-use only, by design (privacy + App Store posture).
8. **Android / web** — iOS only.
9. **In-app purchases or paywalls** — the app is free; monetization lives in CRM tiers.
10. **Chat history persistence** — conversations are intentionally ephemeral in v1.
11. **Scraping or storing homeowner contact data** — lookups remain user-driven links to public sites (legal and App Store review posture).

**Rationale**: keep the field app free, fast, and review-safe; let the CRM carry the heavy
workflow and the revenue.

---

## 7. Technical Considerations

### 7.1 Third-Party Services / APIs

| Service | Purpose | Notes |
|---------|---------|-------|
| NOAA SPC daily CSVs | Storm reports (hail/wind/tornado) | Free, no key; cached per convective day; User-Agent self-identifies |
| NWS API (`api.weather.gov`) | Active alerts at a point | Free; User-Agent self-identifies |
| Apple CLGeocoder / MapKit | Forward & reverse geocoding, map | No key; OS rate limits apply |
| Archie CRM backend (`app.archie.now` → Render `roofy-backend`) | Auth, AI chat, CRM search/context, claims, comms log, R2 presign | Same accounts as the web app; Groq-powered AI server-side |
| Cloudflare R2 (via backend presign) | Claim document storage | Content-Length signed into PUT |
| Anthropic Messages API (legacy mode) | BYO-key direct chat, `claude-opus-4-8`, SSE | Advanced settings only |
| NETR / TruePeopleSearch / FastPeopleSearch / Google | Owner & contact lookups | Link-outs in in-app browser only |

### 7.2 Data Models (as built)
- **Lead** (on-device): id, createdAt/updatedAt, status (7 values), address, lat/lon, homeownerName, phone, notes, stormSummary snapshot
- **StormReport**: kind, convective date (UTC), time, raw magnitude (hail 1/100", wind mph, tornado EF), location/county/state, lat/lon, comments; `NearbyStormReport` pairs it with distance
- **NWSAlert**: event, headline (decoded from GeoJSON)
- **ChatMessage**: role + text (attachment payloads embedded as tagged text blocks)
- **ClientAttachment** (transient): CRM hit + compact context dict + claimID/leadID/jobID + summary line

### 7.3 Key Backend Endpoints Consumed
`POST /api/auth/login` · `POST /api/auth/signup` · `GET /api/auth/token` ·
`POST /api/ai-assistant` (action: chat) · `GET /api/crm-dashboard/search` ·
`GET /api/leads/:id` · `GET /api/crm-jobs/:id` · `GET /api/claims?search=` ·
`GET/POST /api/claims/:id/documents` · `GET/POST /api/communications/log` ·
`POST /api/r2/upload`

### 7.4 Pre-Release Engineering Notes
- `AppSettings.contactEmailForAPIs` is still `support@example.com` — **must** be a real address before App Store release (NOAA/NWS User-Agent guidance; README step 3)
- No analytics/telemetry SDK exists in the app — Section 11 metrics are currently unmeasurable client-side except via backend logs (sign-ins, chat calls) and App Store Connect
- Claims-to-client matching is heuristic (name search + client-side FK match) — a backend `lead_id`/`job_id` filter on `/api/claims` would make it exact

---

## 8. Competitive Context

| Competitor | Position | Key Strength | Key Weakness (our opening) |
|------------|----------|--------------|----------------------------|
| SalesRabbit | D2D market leader | Mature territory/team management, gamification | Per-seat pricing; weather data is a paid add-on; no claims AI |
| Spotio | Field-sales challenger | Pipeline + activity tracking | Generic field sales — no storm evidence, no roofing claim domain |
| HailTrace / Interactive Hail Maps | Weather-data niche | Radar-derived hail swaths, forensics | Expensive subscriptions; maps only — no door logging, CRM, or AI |
| Hail Recon | Roofing-niche canvassing | Hail maps + canvassing combo | Subscription-gated data; not tied to the contractor's CRM/claims |

**Our positioning**: the only free canvassing app where official storm evidence, two-tap
door logging, owner lookup, and a claims-trained AI assistant are wired into the
contractor's own CRM. **Key differentiators**: (1) zero-cost official NOAA evidence at
per-address granularity, (2) "Ask Archie" with live CRM claim context and document filing
from the field, (3) free distribution as an Archie CRM acquisition channel rather than a
per-seat SKU. **Known gap vs. weather competitors**: SPC point reports are coarser than
radar-derived swaths — honest framing ("preliminary, unverified") is the v1 mitigation.

---

## 9. Market Context

- **Market**: ~$25–30B annual US storm-restoration roofing activity; tens of thousands of
  residential roofing contractors; D2D canvassing remains the dominant lead channel after
  major hail events. (Directional; no formal market-research doc exists for this product —
  see Section 10.)
- **Tailwinds**: rising severe-convective-storm losses; contractors consolidating tooling;
  AI assistants becoming expected in field sales.
- **Headwinds**: App Store sensitivity around people-search/lead-gen apps; TCPA and local
  solicitation regulation; incumbent canvassing apps with entrenched team workflows;
  seasonality (DAU follows storms).
- **Revenue model**: the app is **free**; it exists to (a) acquire roofing companies into
  Archie CRM (free tier sign-up in-app → upgrade path to solo/team/enterprise) and
  (b) retain existing CRM customers by making Archie the daily field tool. Success is
  measured in CRM account creation and CRM-feature engagement, not app revenue.

---

## 10. Open Questions & Decisions Needed

**Critical (shape the next release)**:
1. **Should canvass leads sync to the Archie CRM?**
   - Context: today leads are device-only; a signed/appointment door dying on a rep's phone undercuts the CRM story and Dana/Marcus personas. A `POST /api/leads` push (opt-in per lead, or auto for Appointment/Signed) is the single highest-leverage roadmap item.
   - Options: A) one-way push on status milestones; B) full two-way sync; C) stay local.
   - Owner: product owner. Needed before team-tier marketing of the app.
2. **Monetization gating**: does the free app remain fully free, or do CRM tiers gate features (e.g., lookback > 90 days, client attachments, team features)?
   - Current assumption: fully free; AI usage cost is absorbed server-side (Groq) under CRM tier limits.
3. **Analytics instrumentation**: which client-side events do we log (door logged, sheet opened, sign-in, client attached, doc filed), and with what (privacy-friendly self-hosted vs none)?
   - Context: every metric in Section 11 except backend counts is currently unmeasurable.
4. **Default map region**: keep the Charlotte default (source comments call it "for testing") or center on user location / last region at launch?

**Important (don't block, do schedule)**:
5. **App Store review risk** of TruePeopleSearch/FastPeopleSearch link-outs — keep, soften (assessor-only), or make remote-configurable to allow fast removal if review objects?
6. **Replace `support@example.com`** with a real support address (release blocker per README; trivial fix, must not be forgotten).
7. **Chat persistence**: keep ephemeral, or persist conversations (and tie to CRM clients)?
8. **Storm data depth**: is SPC point data enough, or do we license/derive hail swaths for a paid tier? (Direct competitive response to HailTrace.)
9. **Password-in-Keychain refresh pattern**: acceptable long-term, or should the backend issue refresh tokens so the app can stop storing passwords?
10. **2-year lookback performance**: up to 730 sequential daily fetches on first use — add a server-side aggregation or bundled historical index?
11. **Streaming chat**: backend returns a single blob; do we add SSE streaming to `/api/ai-assistant` for perceived speed parity with the legacy Anthropic mode?

---

## 11. Success Criteria & Metrics

### 11.1 North-Star Framing
**North star**: storm-verified doors logged per week across all users — it compounds
canvasser value (Tyler), team value (Dana), and CRM pull-through (Marcus).

### 11.2 Metric Definitions & Targets

**Activation**
- **First door logged** (first Quick Log or Save as Lead) — *the* activation event.
  Target: > 50% of new installs in session 1; > 65% within 7 days.
- Onboarding completion ("Start Canvassing"): > 85%.
- Location permission grant rate: > 70%.

**Engagement**
- **Doors logged / active canvasser / field day**: target ≥ 40 (healthy D2D pace);
  monitor distribution, not just mean.
- **DAU during storm events**: ≥ 3x trailing-30-day baseline within 72 hours of a major
  SPC event in a metro with installed users; measure decay half-life after events.
- Property sheets opened per session; storm overlay toggle retention (stays on > 80%).
- Week-4 retention of activated users: > 30% (expect storm-driven seasonality).

**Conversion (to the Archie ecosystem)**
- **Sign-ins / account creations from the app**: > 35% of installs signed in by day 7;
  track new-account share (CRM acquisition) vs existing-account sign-ins (retention).
- **CRM linkage depth**: > 25% of signed-in users attach a client, document, or pasted
  email within 14 days; documents filed to claims per active CRM company per month.
- "Ask Archie" handoffs from property sheet / lead detail per WAU.
- Downstream (backend-measured): app-originated free accounts upgrading to paid CRM tiers.

**Quality**
- Crash-free sessions > 99.5%; App Store rating > 4.5
- Chat error rate (4xx/5xx surfaced to user) < 2% of sends; silent re-login success > 95%
- SPC fetch cache-hit rate during a canvassing day > 90%

### 11.3 Measurement Plan (gap)
The app currently ships **no analytics**. Until Open Question #3 is resolved: backend
logs cover sign-ins, chat volume, client searches, and document registrations; App Store
Connect covers installs/retention proxies. Client events (doors logged, sheet opens,
overlay usage) require instrumentation before targets above can be tracked.

---

## 12. Near-Term Direction (Phased)

**Phase 1 — Ship & Measure (now → +4 weeks)**
- Release blockers: real NOAA/NWS contact email; App Store assets per `docs/APP_STORE.md`; host privacy policy
- Minimal privacy-friendly event instrumentation (activation + engagement events)
- TestFlight with 2–3 friendly roofing companies (ideally existing CRM customers) during storm season

**Phase 2 — Close the CRM Loop (+1–2 months)** *(pending Open Question #1)*
- One-way lead push: "Send to Archie CRM" on lead detail + auto-prompt on Appointment/Signed
- Pull company branding/profile into the app shell once signed in
- Persist chat threads, optionally linked to attached clients

**Phase 3 — Team & Storm Depth (+3–6 months)**
- Team visibility for Dana: shared door maps, daily tallies, simple leaderboard (CRM team tier)
- Storm push notifications: alert users when a new SPC event lands inside saved territories (the DAU-spike engine)
- Evaluate hail-swath data (license vs derive) as a paid-tier differentiator
- Route-friendly niceties: cluster dense overlays, per-street knock summaries

Phases 2–3 are direction, not commitments; each gates on Phase 1 measurement.

---

## 13. Stakeholders

| Role | Owner | Responsibility |
|------|-------|---------------|
| Product Owner / Developer | James Turner | Priorities, releases, backend coordination |
| Backend (Archie CRM) | Same (roofy-backend) | AI endpoint, auth, claims/comms APIs, R2 |
| Design / QA | Unassigned | UI polish, field testing with pilot crews |

---

## 14. References

- Source of truth: `/Users/jamesturner/Archie-Claims/ArchieClaims/` (Views, Services, Models), verified 2026-06-09
- `README.md` — feature overview, build & ship instructions
- `docs/APP_STORE.md` — submission checklist · `docs/PRIVACY_POLICY.md` · `docs/TESTING.md`
- Tests: `ArchieClaimsTests/` (SPC parser, storm date math, lead store)
- Data: NOAA SPC climo reports · NWS API documentation
- Backend: app.archie.now (Vercel → Render `roofy-backend`)

---

## Appendix A: Glossary

- **SPC convective day**: NOAA Storm Prediction Center's 12Z–12Z reporting day; daily CSVs are keyed by its start date
- **ACV / RCV**: Actual Cash Value / Replacement Cost Value — insurance payout methods reps must explain at the door
- **Quick Log**: the app's two-tap door-logging mode (⚡️)
- **Storm snapshot**: the plain-text summary of nearby SPC evidence frozen onto a lead at save time
- **Client attachment**: a CRM lead/customer whose claim profile, documents, and communications are injected into the AI chat context
- **TCPA**: Telephone Consumer Protection Act — governs calls/texts to looked-up contacts

---

**Document History**
| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0.0 | 2026-06-09 | Product Manager (Claude) | Initial PRD documenting the app as built from source, plus near-term direction |
