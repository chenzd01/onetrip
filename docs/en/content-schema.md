# Content data schema (content/)

`content/` is the app's single content source. To switch to a new destination you only change the files in this directory and the images in `content/media/`; no Swift code changes are needed.

- The final authority on fields is `scripts/verify_content.py` (structure checks) and `scripts/build_ios_resources.py` (build-time checks). If this document conflicts with the scripts, the scripts win — please fix this document while you're at it.
- The bundled 3-day Kyoto example was researched by an agent; you can read every file side by side with this document. Its research records are in `docs/research/kyoto/`.
- The app UI is in Simplified Chinese, and the bundled sample content is written in Chinese. Chinese strings that the app matches literally are kept in backticks below, with their English meaning.
- All IDs use lowercase letters, digits and hyphens (`^[a-z0-9][a-z0-9-]{0,79}$`). **Never change an ID once published**: users' plans, favorites and check marks are all linked by ID.
- Dates are always `yyyy-MM-dd`, times `HH:mm`, date-times `yyyy-MM-ddTHH:mm`, all in **destination local time** (except flights, see below).
- Factual content must carry a source link (https) and a check date `checkedAt`; for research methods see [research-playbook.md](research-playbook.md).

## File overview

| File | Required | Contents | Where it appears in the app |
| --- | --- | --- | --- |
| `trip.json` | Yes | Destination config: name, dates, time zone, currencies, map bounds, speech language | Global |
| `places.json` | Yes | Sights / places directory, can embed in-depth guides `guides` | Explore › Places; referenced by the itinerary |
| `itinerary.json` | Yes | Default itinerary (day-by-day stops) and default budget | Today, Itinerary, Budget |
| `preparation.json` | Yes | Pre-trip preparation checklist | Kit › Checklist; date-based reminders on the Today tab |
| `dining.json` | No | Restaurant directory, menus, booking observations, recommendations and how-to-choose guides | Explore › Dining; meals in the itinerary |
| `hotels.json` | No | Hotel options and quote snapshots | Explore › Hotels |
| `locations.json` | No (strongly recommended) | Place coordinates | Maps, routes, "Open in Maps" |
| `photo-sources.json` | No | Real photos of places and their licenses | Place detail photo album |
| `posts.json` | No | Social media reference posts (Xiaohongshu, etc.) | Place detail, Explore › Guides |
| `phrases.json` | No | Travel phrases (can be read aloud) | Kit › Travel phrases |
| `references.json` | No | Practical info (transit cards, emergency numbers, etc.) | Kit |
| `flights.json` | No | Flight times | Kit › Flights |
| `media/` | As needed | Images referenced by the files above | — |

Build: `python3 scripts/build_ios_resources.py` merges these files into `ios/TripJournal/Resources/Content/catalog.json`, copies and resizes images, generates `manifest.json` (size and SHA-256 of each file), and writes `ios/Generated.xcconfig` (app display name) from `trip.json`. All generated output is git-ignored.

## trip.json

```json
{
  "id": "kyoto-2027-autumn-v1",
  "appName": "京都三日",
  "tagline": "红叶季的三天京都 · 由 AI Agent 按官方来源调研",
  "destination": { "name": "京都", "nameEn": "Kyoto", "countryCode": "JP",
                   "addressSuffix": "Kyoto", "postcodePattern": "\\d{3}-\\d{4}" },
  "timezone": "Asia/Tokyo",
  "startDate": "2027-11-16", "endDate": "2027-11-18", "departureDate": "2027-11-15",
  "homeCity": "上海", "partySize": 2,
  "currency": { "local": "JPY", "home": "CNY", "localSymbol": "JP¥", "homeSymbol": "¥",
                "homePerLocal": 0.0426, "rateDate": "2026-09-24", "rateSource": "https://www.chinamoney.com.cn/chinese/bkccpr/" },
  "map": { "center": [35.0, 135.735], "span": [0.11, 0.14],
           "bounds": { "minLat": 34.93, "maxLat": 35.06, "minLon": 135.66, "maxLon": 135.81 } },
  "speech": { "language": "ja-JP", "label": "日语" },
  "attributions": [ { "label": "地点坐标：© OpenStreetMap contributors（ODbL）", "url": "https://www.openstreetmap.org/copyright" } ]
}
```

Example values: `京都三日` ("Kyoto in three days"), `京都` ("Kyoto"), `上海` ("Shanghai"), `日语` ("Japanese"). Yen and yuan share the ¥ sign, so the example writes the yen as `JP¥`.

| Field | Description |
| --- | --- |
| `id` | Plan document ID. Shared sync and backup import both check it. Use a new ID for every trip (e.g. `kyoto-2031-v1`). |
| `appName` | Home screen name, page titles, notification titles, Live Activity name. |
| `destination.name` / `nameEn` | Chinese name / English name, used in copy and map search. |
| `destination.countryCode` | ISO 3166-1 two-letter code. Map search only accepts results from this country/region. |
| `destination.addressSuffix` | Appended to map search terms and to the end of "Copy English address"; usually the city name. |
| `destination.postcodePattern` | Optional regex for the postcode in English addresses, e.g. Japan `\\d{3}-\\d{4}`. |
| `timezone` | IANA time zone name. Every itinerary time in the app is interpreted in this time zone, regardless of the phone's current time zone. |
| `startDate` / `endDate` | First and last day of the trip. The number of days is derived from them (1–60 days), and `itinerary.json` must match day by day. |
| `departureDate` | The day you leave home. A red-eye flight may leave before `startDate`; the countdown and hotel check-in dates may start from this day. |
| `homeCity` | Departure city, used only in the Kit tab title "From X, to Y". If you'd rather not say, enter "home". |
| `partySize` | Number of travelers. Default headcount for tickets and reservations; restaurant booking observations must be queried for this headcount. |
| `currency` | `local` is the destination currency, `home` your home currency (ISO 4217). `homePerLocal` = how much home currency 1 unit of local currency is worth; it must carry a fetch date and source. |
| `map.center` / `span` | Default map center and span (latitude, longitude). |
| `map.bounds` | Valid coordinate range for the destination. Every coordinate must fall inside it; map search and route results are filtered by it too. Don't draw it too large, or identically named places in neighboring countries will creep in. |
| `speech.language` | Language for reading travel phrases aloud (BCP-47, e.g. `en-US`, `ja-JP`, `ko-KR`, `th-TH`); `label` is the language name shown in the UI. |
| `attributions` | Data sources and licenses shown on the About page (maps, photos, official data, etc.). |

## places.json

```json
{ "places": [ {
  "id": "harbor-light", "name": "港湾灯塔", "en": "Harbor Lighthouse",
  "zone": "北岸", "kind": "地标", "hours": 1, "budget": 0,
  "desc": "Why it's worth going", "tip": "How best to do it (actionable steps and time slots)",
  "travel": "How to get there", "rain": "What to do if it rains", "food": "What to eat nearby",
  "link": "https://official-page", "opening": "Opening hours (with a note on how they were checked)", "price": "Official price / planning budget",
  "bestTime": "Suggested time slot｜reason",
  "guides": [ … ],
  "sources": [ { "label": "Official page", "url": "https://…" } ], "checkedAt": "2030-04-01"
} ] }
```

Sample values: `港湾灯塔` ("Harbor Lighthouse"), `北岸` ("North Shore"), `地标` ("landmark").

| Field | Description |
| --- | --- |
| `zone` | Area name, used for grouping and itinerary planning (clustering by area). |
| `kind` | Free-text type, e.g. landmark / museum / neighborhood / viewpoint / nature / theme park. **`餐饮` (dining) is a reserved value**, generated automatically from `dining.json`; don't write it by hand. |
| `hours` | Suggested length of stay in hours (used when the itinerary doesn't specify a duration). |
| `budget` | Planned ticket budget per person, in local currency. Enter 0 if free. |
| `opening` vs `bestTime` | Opening hours are the operator's facts; the suggested time slot is your planning judgment. Keep them separate. |
| `price` | State clearly whether it's the "official price" or a "planning budget (with margin)"; don't mix the two. |
| `guides` | Optional in-depth guides: `{id, title, summary, updatedAt, sections:[{title, paragraphs[]}], links:[{label,url}]}`. |
| `sources` / `checkedAt` | Not included in the app build, but `verify_content.py` requires them on every place. |

## itinerary.json

```json
{
  "days": [ { "date": "2030-05-01", "title": "抵达与北岸", "area": "北岸 → 老城", "note": "Notes for the day",
              "items": [ { "uid": "d1-museum", "place": "maritime-museum", "time": "11:00",
                           "note": "", "durationMinutes": 120 } ] } ],
  "budget": { "flightOut": 0, "flightReturn": 0, "hotel": 600, "food": 300, "transport": 80, "other": 0 }
}
```

Sample values: `抵达与北岸` ("Arrival and North Shore"), `北岸 → 老城` ("North Shore → Old Town").

- `days` must correspond one-to-one with the dates in `trip.json`.
- `uid` is unique across the whole itinerary; **never change it after publishing** (shared sync uses it to merge changes from two phones).
- `place` can be any ID from `places.json` or `dining.json`.
- `time` may be an empty string (time TBD); `durationMinutes` may be omitted (the place's `hours` is used), and if present `time` is required.
- `budget` is the **total for the whole trip**: `flightOut` and `flightReturn` are in home currency, everything else in local currency. Users can edit it in the app.

## preparation.json

```json
{ "items": [ { "id": "arrival-card", "group": "出发前 3 天", "dueDate": "2030-04-27",
               "title": "电子入境卡", "summary": "One sentence",
               "body": ["How to do it…", "Done when: …"],
               "copy": "Template that can be copied with one tap (optional)",
               "links": [ { "label": "Official page", "url": "https://…" } ],
               "guideImage": "media/preparation/xxx.jpg" } ] }
```

Sample values: `出发前 3 天` ("3 days before departure"), `电子入境卡` ("e-arrival card").

- `group` groups items by "when to do it" (confirm now / 3 days before departure / pack on departure day / before leaving home / local notes / night before the return trip…); the app shows groups in the order they first appear.
- `dueDate` is optional: the Today tab starts reminding about the item on this date; omit it to mean "any time".
- Each `body` paragraph is at least one sentence; the last paragraph states the **done criteria**.
- Don't write personal information such as ID numbers, order numbers or phone numbers (the validation script blocks things that look like passport numbers).

## dining.json

See `content/dining.json` for structure and examples. Key points:

| Field | Values |
| --- | --- |
| `currency` | Must equal `trip.currency.local` |
| `directory` | Completeness anchor: `{edition, status, sourceURL, notes, counts?}`; `status` is `verified / partial / unverified` (the sample may use `sample`); when there are star ratings, `counts` holds the number of restaurants at each star level in the official list, and validation checks each count |
| `restaurants[].type` | `restaurant / foodCourt / stall / casual` |
| `restaurants[].depth` | `detailed` (full menu and booking) / `light` (basic info) / `directory` (listed in the directory only) |
| `award.kind` | `stars / bibGourmand / selected / none / unverified`; when not none, `year` must equal `directory.edition` and a source is required |
| `menus[].meal` | `breakfast / lunch / dinner / snack / allDay / both / any` |
| `menus[].basis` | `perPerson / estimate / perDish / perSet / perTable / marketPrice` |
| `menus[].tax` | `nett` (tax and service charge included) / `++` (added on top) / `unknown`; if `serviceChargePercent` or `taxPercent` is set it must be `++` |
| `menus[].price` | May be null, but the name or description must say whether it is "unverified" or "not published" |
| `pricingStatus` | `verified / estimate / unverified / unknown / notPublished` |
| `booking.availability` | `notChecked / unknown / notRequired / walkIn / available / full / soldOut`; `available/full/soldOut` require `observations` |
| `booking.observations[]` | `{date, meal, partySize, status, detail, checkedAt, sourceURL}`; `date` falls within the trip, `partySize` equals `trip.partySize`; `status` is one of `available / full / soldOut / waitlist / closed / notReleased / notChecked / unknown / blocked`; this is a **query snapshot** and must not be presented as real-time or as guaranteed availability |
| `closedWeekdays` | ISO weekdays: 1=Monday … 7=Sunday |
| `recommendations[]` | `{id, title, day (0-based trip day index), meal, restaurantIDs, reason}` |
| `guides[]` | `{id, title, summary, body[], restaurantIDs, sources[]}` |

Every restaurant automatically becomes a place with `kind: "餐饮"` (dining) and can go straight into the itinerary; put its coordinates in `coordinates` — no need to also add it to `locations.json`.

## hotels.json

- Top level: `checkIn`, `checkOut`, `adults`, `rooms`, `currency` (quote currency, usually your home currency) and `hotels[]`.
- Each hotel: `id, name, en, region, reason, notice, rating, address, coords [lat, lon], coordinateSource, source, checkedAt, policies[], transport[], photo {file, source}, rooms[], tier`.
- `rooms[].quote`: `{status, totalHome?, breakfast, cancel, confirmation, extraFees}`; `status` is `available / pending / unavailable`; `totalHome` is the **total price for the whole stay** (home currency), not nightly price × nights. Conditional deals are marked `pending`, without `totalHome`.
- Put issues such as windowless rooms or renovation in `notice`; the app displays it prominently.

## locations.json

```json
{ "attribution": "© OpenStreetMap contributors", "license": "ODbL-1.0", "checkedAt": "…",
  "locations": { "harbor-light": { "name": "Harbor Lighthouse", "address": "…",
                                   "coordinates": [20.018, -150.03], "source": "https://www.openstreetmap.org/way/…" } } }
```

Coordinates are reference points, not guaranteed entrances; they must be inside `trip.map.bounds`. The English `name` / `address` are used by "Copy English address" for drivers or ride-hailing apps.

## photo-sources.json

```json
{ "albums": { "harbor-light": { "photos": [ {
  "file": "media/photos/harbor-light-1.jpg", "caption": "Caption", "sourceUrl": "https://commons.wikimedia.org/…",
  "creator": "Author", "license": "CC BY-SA 4.0", "licenseUrl": "https://…", "date": "Date taken",
  "downloadUrl": "https://upload.wikimedia.org/… (optional, for build_photos.py to download)" } ] } } }
```

`scripts/build_photos.py --download-missing` downloads originals that have a `downloadUrl` (the cache directory is not committed), compresses them to at most 1200 px on the long edge and under 180 KB, strips metadata, and writes them to `file`. The first photo also produces the cover thumbnail.

## posts.json

```json
{ "posts": [ { "id": "…", "platform": "xiaohongshu", "title": "…", "author": "…", "date": "Date shown on the platform",
               "heat": "Likes/saves snapshot", "url": "https://…", "capturedAt": "2030-04-01",
               "categories": ["整体" | "目的地" | "拍照" | "酒店" | …], "summary": "A summary you write yourself",
               "body": "Original text (only with permission)", "images": [ { "file": "media/posts/<id>/01.jpg", "order": 1 } ],
               "guidePlaces": ["harbor-light"] } ] }
```

Sample `categories` values: `整体` ("overall"), `目的地` ("destination"), `拍照` ("photography"), `酒店` ("hotels").

- When `platform` is `xiaohongshu`, the app tries to open the original post in the Xiaohongshu app (`xhsdiscover://item/<noteId>`) and falls back to the browser.
- **Copyright**: don't put unauthorized original post images or text in a public repository. A private branch for personal use may keep them, but must retain the author, link and capture date.
- `images` needs at least one entry (it can be a cover you photographed or drew yourself); `order` is numbered consecutively from 1.

## phrases.json

```json
{ "sections": [ { "id": "restaurant", "title": "餐厅",
                  "items": [ { "native": "请结账。", "local": "お会計をお願いします。", "note": "Notes on local usage (optional)" } ] } ] }
```

Sample values: `餐厅` ("Restaurant"), `请结账。` (the traveler's-language version of "The bill, please.").

`local` is the destination-language text that gets read aloud; the speech language is set by `trip.speech.language`.

## references.json / flights.json

- `references`: `[{id, title, body, links:[{label,url}]}]`, for practical info such as transit cards, emergency numbers and tax refunds.
- `flights`: `[{id, number, from, to, departure, arrival}]`, with times in **each airport's local time**. Only write the flight number and times — no order numbers, ticket numbers, seats or fares.

## Validation and build commands

```bash
python3 scripts/verify_content.py                    # structure, references, coordinates, dates, enums, sources
python3 scripts/build_ios_resources.py               # generate app content
python3 scripts/verify_content.py --built-catalog    # confirm generated output is up to date
python3 scripts/verify_content.py --require-complete # release gate for a real trip: no sample text, example.com, 待核实 (to be verified) / TODO allowed
```
