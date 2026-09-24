# Building an app for a new destination: from zero to TestFlight

This is the complete process checklist. Every step has a **done criterion**; don't move on until it's met. It works for a person following along, and can also be handed straight to Codex / Claude Code: type `/new-trip <destination> <dates> <party size>` in Claude Code or Codex and the agent works through this checklist with the phase prompts in [agent-prompts.md](agent-prompts.md).

Note: the app UI is in Simplified Chinese (tab names, labels, status text). Where you must type or match a Chinese value, it is shown in backticks with its English meaning.

Estimated effort: 1–3 days of content research (depending on destination and depth), half a day to a day for engineering and release.

## 0. Prerequisites

| Need | Notes |
| --- | --- |
| macOS + Xcode 26 or later | The app requires iOS 26 minimum, iPhone only |
| [XcodeGen](https://github.com/yonaskolb/XcodeGen) | `brew install xcodegen`; the project is generated from `ios/project.yml` |
| Python 3.11+ and Pillow | `python3 -m pip install Pillow` |
| A paid Apple Developer account | Only needed to install on a real device / TestFlight; not needed for the simulator |
| An AI coding agent (optional) | Codex, Claude Code, etc., able to read and write this repo and use a browser for research |

**Done when**: `make setup && make open` succeeds and the bundled Kyoto example runs in the simulator (step 6 lists the equivalent individual commands).

## 1. Create your repository

1. On GitHub, create a new repository from this template (Use this template), or fork it and rename. **Making it private is recommended**: your itinerary, hotels and companion details will all go into this repo.
2. Create a working branch, e.g. `trip/kyoto-2031`.
3. Delete the Kyoto example but keep the structure: the entries in `content/*.json`, the photos under `content/media/` and the research records in `docs/research/kyoto/`. You can also keep the example at first and replace it as you go; it doubles as a worked answer for every field.

**Done when**: you have a private repository and `content/` contains only the structure you plan to fill in.

## 2. Pin down the trip requirements (with your companions)

Write a one-page brief in `docs/research/00-brief.md` (create the directory yourself); research and planning are both based on it:

- Destination, dates (first day / last day / day you leave home), flight times (no order numbers).
- Number of travelers, pace preferences (when to get up, when to head out, how much walking per day), stamina and dietary restrictions.
- Must-go / want-to-go / could-go lists, photography preferences, budget tier (accommodation, dining, tickets).
- Fallback plans for rain or extreme heat.
- Language: what the local language is and which speech voice you need.

**Done when**: every companion has confirmed the brief.

## 3. Fill in `trip.json`

Fill in each field following [content-schema.md](content-schema.md#tripjson). Key points:

- Use a new `id` that has never been used, e.g. `kyoto-2031-v1`. To protect user data, the app refuses to open a local save left by another trip (another `id`): if a phone still has the previous trip's build, export a backup there and delete the old app first, or give the new trip its own Bundle ID.
- Use an IANA name for `timezone` (`Asia/Tokyo`).
- Draw `map.bounds` as a rectangle that **just covers the trip area**; don't include large chunks of neighboring countries/cities.
- Exchange rate: take it from one public source and record `rateDate` and `rateSource`; it's a planning reference, not a bank settlement rate.
- `speech.language`: Japanese `ja-JP`, Korean `ko-KR`, Thai `th-TH`, English `en-US` / `en-GB`.

**Done when**: `python3 scripts/verify_content.py` reports no errors for `trip.json` (errors in other files can be ignored for now).

## 4. Research and fill in content

Follow the evidence rules in [research-playbook.md](research-playbook.md) strictly. Recommended order (later files depend on IDs from earlier ones):

| Order | File | Minimum | Recommended |
| --- | --- | --- | --- |
| 1 | `places.json` + `locations.json` | ≥5 places, all with coordinates, sources and check dates | For each place, spell out opening hours, ticket price, suggested time slot and rain alternative |
| 2 | `dining.json` | Optional | First find one authoritative, complete list as an anchor, then pick 10–20 restaurants to detail |
| 3 | `itinerary.json` | Stops every day, times increasing with no overlap | Cluster by area, leave 15–45 minutes of travel buffer, have a rain swap for each day |
| 4 | `preparation.json` | ≥10 items, grouped by "when to do it" | Entry, documents, connectivity, payments, transit cards and local rules all come from official pages |
| 5 | `hotels.json` | Optional | Compare prices with one fixed set of search conditions; quotes are totals for the whole stay |
| 6 | `photo-sources.json` | Optional | Openly licensed image libraries, 2–3 photos from different angles per place |
| 7 | `posts.json` | Optional | Only include content you have permission for; otherwise keep just the title, link and your own summary |
| 8 | `phrases.json` | Optional | 4–8 groups by situation; explain the meaning of locally specific expressions |
| 9 | `references.json` / `flights.json` | Optional | Transit cards, emergency numbers, tax refunds; flights get only flight number and times |

After each category of content, leave a research record in `docs/research/` (template: [../templates/research-record.md](../templates/research-record.md)) stating which sources you read, when you read them, how conflicts were resolved, and what remains unconfirmed.

**Done when**:

```bash
python3 scripts/verify_content.py --require-complete
```

prints `PASS` (no leftover `【示例】` (sample marker), `example.com`, `待核实` (to be verified) or `TODO` allowed).

## 5. Build content and check locally

```bash
python3 scripts/build_ios_resources.py
python3 scripts/verify_content.py --built-catalog
python3 -m unittest discover -s scripts -p 'test_*.py'
```

The build output lists the number of days, places and images, and the total bytes. A content bundle is typically a few MB to a few tens of MB; more photos make it larger.

**Done when**: all three commands pass.

## 6. Run in the simulator

```bash
cp -n ios/Signing.example.xcconfig ios/Signing.xcconfig   # Team can be left empty for the simulator
xcodegen generate --spec ios/project.yml
xcodebuild test -project ios/TripJournal.xcodeproj -scheme TripJournal \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
open ios/TripJournal.xcodeproj   # or run directly in Xcode
```

Check every tab: Today (`今日`), Itinerary (`行程`, every day), Explore (`探索`: places / dining / guides / hotels), Kit (`行囊`: checklist, budget, flights, phrase read-aloud). Look through once at the largest text size and once in dark mode.

To see the "during the trip" Today screen, add the launch argument `-TripNow 2031-04-02T10:30` (destination local time; Debug builds only) to the Xcode scheme.

`make screenshots` captures every tab with your content and writes a hero image, single-screen images, a social preview and an animation to `docs/assets/`: a handy visual checklist, and something to share.

**Done when**: tests pass; none of the four tabs has blank areas, truncation, wrong dates or leftover sample text.

## 7. (Optional) Two-person sharing and route backend

By default the app is fully offline: itinerary changes are saved only on the device. If you need two phones sharing the same itinerary, full-day route computation, or couple interaction push notifications, self-host a backend following [backend.md](backend.md), then create `ios/SharedAccess.xcconfig` (see `SharedAccess.example.xcconfig`).

**Done when**: two devices each edit different stops on the same day and both see the other's changes; editing the same item at the same time produces a conflict comparison rather than an overwrite.

## 8. Signing and TestFlight

Following [ios-delivery.md](ios-delivery.md):

1. In `ios/Signing.xcconfig`, fill in `DEVELOPMENT_TEAM` and your own `APP_BUNDLE_ID` (reverse domain).
2. In Apple Developer, register the App ID, the widget extension ID (`<bundle id>.widgets`) and the App Group (`group.<bundle id>`); enable Push Notifications if you use backend push.
3. Create the app record in App Store Connect, archive and upload, create internal / external test groups, and add your companions.
4. Keep a release record for every upload (template: [../templates/release-record.md](../templates/release-record.md)).

**Done when**: TestFlight on your companions' phones shows the new build as available to test ("Ready to Test"), and they have actually installed and opened it.

## 9. Before departure and during the trip

- 3–5 days before departure: re-check opening hours, temporary closures, ticket prices and weather, update `checkedAt`, and ship another build.
- Do a fresh install in airplane mode to confirm offline content is complete and ticket attachments open.
- During the trip, make only small fixes; large content changes will cause conflicts in the shared itinerary across the two devices.

## 10. After the trip

- Export an itinerary backup (Kit › Backup) and archive it together with the original ticket files.
- If you self-hosted a backend: stop the service, back up the database, remove the public entry point; whether to keep or delete the data is up to you.
- Add the pitfalls you hit this time to [lessons-learned.md](lessons-learned.md) so the next trip goes faster.
