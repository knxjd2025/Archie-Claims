# Backend Spec — Lead → CRM Sync (V1-1)

**Status:** Proposed · **Date:** 2026-06-09 · **Owner:** backend (roof-report-ai / roofy-backend)
**Consumers:** Archie Claims iOS (`ArchieBackendService`), Archie web CRM
**Related:** improvement-plan.md V1-1 / B1, do-first sprint #2 & #11; architecture.md §10.2

---

## 1. Goal & the core insight

Today canvass leads live only in the iOS app's on-device JSON (`LeadStore`). The whole
"field companion to Archie CRM" positioning — and the free→paid monetization funnel — depends on
those leads reaching the CRM. This spec defines the one-way push (device → CRM).

**The insight that shapes everything: a knocked door is not a CRM lead.** A rep logs 80–120 doors/day,
~70% "Not Home." The existing `POST /api/leads` hardcodes `status='new'` and enforces a **2-leads/month
cap on the free tier** — pushing every door as a lead would (a) hit that cap on door #3, and (b) flood
the CRM pipeline with junk. The backend already models this correctly with **two tables**:

| iOS lead | Goes to | Why |
|---|---|---|
| Every logged door (all statuses) | `door_knocks` row | The canvassing audit trail; cheap, uncapped, GPS-stamped |
| Only **qualified** doors (Interested / Appointment / Inspected / Signed) | `leads` row (+ the knock links to it) | A real CRM contact worth a pipeline slot |
| Not Home / Not Interested / New | `door_knocks` only | Not a pipeline lead unless it was already qualified before |

This makes the free-tier cap a non-issue for normal canvassing (you create a handful of *leads*, not
hundreds), keeps the CRM pipeline clean, and uses the schema the way it was designed.

---

## 2. What already exists (reuse, don't reinvent)

Verified in `roof-report-ai` @ `4e3e069`:

- **`leads` table** (`api/db/migrate-leads.ts:15`): `id`, `company_id`, `first_name/last_name`,
  `email`, `phone`, `address_line1/2`, `city/state/zip`, `latitude` DECIMAL(10,8),
  `longitude` DECIMAL(11,8), `source` VARCHAR(100), `status` VARCHAR(50) **default 'new', no CHECK**,
  `priority`, `estimated_value`, `assigned_to`, `created_by`, `damage_type`, `damage_notes` TEXT,
  `roof_type`, `roof_age_years`, `insurance_claim` BOOL, `appointment_date`, `appointment_notes`,
  `next_follow_up_date`, `tags` TEXT[], `custom_fields` JSONB, timestamps.
- **`door_knocks` table** (`:98`): `id`, `company_id`, `user_id`, `lead_id` (nullable FK),
  `address`, `latitude`, `longitude`, `status` VARCHAR(50), `notes`, `contact_name/phone/email`,
  `appointment_set` BOOL, `appointment_date`, `photo_url`, `gps_accuracy`, `device_info`,
  `knocked_at`, `created_at`. **Purpose-built for exactly this.**
- **`lead_activities` table** (`:72`): status-change/audit log.
- **`POST /api/leads/`** (`server/src/routes/leads.ts:1020`) — creates a lead; **status hardcoded
  `'new'`**; 2/mo free-tier cap; logs a `lead_activities` row; fires async enrichment + scoring.
- **`PUT /api/leads/:id`** (`:1256`) — dynamic partial update; **does accept `status`**, `appointment_date`,
  `next_follow_up_date`, `custom_fields`, etc.
- **`GET /api/leads`** (`:906`) and **`GET /api/leads/:id`** (`:1171`).
- **Auth**: `resolveUserAndCompany(req,res)` → Bearer/cookie JWT, company via `ensureUserHasCompany`,
  role scoping (sales_rep/field_tech see only their own).

**Gap:** no idempotency key, no canvass-status acceptance on create, no door_knocks write path, no
batch endpoint for draining an offline queue. We add a thin **sync** endpoint rather than overloading
`POST /api/leads`.

---

## 3. New endpoint: `POST /api/leads/sync`

One batch, idempotent, upsert-by-device-id endpoint. Drains the iOS offline queue in a single call and
is safe to retry (canvassing happens on rural LTE — retries are the norm, not the exception).

Mount in `server/src/routes/leads.ts` (same router, so it inherits auth + company scoping).

### Request

```
POST /api/leads/sync
Authorization: Bearer <jwt>
Content-Type: application/json
```

```jsonc
{
  "knocks": [                         // 1–200 per call (cap; 413 over)
    {
      "client_id": "E0B...UUID",      // REQUIRED — the iOS Lead.id; the idempotency key
      "status": "appointment",        // REQUIRED — iOS status (see §4 mapping)
      "knocked_at": "2026-06-09T18:22:05Z", // REQUIRED — when the door was logged (lastKnockAt)
      "address": "123 Oak St, Charlotte, NC 28202",
      "latitude": 35.2271,
      "longitude": -80.8431,
      "homeowner_name": "Pat Smith",  // optional
      "phone": "+17045551234",        // optional
      "email": null,                  // optional
      "notes": "Back slope hail bruising; wants Tues AM",
      "storm_summary": "Last 30 days: 3 SPC reports in range (1 hail, 2 wind). Closest: 1.75\" hail ~0.8 mi …",
      "appointment_at": "2026-06-11T14:00:00Z", // optional; present when status=appointment
      "gps_accuracy_m": 8.0,          // optional
      "device_info": "iPhone17,2 / iOS 26.1 / ArchieClaims 1.0"
    }
  ]
}
```

Field rules:
- `client_id` is the stable dedupe key. Same `client_id` re-sent = update, never duplicate.
- `status` is the **iOS** status string; the server maps it (§4) — the client never sends CRM statuses.
- `knocked_at` is authoritative for `door_knocks.knocked_at` and tally reconciliation; the server still
  stamps its own `created_at`. Reject `knocked_at` more than 7 days in the future (clock-skew guard).
- All strings sanitized + length-clamped server-side (reuse `sanitizeInput`). `notes`/`storm_summary`
  clamped to 4 000 chars each.

### Behavior (per knock, in one transaction per item)

1. **Resolve** `(company_id, user_id)` from JWT.
2. **Upsert door_knock** keyed on `(company_id, client_id)`:
   - Look up `door_knocks WHERE company_id=$c AND external_id=$client_id` (new column, §6).
   - Insert or update `address, latitude, longitude, status→mapped knock status, notes, contact_*,
     appointment_set, appointment_date, gps_accuracy, device_info, knocked_at`.
3. **Decide lead creation** by mapped tier (§4):
   - **Qualified** status (interested/appointment/inspected/signed) → upsert a `leads` row keyed on
     `(company_id, custom_fields->>'archie_client_id' = $client_id)`:
     - On insert: set `source='Archie Canvassing'`, `status`=mapped CRM status, `created_by`/`assigned_to`=user,
       `damage_notes`=notes, `custom_fields = {archie_client_id, storm_summary, app:'ios'}`,
       `insurance_claim=true` if `storm_summary` is non-empty, `appointment_date` if present.
     - On update: update `status` (forward-only — never downgrade `won`→`qualified`; see §4 note),
       `appointment_date`, `damage_notes`, `next_follow_up_date`.
     - Link the door_knock: `door_knocks.lead_id = lead.id`.
     - Write a `lead_activities` row (`activity_type='synced'` on first link, `'status_change'` on change).
   - **Unqualified** status (new/not_home/not_interested) → door_knock only. *Exception:* if a lead already
     exists for this `client_id` and status went to `not_interested`, set that lead `status='lost'`.
4. **Free-tier cap applies to *leads only*, not knocks.** If creating a *new* lead would exceed the 2/mo
   free cap, the door_knock still succeeds; the lead is **deferred** and the item returns
   `lead_status:"deferred_free_limit"` (not a hard error — the rep keeps canvassing; the knock is saved).
   Surface upgrade messaging in the app, don't block.

### Response (`200`)

Per-item result so the client can mark each queued knock synced or retry just the failures.

```jsonc
{
  "results": [
    {
      "client_id": "E0B...UUID",
      "ok": true,
      "door_knock_id": "uuid",
      "lead_id": "uuid|null",          // null when door-knock-only
      "lead_status": "created|updated|deferred_free_limit|none",
      "crm_status": "qualified"        // mapped CRM lead status, when a lead exists
    },
    { "client_id": "BAD", "ok": false, "error": "invalid_status" }
  ],
  "synced": 11,
  "failed": 0,
  "free_limit": { "tier": "free", "leads_used": 2, "leads_limit": 2, "deferred": 3 } // present on free tier
}
```

- The whole call returns `200` even with per-item failures (partial success); only auth/limit/shape
  errors fail the request (`401/413/400`). Rate limit: `rateLimit('write')` (30/min) — generous because
  it's batched. A 200-knock batch is one request.

### Why batch + per-item results
The iOS queue may hold a day's backlog after a dead zone. One round-trip drains it; per-item `ok` lets the
client clear synced rows and keep only true failures in the queue. Idempotent upsert means a retried batch
(e.g. response lost on flaky LTE) is harmless.

---

## 4. Status mapping (iOS → CRM)

iOS `Lead.Status` → `door_knocks.status` (free-form string, kept verbatim-ish) and, when qualified, a
canonical `leads.status` (CRM pipeline: `new|contacted|qualified|proposal_sent|negotiating|won|lost`).

| iOS status | Qualified? | `door_knocks.status` | `leads.status` | Notes |
|---|---|---|---|---|
| New | no | `new` | — | door-knock only |
| Not Home | no | `not_home` | — | ~70% of knocks; never a lead |
| Interested | **yes** | `interested` | `contacted` | first pipeline entry |
| Appointment | **yes** | `appointment` | `qualified` | sets `appointment_set=true`, `appointment_date` |
| Inspected | **yes** | `inspected` | `qualified` | (stays qualified; inspection ≠ proposal) |
| Signed | **yes** | `signed` | `won` | the conversion |
| Not Interested | no* | `not_interested` | `lost` *(only if lead already existed)* | otherwise knock-only |

**Forward-only lead status:** never let a re-sync downgrade the pipeline (e.g. a late "Interested" re-push
must not move a `won` lead back to `contacted`). Implement an ordinal guard: `new(0) < contacted(1) <
qualified(2) < proposal_sent(3) < negotiating(4) < won(5)`, and `lost` only from a non-won state. Door_knock
status is always overwritten with the latest (the knock reflects the most recent disposition).

Centralize this table in `server/src/lib/canvass-status-map.ts` (single source of truth, unit-tested).

---

## 5. iOS client contract (Archie Claims)

Additions to the app (separate PR, gated on this endpoint shipping):

- **`Lead` model:** add `syncedCRMLeadID: String?`, `syncedKnockID: String?`, `syncState: enum
  {local, queued, syncing, synced, failed}`, `lastSyncAttempt: Date?`. All optional → migration-safe.
- **`LeadStore`:** an outbound queue of dirty `client_id`s; a `SyncService` that batches ≤200 and POSTs
  to `/api/leads/sync`, marks results, retries failures with backoff. Trigger on: app foreground,
  network-regained (`NWPathMonitor`), and after a status change to a qualified status.
- **Auto-prompt:** when a door is logged **Appointment / Signed** (or **Inspected**), and the rep is signed
  in, push immediately (best-effort) and show "Sent to Archie CRM ✓" on the lead. Manual "Send to Archie
  CRM" button in `LeadDetailView`; bulk "Push N leads" in `LeadsView`.
- **Offline:** queue persists in `LeadStore` JSON; the batch endpoint drains it on reconnect (pairs with
  V1-5 offline hardening). Idempotency means a queued item re-sent after a crash is safe.
- **Synced badge** on lead rows/pins; tapping a synced lead can deep-link to the web CRM
  (`https://app.archie.now/leads/<lead_id>`).
- **Field mapping:** iOS `homeownerName` → split to `first_name`/`last_name` server-side (last token =
  last name; keep raw in `contact_name`); `stormSummary` → `storm_summary`; `address` → `address` +
  best-effort parse to `address_line1/city/state/zip` (or leave parsing to existing enrichment).

---

## 6. Schema migration

New migration `api/db/migrate-leads-sync.ts` (additive, idempotent — follows the repo's migration pattern,
run via `POST /api/admin/run-migrations`):

```sql
-- Idempotency key for device-originated knocks
ALTER TABLE door_knocks ADD COLUMN IF NOT EXISTS external_id VARCHAR(64);
CREATE UNIQUE INDEX IF NOT EXISTS uq_door_knocks_company_external
  ON door_knocks(company_id, external_id) WHERE external_id IS NOT NULL;

-- Fast dedupe of canvass-originated leads by the app's client id
CREATE INDEX IF NOT EXISTS idx_leads_archie_client
  ON leads ((custom_fields->>'archie_client_id'))
  WHERE custom_fields ? 'archie_client_id';
```

Storing the lead's client id in `custom_fields.archie_client_id` (vs a new column) keeps the change minimal
and the leads table untouched; the partial expression index keeps the upsert lookup fast. If preferred,
promote to a real `leads.external_id` column later — the endpoint contract doesn't change.

---

## 7. Secondary endpoints (the other day-1 backend tickets)

These were called out alongside lead sync (improvement-plan do-first #2). Briefly specced so they can ship
in the same backend release; full detail in follow-ups.

### `POST /api/app-events` — analytics (unblocks QW-15)
- Body: `{ events: [{ name, ts, props?: object, anon_id }] }`, ≤100/batch.
- Auth: Bearer **optional** (pre-sign-in events carry only `anon_id`; never PII). `rateLimit('write')`.
- Store to a new `app_events` table (`company_id?`, `user_id?`, `anon_id`, `name`, `props` JSONB, `ts`).
- Core events listed in improvement-plan UX-23. This is the prerequisite for *every* success metric in the
  PRD — ship it first.

### `GET /api/app-config` — remote flags (unblocks QW-14 kill-switch)
- Auth: Bearer **optional**; cache-friendly (`Cache-Control: max-age=300`).
- Returns `{ people_search_links_enabled: bool, min_supported_build: int, message?: string }`.
- Lets the App-Store-risky people-search links become a config flip, not a resubmission; also a force-update
  lever. Defaults all-permissive if the call fails (fail-open for non-critical flags).

### `POST /api/auth/refresh` — kill the stored password (V1-7 / UX-24, security)
- Issues a fresh access token from a refresh token so the app can stop storing the plaintext password in
  Keychain (current silent-re-login hack). High-severity security item; do in this same backend release.
- Out of scope for *this* doc beyond noting the dependency.

---

## 8. Errors, security, observability

- **Auth:** every sync endpoint requires JWT (Bearer or cookie); `resolveUserAndCompany` enforces company
  scoping — a knock can only land in the caller's company. No cross-tenant `company_id` from the client.
- **Validation:** reject unknown `status` (`400 invalid_status` per item); clamp array length (`413`);
  sanitize all text; reject absurd coords (lat∉[-90,90], lng∉[-180,180]).
- **Idempotency:** unique `(company_id, external_id)` on door_knocks; `custom_fields.archie_client_id`
  dedupe on leads. Retries and double-taps converge.
- **Free tier:** never hard-block canvassing; defer lead creation, keep the knock, surface upgrade copy.
- **Audit:** `lead_activities` row on lead create/status-change with `metadata.source='ios-sync'`.
- **Privacy:** `device_info`/`gps_accuracy` are for the company's own audit; documented in the privacy
  policy update (release-plan dependency).

---

## 9. Acceptance criteria

1. `POST /api/leads/sync` with one Appointment knock → one `door_knocks` row (`appointment_set=true`,
   `appointment_date` set) **and** one `leads` row (`status='qualified'`, `source='Archie Canvassing'`,
   `custom_fields.archie_client_id` set), linked via `door_knocks.lead_id`. Response `lead_status:'created'`.
2. Re-sending the **same** `client_id` with status Signed → **no new rows**; the lead moves to `won`, the
   door_knock status updates; response `lead_status:'updated'`.
3. A "Not Home" knock → `door_knocks` row only, `lead_id null`, `lead_status:'none'`; does **not** count
   against the free lead cap.
4. On the free tier, after 2 qualified leads exist this month, a 3rd qualified knock → knock saved,
   `lead_status:'deferred_free_limit'`, `free_limit.deferred` increments; **request still 200**.
5. A re-sync that arrives out of order (Interested after Signed) does **not** downgrade `won`.
6. Batch of 50 mixed knocks → one request, per-item `results[]`, `synced/failed` accurate; retrying the
   identical batch changes nothing (idempotent).
7. Cross-tenant attempt (spoofed company) → impossible; rows scoped to JWT company.

## 10. Test plan (backend)

- Unit: `canvass-status-map` (every iOS status → knock+lead status; forward-only guard).
- Unit: upsert dedupe (same `client_id` twice → 1 row each table).
- Integration: free-tier defer path; partial-batch failure; coord/length validation; clock-skew reject.
- Load: 200-item batch under the write rate limit; p95 latency target < 800 ms on Render.

---

## 11. Rollout

1. Migration (`migrate-leads-sync.ts`) via `/api/admin/run-migrations`.
2. Ship `/api/leads/sync` + `canvass-status-map` behind no flag (additive; nothing else calls it).
3. iOS sync PR (model fields, queue, auto-prompt) — release-noted as "Send leads to Archie CRM."
4. `/api/app-events` + `/api/app-config` in the same or next backend deploy (unblock analytics + kill-switch).
5. Measure (needs app-events): % leads pushed, qualified-knock→lead rate, free→paid conversion from
   `deferred_free_limit` exposure.
```
