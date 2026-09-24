#!/usr/bin/env python3
"""Build the optional backend's place-search index from an OpenStreetMap extract.

Usage:
  python3 scripts/build_route_places.py region.osm.pbf places.json --country JP \
      [--trip content/trip.json] [--native-name name:ja]
Keeps named POIs and streets inside trip.json map.bounds AND inside the country's
admin_level=2 boundary (ISO3166-1 = --country), so same-name places across a border
are excluded. Requires pinned pyosmium and shapely. No itinerary data is read.
"""
import argparse, json
from pathlib import Path
import osmium
from shapely.geometry import Point, shape
from shapely.prepared import prep

ROOT = Path(__file__).resolve().parents[1]


class Places(osmium.SimpleHandler):
    def __init__(self, bounds, country, suffix, native_key):
        super().__init__()
        self.bounds, self.country, self.suffix, self.native_key = bounds, country, suffix, native_key
        self.places, self.boundary = [], None
        self.factory = osmium.geom.GeoJSONFactory()

    def add(self, tags, lat, lon, source):
        b = self.bounds
        if not (b['minLat'] <= lat <= b['maxLat'] and b['minLon'] <= lon <= b['maxLon']): return
        name = tags.get('name:en') or tags.get('name')
        if not name: return
        native = tags.get(self.native_key) if self.native_key else None
        address = ', '.join(filter(None, [' '.join(filter(None, [tags.get('addr:housenumber'), tags.get('addr:street')])),
                                         tags.get('addr:unit'), tags.get('addr:postcode'), self.suffix]))
        self.places.append({'name': name + (' · ' + native if native and native != name else ''),
                            'address': address, 'latitude': round(lat, 7), 'longitude': round(lon, 7),
                            'aliases': ' '.join(v for k, v in tags.items() if k in ('name', 'name:en', self.native_key, 'alt_name', 'short_name', 'brand')),
                            'source': source})

    def area(self, area):
        tags = dict(area.tags)
        if tags.get('admin_level') == '2' and tags.get('ISO3166-1') == self.country:
            self.boundary = shape(json.loads(self.factory.create_multipolygon(area)))

    def node(self, n):
        if n.location.valid(): self.add(dict(n.tags), n.location.lat, n.location.lon, 'node/' + str(n.id))

    def way(self, w):
        tags = dict(w.tags)
        if not (tags.get('name') or tags.get('name:en')): return
        points = [(n.lat, n.lon) for n in w.nodes if n.location.valid()]
        if points:
            self.add(tags, sum(p[0] for p in points) / len(points), sum(p[1] for p in points) / len(points), 'way/' + str(w.id))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('pbf'); parser.add_argument('output')
    parser.add_argument('--country', required=True, help='ISO 3166-1 alpha-2 code of the destination country')
    parser.add_argument('--trip', type=Path, default=ROOT / 'content/trip.json')
    parser.add_argument('--native-name', default=None, help='OSM tag for a second display name, e.g. name:zh or name:ja')
    args = parser.parse_args()
    trip = json.loads(args.trip.read_text())
    handler = Places(trip['map']['bounds'], args.country, trip['destination'].get('addressSuffix', ''), args.native_name)
    handler.apply_file(args.pbf, locations=True, idx='flex_mem')
    if handler.boundary is None: raise SystemExit(f'the extract must contain the complete {args.country} national boundary')
    boundary = prep(handler.boundary)
    handler.places = [p for p in handler.places if boundary.covers(Point(p['longitude'], p['latitude']))]
    Path(args.output).write_text(json.dumps({'attribution': '© OpenStreetMap contributors', 'license': 'ODbL 1.0',
                                             'places': handler.places}, ensure_ascii=False, separators=(',', ':')))
    print('Indexed', len(handler.places), 'public places')
