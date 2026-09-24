# Travel Content Research Playbook

This playbook is for two kinds of readers: friends preparing content for a new trip, and the AI agents (Codex, Claude Code, etc.) doing the research for you. It turns practices that were repeatedly validated in a real trip project into a reusable method: where to look, how much verification counts, how to write it into `content/*.json`, how to self-check, and which pitfalls have already been hit.

The playbook covers only "how to research and how to write". For full field definitions see [content-schema.md](content-schema.md); for engineering and release experience see [lessons-learned.md](lessons-learned.md) and [ios-delivery.md](ios-delivery.md).

---

## Contents

0. [Before You Start](#0-before-you-start)
1. [General Evidence Rules](#1-general-evidence-rules)
2. [Itinerary Planning](#2-itinerary-planning)
3. [Places and Coordinates](#3-places-and-coordinates)
4. [Photos](#4-photos)
5. [Social Media Reference Posts](#5-social-media-reference-posts)
6. [Hotels](#6-hotels)
7. [Dining](#7-dining)
8. [Pre-Trip Preparation](#8-pre-trip-preparation)
9. [Attraction Guides](#9-attraction-guides)
10. [Travel Phrases](#10-travel-phrases)
11. [Routes and Maps](#11-routes-and-maps)
12. [Exchange Rates](#12-exchange-rates)
13. [Reference Information](#13-reference-information)
14. [Tools and Techniques](#14-tools-and-techniques)
15. [Final Pre-Delivery Check](#15-final-pre-delivery-check)

---

## 0. Before You Start

### 0.1 Pin down the constraints first

Get this information before researching. If anything is missing, write it in the research record as "pending user confirmation" — do not assume.

| Constraint | Used for | Where it goes |
| --- | --- | --- |
| Destination, departure city, travel dates | Opening calendars, season, sunset, public holidays | `trip.json`: `destination`, `startDate`, `endDate`, `departureDate`, `homeCity` |
| Party size, age groups | Price basis (adult/child), reservation headcount, hotel occupancy | `trip.json`: `partySize`; `hotels.json`: `adults`, `rooms` |
| Outbound/return flight times and terminals | Earliest start on the first day, latest finish on the last day | `flights.json` (flight numbers and times only) |
| Daily rhythm: wake-up time, time out the door | Time of the first stop each day | Research record; affects `itinerary.json` |
| Interests and no-gos | Which places to keep, dining preferences, stamina limits | Research record |
| Hotel already booked or not | First/last-leg transport estimates, resting nearby | `hotels.json`; if not booked, note in the itinerary that "first/last legs are estimated from the city center" |
| Local time zone, currency | Date conversion, budget, exchange rate | `trip.json`: `timezone`, `currency` |
| Map extent | Out-of-bounds coordinate check | `trip.json`: `map.bounds` |

Fill in `trip.json` first, because `scripts/verify_content.py` uses `startDate..endDate` to check the number of itinerary days and `map.bounds` to check every coordinate.

### 0.2 Start a research record for the day

Open a record for each research session under `docs/research/`, named `YYYY-MM-DD-topic.md`, copied from the [research-record.md](../templates/research-record.md) template. The record should answer: which pages you looked at, when, what you concluded, whether there were conflicts, which fields you changed, and what comes next. Everything written into JSON should be traceable to a source in some record.

### 0.3 Workflow overview

```text
Confirm constraints → research by content type → write into content/*.json
        → python3 scripts/verify_content.py            (structural gate)
        → python3 scripts/verify_content.py --require-complete   (completeness gate for a real trip)
        → python3 scripts/build_ios_resources.py        (generate the App's bundled resources)
        → python3 scripts/verify_content.py --built-catalog      (confirm the generated output is up to date)
        → close out the research record (fields written, conflicts, next steps)
```

`--require-complete` rejects sample text, `example.com` links, placeholder words such as “待核实” (to be verified) / “TODO”, and content with coverage that is too thin. The bundled Kyoto example passes this gate; once you replace it with your own content, any leftover sample text or placeholder fails it.

---

## 1. General Evidence Rules

Every content type below follows this section. For situations not covered here, lean toward "better to say it's uncertain than to say it wrong".

### 1.1 Evidence grades

| Grade | Source | Can prove | Cannot prove |
| --- | --- | --- | --- |
| A | Operator's official website, government/public-agency pages, opened in a real browser with the content visible | Opening hours, prices, rules, closure notices, entry requirements | Live status on the day (unless the page itself is a live system) |
| B | Authoritative complete third-party lists (e.g. that year's full official Michelin list), official reservation systems | List completeness, honors, availability at query time | Menu prices (check the restaurant's own site), future availability |
| C | Booking platforms (Trip.com, Booking-type sites), map POIs (OpenStreetMap, Apple Maps, Google Maps) | Quotes for specific dates and headcount, address candidates, platform categories | Authoritative conclusions on official star rating or operating status |
| D | Travel guides, social media (Xiaohongshu, etc.), blogs | Photo spots, common aliases, what visitors care about, on-site experience | Prices, opening hours, rules, reservation conditions |
| X | Model memory, unopened search snippets, "I recall" | Nothing | Everything |

The rule is simple: **any fact written into JSON needs at least an A- or B-grade source**; C grade is only for data that can only come from platforms anyway, such as quotes and coordinate candidates, and must be labeled honestly with the platform's basis; D grade may only supplement "what to see, how to shoot it, what people call it".

### 1.2 What counts as "verified"

- **You must see the content in a real browser.** HTTP 200 does not mean you found it: many official sites are single-page apps, so a command-line fetch returns an empty shell; some old links return 200 and then redirect to a 404 page or the homepage. Neither counts as verified.
- **Click into dynamic content.** Operating calendars must be clicked day by day, collapsed FAQs expanded, prices selected down to a specific date and ticket type. Reading only the static part of a page often gives you default or stale values.
- **Look for the page's own date.** Find "updated on / Last updated / exhibition period / valid until". The copyright year in the site footer is not the content's year; you cannot infer "this is this year's list" from it.
- **Search snippets are not sources.** A snippet may come from an old version of the page, or even mix up different things. Example: a search snippet gave an address whose street name differed from the official site; the official site won.
- **A page proves only what it says.** A park being open 24 hours does not mean a separately ticketed garden inside it is open 24 hours; a neighborhood having "no fixed opening hours" does not mean its temples and shops are open all day; a building open until 22:00 does not mean a particular floor is open to the public until 22:00.
- **When fetching is blocked (403, CAPTCHA, security check)**, open it in a real browser instead; if it still won't open, record it as "could not be read" — never treat it as having found the current price. **Do not try to bypass CAPTCHAs or bot detection.**

### 1.3 Limits on secondhand sources

Guides and social media are very useful, but only for these purposes:

| Can be used to | Cannot be used to |
| --- | --- |
| Discover candidate places, photo angles, names visitors commonly use | Prove prices, opening hours, reservation rules |
| Add a searchable alias to a place (in `name` or `desc`) | Prove an exhibit is still running or a facility still open |
| Learn common pitfalls (queues, harsh sun, dress codes) | Prove rules such as "you can bring your own food" |
| On-site photographed prices as a dining reference (clearly labeled as historical photos) | Stand in for today's menu prices |

Rule-like claims in old posts ("you can bring snacks", "you can finish it in half a day", "you can always just queue on the day") must be labeled "personal experience / possibly outdated" when they conflict with official information; the official source wins.

### 1.4 Keep three kinds of numbers separate

Prices come in at least three bases; always say which one you mean:

| Basis | Meaning | Example (`places[].price`) |
| --- | --- | --- |
| Official price | Price for a specific ticket type shown on the official site that day | `Official ticket JPY 1,300/person (adult, general admission)` |
| Planning budget | Amount set aside for the overall budget; may be higher than the official price | `Official ticket JPY 1,300/person; planning budget JPY 1,500 for margin` |
| Estimate | Editor's estimate when there is no official price | `Day pass budgeted at JPY 1,100/person; not the actual price for the day` |

- `places[].budget` is the per-person planning budget (local currency) used for budget totals, not a statement of ticket price.
- Do not mix resident prices, member prices, multi-attraction bundles, night tickets, or express passes into the standard admission price.
- A "from" price seen without selecting a date is only a starting price; to state a specific price, select the travel date, headcount and ticket type.
- Small price fluctuations don't need a warning; only information that affects whether you can go at all (reservation required, zone closed, guests only) needs to stand out.

### 1.5 Suggested time and opening hours are two different things

- `opening` holds the operator's opening information: hours, last entry, closing days, special dates.
- `bestTime` holds the editor's suggestion: when it's best to go and why (light, crowds, avoiding heat).
- They are displayed separately; do not turn "suggested 16:00–18:30" into "open 16:00–18:30".
- Visit durations, walking and waiting times in the itinerary are planning estimates — not operator commitments and not live navigation results.

### 1.6 Every fact must be traceable

- Every place, menu, reservation observation and hotel quote carries `checkedAt` (verification date, `YYYY-MM-DD`) and a source URL.
- Use a specific page as the source URL (ticket page, opening-hours page, menu PDF), not just the site's homepage.
- When several pages state the same fact, use the most direct one; when they conflict, record both in the research record (see 1.13).
- Sources must be `https` links; `verify_content.py` checks this.

### 1.7 Snapshot wording

Anything that can change must be worded as "this is what a query on a given day showed":

| Don't write | Write |
| --- | --- |
| Available / seats left | At query time, 18:30 and 19:00 showed tables for two; this is a snapshot, not live availability |
| Sold out | At query time, no bookable slots were shown for the selected date |
| Open | Official site (as of verification date) shows 10:00–18:00, last entry 17:00 |
| Free | Official site states standard hours are free; special events are ticketed separately |
| Cheapest | Under (dates, headcount, rooms), the lowest total stay price shown by the platform |

For any historical observation, avoid words like "live", "guaranteed" or "definitely". `verify_content.py` blocks phrases such as “实时有位” (seats available in real time) / “保证有位” (seat guaranteed) in reservation observations.

### 1.8 Make uncertainty visible to the user

- Information that is uncertain, conditional, reservation-only or partly closed must be visible in the UI: **color + icon + text** together, never color alone (color can fail for color-blind users, in dark mode, or when a screenshot is forwarded).
- The conventional levels:
  - Red: definitely closed, unavailable, or will result in a wasted trip.
  - Orange: reservation required, price or conditions unconfirmed, only partly open.
  - Normal: ordinary planning estimates, small price fluctuations.
- Write the qualifying conditions directly into the field text (e.g. `opening` says "subject to on-site notices during thunderstorms or special events") rather than relying on the UI to infer them.

### 1.9 No irreversible actions

Research is **read-only**:

- When checking hotel quotes you may go as far as the "enter guest details" step to see the total price, taxes and cancellation policy, then stop. Do not enter personal information, submit an order, pay, or claim coupons.
- When checking restaurant reservations, only choose date, meal period and headcount, look at the returned slots, then stop. Do not click confirm, enter information, or hold a table.
- Do not submit any form or send emails, DMs or inquiries; when a hotel, attraction or restaurant needs to be contacted, **draft the text** for the user to send themselves.
- Do not accept platform agreements or grant any authorization beyond cookies; on cookie banners choose the minimum necessary.
- Never enter ID numbers, bank card numbers or passwords anywhere. The user logs into platforms that require login themselves.

### 1.10 Don't fabricate

- No verified coordinates, no coordinates — do not make up a pin from a district or city center.
- No properly licensed photo, no photo — do not pass off photos from elsewhere, of a same-named place, or old photos.
- A failed query does not mean sold out, closed, or nonexistent.
- If you can't find a suitable post, do not pad with a wrong or promotional one.
- Do not invent street numbers, postal codes, phone numbers or opening hours.

### 1.11 Stable IDs

- `places[].id`, `restaurants[].id`, `hotels[].id`, `preparation.items[].id`, and every `uid` in `itinerary` must never change once published. Photos, favorites, itinerary references and checked states all hang off IDs.
- IDs use lowercase letters, digits and hyphens (`verify_content.py` checks the format).
- When a place is renamed or gets a more accurate Chinese name, change `name`, not `id`.
- When something is no longer recommended, prefer removing it from the itinerary or explaining in the copy; do not delete an ID and then reuse the same ID for something else.

### 1.12 Content updates don't touch user state

- `content/*.json` is the **default content bundled into the App**. Itineraries users edited in the App, prep items they checked off, and tickets they saved live in the local workspace on the device and in the (optional) sharing service.
- New content versions only affect installs that don't yet have a local workspace; for users who have already edited, the default itinerary is not overwritten. This is by design: fixing a recommended order must not wipe out an itinerary the user arranged themselves.
- So if a content change is something users need to know about (e.g. an attraction is temporarily closed), write it into the place's `opening`, `notice` or similar text so users see it when they open the details, rather than editing their itinerary.
- Never write real private data (order numbers, shared itinerary contents) into `content/`.

### 1.13 Record conflicts; don't guess

When two sources disagree:

1. Record both in the research record, with each URL and the time it was read.
2. Where you can decide, prioritize: the operator's own page > third-party pages; specific page > overview page; dated > undated.
3. Where you can't decide, write the conservative version in JSON and prompt the user to verify.

Typical conflicts already encountered:

- The restaurant's site says "dinner Monday to Saturday" while a food guide page says "closed Monday": only days both sides agree on are written as definitely closed; Monday keeps a "reconfirm before departure" note.
- The site's homepage says "autumn menu" but the menu link still opens the summer menu: summer prices are not treated as verified prices for the travel season.
- The official "last entry time" differs from a later slot that appears in the reservation system: the final confirmation wins, and the note says so.
- The top of an attraction page says "reservations available" while a leftover line further down says "reservations closed": record it as a contradiction and suggest the user ask the operator first.
- A menu PDF doesn't say whether it's lunch or dinner: set `meal` to `any` and prompt to check when reserving.

### 1.14 Fewer but right

- Gaps are acceptable at release, but they must be honest: "price not verified this round" is written as `pricingStatus: unverified`, not a guessed number.
- "Couldn't find a suitable photo" and "found one but the license isn't suitable" are two different situations; record them separately in the research record.
- Coverage targets (e.g. 3 reference posts per place) are goals, not quotas; if you can't meet them, state the gap and why.

### 1.15 Privacy

- Do not write ID numbers, order numbers, ticket numbers, pickup codes, membership numbers, phone numbers or email addresses. `flights.json` holds only flight numbers and times.
- Do not write travel companions' real names.
- Crop personal information from evidence screenshots; don't paste private order screenshots into research records.
- For templates such as hotel emails and arrival-card field lists, write personal information as `[placeholder]`.

---

## 2. Itinerary Planning

### Target fields

`itinerary.json`:

- `days[]`: must map one-to-one, day by day, to `startDate..endDate` in `trip.json`.
- `days[].date`, `title` (the day's theme), `area` (direction across districts, e.g. "North Shore → Old Town"), `note` (overall notes for the day, explaining trade-offs).
- `days[].items[]`: `uid` (unique across the whole itinerary, never changed after publishing), `place` (references an ID in `places` or `dining`), `time` (`HH:mm`, or an empty string meaning time TBD), `durationMinutes`, `note`.
- `budget`: `flightOut`, `flightReturn`, `hotel`, `food`, `transport`, `other`.

### Source priority

1. Hard constraints given by the user (flights, wake-up time, items already booked).
2. Each place's official opening hours, last entry, closing days, special dates (day-by-day calendar).
3. Local sunset times and climate averages (official meteorological agency).
4. Transport estimates (planning values from map services, estimates only).

### Steps

1. **List constraints and split them into hard and soft.**
   - Hard: flight arrival/departure, reservation-only slots, fixed showtimes (e.g. a performance at set times), closing days, last entry, the latest time to head back to the airport.
   - Soft: suggested times, photo light, mealtimes, stamina.
   - Hard constraints set the skeleton; soft constraints only adjust within it.
2. **Cluster by district.** Group candidate places by area first (recorded in `places[].zone`), and cover only one or two adjacent districts per day to avoid crisscrossing the city.
3. **Set each day's start and end.**
   - First day: work backward from landing time + immigration + getting to the hotel; for late-night or early-morning arrivals, leave the first morning empty.
   - Other days: start from the user's time out the door (e.g. if they leave at 11:00, don't put something that opens at 9:00 as the first stop and assume they'll get up early).
   - Last day: work backward from departure time to when they must leave for the airport (check-in, security, transport, buffer); the last item must end before that point, with margin.
4. **Order stops and leave buffers.**
   - Leave 15–45 minutes of transit time between adjacent stops (depending on distance and mode of transport).
   - Put indoor activities or rest in the hottest, most tiring hours around noon and afternoon.
   - Keep planned activity time to roughly 7 hours a day; if it runs over, cut items rather than compressing transit.
5. **Daylight rule.** Landmarks where the user wants daytime photos must be scheduled before sunset; night views are scheduled separately. Don't substitute a night shot for a daytime photo the user explicitly wants. If the first day's shot is missed due to weather, offer a "reshoot in daylight the next day" adjustment.
6. **Rainy-day swaps.** Every outdoor item gets an indoor alternative **in the same district** in `places[].rain`; don't make users cross the city when it rains.
7. **Replace wholesale, don't stack.** For items that take a whole day (theme parks, day trips out of town), choosing one replaces that entire day rather than being stacked onto the original district. State in `desc` or `tip` "choosing this cancels X".
8. **Write `note`.** Each day's `note` explains the trade-off logic and "which item to drop first if you're tired".

### Checks and validation

`verify_content.py` automatically checks:

- The number of days matches `trip.json`, `uid`s are unique and well-formed, and `place` references exist.
- `time` is `HH:mm` or empty; if `durationMinutes` is set, a start time is required.
- Times increase through the day, adjacent items don't overlap (using `durationMinutes`, or the place's `hours` if absent), and the daily planned-time cap (warning).

Then check manually:

- [ ] Arrival at every stop falls within that place's opening hours and before last entry.
- [ ] No closing days are scheduled (check day by day, especially Mondays, public holidays and special event days).
- [ ] The end of the last item on the last day leaves enough margin for the return trip.
- [ ] Daily activity time is within about 7 hours (adjust for actual stamina).
- [ ] For fixed-showtime items (performances, guided tours), arrive 15–20 minutes early and allow time to leave.
- [ ] Every outdoor item has a same-district rainy-day alternative.
- [ ] Items requiring reservations say so in `tip` or `opening`, and have a matching item in pre-trip preparation.

### Common pitfalls

- Scheduling a "suggested time" as "opening hours", so the user thinks that's the only time they can go.
- Assuming a neighborhood walk is open all day, when its places of worship can only be entered at certain times and have dress codes. Write it as "exterior only; for entry, check visiting hours and dress code separately".
- Assuming a beach is swimmable: outside lifeguard hours, or when authorities issue safety advisories, schedule only onshore activities.
- One park complex with several separate venues, each with different opening and last-entry times.
- A park with different weekday and weekend hours, or early closing on certain days — change the date and you must recheck the calendar.
- Writing a transport estimate as "takes 20 minutes" instead of "about 20 minutes (planning estimate)".

### Done criteria

- [ ] `verify_content.py` has no errors; time-order, overlap and duration warnings have each been handled or explained in the research record.
- [ ] Every day has `title`, `area` and `note`; `note` states the trade-offs and what can be dropped.
- [ ] All hard constraints are satisfied, with the verification basis listed in the research record.
- [ ] The first and last days have been checked against flight times.

---

## 3. Places and Coordinates

### Target fields

`places[]` in `places.json`:

| Field | What to write |
| --- | --- |
| `id` | Stable ID, never changed after publishing |
| `name` / `en` | Chinese name (prefer the name visitors actually search for) / English or local official name |
| `zone` | District, used for clustering and filtering |
| `kind` | Type (landmark, museum, neighborhood, viewpoint, nature, theme park…) |
| `hours` | Suggested visit length in hours (planning estimate) |
| `budget` | Per-person planning budget in local currency; 0 if free |
| `desc` | One-line reason to go: why it's worth it, who it suits |
| `tip` | Actionable advice and limits: how to get around, how to shoot, whether reservation is needed, any restrictions |
| `travel` | How to get there (planning estimate) |
| `rain` | Same-district rainy-day alternative |
| `food` | What to eat nearby |
| `link` | Official page |
| `opening` | Official opening information (including last entry, closing days, closure notices) |
| `price` | Price basis (see 1.4) |
| `bestTime` | Suggested time and why |
| `guides` | Optional, structured guide (see section 9) |
| `sources` | `[{label, url}]`, at least one |
| `checkedAt` | Verification date |

`locations.json`:

- File level: `attribution` (data source and credit, e.g. `© OpenStreetMap contributors`), `license` (e.g. `ODbL-1.0`), `checkedAt`, `notes` (state that "coordinates are reference points, not guaranteed to be entrances").
- `locations.<placeId>`: `name`, `address`, `coordinates` (`[latitude, longitude]`), `source`.

### Source priority

- Place content: operator's official site > destination tourism board / government agency pages > others.
- Candidate discovery: tourism board "must-do list" pages (for coverage screening, not as a popularity ranking), guides and social media (for photo spots and aliases).
- Coordinates: OpenStreetMap candidates + spot checks against the local official survey / mapping agency > address on the operator's page > map apps.

### Steps: place content

1. **Cast a wide net for candidates.** Tourism board theme pages, official category lists, popular guides, social media — list candidates and label each source type. Having many candidates doesn't mean all go into the itinerary; for either-or items (e.g. two similar viewpoints), say so in `desc`.
2. **Open each official site and verify.** Opening hours, last entry, closing days, prices (selected down to a specific date and ticket type), reservation requirements, current closure or maintenance notices, exhibition periods.
3. **Look for restrictions.** Guests only, reservations only, only for a certain restaurant's customers, age limits, dress codes, prohibited items, a zone closed, construction detours, weather suspensions.
4. **Write the copy.** `desc` says in one sentence why to go; `tip` gives concrete actions and limits; don't dress up an ordinary mall or café as a "must-visit".
5. **Fill in `sources` and `checkedAt`.**

### Steps: coordinates

1. **Find candidates in OpenStreetMap by name, type and address.** Use the Nominatim web page or an Overpass query, comparing the name (Chinese/English/local language), feature type (`tourism=attraction`, `amenity=restaurant`, etc.) and address together.
2. **Reject wrong matches.** Common wrong candidates: same-named metro stations, bus stops, parking lots, parcel lockers, same-named hotels, travel agencies, some minor facility inside the attraction. Reject anything whose type doesn't match.
3. **Spot-check a subset.** Use the public map or search service of the local official survey/mapping agency to check a few key places (especially newly opened, relocated, or poorly tagged in OSM).
4. **Country filter.** For border cities or places sharing names with a neighboring country, check that the candidate's country/region code matches `destination.countryCode` in `trip.json`, and reject same-named results across the border.
5. **Bounds check.** All coordinates must fall inside `map.bounds` in `trip.json` (`verify_content.py` checks this). Out-of-bounds points usually mean the wrong same-named place was picked.
6. **Write attribution and license.** When using OSM data, write `© OpenStreetMap contributors` and `ODbL-1.0` at the file level of `locations.json`, and keep the attribution in the App's "About".
7. **Don't guess.** Items without a definite address (e.g. places not open to the public, rest blocks) get no coordinates; better for the map not to show that stop.

### Checks and validation

- [ ] `verify_content.py`: sources are `https`, `checkedAt` is valid, coordinates are within bounds, every ID in `locations` maps to a place.
- [ ] `--require-complete`: every place has coordinates (any without must be explained in the research record, with a decision on whether to accept that gate failure).
- [ ] Spot-check 3–5 coordinates: open them in a map app and confirm they land on the right building or area.
- [ ] Times in every `opening` match the pages the `sources` links point to.

### Common pitfalls

- The reference coordinate of a large building or complex is its geometric center, which may not be near any entrance, and walking routes may fail to compute. State in `notes` that "reference points are not guaranteed to be entrances".
- The same place has an old and a new address (relocation, new campus), and old guides still use the old one.
- A map app marks a place as "permanently closed": that is just the map's label at the time — confirm through official channels; don't write it into the copy as fact.
- A search snippet's address ("New Town / Such-and-such Avenue") doesn't match the official site's street name — the official site wins.
- Chinese names vary wildly: pick the name visitors use most, and put other names in `desc` for searchability.

### Done criteria

- [ ] Every place has an A-grade source and `checkedAt`.
- [ ] Every place has `rain` and `bestTime`; reservation needs or restrictions are written in `tip` / `opening`.
- [ ] All coordinates come from traceable sources, with file-level attribution and license in place; no pins generated out of thin air.
- [ ] The research record lists rejected candidates and why (at least for easily confused places).

---

## 4. Photos

### Target fields

`albums.<placeId>.photos[]` in `photo-sources.json`:

| Field | What to write |
| --- | --- |
| `file` | Path in the repo, e.g. `media/photos/<placeId>-1.jpg` (relative to `content/`) |
| `caption` | What the photo shows; if only the exterior, say "exterior" |
| `sourceUrl` | The original file page (not a thumbnail URL) |
| `creator` | Author (written exactly as the source page's attribution requires) |
| `license` | License name, e.g. `CC BY-SA 4.0` |
| `licenseUrl` | License link |
| `date` | Date taken (as labeled on the source page) |
| `downloadUrl` | Optional, original download URL; the photo processing script uses it to download the original into a local cache |

### Source priority

1. Openly licensed image libraries such as Wikimedia Commons (CC0, CC BY, CC BY-SA; mind the ShareAlike obligation of SA).
2. Material the operator explicitly permits for media use (you must see written license terms).
3. **Do not use**: official-site photos marked All Rights Reserved, social media images, search engine images, hotel platform galleries — unless you have permission. Official material you found but whose license isn't suitable is listed for the user to decide, not used by default.

### Steps

1. Search Commons by place name, English name and local-language name, and also browse the corresponding Category page.
2. **Inspect each image visually.** Open every one at full size; don't batch-pick from thumbnails.
3. **3 per place, from different angles**: distant/panoramic, close-up/detail, a representative scene. If all three would be similar angles, use fewer.
4. **Exclude these images:**
   - Composites, promotional images with added effects/text/borders in post-processing, collages.
   - Outdated scenes: old versions of shows, demolished or remodeled facilities, pre-relocation sites.
   - Areas ordinary visitors can't enter: guests-only facilities, staff areas, interiors needing special permission.
   - A closed zone as the main image (implies "you'll see this if you go").
   - Other places with the same name (a same-named attraction in another country, a same-named street in another city).
   - Poor quality, unclear subject, prominent watermarks.
5. **Label video frames.** For frames extracted from Commons videos, note "video frame" in `caption`; don't pass them off as original photographs.
6. **Say when it's exterior only.** For private buildings and institutions where only the exterior can be photographed, `caption` says "exterior of X building; not the interior", without implying entry is possible.
7. **Download originals to a local cache.** Write `downloadUrl` in the entry and run `python3 scripts/build_photos.py --download-missing`: originals are downloaded to a cache directory outside git (default `.photo-cache`), and only processed files are written to the entry's `file` path (`content/media/photos/`). See `--help` for the script's exact options.
8. **Process the images.** The script's processing rules:
   - Rotate upright according to EXIF orientation.
   - Strip metadata (EXIF, GPS), keeping only pixels.
   - Long edge at most 1200 px, each JPEG at most about 180 KB (lower quality first; once quality hits the floor, reduce dimensions).
   - Compute SHA-256 of processed files and deduplicate across the whole library; duplicates are an error.
   - Space out download requests and send a clear User-Agent, to be polite to the image library.
9. **Write the source fields**, complete for every photo.

### Checks and validation

- [ ] `verify_content.py`: file exists; `creator`, `license`, `licenseUrl`, `sourceUrl` all present.
- [ ] Open each album in the App and confirm every photo loads and the attribution displays correctly.
- [ ] The research record lists excluded candidates and reasons for each place.

### Common pitfalls

- Assuming everything on Commons is free to use: CC BY-SA requires attribution and ShareAlike, and some files carry extra notes on personality rights, trademarks or freedom of panorama — check each one.
- Picking a beautiful night shot that turns out to show the place years ago, before it was rebuilt.
- Picking a photo of an "extra ticket required" area, so users think a standard ticket gets them in.
- Photos that actually show a same-named place in another country.
- Originals committed to git, bloating the repo; originals belong only in the local cache.

> A photo only proves "this is what it looked like when it was taken", not that you can enter now, that it's still open, or that the scene hasn't changed.

### Done criteria

- [ ] Every photo has complete source, author, license and date taken, and has been visually reviewed by a human.
- [ ] Every place with an album has 1–3 photos (target 3), from different angles, no duplicates.
- [ ] All processed files meet the size and file-size requirements, have no metadata, and have unique SHA-256s.
- [ ] No images with unclear licensing.

---

## 5. Social Media Reference Posts

Real travel posts on social media (Xiaohongshu, etc.) tell you "how others actually did it, where they shot, what went wrong". They are D-grade sources and involve copyright, so there are more rules here than for other content.

### Target fields

`posts[]` in `posts.json`:

| Field | What to write |
| --- | --- |
| `id` | Stable ID (may be derived from the platform's post ID, but must satisfy the ID format) |
| `platform` | Platform, e.g. `xiaohongshu`, `web` |
| `title` | Original post title (verbatim) |
| `author` | Author name as shown on the platform |
| `date` | Date as shown on the platform; an "edited on" date must not be recorded as the first-published date |
| `heat` | Engagement snapshot, stating it's the count at capture time; only write a number if the platform explicitly shows one |
| `url` | Original post link |
| `capturedAt` | Capture date |
| `categories` | Categories, e.g. `整体` (overall), `拍照` (photography), `目的地` (destination), `酒店` (hotel), `餐饮` (dining) |
| `summary` | An editorial summary **you write yourself**, not copied from the original |
| `images` | `[{file, order}]`, `order` numbered consecutively from 1 |
| `guidePlaces` | IDs of places this post actually covers |

### Copyright and permission (most important)

- **A public repository must not contain post images or body text without permission.** The template is a public repository, so by default it keeps only: title, link, author, date, your own summary, and images you have the right to use (your own photos, your own drawings, explicitly licensed).
- Even in a fork for private use, save original images byte-for-byte only **with explicit permission**, and never make such a fork public.
- Don't copy the post's body into `summary`. Keep the summary short, in your own words, explaining what the post is useful for in planning.

### Source priority (choosing posts)

1. Recent (within a year before the trip), from people who actually went, with concrete routes and real photos.
2. Posts that add what official sources don't: shooting spots, queue experience, walking routes, on-site conditions.
3. High engagement doesn't mean accurate; **accurate > popular**.

### Steps

1. **Read the full original post in a real, logged-in browser.** The user logs into the platform account themselves. Search result cards and thumbnails cannot stand in for the original post.
2. **Read the body and all images.** Go through them in carousel order, noting which images correspond to which place.
3. **Decide whether to include it**, using the exclusion criteria below.
4. **Write the record.** Title, author, date (verbatim), link, engagement snapshot, capture date, categories, your own summary, linked places.
5. **Images (only with permission):**
   - Save in carousel order, `order` consecutive from 1.
   - Exclude avatars, comment-section images, ad images, and duplicate copies within the carousel.
   - Save the original files served by the platform — no recompression, cropping, watermark removal or added text; record each file's byte size and SHA-256.
6. **App deep links.** A Xiaohongshu post can be opened in the App via `xhsdiscover://item/<noteId>` (`noteId` is the last path segment of the original post URL), falling back to the web link if that fails. In the template, `ExternalLinks.swift` implements this policy. Being able to issue the open request does not mean it opened successfully in the target App; verify separately on a real device.

### Coverage targets (adjust per trip)

- Overall guides: about 5, covering different paces (lazy, slow travel, packed).
- Each major place: about 3 guides; 1–3 for photography.
- Hotels: 1 actual-stay post per candidate hotel (linked only to that exact property; different branches of the same brand can't be mixed).
- Anything not met is listed in the research record with the gap and reason ("search results were mostly ads / places confused / incorrect content").

### Exclusion criteria (with examples)

| Reason for exclusion | Example |
| --- | --- |
| Geographic error | A hand-drawn map with wrong directions and distances between attractions |
| Factual error | Calling a paid observation deck free; naming the wrong metro station |
| Outdated | An old festival theme superseded by newer posts; old prices since raised; a pre-relocation site |
| Confused places | Treating two adjacent stalls, or two same-named shops, as one |
| Conflicts with official info and adds no value | Advice on getting around park restrictions or evading rules |
| Ads / advertorials | Promotes a product throughout with no actual travel content |
| Video post passed off as image post | Video content can't be included as an image/text post |
| Just padding | Generic "top 10 must-visit" lists |

### Checks and validation

- [ ] `verify_content.py`: unique IDs, `https` URLs, valid `capturedAt`, `images.order` is 1..n, files exist, `guidePlaces` references are valid.
- [ ] Each original post is included only once (a travelogue spanning several places is stored once and linked to multiple places via `guidePlaces`; don't inflate the post count with link counts).
- [ ] When there are images, check each one: byte size, SHA-256, order, no duplicate source URLs.

### Common pitfalls

- **Duplicate frames from Live Photos.** For a Xiaohongshu Live Photo, the first image appears in the page as two image nodes — the player's still frame and the overlay's still frame — whose URLs differ only in protocol (`http://` vs `https://`). Bulk capture saves the same image twice. Fix: take only the first image of each carousel item; when validating, strip the protocol from URLs before deduplicating.
- Recording "edited 07-25" as the publish date.
- Writing the post's prices or opening hours into place data as new facts. Prices and rules in a post belong only to the original author's experience.
- Padding "portrait references" with shots of people's backs, staff, or animal close-ups.
- Turning the author's "family trip" or "student ticket" experience into a general rule.

### Done criteria

- [ ] Every included post was read in full, and every summary is your own writing.
- [ ] The public repository contains no unlicensed post images or body text.
- [ ] Coverage and gaps are written in the research record.
- [ ] No prices, opening or reservation information from posts has entered the official place data.

---

## 6. Hotels

### Target fields

`hotels.json`:

- File-level query conditions: `checkIn`, `checkOut`, `adults`, `rooms`, `currency` (quote currency).
- `hotels[]`: `id`, `name`, `en`, `region`, `reason` (why recommended), `notice` (prominent warning: windowless, renovation, conditions), `rating` (platform rating, written verbatim on the platform's basis), `address`, `coords`, `coordinateSource`, `source`, `checkedAt`, `policies` (check-in/check-out times, deposit, front desk), `transport` (distance to transit stops, stated as platform distance), `photo` (`{file, source}`), `rooms[]`, `tier`.
- `rooms[]`: `name`, `area`, `bed`, `view`, `quote`.
- `quote`: `status` (`available` / `pending` / `unavailable`), `totalHome` (total for the whole stay, in home currency), `breakfast`, `cancel`, `confirmation`, `extraFees`.

### Source priority

1. The booking platform's "enter guest details" page under fixed query conditions (final price breakdown).
2. The hotel's official site (room types, policies, facilities, renovation notices).
3. The platform's hotel detail page (address, coordinates, platform category, policies).

### Steps

1. **Fix the query conditions.** Check-in date, number of nights, adults, rooms, currency — written into the file-level fields. Every quote must use the same set of conditions. For late-night/early-morning arrivals, check-in starts the previous day (and is charged per night).
2. **List candidates.** Filter by district and budget tier; write `region` and `tier`.
3. **Check room types one by one.** On the platform, select a specific room type and rate plan, go to the "enter guest details" page, and read:
   - The total-stay price breakdown (including taxes), not the per-night price on the list page.
   - Breakfast, cancellation policy (free-cancellation deadline, penalty after that), confirmation method.
   - Occupancy limits (some cheap plans allow only 1 guest).
   - Eligibility limits (some plans don't apply to certain nationalities or ages).
   - **Stop** at this step: no personal information, no submission, no payment, no coupons.
4. **Write the quote.**
   - `totalHome` takes the total from the full-stay breakdown; **do not use per-night price × nights** (rounding, varying nightly rates and tax calculation all cause discrepancies).
   - For discounted prices, check the conditions: new-customer discounts, member prices, limited-time subsidies, coupons that must be claimed — if the conditions can't be confirmed, set `status` to `pending` and describe the conditions in `extraFees` or `notice`; such quotes **are excluded from price sorting**.
   - For plans paid in foreign currency at the property, or with a separate online guarantee deposit, state the currency and guarantee rules; converted prices are only a reference and are not sorted together with fixed totals.
5. **Check room-type facts.**
   - A platform's "diamonds" or "stars" are platform categories, not an officially certified star rating; write `rating` as the platform states it.
   - "Double or twin" does not guarantee a double. If the user requires a guaranteed double bed, such room types are not recommended.
   - Windowless rooms, uncertain views (a "View" in the hotel name doesn't mean the room has one), and ongoing renovation go into `notice`, displayed prominently.
   - City view vs sea view, and views in different directions, are different room types; don't mix them.
6. **Late-night arrival.** If the flight lands late at night, draft an email asking the hotel to hold the room and not mark it as a no-show, put it in the `copy` field of a pre-trip preparation item, and let the user send it. A platform page saying "held all night" does not constitute a written agreement with the hotel.
7. **Coordinates and photos.** Use the location published by the platform or official site, and write `coordinateSource`; photos must have usage rights (see section 4) — otherwise use the template placeholder image or leave it empty; never use platform galleries.

### Checks and validation

- [ ] `verify_content.py`: `available` quotes must have a positive `totalHome`; coordinates within bounds; `source` is `https` and has `checkedAt`; photo files exist.
- [ ] All quotes use the same query conditions (dates, nights, headcount, rooms, currency).
- [ ] Every `pending` has its reason written down.
- [ ] No hotel is labeled "sold out" because of a failed query or a conditional price.

### Common pitfalls

- The list price differs from the final page price: the final page breakdown wins, and note it in the research record.
- Forgetting the guarantee deposit: pay-at-property plans may place a separate hold that is released only several business days after check-out.
- Writing the platform's "300 m to the metro station" as "3-minute walk". Platform distance is not walking time.
- Looking only at a basic room's "double or twin" and recommending it to a user who requires a double bed.
- Ignoring renovation notices: some hotels have phased renovation notices at the bottom of the booking page that affect the experience.

### Done criteria

- [ ] Every quote comes from the final price page under the same query conditions, with `checkedAt`.
- [ ] All conditional prices are `pending` and excluded from sorting.
- [ ] Windowless rooms, renovation, non-guaranteed bed type, uncertain views and similar information are all in `notice`.
- [ ] No orders were submitted and no hotels were contacted; the late-arrival email is a draft.

---

## 7. Dining

Dining content is the easiest to get wrong: prices carry taxes and service charges, menus split between lunch and dinner, and reservation availability changes constantly. This is the most detailed section.

### Target fields

`dining.json`:

- File level: `version`, `checkedAt`, `currency`.
- `directory`: the completeness anchor — `edition` (list year), `status`, `sourceURL` (official complete list page), `notes`, `counts` (number per star level, e.g. `{"1": 30, "2": 8, "3": 3}`, must match the list).
- `restaurants[]`:
  - Identity: `id`, `name`, `en`, `zone`, `type`, `cuisines`, `address`, `coordinates` (`{latitude, longitude}`).
  - Honors: `award` = `{kind, stars, year, sourceURL}`.
  - Menus: `menus[]` = `{name, meal, price, priceMax, basis, tax, includes, sourceURL, checkedAt, serviceChargePercent, taxPercent}`.
  - Reservations: `booking` = `{url, policy, releaseRule, cancellation, availability, checkedAt, observations[]}`.
  - Reservation observations: `observations[]` = `{date, meal, partySize, status, detail, checkedAt, sourceURL}`.
  - Other: `hours`, `durationMinutes`, `closedWeekdays`, `closedDates`, `tips`, `sources[]` (`{title, url, checkedAt}`), `depth`, `checkedAt`, `pricingStatus`.
- `recommendations[]`: `{id, title, day, meal, restaurantIDs, reason}` (`day` is the zero-based itinerary day index).
- `guides[]`: `{id, title, summary, body, restaurantIDs, sources}`.

### Enum values

| Field | Allowed values | Meaning |
| --- | --- | --- |
| `type` | `restaurant`, `foodCourt`, `stall`, `casual` | Formal restaurant / multi-stall food court / single stall / casual dining |
| `depth` | `detailed`, `light`, `directory` | In-depth verification / light snack / listed only |
| `award.kind` | `stars`, `bibGourmand`, `selected`, `none`, `unverified` | Stars / Bib Gourmand / guide selection / none / unverified |
| `menus[].meal` | `breakfast`, `lunch`, `dinner`, `snack`, `allDay`, `both`, `any` | `any` is for when the source doesn't specify a meal period |
| `menus[].basis` | `perPerson`, `estimate`, `perDish`, `perSet`, `perTable`, `marketPrice` | How the price is measured |
| `menus[].tax` | `nett`, `++`, `unknown` | Included / added on top / not stated |
| `booking.availability` | `notChecked`, `unknown`, `notRequired`, `walkIn`, `available`, `full`, `soldOut` | Overall reservation situation |
| `observations[].status` | `available`, `full`, `soldOut`, `waitlist`, `closed`, `notReleased`, `notChecked`, `unknown`, `blocked` | Result of a single query |
| `pricingStatus` | `verified`, `estimate`, `unverified`, `unknown`, `notPublished` | Price verification status |

`recommendations[].meal` and `observations[].meal` may only use `breakfast`, `lunch`, `dinner`, `snack`.

### Source priority

1. **Completeness anchor**: that year's official complete list (e.g. the Michelin Guide's full-list article for that year, stating the publish date and the count at each star level).
2. The restaurant's official site: menu page, menu PDF, reservation page, notices (temporary closures, menu changes).
3. The reservation system linked from the restaurant's official site (TableCheck, OpenTable-type).
4. The food guide's dynamic restaurant directory (to check name, stars, address, cuisine).
5. The local tax authority's page (current consumption tax / VAT rate).
6. Snacks, food courts and markets: tourism board and operator pages; prices photographed on social media are only a historical reference.

### Steps

1. **Establish the completeness anchor.** Find the official complete list, record the publish date, author and count per star level, and write them into `directory`. Then filter the dynamic directory level by level and page through it, making sure every restaurant on the list is in `restaurants` (`depth: directory` counts as included). If the counts don't match, stop and find out why.
2. **Open every restaurant's page.** For each one on the list, open the food guide page and the official site, and check: name, stars (this year's, not carried over from last year), cuisine, current address (relocations are common), official site entry point.
3. **Restaurants with in-depth verification (`depth: detailed`):**
   - Find the official menus: lunch, dinner, vegetarian and tasting menus are separate, each its own `menus` entry with its own `sourceURL` and `checkedAt`.
   - PDF menus: extract the text first, then **look at the pages yourself** (layout, prices matched to dish names, service charge and tax in footnotes).
   - When a plain request is refused (HTTP 403), open the official site in a real browser, read the prices from a screenshot, and store the screenshot in research evidence (not in the product bundle).
   - For PDFs obtained via a third-party menu platform linked from the official site, check the menu's year and season; don't carry over search snippets or last year's prices.
4. **Taxes and service charges.**
   - `++` only means "charges added on top"; do not assume the service charge is any particular rate. Only fill `serviceChargePercent` when the official source states a specific rate.
   - Verify the tax rate on the local tax authority's page, write it into `taxPercent`, and keep the link in the research record.
   - If it's not stated whether tax is included, set `tax` to `unknown`; the UI must not say "definitely added on top".
5. **Special pricing.**
   - Set menus that the whole table must order, or menus with a two-person minimum, are noted in `includes`.
   - Banquets for many people (e.g. tables of 8–10) must not be divided by headcount and presented as a per-person price a party of two can order.
   - Unpublished prices get `pricingStatus: notPublished`; prices not found this round get `unverified` (which doesn't mean the restaurant doesn't publish them).
6. **Honors.**
   - Food courts and markets themselves don't carry stars; if no stall inside has an individually confirmed honor, `award.kind` is `none`.
   - Bib Gourmand and guide selections must not be written as stars.
   - A single stall's honor must be checked on that stall's own guide page and not extrapolated to the whole food court or market.
7. **Reservation observations (snapshots).**
   - Enter the reservation system via **the reservation link on the restaurant's official site**, choose only date, meal period and headcount (equal to `partySize` in `trip.json`), read the returned slots, then stop.
   - Write one `observations` entry per query: date, meal period, headcount, status, details (specific slots, area such as indoor/outdoor/bar), query time, source URL.
   - "Waitlist" and "no online slots" are two different statuses; "no online slots" also doesn't mean fully booked (it may be bookable by phone, or not yet released).
   - Query results are always snapshots: `detail` says "at query time it showed…", never "available" or "live".
   - Temporary closure dates found in notices go into `closedDates`; regular closing days go into `closedWeekdays` (ISO numbering: 1 = Monday … 7 = Sunday).
8. **Budgets for snacks and food courts.**
   - Use `basis: estimate` and `tax: unknown`, and write a range (e.g. one person, one meal: `price` 8 – `priceMax` 15).
   - Spell out the composition in `includes`: main dish reference + allowance for drinks/extras. The upper part is a budget allowance, not a measured quote.
   - Price boards photographed on social media can be a direct reference, but state that they are "listed prices photographed during a certain period", not prices on the travel day. Single stalls without direct evidence get no exact unit price.
9. **Recommendations.** `recommendations` gives candidates by itinerary day and meal period; `reason` explains the geographic and timing rationale ("walkable to the next stop"). **A recommendation does not mean a table is available**, and adding it to the itinerary does not mean it's booked.

### Checks and validation

`verify_content.py` checks: enum values, `https` sources, `checkedAt`, `observations` dates within the itinerary, headcount equal to `partySize`, no claims of live availability, and `directory.counts` matching the star counts; under `--require-complete`, `detailed` restaurants must have sourced prices (or `notPublished`) and a reservation link, and if there are starred restaurants, `directory.counts` is required.

Then check manually:

- [ ] The list count matches the official complete list, and every restaurant was opened.
- [ ] Entries that changed this year (gained/lost stars, newly listed, relocated) are updated, with no stale data carried over.
- [ ] No lunch card shows a dinner price.
- [ ] For all `++` prices: only treat as tax-inclusive when the official source states the rate.
- [ ] Every reservation observation comes from the reservation system linked on the restaurant's official site, and confirm was never clicked.

### Common pitfalls

- Inferring the list year from the site footer year.
- Writing a restaurant that was one star last year and two stars this year as one star.
- Writing "no online slots at query time" as "fully booked".
- Labeling a whole food court or market as an award winner.
- Treating `++` as a fixed-rate service charge.
- Extracting only the text from a PDF without looking at the layout, so prices and dish names get misaligned.
- Using menu prices from search snippets (often outdated).
- The official site says "open Monday to Saturday", the guide says "closed Monday", and one is simply picked (see 1.13).

### Done criteria

- [ ] `directory` states the official complete list's source, date and counts, and `counts` matches what's included.
- [ ] Every menu of a `detailed` restaurant has `sourceURL` and `checkedAt`, with lunch and dinner separate.
- [ ] All reservation information is timestamped snapshots, with no "live" or "guaranteed" wording.
- [ ] Unresolved prices and conflicts are listed one by one in the research record.
- [ ] Snack budgets are clearly marked as estimates.

---

## 8. Pre-Trip Preparation

### Target fields

`items[]` in `preparation.json`:

| Field | What to write |
| --- | --- |
| `id` | Stable ID; keep published IDs, since the user's check marks hang off them |
| `group` | Grouped by "when to do it": e.g. "confirm now", "3 days before departure", "pack on departure day", "before heading out", "local notes", "night before return" |
| `title` | One concrete task; important items get their own entry (plug adapter, data SIM, cash, transit card) |
| `summary` | One-line summary |
| `body` | Method + done criterion; the last paragraph starts with "Done criterion:" |
| `copy` | Optional, copyable template text (emails, field lists), with personal information written as `[placeholder]` |
| `dueDate` | Optional, the earliest date to handle it (`YYYY-MM-DD`, no later than the last day of the trip); empty means it can be done anytime |
| `links` | Official sources `[{label, url}]` |

`flights.json`: `flights[]` = `{id, number, from, to, departure, arrival}`, with times in each airport's local time (`YYYY-MM-DDTHH:mm`). Only flight numbers and times — no order numbers, ticket numbers or fares.

### Source priority

1. The destination government's immigration authority website (entry requirements, visa-exemption conditions, electronic arrival card).
2. The destination's health/drug regulator (personal medication, especially controlled drugs).
3. The destination's customs (prohibited and restricted items).
4. Your own country's foreign ministry, the destination tourism board (safety advisories, local regulations).
5. Card networks, card issuers, phone manufacturers (overseas payments, ATM withdrawals, eSIM support).
6. Transit operators (transit cards, riding with bank cards).

### Steps

1. **Read official pages before departure (as close to departure as practical).** Rules change. For each item, note the page and date you checked it.
2. **Distinguish "universal requirements" from "conditional requirements".**
   - Universal: every traveler must do it (e.g. fill in the electronic arrival card within its open window).
   - Conditional: only some people must do it (carrying controlled medication requires applying several weeks in advance; arriving from certain regions requires a vaccination certificate). Write conditional ones as "if…, then…", not as something everyone must do.
   - Suggestions (travel insurance, how much cash, data allowance) are written as references, not requirements.
3. **Group by "when to do it" and set `dueDate`.**
   - Window items (e.g. "can only be filled in during the last few days before arrival"): set `dueDate` to the window's start date, and state the window clearly in the body (whether it includes the arrival day).
   - Packing items: departure day or the day before.
   - Return-trip review: the night before return.
   - The App's “今日” (Today) page shows only items whose `dueDate` has arrived (or is empty) and that aren't done, so `dueDate` determines when the user sees the reminder.
4. **Write the method and done criterion for each item.** Example: "Done criterion: confirmation email received and saved offline." The done criterion must make it possible to tell "is it done or not".
5. **Write copyable templates.** A late-arrival email to the hotel, the list of fields to prepare for the arrival card (field names only, no personal information), inquiry emails to hotels or attractions — written into `copy` for the user to send themselves.
6. **Payments and connectivity.** Write these separately: whether merchants accept a given payment method, the card's eligibility for overseas transactions, hotels' card requirements for deposits, how ATM withdrawals of local cash are charged and converted, and choosing local currency when offered dynamic currency conversion (DCC). When you don't know the user's bank and card type, write "check against your card issuer's rules" rather than assuming it works.
7. **No personal information.** No ID numbers, order numbers or membership numbers. `verify_content.py` blocks strings that look like ID numbers.

### Checks and validation

- [ ] `verify_content.py`: unique IDs, `group`/`title`/`body` present, `dueDate` valid and no later than the trip end, `https` links, no suspected ID numbers.
- [ ] `--require-complete`: at least 10 items.
- [ ] Each window item's date window matches the official page (mind whether it includes the arrival day).
- [ ] Conditional requirements aren't written as universal ones.

### Common pitfalls

- Getting the electronic arrival card's open window wrong by one day (whether it includes the arrival day).
- Writing "insurance recommended" as an entry requirement.
- Writing the advance application period for controlled medication as "deal with it before departure" — such items belong in the "confirm now" group with the earliest `dueDate`.
- Treating a tourism board or customs page as "fully verified" when the full terms couldn't be fetched. If it can't be fetched, say so and give the official entry point for the user to check themselves.
- Keeping a "buy flights" item after the user has already booked flights; change it to "recheck flights before departure" without touching existing check marks.
- After deleting an old item, reassigning its old ID to a new item, so the new item shows as "done".

### Done criteria

- [ ] Every item has a method, a done criterion and an official source (where applicable), with the verification date recorded.
- [ ] Groups are by "when to do it", and window items have the correct `dueDate`.
- [ ] Template text can be copied directly, personal information is placeholders, and nothing was sent on the user's behalf.
- [ ] Flights contain only flight numbers and times.

---

## 9. Attraction Guides

For places that take a whole day or have complex rules (theme parks, reservation-only venues), write structured guides in `places[].guides`.

### Target fields

`places[].guides[]`: `id`, `title`, `summary`, `updatedAt`, `sections[]` (`{title, paragraphs[]}`), `links[]` (`{label, url}`).

The usual three: choosing a day and buying tickets, a one-day route, and transport, food and pitfalls.

### Source priority

1. The official operating calendar (clicked day by day).
2. Official ticket-type pages and express pass terms pages.
3. Official planned closure/maintenance notice pages.
4. Official FAQ (outside food, lockers, security checks, strollers, etc.).
5. Feature descriptions of the official App (live queue times, showtimes).
6. Social media travelogues: only to supplement route experience; rule-like claims are labeled "personal experience / possibly outdated".

### Steps

1. **Click through the operating calendar day by day**, and record the opening hours for each day of the trip. Closing times may differ by date.
2. **Read the ticket terms.** What a standard day ticket includes and doesn't (night events and express passes are usually extra); the express pass rules (how many uses per ride, whether date-specific, whether admission is included).
3. **Read closure notices.** Rides planned to be closed and shows suspended during the trip; note that "unplanned closures may also occur".
4. **Read the FAQ.** Outside food, lockers, security checks, rain policy. Expand every collapsed Q&A one by one.
5. **Write recommendations.** "Recommended to go on day X" is a planning judgment (longer hours, fits better with other plans), **not a guarantee of low crowds** — say so explicitly.
6. **Label old claims.** Travelogue claims like "done in half a day", "you can bring snacks", "lockers cost this much" that conflict with official information or can't be verified are labeled as personal experience or old information.
7. **Write `updatedAt` and `links`.** Each guide carries its verification date, and links point to specific official pages.

### Checks and validation

- [ ] `verify_content.py`: every guide has `title`, `updatedAt`, `sections`.
- [ ] Calendar, price and closure information all note the verification date.
- [ ] Planning budgets (tickets, food, transport) are clearly labeled as budgets, not quotes.

### Common pitfalls

- Looking only at the day the calendar shows by default.
- Writing an express pass as "includes admission".
- Treating a special event (a separately ticketed night event) as part of the standard day ticket.
- Maintaining two copies of the guide text (e.g. one for the web, one for the App) and later updating only one. The template maintains only one copy, in `content/places.json`.

### Done criteria

- [ ] Opening hours were checked day by day for every day.
- [ ] Key terms for ticket types, express passes, closures and FAQ all have official links.
- [ ] "Which day to go" is stated as a planning judgment; old claims are all labeled.

---

## 10. Travel Phrases

### Target fields

`sections[]` in `phrases.json`: `id`, `title`, `items[]` (`{native, local, note}`). The speech language is `speech.language` in `trip.json` (BCP-47, e.g. `en-US`, `ja-JP`); `speech.label` is its display name.

### Steps

1. **Group by scenario**: communication fallbacks, restaurants, ordering drinks, transport/taxis, hotels, shopping, asking directions, emergencies, health/allergies, asking someone to take a photo.
2. **Write each phrase the way locals will actually understand it**, preferring short, polite phrases that can be shown directly on screen.
3. **Explain local meaning.** Local ordering terms, forms of address and customs (tipping, service charges, queueing etiquette) are explained in `note` — especially phrases whose literal meaning differs from the actual meaning.
4. **Check the speech output.** Set the correct `speech.language`, play a few phrases in the simulator or on a device, and confirm the accent and pronunciation are acceptable; when the local language has several variants, choose the one common at the destination.
5. **No sensitive content.** No personal information of any kind, and no phrases that require ID numbers.

### Common pitfalls

- Machine-translating long sentences directly, which nobody can actually say on the spot.
- Local ordering terms (e.g. local shorthand for drinks or toppings) given only a literal translation without explanation.
- Wrong `speech.language`, so speech comes out in a different accent or can't be read at all.

### Done criteria

- [ ] Covers at least four categories: communication fallbacks, restaurants, transport, emergencies.
- [ ] Every locally specific term has a `note`.
- [ ] Playback was tested on a device, with the correct language setting.

---

## 11. Routes and Maps

### Background: a pitfall you must verify early

Under mainland China network and account conditions, iOS MapKit may **fail to return routes** for some overseas regions (`MKDirections` reports `OUT_OF_COVERAGE` / search fails), and place search may also error out, while a domestic control route works fine. This means "it'll probably work once we're there" can't be verified, and it's unusable before departure. In the real project, this was discovered only after the feature was finished.

**Countermeasures:**

- **Verify in the target environment in the first week**: request one walking route between two real destination coordinates, alongside a domestic route as a control. If it fails, change the approach immediately.
- **Bundle coordinates into the App** (`locations.json`) instead of relying on online geocoding during the trip.
- **Optional: self-host a routing service.** The template's `server/` provides a Valhalla-based routing service and an OpenStreetMap-based place index:
  - Road network: download an OSM extract (`.pbf`) of the destination region from BBBike or Geofabrik, and build Valhalla tiles.
  - Administrative boundaries: build from a regional extract that includes complete national borders, so that country filtering and driving side (left/right) are correct.
  - Place index: `scripts/build_route_places.py` generates it from the OSM extract, filtered by national border, keeping only destination records.
  - Data source, snapshot date, checksum and license are written into the artifact's source file; the App keeps the OSM attribution.
  - The road network is a static snapshot, with no live traffic.
- Without a deployed backend, the App still works offline, just without leg-by-leg routes; navigation is handed off to the system map app.

### Rules for presenting routes

- **No fake straight lines.** A leg whose route can't be computed is shown as failed; don't pass off a line between two points as a route.
- **Coordinate snapping has a limit.** Snapping start/end points to the road network is limited to about 100 m; beyond that, report a failure and prompt the user to check the entrance.
- **Label partial results.** When some legs fail, show "partially computed"; failed legs are not counted as 0 distance and 0 minutes.
- **Stops missing coordinates stay in the list**, breaking only their adjacent legs.
- **Measured samples are not promises.** The research record may say "walking between two points is about 1.2 km, about 15 minutes, request took about 0.5 s", but that is only a sample, not a performance or time commitment.
- **The center of a large building may not be reachable on foot** (the coordinate is inside the building); keep the failed state and let the user check the entrance or switch transport mode.

### Copying English addresses

Ride-hailing and map apps usually search best with English addresses. The template supports copying English addresses from route stops. When researching:

- Write `name` and `address` in `locations.json` in English (or the commonly used local spelling), keeping branch names, floor/unit numbers and postal codes, and removing duplicated fragments.
- `destination.addressSuffix` and `postcodePattern` in `trip.json` are used to normalize address endings.
- **Spot-check**: pick 3 addresses (a landmark, a small shop with a unit number, a hotel), paste them into Google Maps on the web, and confirm the first result is the target place. Write the results into the research record. Don't claim "every map and ride-hailing app will recognize them accurately", and it doesn't mean the pickup point is correct.

### Done criteria

- [ ] The system map's routing capability has been verified in the target environment, with the conclusion in the research record.
- [ ] Every place that can be pinned down has bundled coordinates; for a self-hosted service (if used), data source, snapshot date and license are complete.
- [ ] At least 3 English addresses were spot-checked, with results recorded.
- [ ] The UI never shows fake straight lines or counts failures as 0.

---

## 12. Exchange Rates

### Target fields

`currency` in `trip.json`: `local`, `home` (ISO 4217 codes), `localSymbol`, `homeSymbol`, `homePerLocal` (1 unit of local currency = how many units of home currency), `rateDate`, `rateSource` (`https`).

### Steps

1. Choose a public, accessible exchange-rate source with an update time (a central bank, a public exchange-rate API, etc.), and record: the value, the source URL, and the update time given by the source (with time zone).
2. If a fallback source shows a date older than today, **do not** treat it as today's rate.
3. `rateDate` is the capture date; `rateSource` is the specific link.
4. State in the UI and copy that this is a reference rate for planning, unrelated to banks' actual settlement, fees, or dynamic currency conversion.

### Common pitfalls

- Using a rate from several days ago as "today's".
- Conflating the amount actually charged to a card with the planning conversion.
- Getting the rate direction backwards (`homePerLocal` is "1 local = ? home").

### Done criteria

- [ ] `homePerLocal`, `rateDate` and `rateSource` are all present, and the source has an update time.
- [ ] The copy notes "planning reference".

---

## 13. Reference Information

`references[]` in `references.json`: `{id, title, body, links}`. This holds information that doesn't belong to any particular place but is often needed during the trip: transit cards and how to ride, emergency numbers, common local regulations (prohibited items, no-smoking areas, waste sorting, etc.), climate.

- Emergency numbers and local regulations must have government or official source links.
- Climate lists only climate averages from the official meteorological agency, with the note that "climate averages cannot predict the weather on the day of travel".
- Safety advisories come from your own country's foreign ministry or the destination's official sources; this plan's own suggestions (e.g. "suggest returning to the hotel before 22:00") must be stated as suggestions, not local regulations.

---

## 14. Tools and Techniques

### 14.1 Reading web pages: browser automation

- Read official sites with a real browser that renders JavaScript (the agent's browser tool, Playwright, etc.); command-line `curl` is only suitable for static pages and APIs.
- The routine for dynamic pages: open → wait for content to load → click open calendars/collapsed items/tabs → read the visible text → take evidence screenshots (evidence goes into `test-results/` or a research evidence directory kept out of git).
- For platforms that require login (Xiaohongshu, booking platforms), the user logs in themselves in the browser; the agent only reads. Never save cookies or account information into the repo.
- On CAPTCHAs or bot detection: stop, ask the user to handle it manually or give up that source; **do not try to bypass it**.
- Slow down when opening many pages in one session; when downloading images, space requests a few seconds apart and send a clear User-Agent.

### 14.2 Operating native apps: Computer Use

Some work can only be done in native apps, e.g. compiling a destination guide (a saved list) in Apple Maps for easy reference during the trip.

- Search and add items one by one, **choosing by name and address**; don't just add the first search result — results often include same-named places abroad, parking lots, travel agencies, and duplicate Chinese/English entries.
- Deduplicate by address: keep only one of the Chinese-name and English-name entries for the same place.
- **The app may crash midway.** After reopening, recount the saved items before continuing; don't continue based on "I remember getting to item N".
- When wrapping up, scroll through the complete list from top to bottom, deduplicate, and check that the total matches what the UI shows.
- Delete only entries the user explicitly asked to remove; a "permanently closed" label on the map is just the map's state at the time, not an official notice.
- Record an operation snapshot: the final list, how counts were tallied (how many existed, added, deleted), and choices made while searching.

### 14.3 How to search effectively

- **Official sites first.** Find the operator's official site first, then look for information within it; don't start from aggregator sites.
- **`site:` queries.** `site:<official-domain> opening hours`, `site:<official-domain> filetype:pdf menu`, `site:<government-domain> keyword`.
- **Multiple languages and names.** Search with the Chinese name, English name, local-language name and former names together; many places have several Chinese spellings.
- **English names are often more precise.** Official pages are usually primarily in English or the local language, so searching the English name hits the official site directly.
- **Check dates.** Look at the page date of every result; top-ranked results may be old pages from years ago.
- **Official news and notices.** Closures, maintenance, relocations and price increases usually appear first on official news/notice pages, not the main pages.
- **Compare with archives.** When a page seems to have been redesigned, you can use a web archive service to view older versions and understand what changed; but archives are only for understanding, not a source for current facts.
- **Enter reservation systems from the official site.** The entry point to a restaurant's or attraction's reservation system must be the one linked from its official site, to avoid landing on third-party booking-agent pages.

### 14.4 Research records

- One record per research session: `docs/research/YYYY-MM-DD-topic.md`, copied from [research-record.md](../templates/research-record.md).
- The source table, one row each: URL, time read, conclusion, confidence (high/medium/low).
- Conflicts and open items get their own section, to be prioritized in later research.
- State which `content` files and fields were changed this time, to make reviewing the diff easier.
- Raw evidence such as screenshots and PDFs goes in a directory kept out of git; the record only lists file names.
- Don't paste private orders, accounts or personal information.

### 14.5 Writing tasks for AI agents

When handing a task to an agent, spelling out the following saves a lot of rework:

- Destination, dates, party size, daily rhythm, flight times (or "TBD").
- Which content types to research and target quantities (e.g. "3 photos and 3 reference posts per place").
- Rules that must be followed: section 1 of this playbook; read-only; no form submissions; no messages sent.
- Deliverables: modified `content/*.json`, the research record, and `verify_content.py` output.
- Acceptance criteria: `verify_content.py --require-complete` passes, or the reason for every failure is listed.

---

## 15. Final Pre-Delivery Check

- [ ] Dates, time zone, currency, exchange rate, map extent and speech language in `trip.json` are all filled in for the real trip.
- [ ] `python3 scripts/verify_content.py --require-complete` passes; warnings are handled one by one or explained in the research record.
- [ ] `python3 scripts/build_ios_resources.py` succeeds, and `python3 scripts/verify_content.py --built-catalog` passes.
- [ ] Every fact has `checkedAt` and a specific source link; all changeable information uses snapshot wording.
- [ ] Uncertain, conditional, reservation-only and partly closed information is stated in the copy and visible in the UI.
- [ ] No fabricated coordinates, photos, prices or opening hours; no failed queries written as sold out.
- [ ] The public repository contains no unlicensed social media images or body text and no private information; before publishing, run `python3 scripts/privacy_check.py` (you can list your own name, domains and other private strings in `.privacy-denylist`, which is kept out of git).
- [ ] Published IDs are unchanged; nothing overwrites user state.
- [ ] The research record is complete: source table, conflicts and open items, fields written, next steps.
