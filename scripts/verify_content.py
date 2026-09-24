#!/usr/bin/env python3
"""Validate everything in content/ before building the app.

Default mode checks structure, references, dates, coordinates, enumerations and provenance.
--require-complete is the gate for real trips: it additionally rejects sample text,
example.com links, placeholders (待核实 / TODO …) and thin coverage.
--built-catalog also checks the generated catalog.json was rebuilt from these sources.
Exit code 0 = pass. Uses only the standard library (Pillow optional for image checks).
"""
import argparse, json, math, re, sys
from collections import Counter
from datetime import date, datetime, timedelta
from pathlib import Path
from urllib.parse import urlparse

ROOT = Path(__file__).resolve().parents[1]
MAX_BUDGET = 10_000_000  # keep in sync with PlanValidation.maximumBudget and server/trip_server.py
MEALS = {'breakfast', 'lunch', 'dinner', 'snack', 'allDay', 'both', 'any'}
PLAN_MEALS = {'breakfast', 'lunch', 'dinner', 'snack'}
VENUE_TYPES = {'restaurant', 'foodCourt', 'stall', 'casual'}
DEPTHS = {'detailed', 'light', 'directory'}
AWARDS = {'stars', 'bibGourmand', 'selected', 'none', 'unverified'}
BASES = {'perPerson', 'estimate', 'perDish', 'perSet', 'perTable', 'marketPrice'}
TAXES = {'nett', '++', 'unknown'}
AVAILABILITY = {'notChecked', 'unknown', 'notRequired', 'walkIn', 'available', 'full', 'soldOut'}
OBSERVATIONS = {'available', 'full', 'soldOut', 'waitlist', 'closed', 'notReleased', 'notChecked', 'unknown', 'blocked'}
PRICE_STATUS = {'verified', 'estimate', 'unverified', 'unknown', 'notPublished'}
QUOTE_STATUS = {'available', 'pending', 'unavailable'}
ID = re.compile(r'^[a-z0-9][a-z0-9-]{0,79}$')
PLACEHOLDER = re.compile(r'【示例】|示例数据|example\.com|待核实|待补充|待确认|TODO|TBD|lorem', re.I)
LIVE_CLAIM = re.compile(r'保证有位|实时有位|保证订到|guaranteed seat', re.I)


def text(value): return isinstance(value, str) and bool(value.strip())
def finite(value, minimum=0.0): return isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(value) and value >= minimum


def https(value):
    if not text(value): return False
    parsed = urlparse(value)
    return parsed.scheme == 'https' and bool(parsed.hostname) and not parsed.username and not parsed.password


def valid_date(value):
    if not text(value): return False
    try:
        (date.fromisoformat if re.fullmatch(r'\d{4}-\d{2}-\d{2}', value) else datetime.fromisoformat)(value)
        return True
    except ValueError:
        return False


class Report:
    def __init__(self): self.errors, self.warnings = [], []
    def check(self, condition, message):
        if not condition: self.errors.append(message)
        return bool(condition)
    def warn(self, condition, message):
        if not condition: self.warnings.append(message)


def load(content, name, required=True):
    path = content / name
    if not path.exists():
        if required: raise FileNotFoundError(f'missing content/{name}')
        return None
    return json.loads(path.read_text())


def validate(content, require_complete=False, built=None):
    r = Report()
    check = r.check
    trip = load(content, 'trip.json')

    # trip.json
    for field in ('id', 'appName', 'timezone', 'startDate', 'endDate', 'departureDate', 'homeCity'):
        check(text(trip.get(field)), f'trip.{field} required')
    check(ID.match(trip.get('id', '')), 'trip.id must be lowercase letters, digits and hyphens')
    days = []
    if check(all(valid_date(trip.get(k)) for k in ('startDate', 'endDate', 'departureDate')), 'trip dates must be yyyy-MM-dd'):
        start, end = date.fromisoformat(trip['startDate']), date.fromisoformat(trip['endDate'])
        check(start <= end and (end - start).days < 60, 'trip.endDate must be 0–59 days after startDate')
        check(date.fromisoformat(trip['departureDate']) <= start, 'trip.departureDate must be on or before startDate')
        days = [(start + timedelta(days=i)).isoformat() for i in range(max((end - start).days + 1, 0))]
    try:
        from zoneinfo import ZoneInfo
        ZoneInfo(trip.get('timezone', ''))
    except Exception:
        check(False, 'trip.timezone must be an IANA name such as Asia/Tokyo')
    destination = trip.get('destination', {})
    for field in ('name', 'nameEn', 'countryCode'):
        check(text(destination.get(field)), f'trip.destination.{field} required')
    if destination.get('postcodePattern'):
        try: re.compile(destination['postcodePattern'])
        except re.error: check(False, 'trip.destination.postcodePattern is not a valid regex')
    currency = trip.get('currency', {})
    for field in ('local', 'home'):
        check(re.fullmatch(r'[A-Z]{3}', currency.get(field, '')), f'trip.currency.{field} must be an ISO 4217 code')
    check(finite(currency.get('homePerLocal')) and currency['homePerLocal'] > 0, 'trip.currency.homePerLocal must be > 0')
    check(valid_date(currency.get('rateDate')) and https(currency.get('rateSource')), 'exchange rate needs rateDate and an https rateSource')
    check(isinstance(trip.get('partySize'), int) and 1 <= trip['partySize'] <= 20, 'trip.partySize must be 1–20')
    bounds = trip.get('map', {}).get('bounds', {})
    check(all(finite(bounds.get(k), -180) for k in ('minLat', 'maxLat', 'minLon', 'maxLon'))
          and bounds['minLat'] < bounds['maxLat'] and bounds['minLon'] < bounds['maxLon'], 'trip.map.bounds invalid')
    center = trip.get('map', {}).get('center', [])

    def inside(lat, lon):
        try: return bounds['minLat'] <= lat <= bounds['maxLat'] and bounds['minLon'] <= lon <= bounds['maxLon']
        except (KeyError, TypeError): return False
    check(len(center) == 2 and inside(*center), 'trip.map.center must be inside bounds')
    check(text(trip.get('speech', {}).get('language')), 'trip.speech.language required (BCP-47, e.g. en-US)')

    # places + itinerary
    places = load(content, 'places.json')['places']
    dining = load(content, 'dining.json', required=False)
    venues = (dining or {}).get('restaurants', [])
    place_ids = [p.get('id') for p in places]
    all_ids = place_ids + [v.get('id') for v in venues if v.get('id') not in place_ids]
    check(len(set(place_ids)) == len(place_ids), 'places.json: duplicate ids')
    for p in places:
        path = f"place.{p.get('id')}"
        check(ID.match(p.get('id', '')), path + ': invalid id')
        for field in ('name', 'en', 'zone', 'kind', 'desc', 'tip', 'travel', 'rain', 'food'):
            check(isinstance(p.get(field), str), f'{path}.{field} must be a string')
        check(finite(p.get('hours')) and p['hours'] <= 24, path + ': hours must be 0–24')
        check(finite(p.get('budget')), path + ': budget must be ≥ 0 (local currency per person)')
        check(not p.get('link') or https(p['link']), path + ': link must be https')
        sources = p.get('sources', [])
        check(bool(sources) and all(https(s.get('url')) and text(s.get('label')) for s in sources), path + ': needs sources [{label,url}]')
        check(valid_date(p.get('checkedAt')), path + ': needs checkedAt')
        for guide in p.get('guides', []):
            check(text(guide.get('title')) and valid_date(guide.get('updatedAt')) and guide.get('sections'), f"{path}.guide.{guide.get('id')}: title, updatedAt, sections required")
    itinerary = load(content, 'itinerary.json')
    check([d.get('date') for d in itinerary['days']] == days, 'itinerary.json: days must match trip startDate..endDate one-to-one')
    uids = []
    for day in itinerary['days']:
        timed = []
        for item in day['items']:
            uids.append(item.get('uid'))
            check(item.get('place') in all_ids, f"itinerary {day['date']}: unknown place {item.get('place')}")
            check(re.fullmatch(r'([01]\d|2[0-3]):[0-5]\d', item.get('time', '')) or item.get('time') == '', f"itinerary {item.get('uid')}: time must be HH:mm or empty")
            if item.get('durationMinutes') is not None:
                check(isinstance(item['durationMinutes'], int) and 1 <= item['durationMinutes'] <= 1440 and item.get('time'), f"itinerary {item.get('uid')}: duration 1–1440 needs a start time")
            if item.get('time'): timed.append(item)
        times = [i['time'] for i in timed]
        r.warn(times == sorted(times), f"itinerary {day['date']}: items are not in time order")
        ends = []
        for item in timed:
            h, m = map(int, item['time'].split(':'))
            place = next((p for p in places if p['id'] == item['place']), None)
            minutes = item.get('durationMinutes') or int(((place or {}).get('hours') or 1) * 60)
            ends.append((h * 60 + m, h * 60 + m + minutes, item['uid']))
        for (s1, e1, a), (s2, e2, b) in zip(ends, ends[1:]):
            r.warn(e1 <= s2, f"itinerary {day['date']}: {a} overlaps {b}")
        r.warn(sum(e - s for s, e, _ in ends) <= 12 * 60, f"itinerary {day['date']}: more than 12 planned hours")
    check(len(set(uids)) == len(uids) and all(ID.match(u or '') for u in uids), 'itinerary.json: uids must be unique ids')
    budget = itinerary.get('budget', {})
    check(set(budget) == {'flightOut', 'flightReturn', 'hotel', 'food', 'transport', 'other'} and all(finite(v) and v <= MAX_BUDGET for v in budget.values()),
          'itinerary.budget must be {flightOut, flightReturn, hotel, food, transport, other}, each 0–10000000')

    # locations
    locations = (load(content, 'locations.json', required=False) or {}).get('locations', {})
    for identifier, loc in locations.items():
        check(identifier in all_ids, f'locations.json: unknown place {identifier}')
        coordinates = loc.get('coordinates', [])
        check(len(coordinates) == 2 and inside(*coordinates), f'locations.json: {identifier} outside trip.map.bounds')
        check(text(loc.get('address')) and https(loc.get('source')), f'locations.json: {identifier} needs address and https source')
    r.warn(all(p['id'] in locations for p in places), 'some places have no coordinates: ' + ', '.join(p['id'] for p in places if p['id'] not in locations))

    # preparation
    prep = load(content, 'preparation.json')['items']
    prep_ids = [p.get('id') for p in prep]
    check(len(set(prep_ids)) == len(prep_ids), 'preparation.json: duplicate ids')
    for item in prep:
        path = f"preparation.{item.get('id')}"
        check(ID.match(item.get('id', '')) and text(item.get('group')) and text(item.get('title')) and item.get('body'), path + ': id, group, title, body required')
        if item.get('dueDate') is not None:
            check(valid_date(item['dueDate']) and (not days or item['dueDate'] <= days[-1]), path + ': dueDate must be a date no later than the trip end')
        check(all(text(l.get('label')) and https(l.get('url')) for l in item.get('links', [])), path + ': links need label + https url')
        check(not re.search(r'\b[A-Z]{1,2}\d{7,9}\b', json.dumps(item, ensure_ascii=False)), path + ': looks like it contains a passport/ID number')

    # hotels
    hotels = load(content, 'hotels.json', required=False) or {'hotels': []}
    for hotel in hotels['hotels']:
        path = f"hotel.{hotel.get('id')}"
        check(ID.match(hotel.get('id', '')) and text(hotel.get('name')) and text(hotel.get('address')), path + ': id, name, address required')
        check(len(hotel.get('coords', [])) == 2 and inside(*hotel['coords']), path + ': coords outside trip.map.bounds')
        check(https(hotel.get('source')) and valid_date(hotel.get('checkedAt')), path + ': needs https source and checkedAt')
        check((content / hotel.get('photo', {}).get('file', '')).is_file(), path + ': photo.file missing')
        for room in hotel.get('rooms', []):
            quote = room.get('quote', {})
            check(quote.get('status') in QUOTE_STATUS, f"{path}.{room.get('name')}: quote.status must be one of {sorted(QUOTE_STATUS)}")
            if quote.get('status') == 'available':
                check(finite(quote.get('totalHome')) and quote['totalHome'] > 0, f"{path}.{room.get('name')}: available quote needs totalHome (full-stay total, home currency)")

    # photos
    for pid, album in ((load(content, 'photo-sources.json', required=False) or {}).get('albums', {})).items():
        check(pid in all_ids, f'photo-sources.json: unknown place {pid}')
        for photo in album.get('photos', []):
            path = f"photo {photo.get('file')}"
            check((content / photo.get('file', '')).is_file(), path + ': file missing')
            check(text(photo.get('creator')) and text(photo.get('license')) and https(photo.get('licenseUrl')) and https(photo.get('sourceUrl')), path + ': creator, license, licenseUrl, sourceUrl required')

    # posts
    posts = (load(content, 'posts.json', required=False) or {}).get('posts', [])
    post_ids = [p.get('id') for p in posts]
    check(len(set(post_ids)) == len(post_ids), 'posts.json: duplicate ids')
    for post in posts:
        path = f"post.{post.get('id')}"
        check(ID.match(post.get('id', '')) and text(post.get('title')) and text(post.get('platform')) and https(post.get('url')), path + ': id, platform, title, https url required')
        check(valid_date(post.get('capturedAt')) and post.get('images'), path + ': capturedAt and at least one image required')
        check([i.get('order') for i in post.get('images', [])] == list(range(1, len(post.get('images', [])) + 1)), path + ': image order must be 1..n')
        check(all((content / i.get('file', '')).is_file() for i in post.get('images', [])), path + ': image file missing')
        check(set(post.get('guidePlaces', [])) <= set(all_ids), path + ': unknown guidePlaces')

    # phrases
    for section in (load(content, 'phrases.json', required=False) or {}).get('sections', []):
        check(ID.match(section.get('id', '')) and text(section.get('title')), f"phrases: section {section.get('id')} needs id and title")
        check(all(text(i.get('native')) and text(i.get('local')) for i in section.get('items', [])), f"phrases.{section.get('id')}: every item needs native and local")

    # flights
    for flight in (load(content, 'flights.json', required=False) or {}).get('flights', []):
        timed = valid_date(flight.get('departure')) and valid_date(flight.get('arrival'))
        check(text(flight.get('number')) and timed and flight['departure'] < flight['arrival'],
              f"flight {flight.get('id')}: number and yyyy-MM-ddTHH:mm departure < arrival required")

    stats = {'days': len(days), 'places': len(places), 'restaurants': len(venues), 'preparation': len(prep), 'hotels': len(hotels['hotels']), 'posts': len(posts), 'locations': len(locations)}
    if dining:
        stats.update(validate_dining(r, dining, trip, days, inside, require_complete))

    if require_complete:
        for name in sorted(p.name for p in content.glob('*.json')):
            raw = (content / name).read_text()
            for match in sorted(set(PLACEHOLDER.findall(raw))):
                check(False, f'{name}: contains placeholder/sample text "{match}"')
        check(len(places) >= 5, 'complete gate: at least 5 places')
        check(all(p['id'] in locations for p in places), 'complete gate: every place needs coordinates in locations.json')
        check(len(prep) >= 10, 'complete gate: at least 10 preparation items')

    if built is not None:
        check(built.get('trip') == trip, 'catalog.json trip differs from content/trip.json; rerun build_ios_resources.py')
        check([d['date'] for d in built.get('catalog', {}).get('days', [])] == days, 'catalog.json days are stale; rerun build_ios_resources.py')
        check(built.get('dining') == dining if dining else True, 'catalog.json dining is stale; rerun build_ios_resources.py')
    return r, stats


def validate_dining(r, document, trip, days, inside, require_complete):
    check = r.check
    directory = document.get('directory', {})
    check(re.fullmatch(r'[A-Z]{3}', document.get('currency', '')) and document['currency'] == trip['currency']['local'], 'dining.currency must equal trip.currency.local')
    statuses = {'verified', 'partial', 'unverified'} | (set() if require_complete else {'sample'})
    check(directory.get('status') in statuses, f'dining.directory.status must be one of {sorted(statuses)}')
    check(isinstance(directory.get('edition'), int) and https(directory.get('sourceURL')), 'dining.directory needs integer edition and https sourceURL')
    venues = document.get('restaurants', [])
    ids = [v.get('id') for v in venues]
    check(len(ids) == len(set(ids)), 'dining: duplicate restaurant ids')
    star_counts, depth = Counter(), Counter()
    for venue in venues:
        path = f"restaurant.{venue.get('id')}"
        check(ID.match(venue.get('id', '')), path + ': invalid id')
        for field in ('name', 'en', 'zone', 'description', 'hours', 'address'):
            check(text(venue.get(field)), f'{path}.{field} required')
        check(venue.get('type') in VENUE_TYPES, path + ': invalid type')
        check(venue.get('depth') in DEPTHS, path + ': invalid depth')
        depth[venue.get('depth')] += 1
        check(bool(venue.get('cuisines')), path + ': cuisines required')
        check(bool(venue.get('sources')) and all(text(s.get('title')) and https(s.get('url')) and valid_date(s.get('checkedAt')) for s in venue.get('sources', [])), path + ': dated https sources required')
        if venue.get('closedWeekdays') is not None:
            check(all(type(d) is int and 1 <= d <= 7 for d in venue['closedWeekdays']), path + ': closedWeekdays use ISO 1 (Mon)…7 (Sun)')
        if c := venue.get('coordinates'):
            check(inside(c.get('latitude'), c.get('longitude')), path + ': coordinates outside trip.map.bounds')
        award = venue.get('award', {})
        check(award.get('kind') in AWARDS, path + ': invalid award.kind')
        if award.get('kind') == 'stars':
            check(award.get('stars') in {1, 2, 3}, path + ': stars must be 1–3')
            star_counts[award['stars']] += 1
        if award.get('kind') in {'stars', 'bibGourmand', 'selected'}:
            check(award.get('year') == directory.get('edition') and https(award.get('sourceURL')), path + ': award needs year == directory.edition and an https sourceURL')
        if venue.get('pricingStatus') is not None:
            check(venue['pricingStatus'] in PRICE_STATUS, path + ': invalid pricingStatus')
        for i, menu in enumerate(venue.get('menus', [])):
            label = f'{path}.menu.{i}'
            check(menu.get('meal') in MEALS and menu.get('basis') in BASES and menu.get('tax') in TAXES, label + ': invalid meal/basis/tax')
            check(https(menu.get('sourceURL')) and valid_date(menu.get('checkedAt')), label + ': each menu needs its own sourceURL + checkedAt')
            price, maximum = menu.get('price'), menu.get('priceMax')
            check(price is None or (finite(price) and price > 0), label + ': price must be > 0 or null')
            check(maximum is None or (finite(maximum) and price is not None and maximum >= price), label + ': invalid price range')
            if menu.get('serviceChargePercent') is not None or menu.get('taxPercent') is not None:
                check(menu.get('tax') == '++', label + ': explicit added rates require tax "++"')
            if price is None:
                check(bool(re.search(r'未核实|未公布|未公开|unpublished|unverified', menu.get('name', '') + menu.get('includes', ''), re.I)), label + ': null price must say unverified vs unpublished')
        booking = venue.get('booking', {})
        check(text(booking.get('policy')) and booking.get('availability') in AVAILABILITY and valid_date(booking.get('checkedAt')), path + ': booking needs policy, valid availability, checkedAt')
        check(not booking.get('url') or https(booking['url']), path + ': booking.url must be https')
        observations = booking.get('observations') or []
        if booking.get('availability') in {'available', 'full', 'soldOut'}:
            check(bool(observations), path + ': an availability claim needs dated observations')
        for j, obs in enumerate(observations):
            label = f'{path}.observation.{j}'
            check(obs.get('date') in days and obs.get('meal') in PLAN_MEALS and obs.get('status') in OBSERVATIONS, label + ': date within trip, valid meal and status required')
            check(obs.get('partySize') == trip.get('partySize'), label + ': partySize must equal trip.partySize')
            check(https(obs.get('sourceURL')) and valid_date(obs.get('checkedAt')) and text(obs.get('detail')), label + ': sourceURL, checkedAt, detail required')
            check(not obs.get('live') and not LIVE_CLAIM.search(obs.get('detail', '')), label + ': a snapshot cannot claim live or guaranteed availability')
        if require_complete and venue.get('depth') == 'detailed':
            check(any(finite(m.get('price')) for m in venue.get('menus', [])) or venue.get('pricingStatus') == 'notPublished', path + ': detailed entry needs a sourced price or notPublished')
            check(text(booking.get('url')), path + ': detailed entry needs a booking url')
    if counts := directory.get('counts'):
        normalized = {int(k): v for k, v in counts.items()}
        check(dict(star_counts) == normalized, f'dining: star counts {dict(star_counts)} differ from directory.counts {normalized}')
    elif require_complete and star_counts:
        check(False, 'dining: starred directory needs directory.counts from the cited full list')
    for kind in ('guides', 'recommendations'):
        for entry in document.get(kind) or []:
            path = f"dining.{kind}.{entry.get('id')}"
            check(entry.get('restaurantIDs') and set(entry['restaurantIDs']) <= set(ids), path + ': unknown or missing restaurantIDs')
            if kind == 'recommendations':
                check(type(entry.get('day')) is int and 0 <= entry['day'] < len(days) and entry.get('meal') in PLAN_MEALS, path + ': day index within trip and valid meal')
    return {'stars': dict(sorted(star_counts.items())), 'diningDepths': dict(depth)}


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--content', type=Path, default=ROOT / 'content')
    parser.add_argument('--require-complete', action='store_true')
    parser.add_argument('--built-catalog', type=Path, nargs='?', const=ROOT / 'ios/TripJournal/Resources/Content/catalog.json')
    args = parser.parse_args()
    try:
        built = json.loads(args.built_catalog.read_text()) if args.built_catalog else None
        report, stats = validate(args.content, args.require_complete, built)
    except (OSError, ValueError, KeyError, TypeError) as error:
        print('FAIL: ' + str(error), file=sys.stderr)
        return 1
    for warning in report.warnings: print('WARN: ' + warning)
    for error in report.errors: print('FAIL: ' + error, file=sys.stderr)
    print(json.dumps(stats, ensure_ascii=False, sort_keys=True))
    gate = 'complete content gate' if args.require_complete else 'structure gate'
    print(('FAIL' if report.errors else 'PASS') + f': {gate} ({len(report.errors)} errors, {len(report.warnings)} warnings)')
    return 1 if report.errors else 0


if __name__ == '__main__':
    sys.exit(main())
