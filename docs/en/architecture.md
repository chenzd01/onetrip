# Architecture

This document describes the app's module layout, data flow, offline and sync model, and the optional backend. For field-level details see [content-schema.md](content-schema.md); for backend deployment see [backend.md](backend.md).

## Overview

```
content/*.json + content/media/          (the single content source you maintain)
        │  scripts/verify_content.py      structure / reference / coordinate / date / source checks
        ▼  scripts/build_ios_resources.py
ios/TripJournal/Resources/Content/       (generated, git-ignored)
  catalog.json  trip.json  place-locations.json  media/…  manifest.json
ios/Generated.xcconfig                   (app display name)
        │  xcodegen + xcodebuild
        ▼
TripJournal.app ──────────────► TripWidgets.appex (reads trip.json and schedule.json from the App Group)
   │  On device: Application Support/TripWorkspace/workspace.json (plan, baseline, revision, pending-sync flag)
   │
   └── Optional: HTTPS ──► server/trip_server.py (shared plan, attachments, route preferences, routing, companion interactions)
                              ├─ SQLite (WAL)
                              ├─ route_engine.py → valhalla_service (self-hosted road network)
                              └─ touch_push.py (separate process, APNs)
```

Design principles:

1. **Content is separate from code**: switching destinations only touches `content/`. The Swift code contains no city names, dates, currencies or coordinates; all of it comes from `trip.json` (`TripConfig`) and `catalog.json` (`ContentCatalog`).
2. **Offline first**: all content is bundled into the app; place coordinates are built in and do not depend on geocoding during the trip (in practice we hit a map service that was unavailable for regions abroad, see [lessons-learned.md](lessons-learned.md)).
3. **Local first, sync optional**: every change is first written atomically to a local file, then sync is attempted; the app is fully usable without a backend.
4. **Content updates never touch user data**: the default plan shipped with a new build only takes effect if the user has never modified the plan; saved plans, check marks and favorites are never overwritten.
5. **Never fabricate; show uncertainty**: content marked "to be confirmed / snapshot / estimate" is clearly labeled in the UI with color + icon + text.

## iOS project

- The project is generated from `ios/project.yml` (XcodeGen); the `.xcodeproj` is not committed. The project and target name `TripJournal` is an internal code name; the project is published as OneTrip, and the name on the home screen comes from `appName` in `trip.json`.
- iOS 26+, iPhone only, Swift 6, strict concurrency checking (`SWIFT_STRICT_CONCURRENCY: complete`).
- Three targets:

| Target | Contents |
| --- | --- |
| `TripJournal` | The app itself; resources are the generated `Resources/Content` (folder reference) and `Assets.xcassets` |
| `TripWidgets` | WidgetKit widgets + Live Activity; compiles `TripJournal/Shared`, bundles only `trip.json` as a resource |
| `TripJournalTests` | Unit tests and optional local HTTP integration tests |

- Build configuration: `App.xcconfig` → `Generated.xcconfig` (display name) → `Signing.xcconfig` (Team, Bundle ID; required, ignored by git) → `SharedAccess.xcconfig` (backend URL and shared key; optional, ignored by git).
- Derived from the Bundle ID: widget `<id>.widgets`, App Group `group.<id>`, Keychain service name, logging subsystem (see `AppIdentity` in `Shared/TripConfig.swift`).

### Directories and modules

| Path | Responsibility |
| --- | --- |
| `App/TripJournalApp.swift` | Entry point and the four tabs: Today, Itinerary, Explore, Kit (`今日`, `行程`, `探索`, `行囊`); sync entry point; (with a backend) the floating companion-interaction button |
| `App/Design.swift` | Colors, fonts, image loading |
| `Shared/TripConfig.swift` | Destination config `TripConfig.current`, `AppIdentity` (shared by app and widget) |
| `Shared/TripClock.swift` | Interprets all times in the destination time zone; widget snapshots and schedule timeline |
| `Core/Models.swift` | Content models and the plan document `TripPlan` (days, stops, custom places, checklist, budget, stays, tickets) |
| `Core/TripStore.swift` | Main state: local saving, undo, sync loop, three-way merge, widget / reminder / Live Activity refresh, backups |
| `Core/TripAPI.swift` | Backend transport (`TripService` protocol), Keychain credentials |
| `Core/PlanMerge.swift` | Generic JSON three-way merge and conflict list |
| `Core/PlanValidation.swift` | Plan document validation (dates, IDs, counts, formats), consistent with backend validation |
| `Core/AttachmentStore.swift` | Original ticket files (stored by SHA-256) |
| `Core/Dining.swift` | Dining model, meals and reservations, closed-day and time-conflict warnings |
| `Core/BudgetCalculator.swift` | Two-currency budget rows and edit drafts |
| `Core/DestinationMaps.swift` | Map region, coordinate bounds checks, map search, opening the system Maps app |
| `Core/DayRoute*.swift`, `RoutePreferenceStore.swift`, `RouteEnglishAddress.swift` | Full-day routes (require backend), route preference sync, copying English addresses |
| `Core/Touch*.swift` | Companion interactions: pairing, events, push (require backend) |
| `Core/ReminderController.swift`, `LiveActivityController.swift` | Local notifications, Live Activities |
| `Core/PhraseSpeechPlayer.swift` | Reads travel phrases aloud (system voice; language from `trip.speech.language`) |
| `Core/ExternalLinks.swift` | External link handling (including Xiaohongshu original-post deep links) |
| `Features/*` | Screen views |

### Content loading

`ContentCatalog.load()` decodes `Content/catalog.json` from the app bundle; image paths are relative to `Content/`. `manifest.json` records each file's byte size and SHA-256; tests verify every entry, and the Kit tab also shows offline content integrity.

### Plan document and local storage

`TripPlan` is the only document that gets synced:

```
{ version, id, days:[{date,title,area,note,items:[Stop]}], custom:[Place], checks:{id:Bool},
  budget:{flightOut, flightReturn, hotel, food, transport, other},
  hotelFavorites:[id], stays:[Stay], tickets:{placeID:[Ticket]} }
```

Local files (`Application Support/TripWorkspace/`):

| File | Contents |
| --- | --- |
| `workspace.json` | `{plan, base, revision, pending}`: current plan, baseline from the last sync, server revision, whether there are unsynced changes |
| `ticket-drafts.json` | Unfinished ticket drafts |
| `route-preferences.json` | Route preferences (synced separately) |
| `Attachments/` | Original ticket files |

All writes are atomic and use file protection. `schedule.json` in the App Group container contains only public place names and times for the widget to read; it has no notes, orders or ticket numbers.

### Sync model (with a backend)

1. Exchange the install-level shared key for a session cookie (`POST api/native-session`), then fetch the CSRF token (`GET api/session`).
2. In the foreground, poll `GET api/plan?since=<revision>` about every 3 seconds; no change returns 204.
3. When there are local changes, `PUT api/plan {revision, state, device}`; the server does a compare-and-swap (CAS) on the revision, and a conflict returns 409 with the latest version.
4. The client does a **three-way merge** using the "baseline from the last sync" as the common ancestor: if the two sides changed different fields, they merge automatically; if they changed the same field, the UI shows "This device / Shared" side by side and lets the user choose.
5. The baseline is frozen on the first edit, so default content in a new build is not mistaken for a user change.
6. Unknown new fields are always rejected on write (fail closed) with a prompt to update the app; shared content is never overwritten.
7. Sync pauses while a form is open; connection failures back off exponentially (up to 60 seconds), and changes are always kept locally.

Without a configured backend: the sync entry point shows "Local only", with no polling and no errors; route and companion-interaction entry points are hidden or say that a self-hosted backend is required.

### Widget and Live Activity

After every change the app writes `schedule.json` and reloads the timeline; based on the current time the widget shows "days until departure / up next / today's full schedule / trip over". The Live Activity is started manually in the foreground and updated along the timeline; it does not use push.

## Backend (optional)

`server/` depends only on the Python standard library (the push process additionally needs `httpx[http2]` and `PyJWT[crypto]`); data lives in SQLite (WAL mode, file permissions 0600). See [backend.md](backend.md).

### API overview

| Endpoint | Auth | Description |
| --- | --- | --- |
| `GET /healthz` | None | Health check |
| `POST /api/native-session` | Origin | Exchange the install-level shared key (server stores only its SHA-256) for a session |
| `GET /api/session` | cookie | CSRF token and expiry |
| `GET /api/plan?since=N` | cookie | 204 or `{revision, state, updatedAt}` |
| `PUT /api/plan` | cookie + Origin + CSRF | Revision CAS; 409 returns the latest version; verifies that referenced attachments exist |
| `POST /api/attachments`, `GET /api/attachments/<sha256>` | Same as above | JPEG/PNG/WebP/PDF, content-addressed, ≤10 MiB each |
| `GET/PUT /api/route-preferences` | Same as above | Route preference document, same CAS semantics |
| `GET /api/route-address-status` | cookie | Feature flag for English address sharing |
| `POST /api/routes` | Same as above | Walking / driving routes, returns an encoded polyline |
| `GET /api/route-places?query=` | cookie | Place search based on OpenStreetMap |
| `/api/touch/*` | Same as above + device key | Companion pairing (invite code), events, push status |

### Tables

`trip` (single-row plan document and revision), `revisions` (roughly the last 100 versions), `sessions` (tokens stored only as hashes), `attempts` (rate limiting), `attachments`, `route_preferences`, `touch_*` (members, pairing, invites, events, push queue, rate limiting). New features only add tables; `init` refuses to overwrite an existing database.

### Push (companion interactions)

A separate `touch_push.py` process claims pending events every second: ES256 JWT, HTTP/2, retries only on 429/500/503 (up to 5 times, exponential backoff, honors Retry-After); events in flight when the process crashes are marked "uncertain" and **not resent**, to avoid duplicate alerts. "Accepted by APNs" does not mean "the phone rang".

### Routes

`route_engine.py` calls `valhalla_service` as a subprocess (semaphore 2, 12-second timeout); coordinates are snapped only within the destination bounds (≤100 m); segments that cannot be computed are labeled honestly, and fake straight lines are never drawn. The road network and place index are built from OpenStreetMap regional extracts by `deploy/build_route_artifact.py` and `scripts/build_route_places.py`, published as immutable versioned directories and switched atomically.

## Testing

| Scope | Command |
| --- | --- |
| Content pipeline | `python3 -m unittest discover -s scripts -p 'test_*.py'` |
| Backend | `python3 -m unittest discover -s server -p 'test_*.py'` |
| Deployment scripts | `python3 -m unittest discover -s deploy -p 'test_*.py'` |
| Screenshots | `python3 scripts/make_screenshots.py` (UI tests in `TripJournalUITests`, run only by the `Screenshots` scheme; the app clock is frozen with the DEBUG-only `-TripNow` launch argument) |
| iOS | `xcodebuild test …` (`HTTPIntegrationTests` needs `TRIP_INTEGRATION_URL` set to a local test server; only 127.0.0.1 / localhost are accepted, and the tests are skipped automatically when it is unset) |

**Tests that write data must never connect to a real service.**
