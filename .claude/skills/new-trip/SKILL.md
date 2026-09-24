---
name: new-trip
description: Turn this OneTrip template into an iOS app for a new destination. Walks the user through the trip brief, content/trip.json, evidence-based research, itinerary, validation, build and simulator check, following the repository's own playbook. Use when the user wants to make the app for a trip, e.g. "/new-trip 京都 2027-11-16..18 2人" or "make this app for my Lisbon trip".
---

# New trip

You are making this repository's app for the user's next trip. Everything the app shows comes from
`content/`; do not change Swift or Python code unless the user asks for a feature or fix.

Read `AGENTS.md` first and follow it throughout. Reply in the user's language. The detailed, copy-ready
prompt for every phase is in `docs/zh/agent-prompts.md` (Chinese) and `docs/en/agent-prompts.md` (English);
the phases below follow them, so read the matching section before starting each phase.

## Phases

1. **Brief** — collect destination, first/last day, departure date, flights (times only), party size, pace,
   must-see / skip lists, food limits, budget level and local language. Write `docs/research/00-brief.md`
   and ask the questions you still need answered. **Stop and wait for the user to confirm the brief.**
2. **Destination config** — replace `content/trip.json` (new `id`, IANA `timezone`, map bounds that just
   cover the trip, dated exchange-rate source, `speech.language`). Run `python3 scripts/verify_content.py`.
3. **Research** — places + coordinates, dining, preparation, phrases, references, photos (openly licensed
   only), optional hotels and posts, strictly by `docs/<lang>/research-playbook.md`: official sources read
   in a browser, every fact with a source URL and `checkedAt`, official price kept apart from planning
   budget, conflicts recorded instead of guessed. Keep a research record per content type in
   `docs/research/` (template: `docs/templates/research-record.md`). Independent content types can be
   researched in parallel (for example with sub-agents), each writing its own file.
4. **Itinerary** — `content/itinerary.json`: one entry per trip day, clustered by area, 15–45 min buffers,
   hard constraints first, a rainy-day swap in each day's note.
5. **Gate and build** —
   ```bash
   python3 scripts/verify_content.py --require-complete
   python3 scripts/build_ios_resources.py && python3 scripts/verify_content.py --built-catalog
   make test
   ```
   Fix until everything passes and report exact test counts.
6. **Look at it** — run the app in the simulator (`make open`), check every tab and day for blanks,
   truncation, wrong dates or leftover example text. `make screenshots` produces shareable images of
   the user's own trip in `docs/assets/`.
7. **Ship** (only when asked) — `docs/<lang>/ios-delivery.md`. Tell the user before any App Store Connect
   action and wait for a yes.

## Never

- Book, pay, submit forms, sign in, send messages or change accounts: stop before guest details or
  payment and report what you saw.
- Invent coordinates, prices, hours, photos or reviews; leave a gap and say so.
- Commit `ios/Signing.xcconfig`, `ios/SharedAccess.xcconfig`, keys, booking references or personal
  data. The user's trip repository should stay private; run `python3 scripts/privacy_check.py --history`
  before anything is published.
