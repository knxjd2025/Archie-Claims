# Testing Guide — Archie Claims

## Unit tests

Run in Xcode (Product → Test) or CLI:

```sh
xcodebuild test -project ArchieClaims.xcodeproj -scheme ArchieClaims \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

Covered:
- `SPCReportParserTests` — SPC CSV sections (tornado/wind/hail), hail size conversion (175 → 1.75"), quoted commas, malformed-row skipping, distance filtering.
- `StormDataServiceTests` — `yymmdd` UTC formatting, convective-day walkback, lookback clamping, storm summaries.
- `LeadStoreTests` — add/update/delete, coordinate proximity lookup, persistence isolation.

## Manual test plan (device or simulator)

### Storm data (no API key needed)
1. Simulator: Features → Location → Custom Location → lat `35.34`, lon `-97.49` (Moore, OK) — or any area with storms in the last 30 days (check spc.noaa.gov/climo/reports/ for active regions).
2. Canvass tab → tap a rooftop. Expect: address resolves, storm section fills with hail/wind reports sorted by date/distance, or a clear "No reports in range" message.
3. Settings → raise radius to 25 mi / lookback to 90 days → tap again → more reports.
4. Airplane mode → tap a house → app stays responsive; storm section shows empty state (no crash).

### Contact lookups
5. Property sheet → each lookup button opens in-app Safari with the address pre-filled where supported.

### Leads
6. Save as Lead → pin appears on map. Change status in Leads tab → pin color/icon updates.
7. Add phone → Call button appears. Swipe-to-delete works. Kill & relaunch app → leads persist.

### AI assistant (needs an Anthropic API key)
8. Without a key: send a message → friendly error pointing to Settings (no crash).
9. Settings → paste key → Save. Archie tab → quick prompt → response streams in live.
10. Map → property sheet → **Ask Archie** → context chip shows; ask "Write a door script using this storm data" → reply references the actual reports.
11. Enter a bogus key → clear 401 error message.

### Onboarding & permissions
12. Fresh install: onboarding shows once; map asks for location When-In-Use with the explanation string; denying location still allows tapping houses anywhere.

## What to watch in review/beta

- SPC has no reports for calm regions/dates — testers in storm-free areas should widen radius/lookback or simulate a location instead of filing "no data" bugs.
- Reverse geocoding occasionally returns no street address for empty land; the sheet falls back to coordinates by design.
