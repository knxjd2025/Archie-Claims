# Technical Architecture: Archie Claims (As Built)

**Version**: 1.0.0
**Last Updated**: 2026-06-09
**Status**: As-built specification (documents the shipped code, not a proposal)
**Owner**: Technical Architect
**Platform**: iOS 17.0+ (iPhone only, portrait only)
**Xcode**: 26.5 · Swift 5 mode (`SWIFT_VERSION: 5.0`) · Bundle `com.archieclaims.app`

Archie Claims is the SwiftUI field companion to the Archie CRM web platform
(app.archie.now). It gives roofing canvassers a storm-overlay map, one-tap
door logging, free property/storm intelligence, and an AI claim assistant
backed by the same accounts and backend as the web CRM.

---

## 1. Architecture Overview

### 1.1 Architecture Pattern

**Pattern as built**: SwiftUI view-centric MV (no ViewModel layer) +
`ObservableObject` stores + stateless service types.

- **Views own their state.** Each screen is a single SwiftUI `View` struct
  holding feature state in `@State`/`@FocusState` and calling services
  directly from `Task {}` blocks. There are no ViewModel classes anywhere in
  the codebase.
- **Three shared stores** are created once in `ArchieClaimsApp` as
  `@StateObject` and injected via `.environmentObject(...)`:
  - `AppState` (`@MainActor ObservableObject`) — tab selection + the
    "Ask Archie" property-context handoff between tabs.
  - `LeadStore` (`@MainActor ObservableObject`) — the on-device lead list,
    persisted to JSON.
  - `LocationManager` (`ObservableObject`, `CLLocationManagerDelegate`) —
    when-in-use location permission + latest fix.
- **Services are mostly value types or caseless enums** (namespaces of
  static functions): `GeocodingService`, `SPCReportParser`,
  `PublicRecordsLinks`, `KeychainStore`, `AppSettings`,
  `DocumentTextExtractor` are `enum`s; `ArchieBackendService` and
  `ClaudeService` are plain `struct`s constructed at call sites; the single
  stateful service is `actor StormDataService` (a `.shared` singleton owning
  the SPC report caches).
- **Preferences flow through `@AppStorage`** (UserDefaults) keyed by
  constants in `AppSettings`; secrets flow through `KeychainStore`.
- **Data flow**: unidirectional in practice — user action → view spawns a
  `Task` → service `async` call → result mutates `@State`/`@Published` on the
  main actor → SwiftUI re-renders.

**Why this works here**: the app has four screens, no offline sync engine,
and every screen's logic is a thin orchestration of one or two service
calls. The cost is that the two largest views (`AssistantView` 602 lines,
`CanvassMapView` 528 lines) mix UI, orchestration, and business rules — see
the tech-debt register (§8) for the recommended extraction path.

### 1.2 High-Level Component Diagram

```
┌────────────────────────────────────────────────────────────────────┐
│ ArchieClaimsApp (@main)                                            │
│   @StateObject AppState · LeadStore · LocationManager → RootView   │
└──────────────────────────────┬─────────────────────────────────────┘
                               │ TabView (+ fullScreenCover OnboardingView)
   ┌──────────────┬────────────┼──────────────┬──────────────┐
   │ CanvassMap   │ Assistant  │ Leads        │ Settings     │
   │ View         │ View       │ View         │ View         │
   │  ├ Property  │  ├ Archie  │  └ LeadDetail│  └ Archie    │
   │  │ SheetView │  │ Account │    View      │    Account   │
   │  └ SafariView│  │ Sheet   │              │    Form      │
   │              │  ├ Client  │              │              │
   │              │  │ Picker  │              │              │
   │              │  └ EmailPasteSheet        │              │
   └──────┬───────┴─────┬──────┴──────┬───────┴──────┬───────┘
          │             │             │              │
┌─────────▼─────────────▼─────────────▼──────────────▼───────────────┐
│ Services                                                            │
│  actor StormDataService (.shared)   ArchieBackendService (struct)  │
│    ├ SPC CSV fetch + 2-level cache    ├ auth / chat                │
│    └ NWS alerts                       └ +CRM extension (search,    │
│  enum GeocodingService (CLGeocoder)     context, R2 upload, comms) │
│  enum SPCReportParser                ClaudeService (struct, legacy) │
│  enum PublicRecordsLinks             enum DocumentTextExtractor     │
│  enum KeychainStore                  enum AppSettings               │
└─────────┬───────────────────────────────────────┬──────────────────┘
          │                                       │
┌─────────▼───────────────┐         ┌─────────────▼──────────────────┐
│ Local persistence       │         │ Network                        │
│  leads.json (App Supp.) │         │  spc.noaa.gov CSVs             │
│  Caches/spc-reports/    │         │  api.weather.gov               │
│  UserDefaults(@AppStor.)│         │  app.archie.now /api/* (CRM)   │
│  Keychain (JWT, creds,  │         │  R2 presigned PUT (storage)    │
│   Anthropic key)        │         │  api.anthropic.com (legacy)    │
└─────────────────────────┘         └────────────────────────────────┘
```

### 1.3 Key Architectural Decisions (as observed in code)

| Decision | Choice | Alternative | Rationale in this codebase |
|----------|--------|-------------|----------------------------|
| UI framework | SwiftUI + MapKit SwiftUI API (`Map`, `MapReader`, `Annotation`) | UIKit/MKMapView | iOS 17 target; tap-to-coordinate via `MapReader.proxy.convert` |
| State mgmt | `ObservableObject` + `@Published` + `@State` | `@Observable` (iOS 17 Observation) | Stores predate/ignore Observation; `@EnvironmentObject` used throughout |
| Persistence | Hand-rolled JSON file (`LeadStore`) | SwiftData/Core Data | Single flat entity (`Lead`), trivially Codable; zero schema overhead |
| Networking | Raw `URLSession.shared` per service | Shared API client layer | Each service is small; no common client abstraction exists |
| Backend payloads | `JSONSerialization` + `[String: Any]` casts | `Codable` DTOs | Tolerant of the CRM's loosely-typed JSON; cost: stringly-typed access (§8) |
| AI default | Archie CRM backend (`POST /api/ai-assistant`, Groq server-side) | Direct Anthropic | One account system, server-owned prompt + company profile; BYO-key kept as legacy fallback |
| Auth bridge | Cookie `Set-Cookie` JWT → Keychain → `Authorization: Bearer` | Native cookie jar only | Backend middleware accepts both; Bearer makes requests explicit and survives cookie clearing |
| Storm data | Free NOAA SPC CSVs + NWS API, no key | Paid weather APIs | $0 data cost; per-day CSV granularity maps cleanly to a disk cache |
| Concurrency | async/await, one `actor`, `Task` + cancellation debounce | Combine | Modern structured concurrency throughout; no Combine imports |
| Dependencies | **Zero third-party packages** | SPM libraries | Apple frameworks cover every need (MapKit, PDFKit, Vision, Security, SafariServices, Contacts) |
| Project gen | Checked-in `.xcodeproj` + `project.yml` XcodeGen fallback | Tuist etc. | Regenerable with `xcodegen generate` if the project file corrupts |

---

## 2. Technology Stack

**Apple frameworks used** (no third-party dependencies at all):

- **SwiftUI** — all UI; `NavigationStack`, `TabView`, `.sheet`,
  `.confirmationDialog`, `.fileImporter`, `ShareLink`,
  `ContentUnavailableView`, `@AppStorage`, `@FocusState`.
- **MapKit (SwiftUI)** — `Map`, `MapReader`, `MapCameraPosition`,
  `Annotation`, `UserAnnotation`, `.onMapCameraChange`, hybrid/standard
  styles.
- **CoreLocation** — `CLLocationManager` (when-in-use), `CLGeocoder`
  forward/reverse geocoding, `CLLocation` distance math.
- **Contacts** — `CNPostalAddressFormatter` for one-line addresses.
- **PDFKit** — text-layer extraction from PDFs (≤40 pages).
- **Vision** — `VNRecognizeTextRequest` (`.accurate`) OCR for photos/scans.
- **UniformTypeIdentifiers** — attachment type routing (`.pdf`, `.image`,
  `.text`, `.emailMessage`).
- **Security** — Keychain (`SecItemAdd/Update/CopyMatching/Delete`,
  `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`).
- **SafariServices** — `SFSafariViewController` for public-records links.
- **Foundation** — `URLSession` (data, bytes/SSE, upload), `JSONEncoder/
  Decoder`, `JSONSerialization`, `HTTPCookie(Storage)`, `FileManager`.

**Build/distribution**: XcodeGen spec (`project.yml`), deployment target
iOS 17.0, `TARGETED_DEVICE_FAMILY: 1` (iPhone), portrait-only, automatic
signing, `ITSAppUsesNonExemptEncryption: false`, `PrivacyInfo.xcprivacy`
present, App Store distribution target.

---

## 3. Module Map

```
ArchieClaims/
├── ArchieClaimsApp.swift          # @main; creates the 3 stores; AppState class
├── Info.plist                     # location usage string, tel scheme, encryption-exempt
├── PrivacyInfo.xcprivacy          # privacy manifest
├── Models/
├── Views/
├── Services/
└── Support/
ArchieClaimsTests/                 # unit tests (3 files)
project.yml                        # XcodeGen fallback spec
```

### App / Root

| File | Responsibility |
|------|----------------|
| `ArchieClaimsApp.swift` | `@main` entry; instantiates `AppState`, `LeadStore`, `LocationManager` as `@StateObject` and injects them; defines `AppState` (tab enum `map/assistant/leads/settings`, `pendingPropertyContext`, `askArchie(about:)` cross-tab handoff). |

### Models (`ArchieClaims/Models/`)

| File | Responsibility |
|------|----------------|
| `Lead.swift` | `Lead` struct (Identifiable/Codable/Hashable): 7-state `Status` enum (New, Not Home, Interested, Appointment, Inspected, Signed, Not Interested) with SF Symbol per status; address, lat/lon, homeowner name/phone, notes, `stormSummary` snapshot; `shortAddress` helper. |
| `StormReport.swift` | One SPC report: `Kind` (hail/wind/tornado), convective-day UTC date, raw magnitude column with typed accessors (`hailSizeInches` = hundredths/100, `windSpeedMPH`, EF-scale `magnitudeText`), `distanceMiles(from:)` haversine via `CLLocation`. Plus `NearbyStormReport` (report + distance) used by map/sheet. |
| `NWSAlert.swift` | `NWSAlert` value type + `NWSAlertResponse` minimal `Decodable` of NWS `/alerts/active?point=` GeoJSON → `[NWSAlert]`. |
| `ChatMessage.swift` | One chat turn: `Role` (user/assistant), mutable `text` (for streaming appends), `createdAt`. |

### Services (`ArchieClaims/Services/`)

| File | Responsibility |
|------|----------------|
| `StormDataService.swift` | `actor`, `.shared` singleton. Fetches SPC daily filtered CSVs (`https://www.spc.noaa.gov/climo/reports/{yymmdd}_rpts_filtered.csv`) in a parallel `withTaskGroup` across the lookback window; two-level cache (in-memory dict + `Caches/spc-reports/{yymmdd}.json`, today's file never frozen to disk); radius filter + sort; NWS active alerts (`api.weather.gov`); static `summary(of:lookbackDays:)` one-paragraph evidence string; convective-day date helpers (`recentConvectiveDays`, `yymmdd`, clamped to 730 days). Sends an identifying `User-Agent`. |
| `SPCReportParser.swift` | Caseless enum. Parses the three concatenated CSV sections (tornado `F_Scale` / wind `Speed` / hail `Size`) by header sniffing; quoted-comma-aware `splitCSVRow`; drops malformed rows and out-of-range lat/lon. |
| `GeocodingService.swift` | Caseless enum over `CLGeocoder`. `geocode(_:)` forward search returning `Place` (title/subtitle/coordinate/`spanDegrees` sized from `CLCircularRegion` radius, address-vs-city flag); `reverseGeocode(_:)` returning formatted address + city/state/zip/county via `CNPostalAddressFormatter`. |
| `ArchieBackendService.swift` | Struct client for the Archie CRM backend (default base `https://app.archie.now`, overridable). Auth: `POST api/auth/login` / `api/auth/signup` → extracts JWT from the `roof_report_token` **Set-Cookie** header (fallback `GET api/auth/token` via cookie jar) → saves token+email+**password** to Keychain. Chat: `POST api/ai-assistant` `{action:"chat", question, conversation_history, context.current_project}`; non-streaming reply wrapped in an `AsyncThrowingStream` facade; one silent re-login on 401. `signOut()` wipes Keychain entries and cookies for app.archie.now + roofy-backend.onrender.com. Typed `BackendError` with user-facing messages. |
| `ArchieCRMService.swift` | **Extension on `ArchieBackendService`** (same file family, CRM concerns): generic `authorizedJSON` (Bearer + one 401 re-login retry); `searchClients` (`GET api/crm-dashboard/search?q=&limit=20`, keeps `lead`/`job` rows); `clientAttachment(for:)` aggregates `GET api/leads/{id}` or `GET api/crm-jobs/{id}?include=projects,invoices,activities`, claim match via `GET api/claims?search={name}` + client-side FK matching, `GET api/claims/{id}/documents`, `GET api/communications/log` → compact `[String: Any]` context for the AI; `uploadFile` (R2 presigned: `POST api/r2/upload` → `PUT` bytes to `uploadUrl` → returns `publicUrl`); `registerClaimDocument` (`POST api/claims/{id}/documents`); `logCommunication` (`POST api/communications/log`). |
| `ClaudeService.swift` | Legacy BYO-key struct. Streams `POST {base}/v1/messages` SSE (`x-api-key`, `anthropic-version: 2023-06-01`); default model `claude-opus-4-8`; roofing-claims system prompt with `cache_control: ephemeral` breakpoint; adaptive thinking; `max_tokens` 16000; parses `content_block_delta`/`error`/`message_stop`. Only used when Settings → Advanced switches the backend to "Anthropic API key". |
| `DocumentTextExtractor.swift` | Caseless enum. Security-scoped file load → routes by `UTType`: PDFKit text layer (≤40 pages), Vision OCR for images (checked continuation on a global queue), UTF-8/Latin-1 decode for text/email; 15,000-char cap with truncation marker; returns `Extraction` (filename, mime, raw `Data` for CRM upload, text for chat). All extraction on-device. |
| `LeadStore.swift` | `@MainActor ObservableObject`. `@Published private(set) leads`; CRUD + `delete(at:in:)` for filtered lists; `lead(near:longitude:toleranceDegrees:)` coordinate dedupe (default 0.0002° ≈ 22 m); loads/saves the whole array to `Application Support/leads.json` (atomic write) on every mutation. |
| `KeychainStore.swift` | Caseless enum wrapper over Keychain generic passwords under service `com.archieclaims.apikeys`; accounts: `anthropic-api-key`, `archie-backend-token`, `archie-backend-email`, `archie-backend-password`; `AfterFirstUnlockThisDeviceOnly` accessibility. |
| `AppSettings.swift` | Caseless enum of UserDefaults keys + defaults: radius (default 10 mi), lookback (default 30 d, max 730, presets 7→730), `AssistantMode` (archie default / anthropic legacy), base-URL/model override resolution (https-only), `lookbackLabel`, `contactEmailForAPIs` (NWS User-Agent contact — **still the `support@example.com` placeholder**). |
| `LocationManager.swift` | `ObservableObject` + `CLLocationManagerDelegate`; publishes `authorization` and `lastLocation`; auto-starts updates once authorized; failures are silently non-fatal (map keeps its default region). |
| `PublicRecordsLinks.swift` | Caseless enum that builds free public-lookup URLs for an address (NETR county-records directory, assessor Google search, TruePeopleSearch, FastPeopleSearch, quoted web search) + TCPA/do-not-knock `complianceNote`. No scraping; links open in-app. |

### Views (`ArchieClaims/Views/`)

| File | Responsibility |
|------|----------------|
| `RootView.swift` | `TabView` bound to `AppState.selectedTab` (Canvass / Archie AI / Leads / Settings); full-screen `OnboardingView` until `settings.onboardingDone`. |
| `OnboardingView.swift` | 3-page paged walkthrough (map, data sources, AI sign-in pitch) + door-knocking compliance reminder; flips the `@AppStorage` flag. |
| `CanvassMapView.swift` | The core screen. Hybrid/standard `Map` defaulting to Charlotte NC (35.2271, −80.8431, span 0.12°); SPC storm markers for the visible region (debounced refresh, ≤80 markers); status-colored lead pins with filter chips; Quick Log mode (tap → status `confirmationDialog` → lead saved instantly, address + storm summary backfilled by a detached `Task`); address/city search overlay via `GeocodingService` with result list and animated camera moves; custom zoom/locate controls; today's door tally bottom bar; taps route to `PropertySheetView` (normal mode) or Quick Log dialog. |
| `PropertySheetView.swift` | Tapped-property sheet (medium/large detents): parallel `async let` reverse-geocode + storm load (SPC reports within radius/lookback + NWS active alerts); storm evidence rows (`StormReportRow`); free public-records links in `SafariView`; save/update lead with storm snapshot; "Ask Archie" handoff (`appState.askArchie`); `ShareLink` storm-report text. |
| `AssistantView.swift` | Archie AI chat. Mode switch (Archie backend default / legacy Anthropic); empty-state with sign-in CTA + quick prompts; client banner & property-context banner; attachment pipeline (file importer → `DocumentTextExtractor`; email paste sheet); outgoing turns assemble `<attached_document>`, `<email_communication>`, `<property_context>` blocks + question; streaming render with cancel; fire-and-forget CRM side-effects (doc → R2 + claim register when a claim is attached; email → communications log); `MessageBubble` renders assistant Markdown and collapses context blocks into chips. |
| `ClientPickerSheet.swift` | Debounced (350 ms) CRM client search (`searchClients`); attach builds the full `ClientAttachment` context. Also hosts `EmailPasteSheet` (subject + pasted body). |
| `ArchieAccountView.swift` | `ArchieAccountForm` (sign in / create account, client-side mirror of server password rules, calls `signIn`/`signUp`) + `ArchieAccountSheet` modal wrapper; link to app.archie.now. |
| `LeadsView.swift` | Lead list with status filter menu + text search (address/homeowner); swipe-to-delete against the filtered array; navigates by lead `UUID` to detail. |
| `LeadDetailView.swift` | Edit a lead (status picker, homeowner, phone, notes); auto-saves on change via `leadStore.update`; `tel://` call link, "Ask Archie about this lead" handoff, `ShareLink`, delete with confirmation. |
| `SettingsView.swift` | Archie account section (or legacy API-key entry, with Advanced disclosure for backend switch + base-URL/model overrides); storm radius slider (1–25 mi) + lookback picker (presets, preserves custom values); About (version, AI backend, NOAA/NWS links, data/compliance disclaimers). |

### Support

| File | Responsibility |
|------|----------------|
| `Support/SafariView.swift` | `UIViewControllerRepresentable` wrapping `SFSafariViewController` with the accent tint. |

### Tests (`ArchieClaimsTests/`)

| File | Coverage |
|------|----------|
| `LeadStoreTests.swift` | CRUD round-trip, coordinate-proximity lookup, `shortAddress` (uses a unique temp filename per test — note: writes into real Application Support, files are not cleaned up). |
| `SPCReportParserTests.swift` | Three-section parse, hail-size/wind conversions, quoted commas, malformed-row skipping, distance filtering, CSV splitter. |
| `StormDataServiceTests.swift` | `yymmdd` formatting, convective-day enumeration/ordering, lookback clamping (1…730), summary text for empty/non-empty inputs. |

Not covered by tests: all networking (`ArchieBackendService`/CRM extension,
`ClaudeService`, NWS/SPC fetch paths), Keychain, geocoding, document
extraction, and all views.

---

## 4. Data Flow (As Built)

### 4.1 Canvass tap → property sheet

```
User taps map (MapReader.proxy.convert(screenPoint) → CLLocationCoordinate2D)
  │
  ├─ Quick Log ON  → confirmationDialog (status buttons)
  │     └─ quickLog(status, coord)
  │          ├─ existing lead within 0.0002°? → update status, done
  │          └─ else: Lead("Locating address…") → leadStore.add (instant pin)
  │               └─ Task (background backfill):
  │                    GeocodingService.reverseGeocode(coord) → address
  │                    StormDataService.shared.reports(near:radius:lookback)
  │                    → StormDataService.summary(...) → leadStore.update
  │
  └─ Quick Log OFF → sheet(PropertySheetView(coordinate))
        └─ .task { async let geocode ∥ async let storms }
             ├─ GeocodingService.reverseGeocode → address/city/state/zip/county
             ├─ StormDataService.reports(near:…)        ← SPC (cache→disk→network,
             │     parallel per-day withTaskGroup)          radius+lookback filter
             ├─ StormDataService.activeAlerts(at:)      ← NWS point alerts
             ├─ PublicRecordsLinks.links(…)             → SafariView (in-app)
             ├─ Save as Lead → leadStore.add/update (storm snapshot string)
             └─ Ask Archie → appState.askArchie(propertyContext)
                              → selectedTab = .assistant
                              → AssistantView banner → next send embeds
                                <property_context> block, then clears it
```

**Storm overlay refresh** (map): `.onMapCameraChange(.onEnd)` →
`scheduleStormOverlayRefresh` cancels the previous `Task`, sleeps 450 ms
(debounce), derives radius from the visible span
(`min(max(latDelta·69·0.75, 2), 60)` miles), fetches via the actor, and
shows at most 80 markers.

### 4.2 Chat → ArchieBackendService → `POST /api/ai-assistant`

```
send() in AssistantView
  ├─ mode == .archie: require signedInEmail (else present auth sheet)
  ├─ build outgoing text: [<attached_document>…][<email_communication>…]
  │                       [<property_context>…] + question (blocks first)
  ├─ append user ChatMessage + empty assistant ChatMessage; isStreaming = true
  └─ archieService.streamReply(history, clientContext: attachedClient?.context)
       └─ AsyncThrowingStream facade over ONE await chat(...) call
            POST {base}/api/ai-assistant
              Authorization: Bearer <jwt from Keychain>
              body: { action:"chat",
                      question: last user turn,
                      conversation_history: prior turns [{role,content}],
                      context: { current_project: <ClientAttachment.context> } }
            ← server builds the roofing system prompt + company profile (Groq)
            ← 401 once → refreshSession() (silent re-login w/ stored creds) → retry
            ← 200 {response} → yielded as a single delta → bubble fills in
  (legacy .anthropic mode: ClaudeService streams SSE deltas token-by-token)
Side effects (fire-and-forget Tasks, independent of the chat call):
  • document attachment + attached claim → uploadFile (R2) → registerClaimDocument
  • pasted email + attached lead/job     → logCommunication (inbound email)
```

**Client attachment** (`ClientPickerSheet` → `clientAttachment(for:)`):
search hit → lead or job detail fetch → claims found by *name search* +
client-side `lead_id`/`job_id` match → claim documents list → recent
communications → all compacted into the `[String: Any]` context dict the
server injects verbatim into its system prompt.

### 4.3 Auth flow (cookie JWT → Keychain → Bearer)

```
ArchieAccountForm.submit
  └─ POST api/auth/login | api/auth/signup  (JSON email/password[/name])
       ← 200/201; JWT arrives ONLY as Set-Cookie: roof_report_token (httpOnly)
       ├─ parse Set-Cookie headers (HTTPCookie.cookies(withResponseHeaderFields:))
       ├─ fallback 1: URLSession's cookie jar for the request URL
       └─ fallback 2: GET api/auth/token (cookie-authenticated) → {token}
  └─ KeychainStore.save: token + email + password   ← password kept for
                                                       silent re-login (§8)
Subsequent requests: Authorization: Bearer <token>   (7-day expiry server-side)
On any 401 (chat or authorizedJSON): exactly one refreshSession() =
  re-POST /api/auth/login with stored creds → new cookie → new Keychain token
  → retry original request; second 401 → BackendError.sessionExpired
signOut(): delete 3 Keychain accounts + purge cookies for
  app.archie.now and roofy-backend.onrender.com
"Signed in" check = Keychain token exists (ArchieBackendService.signedInEmail)
```

### 4.4 R2 presigned upload flow

```
AssistantView.pushDocumentToCRM (only when signed in + attached client has a claim)
  1. POST api/r2/upload  {filename, contentType, size}   (Bearer)
       ← { uploadUrl (presigned PUT, size is signed in), publicUrl }
  2. PUT <uploadUrl>  body = raw file bytes, Content-Type = mime, timeout 300 s
       (direct to R2 — no auth header; Content-Length must equal the signed size)
  3. POST api/claims/{claimID}/documents
       { name, file_url: publicUrl, document_type, file_size, mime_type,
         notes: "Uploaded from Archie Claims iOS" }
       → creates claim_documents row + logs a document_uploaded CRM activity
  UI: attachment chip status "Saving to claim…" → "Saved to claim ✓"
      or "Claim upload failed — still used in chat" (chat is never blocked)
  document_type heuristic: image/* → photo; name contains "denial" →
  denial_letter; "estimate"/"xactimate" → estimate; else correspondence
```

---

## 5. Persistence

| Store | Location | Contents | Notes |
|-------|----------|----------|-------|
| `LeadStore` | `Application Support/leads.json` | Entire `[Lead]` array, `JSONEncoder`, atomic writes | Loaded fully into memory at init; rewritten whole on every add/update/delete; errors silently ignored (`try?`); device-local only — **never synced to the CRM** |
| SPC disk cache | `Caches/spc-reports/{yymmdd}.json` | Parsed `[StormReport]` per convective day | Write skipped for *today* (SPC keeps updating it); OS may purge Caches; no eviction logic needed since files are per-day and tiny |
| SPC memory cache | `StormDataService` actor dict | Same, keyed `yymmdd` | Includes today's reports (session-scoped) |
| Keychain (`com.archieclaims.apikeys`) | device Keychain, `AfterFirstUnlockThisDeviceOnly` | `archie-backend-token` (JWT), `archie-backend-email`, `archie-backend-password` (plaintext, for silent re-login), `anthropic-api-key` (legacy) | Not iCloud-synced; survives reinstalls per iOS behavior |
| UserDefaults via `@AppStorage` | standard defaults | `settings.searchRadiusMiles` (10), `settings.lookbackDays` (30), `settings.modelOverride` (""), `settings.proxyBaseURL` (""), `settings.onboardingDone` (false), `settings.assistantMode` ("" = archie), `settings.archieBaseURL` ("" = app.archie.now) | |
| Cookie jar | `HTTPCookieStorage.shared` | `roof_report_token` httpOnly cookie | Side-channel of login; cleared on sign-out |
| Chat history | in-memory `@State` only | `[ChatMessage]` | **Lost on app relaunch / tab state reset; not persisted anywhere** |

---

## 6. External Dependencies & Endpoints

### Free public data (no API key)

| Source | Endpoint | Use |
|--------|----------|-----|
| NOAA SPC | `GET https://www.spc.noaa.gov/climo/reports/{yymmdd}_rpts_filtered.csv` | Daily filtered storm reports (one file per convective day, 12Z–12Z) |
| NWS | `GET https://api.weather.gov/alerts/active?point={lat},{lon}` (`Accept: application/geo+json`) | Active alerts at a property |
| Apple | `CLGeocoder` forward/reverse | Address ↔ coordinate (rate-limited by Apple; no key) |
| Public records | NETR directory, Google search, TruePeopleSearch, FastPeopleSearch URLs | Opened in `SFSafariViewController`; nothing scraped or stored |

Both NOAA calls send `User-Agent: ArchieClaims/1.0 (roofing canvassing app;
{contact email})` per NWS guidance — the email is currently a placeholder.

### Archie CRM backend (`https://app.archie.now`, Vercel proxy → Render `roofy-backend`)

| Method/Path | Purpose |
|-------------|---------|
| `POST api/auth/login` | Sign in; JWT via `Set-Cookie: roof_report_token` |
| `POST api/auth/signup` | Create account (free tier), then same cookie flow |
| `GET api/auth/token` | Raw JWT for cookie sessions (fallback extraction) |
| `POST api/ai-assistant` | `action:"chat"` — Groq-powered assistant with server-side system prompt + company profile; `context.current_project` injected verbatim |
| `GET api/crm-dashboard/search?q=&limit=20` | Unified lead/job (customer) search (min 2 chars) |
| `GET api/leads/{id}` | Lead detail + activities |
| `GET api/crm-jobs/{id}?include=projects,invoices,activities` | Customer/job detail |
| `GET api/claims?search={name}` | Claim lookup (no FK filter server-side; matched client-side) |
| `GET api/claims/{id}/documents` | Docs on file for the claim |
| `POST api/claims/{id}/documents` | Register an uploaded document on the claim |
| `POST api/r2/upload` | Presign an R2 upload (`uploadUrl` + `publicUrl`) |
| `PUT {presigned uploadUrl}` | Direct byte upload to Cloudflare R2 |
| `GET/POST api/communications/log` | Read recent / write new communication entries |

### Anthropic (legacy mode only)

| Method/Path | Purpose |
|-------------|---------|
| `POST https://api.anthropic.com/v1/messages` (or user proxy) | SSE streaming chat; model default `claude-opus-4-8`; user-supplied `x-api-key`; prompt-cached system prompt; adaptive thinking |

---

## 7. Concurrency Notes

- **`actor StormDataService`** serializes access to the two report caches;
  callers never see partially-written cache state. The per-day fetches fan
  out with `withTaskGroup` (one child task per convective day — up to 730
  for a 2-year lookback; each child is cache-hit-fast after first load).
- **Debounced overlay**: map camera changes cancel-and-replace a single
  `Task` with a 450 ms `Task.sleep`, checking `Task.isCancelled` after both
  the sleep and the fetch before touching `@State`. Same pattern (350 ms) in
  `ClientPickerSheet` search.
- **Parallel sheet loads**: `PropertySheetView` uses `async let` to run
  reverse-geocode and storm fetch concurrently, and again for SPC reports vs
  NWS alerts.
- **Streaming**: both chat backends expose `AsyncThrowingStream<String,
  Error>`; `onTermination` cancels the inner `Task`, and the stop button
  cancels `streamTask` (cancellation is detected via `CancellationError` /
  `URLError.cancelled` and not surfaced as an error).
- **Main-actor stores**: `LeadStore` and `AppState` are `@MainActor`;
  view-spawned `Task {}` blocks inherit the main actor, so `leads`/`@State`
  mutations after `await`s are safe. `LocationManager` publishes from
  CLLocationManager's main-thread delegate callbacks.
- **OCR off-main**: Vision runs on a `DispatchQueue.global(.userInitiated)`
  via a checked continuation; PDFKit extraction runs inline on the calling
  task.
- **Quick Log backfill** is intentionally fire-and-forget: the pin appears
  instantly and the geocode/storm snapshot lands a few seconds later via
  `leadStore.update`.

---

## 8. Tech-Debt Register

| # | Item | Severity | Detail / location | Suggested fix |
|---|------|----------|-------------------|---------------|
| 1 | **Plaintext password stored in Keychain** for silent re-login | High | `ArchieBackendService.authenticate` saves `archie-backend-password`; used by `refreshSession()` on 401 | Add a refresh-token endpoint to the backend; store only token + refresh token; delete the password account on migration |
| 2 | **No token refresh endpoint** — re-login is the refresh mechanism | High | 7-day JWT; `GET api/auth/token` only works for cookie sessions; every 401 replays full credentials | Server: `POST api/auth/refresh` (Bearer); client: drop #1 |
| 3 | **Leads never sync to the CRM** | High (product) | `LeadStore` is explicitly device-local; canvassed doors don't become CRM leads, undercutting the companion-app story | Add `POST api/leads` push (opt-in per lead or bulk), then two-way sync with conflict policy |
| 4 | **Claim lookup is a name-search + client-side FK match** | Medium | `clientAttachment(for:)` hits `GET api/claims?search={displayName}` and filters by `lead_id`/`job_id` locally; ambiguous names with exactly one unrelated claim row can mis-attach (`rows.count == 1` fallback) | Server-side `?lead_id=`/`?job_id=` filters on `/api/claims` |
| 5 | **Unpaginated, unfiltered client-side list handling** | Medium | Claims search (above) and `searchClients` cap at `limit=20` with no paging; doc/comm context uses `prefix(n)` of whatever page one returns | Add paging params; surface "more results" affordance in `ClientPickerSheet` |
| 6 | **`JSONSerialization` + `[String: Any]` throughout the CRM layer** | Medium | `ArchieCRMService` & `ArchieBackendService` are stringly-typed (key typos compile fine); contrasts with `Codable` used for SPC/NWS | Introduce `Codable` DTOs per endpoint (or a tolerant `@dynamicMemberLookup` wrapper); keep `compact(_:keeping:)` behavior |
| 7 | **No ViewModels — `AssistantView` (602 lines) and `CanvassMapView` (528 lines) carry orchestration + business rules** | Medium | Attachment pipeline, CRM side-effects, context-block assembly, marker math all live in view structs; untestable without UI | Extract `ChatSession` and `CanvassSession` `@Observable` objects; views become rendering + intent forwarding |
| 8 | **Chat history is not persisted** | Medium | `@State messages` in `AssistantView`; relaunch loses every conversation | Persist `[ChatMessage]` (JSON file or SwiftData) with a conversation list |
| 9 | **NWS/NOAA `User-Agent` contact is a placeholder** | Medium (release blocker) | `AppSettings.contactEmailForAPIs = "support@example.com"` — code comment says replace before release | Set the real support address; consider a build setting |
| 10 | **Silent error swallowing** | Medium | `LeadStore` load/save `try?` (a failed save loses door knocks silently); `StormDataService` returns `[]` on any error (offline looks identical to "no storms"); `authorizedJSON` returns `[:]` for non-JSON 2xx bodies | Surface save failures; distinguish "couldn't load" vs "no reports" in `PropertySheetView`; log errors |
| 11 | **Scanned PDFs fail instead of falling back to OCR** | Low | `DocumentTextExtractor.extractPDF` throws `noTextFound` when the text layer is <40 chars; the inline comment promises page OCR that isn't implemented | Render first N pages to images and run the existing Vision path |
| 12 | **Default credentials/coords hard-coded** | Low | Charlotte NC default region in `CanvassMapView`; cookie purge list hard-codes `roofy-backend.onrender.com` | Derive default region from last location; centralize backend hosts |
| 13 | **Lead dedupe by coordinate tolerance only** (0.0002° ≈ 22 m) | Low | Two adjacent townhomes can collide; re-tap of same roof at different zoom may miss | Dedupe on reverse-geocoded address once available; make tolerance zoom-aware |
| 14 | **`isLoadingStorms` is set but never rendered** | Low | `CanvassMapView` dead state; no overlay spinner shown | Show a small progress indicator or remove |
| 15 | **Streaming facade hides non-streaming backend** | Low | `streamReply` yields the whole Archie reply as one delta; UI shows a spinner then a full bubble (fine), but "stop" mid-request just cancels the URL task | Add SSE streaming to `/api/ai-assistant` later; facade already isolates the change |
| 16 | **Tests write into real Application Support and never clean up** | Low | `LeadStoreTests.makeStore()` unique filenames accumulate in the simulator container | Use `FileManager.temporaryDirectory` + `tearDown` deletion; inject directory into `LeadStore` |
| 17 | **`AsyncThrowingStream` continuation misuse risk on early errors** | Low | Pattern is correct today; just noted that both services build the stream by hand rather than `AsyncThrowingStream.makeStream` | Adopt `makeStream` for clarity when touched next |
| 18 | **Markdown rendering via `LocalizedStringKey`** | Low | Assistant bubbles get only single-line Markdown (no code blocks, lists render flat) | Adopt `AttributedString(markdown:)` with `.full` options or a lightweight renderer |

---

## 9. Security & Privacy (as built)

- Secrets (JWT, credentials, Anthropic key) in Keychain with
  `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`; never in UserDefaults.
- All endpoints HTTPS; base-URL overrides validate `scheme == "https"`.
- Location: when-in-use only, with a usage string stating location never
  leaves the device (true — it is only used to position the map camera).
- Document text extraction is fully on-device (PDFKit/Vision); original
  bytes leave the device only for the explicit CRM upload path.
- Privacy manifest (`PrivacyInfo.xcprivacy`) ships in the app target;
  `ITSAppUsesNonExemptEncryption=false` declared.
- Public-records features only open public websites in-app; compliance
  copy (TCPA, do-not-knock) is surfaced in the property sheet, settings,
  and onboarding.
- Residual risks: tech-debt #1 (stored password) is the dominant one; the
  attached-client CRM context is sent to the AI backend by design (same
  trust domain as the web CRM).

---

## 10. Evolution Recommendations

Ordered by leverage; each maps to register items in §8.

1. **Kill the stored password** (#1, #2). Backend `POST api/auth/refresh`
   issuing short-lived access + rotating refresh tokens; app migration
   deletes `archie-backend-password` on first launch. This is the only
   high-severity security item and should precede App Store launch
   marketing to CRM customers.
2. **Sync canvass leads into the CRM** (#3). The data model already
   matches (`Lead` ↔ CRM lead: name, phone, address, status, notes, storm
   evidence). A `syncedCRMLeadID: String?` field on `Lead` + a push action
   ("Send to Archie CRM") is a small, high-value first step; full
   bidirectional sync can follow. This is also the natural monetization
   hook (free app → CRM tier upsell).
3. **Introduce thin `@Observable` session objects** for Assistant and
   Canvass (#7), moving attachment/CRM/marker logic out of the views. Do
   this before features grow further; it also unlocks unit tests for the
   chat pipeline (currently 0% service-network coverage).
4. **Typed DTO layer for the CRM API** (#6) — incrementally, endpoint by
   endpoint, starting with the auth and chat payloads (most stable).
5. **Persist conversations** (#8) and add a conversation list; consider
   storing the attached-client reference so a conversation reopens with
   context.
6. **Server-side claim/lead filters + pagination** (#4, #5) in the same
   backend release as the refresh endpoint.
7. **Polish pass**: real NOAA contact email (#9 — release blocker),
   distinguish offline vs no-reports (#10), OCR fallback for scanned PDFs
   (#11), loading indicator for the storm overlay (#14).
8. **Later platform options** (no code today): hail-swath polygon
   rendering (SPC also publishes shapefiles), iPad/landscape support
   (currently locked to iPhone portrait), Live Activity for daily door
   tally, and true SSE streaming from `/api/ai-assistant`.

---

## Appendix: Build & Test

- Open `ArchieClaims.xcodeproj` (Xcode 16+/26.x); or regenerate with
  `brew install xcodegen && xcodegen generate`.
- Targets: `ArchieClaims` (app) and `ArchieClaimsTests` (unit bundle,
  XCTest). Tests are pure-logic (parser, store, date math) and run without
  network.
- No SPM packages, no CocoaPods, no CI configuration in-repo.

**Document History**

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0.0 | 2026-06-09 | Architecture review (automated) | Initial as-built specification from full source read |
