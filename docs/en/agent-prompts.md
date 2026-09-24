# Staged prompts for Codex / Claude Code

Copy the prompts below to your coding agent one stage at a time. Use one conversation or one task per stage, and check the results before moving on to the next stage. Replace the angle brackets `<…>` with your own information. The prompts are in English here, but you can write them in any language.

Common assumptions (the agent automatically reads `AGENTS.md` at the repository root; `CLAUDE.md` points to the same file):

- Content changes go only in `content/`; Swift / Python code is not changed unless you explicitly ask.
- Every fact needs a source + check date; if something can't be found, leave it empty and say so — **don't make things up**.
- No booking, no payment, no submitting forms, no sending email, no logging in to your accounts to change anything.

---

## Stage 1: Trip brief

```text
Please read AGENTS.md and docs/en/new-destination.md.
We are going to build this app for <destination>. Trip details:
- Dates: <first day> to <last day>, leaving home on <departure date>; flights <outbound flight number/times>, <return flight number/times>
- Travelers: <N>; pace: <wake-up time, daily walking, stamina>
- Must-go: <…>; want-to-go: <…>; skip: <…>
- Food: <restrictions/preferences>; budget: <accommodation/dining/ticket tier>
- Local language: <…>
Please organize this into docs/research/00-brief.md and list the questions you still need me to confirm. Don't change content/ yet.
```

## Stage 2: Destination config

```text
Based on docs/research/00-brief.md, fill in content/trip.json (fields are described in docs/en/content-schema.md).
- Use <slug>-<year>-v1 as the id
- Take the exchange rate from one public source using today's data, and record rateDate and rateSource
- map.bounds should cover only the trip area; explain how you determined it
When done, run python3 scripts/verify_content.py, fix only errors related to trip.json, and report the result.
```

## Stage 3: Places and coordinates research

```text
Strictly following the "General evidence rules", "Places and coordinates" and "Photos" sections of docs/en/research-playbook.md,
research places for <destination> and write them to content/places.json and content/locations.json:
- Candidate sources: the destination's official tourism board and each attraction's official website (actually open and read them in the browser); guides/social media are only for discovering candidates and photo spots
- For each place: opening hours, official price kept separate from planning budget, suggested time slot, transport, rain alternative, sources, checkedAt
- Coordinates: manually check OpenStreetMap candidates by name/type/address, rule out false matches such as train stations and bus stops; they must fall inside map.bounds in trip.json
- Anything you can't find or that has conflicting information goes into "Conflicts and open questions" in docs/research/10-places.md — don't guess
Target count: <N>. When done, run verify_content.py and report: places added, items still unconfirmed, and the list of sources used.
```

## Stage 4: Dining

```text
Following the "Dining" section of research-playbook.md, research dining in <destination> and write it to content/dining.json:
1. First find one authoritative, complete list as the anchor (e.g. this year's full official food guide list), and record the edition year, count and source
2. From it, pick <N> restaurants that match our itinerary areas and tastes and make them detailed: give each menu its own sourceURL/checkedAt, and state clearly how tax/service charge is handled
3. Bookings are query-only, never reserve: in the restaurant's own booking system, choose the date, meal period and <party size> people, and record the result as an observations snapshot
4. recommendations give candidates by trip day index
When done, run verify_content.py and report conflicts and unconfirmed items (write them into docs/research/20-dining.md).
```

## Stage 5: Itinerary planning

```text
Based on 00-brief.md, places.json and dining.json, plan content/itinerary.json:
- Days correspond one-to-one with trip.json; uids are unique and never changed afterwards
- Cluster by area, leave 15–45 minutes of buffer between stops; hard constraints (flights, time slots that need reservations, closed days, show times) come first
- In each day's note, write one sentence on the day's plan and the rain swap
- Estimate the default budget from the tiers in the brief (whole-trip total; flights in home currency, everything else in local currency)
When done, run verify_content.py; there must be no time-overlap warnings. Write the planning rationale into docs/research/30-itinerary.md.
```

## Stage 6: Pre-trip preparation, phrases, practical info

```text
Following the "Pre-trip preparation" and "Travel phrases" sections of research-playbook.md:
- content/preparation.json: entry requirements, document validity, e-arrival card, connectivity, payments, transit cards, local rules, pre-return check;
  use only official sources read today; group by "when to do it" and set dueDate where needed; each item states the method and done criteria; never include any personal document numbers
- content/phrases.json: <N> groups by situation, local in <language>, note explains locally specific expressions
- content/references.json, content/flights.json
When done, run verify_content.py and report.
```

## Stage 7: Hotels, photos, reference posts (optional)

```text
Following the corresponding sections of research-playbook.md:
- hotels.json: fixed search conditions <check-in>–<check-out>, <guests>, <rooms>, <currency>; take the itemized total for the whole stay, stop before entering guest details, and never place an order
- photo-sources.json: use only openly licensed image libraries (e.g. Wikimedia Commons), confirm the image and license one by one, fill in downloadUrl, then run
  python3 scripts/build_photos.py --download-missing
- posts.json: we <do/do not> have permission to republish. Without permission, write only the title, author, link, capture date and your own summary, and use our own image as the cover
When done, run verify_content.py.
```

## Stage 8: Release gate and simulator checks

```text
1. Run python3 scripts/verify_content.py --require-complete and fix issues one by one until it prints PASS
2. python3 scripts/build_ios_resources.py && python3 scripts/verify_content.py --built-catalog
3. cp -n ios/Signing.example.xcconfig ios/Signing.xcconfig; xcodegen generate --spec ios/project.yml
4. xcodebuild test (iPhone simulator), and report the exact pass/fail/skip counts
5. Take a screenshot of every screen in the simulator (Today, every day of Itinerary, the four segments of Explore, Kit) and check for blank areas, truncation, wrong dates and leftover sample text
Don't claim that checks you didn't run have passed; report simulator failures honestly.
```

## Stage 9: Release to TestFlight

```text
Prepare a TestFlight build following docs/en/ios-delivery.md:
- Version: MARKETING_VERSION <x.y.z>, increment CURRENT_PROJECT_VERSION by 1 (app and widget must match)
- I've already filled in Team and Bundle ID in ios/Signing.xcconfig (don't read or print any credentials beyond what's in it)
- Archive, export, upload; run codesign and entitlements checks before uploading
- Write a release record to docs/releases/ following docs/templates/release-record.md
For uploading, adding test groups and notifying testers in App Store Connect, tell me what you're going to do first and only proceed after I confirm.
```

## Small changes during the trip

```text
The plan for <date> needs to change: <…>. Please change only the <date> day in content/itinerary.json (don't change uids),
then rebuild and run the tests. Note: itineraries users have already saved in the app are not automatically overwritten by content updates — this is by design;
if we've already enabled shared sync, tell me whether adjusting it manually in the app or shipping a new build is more appropriate.
```
