#!/usr/bin/env python3
"""Build the app's bundled content from content/. Requires Pillow.

content/*.json (+ content/media/) -> ios/TripJournal/Resources/Content/
  catalog.json      everything the app decodes as ContentCatalog
  trip.json         destination config (also read by the widget)
  place-locations.json
  media/            copied originals and generated thumbnails
  manifest.json     path, bytes and SHA-256 of every bundled file
and ios/Generated.xcconfig (APP_DISPLAY_NAME from trip.json).
"""
import argparse, hashlib, io, json, shutil, sys
from datetime import date, timedelta
from pathlib import Path
from PIL import Image, ImageOps

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'server'))
from dining_content import merge_dining_places

CONTENT = ROOT / 'content'
OUT = ROOT / 'ios/TripJournal/Resources/Content'
XCCONFIG = ROOT / 'ios/Generated.xcconfig'


def digest(data): return hashlib.sha256(data).hexdigest()


def trip_days(trip):
    start, end = date.fromisoformat(trip['startDate']), date.fromisoformat(trip['endDate'])
    if end < start or (end - start).days > 59: raise ValueError('trip.json: endDate must be 0–59 days after startDate')
    return [(start + timedelta(days=i)).isoformat() for i in range((end - start).days + 1)]


def inside(bounds, latitude, longitude):
    return bounds['minLat'] <= latitude <= bounds['maxLat'] and bounds['minLon'] <= longitude <= bounds['maxLon']


def build(content=CONTENT, out=OUT, xcconfig=XCCONFIG):
    def read(name, required=True):
        path = content / name
        if not path.exists():
            if required: raise FileNotFoundError(path)
            return None
        return json.loads(path.read_text())

    trip = read('trip.json')
    days = trip_days(trip)
    itinerary = read('itinerary.json')
    if [d['date'] for d in itinerary['days']] != days:
        raise ValueError('itinerary.json: days must match trip.json startDate..endDate one-to-one')
    catalog = {'places': read('places.json')['places'], 'days': itinerary['days']}
    dining = read('dining.json', required=False)
    if dining and dining.get('restaurants'):
        catalog = merge_dining_places(catalog, dining)
    else:
        dining = None
    place_ids = [p['id'] for p in catalog['places']]
    if len(set(place_ids)) != len(place_ids): raise ValueError('Duplicate place id')
    for item in (i for d in catalog['days'] for i in d['items']):
        if item['place'] not in place_ids: raise ValueError('Itinerary references unknown place: ' + item['place'])

    if out.exists(): shutil.rmtree(out)
    media = out / 'media'; media.mkdir(parents=True)

    def save(name, raw):
        p = media / name; p.parent.mkdir(parents=True, exist_ok=True); p.write_bytes(raw)
        return 'media/' + name

    def thumbnail(name, raw, size=(600, 450)):
        with Image.open(io.BytesIO(raw)) as im:
            im = ImageOps.fit(ImageOps.exif_transpose(im).convert('RGB'), size, Image.Resampling.LANCZOS)
            b = io.BytesIO(); im.save(b, 'JPEG', quality=80, optimize=True)
            return save(name, b.getvalue())

    def source_image(relative):
        raw = (content / relative).read_bytes()
        with Image.open(io.BytesIO(raw)) as im:
            im.verify()
        return raw

    def size(raw):
        with Image.open(io.BytesIO(raw)) as im:
            return ImageOps.exif_transpose(im).size

    # Plan defaults: the synced document starts from the itinerary with empty user state.
    defaults = {'version': 1, 'id': trip['id'], 'days': itinerary['days'], 'custom': [], 'checks': {},
                'budget': itinerary['budget'], 'hotelFavorites': [], 'stays': [], 'tickets': {}}

    preparation = read('preparation.json')['items']
    for prep in preparation:
        if prep.get('guideImage'):
            prep['guideImage'] = save('preparation/' + Path(prep['guideImage']).name, source_image(prep['guideImage']))

    photos = {}
    for pid, album in (read('photo-sources.json', required=False) or {}).get('albums', {}).items():
        if pid not in place_ids: raise ValueError('photo-sources.json: unknown place ' + pid)
        entries = []
        for i, photo in enumerate(album['photos']):
            raw = source_image(photo.pop('file'))
            width, height = size(raw)
            entries.append({**photo, 'path': save(f'photos/{pid}-{i}.jpg', raw), 'width': width, 'height': height})
        first = (out / entries[0]['path']).read_bytes()
        photos[pid] = {'thumb': thumbnail(f'photos/{pid}-cover.jpg', first, (480, 300)), 'photos': entries}

    posts = read('posts.json', required=False)
    posts = posts['posts'] if posts else []
    for post in posts:
        for img in post['images']:
            raw = source_image(img.pop('file'))
            img['width'], img['height'] = size(raw)
            img['path'] = save(f"posts/{post['id']}/{img['order']:02d}.jpg", raw)
        post['thumb'] = thumbnail(f"posts/{post['id']}-thumb.jpg", (out / post['images'][0]['path']).read_bytes())
        for pid in post.get('guidePlaces', []):
            if pid not in place_ids: raise ValueError(f"posts.json: {post['id']} references unknown place {pid}")

    hotels = read('hotels.json', required=False) or {'hotels': []}
    for hotel in hotels['hotels']:
        raw = source_image(hotel['photo'].pop('file'))
        hotel['photo']['path'] = save(f"hotels/{hotel['id']}.jpg", raw)
        hotel['thumb'] = thumbnail(f"hotels/{hotel['id']}-thumb.jpg", raw)

    locations = read('locations.json', required=False) or {'locations': {}}
    for restaurant in (dining or {}).get('restaurants', []):
        if coordinates := restaurant.get('coordinates'):
            locations['locations'][restaurant['id']] = {
                'name': restaurant['en'], 'address': restaurant['address'],
                'coordinates': [coordinates['latitude'], coordinates['longitude']],
                'source': restaurant['sources'][0]['url'],
            }
    for identifier, location in locations['locations'].items():
        latitude, longitude = location['coordinates']
        if identifier not in place_ids: raise ValueError('locations.json: unknown place ' + identifier)
        if not inside(trip['map']['bounds'], latitude, longitude):
            raise ValueError(f'locations.json: {identifier} is outside trip.json map.bounds')
    for hotel in hotels['hotels']:
        if not inside(trip['map']['bounds'], *hotel['coords']):
            raise ValueError(f"hotels.json: {hotel['id']} is outside trip.json map.bounds")

    data = {
        'trip': trip,
        'catalog': catalog,
        'defaults': defaults,
        'preparation': preparation,
        'hotels': {'hotels': hotels['hotels']},
        'photos': photos,
        'posts': posts,
        'references': (read('references.json', required=False) or {'references': []})['references'],
        'flights': (read('flights.json', required=False) or {'flights': []})['flights'],
        'locations': locations['locations'],
        'phrases': (read('phrases.json', required=False) or {'sections': []})['sections'],
    }
    if dining: data['dining'] = dining

    (out / 'trip.json').write_text(json.dumps(trip, ensure_ascii=False, indent=2) + '\n')
    (out / 'place-locations.json').write_text(json.dumps(locations, ensure_ascii=False, indent=2) + '\n')
    (out / 'catalog.json').write_text(json.dumps(data, ensure_ascii=False, separators=(',', ':')) + '\n')
    manifest = [{'path': str(p.relative_to(out)), 'bytes': p.stat().st_size, 'sha256': digest(p.read_bytes())}
                for p in sorted(out.rglob('*')) if p.is_file() and p.name != 'manifest.json']
    (out / 'manifest.json').write_text(json.dumps(manifest, separators=(',', ':')) + '\n')
    name = trip['appName'].replace('\n', ' ').strip()
    xcconfig.write_text('// Generated by scripts/build_ios_resources.py from content/trip.json. Do not edit.\n'
                        f'APP_DISPLAY_NAME = {name}\n')
    summary = {'days': len(days), 'places': len(place_ids), 'posts': len(posts), 'photos': sum(len(a['photos']) for a in photos.values()),
               'preparation': len(preparation), 'phrases': sum(len(s['items']) for s in data['phrases']),
               'files': len(manifest), 'bytes': sum(f['bytes'] for f in manifest)}
    return summary


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.parse_args()
    print(json.dumps(build(), indent=2))
