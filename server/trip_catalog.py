"""Read the generated content catalog and the trip's map region. Standard library only.

The catalog is produced by scripts/build_ios_resources.py from content/*.json; the server
never parses content/ itself, so the app and the server always validate the same trip.
"""
from datetime import date, timedelta
import json
import math
import os
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_CATALOG = ROOT / 'ios/TripJournal/Resources/Content/catalog.json'
MAX_DAYS = 60


def catalog_path(value=None):
    return Path(value or os.environ.get('TRIP_CATALOG') or DEFAULT_CATALOG)


def trip_dates(trip):
    start, end = date.fromisoformat(trip['startDate']), date.fromisoformat(trip['endDate'])
    count = (end - start).days + 1
    if not 1 <= count <= MAX_DAYS:
        raise ValueError(f'trip must last 1-{MAX_DAYS} days')
    return [(start + timedelta(days=i)).isoformat() for i in range(count)]


def load_catalog(path=None):
    """Return {'trip', 'places', 'days', 'defaults'} from catalog.json, checked for consistency."""
    document = json.loads(catalog_path(path).read_text())
    trip, catalog, defaults = document['trip'], document['catalog'], document['defaults']
    if [day['date'] for day in catalog['days']] != trip_dates(trip):
        raise ValueError('catalog days must match trip startDate..endDate')
    if defaults.get('id') != trip['id']:
        raise ValueError('catalog defaults must belong to trip.id')
    region_for(trip)
    return {'trip': trip, 'places': catalog['places'], 'days': catalog['days'], 'defaults': defaults}


class Region:
    """Map bounds plus the destination words an address may not consist of alone."""

    def __init__(self, min_lat=-90, max_lat=90, min_lon=-180, max_lon=180, place_words=(), postcode=''):
        values = (min_lat, max_lat, min_lon, max_lon)
        if any(type(v) not in (int, float) or not math.isfinite(v) for v in values) or \
                not (-90 <= min_lat < max_lat <= 90 and -180 <= min_lon < max_lon <= 180):
            raise ValueError('invalid map bounds')
        self.min_lat, self.max_lat, self.min_lon, self.max_lon = values
        words = [re.escape(w) for w in place_words if isinstance(w, str) and w.strip()]
        parts = [r'\b(?:' + '|'.join(words) + r')\b'] if words else []
        if postcode:
            parts.append(r'\b(?:' + postcode + r')\b')
        self.generic = re.compile('(?i)' + '|'.join(parts)) if parts else None

    def contains(self, lat, lon):
        return self.min_lat <= lat <= self.max_lat and self.min_lon <= lon <= self.max_lon

    def is_generic_address(self, address):
        """True when nothing but the city/country name, postcode and separators remains."""
        rest = self.generic.sub('', address) if self.generic else address
        return not re.sub(r'[,\s]', '', rest)


def region_for(trip=None):
    """Bounds from TRIP_MAP_BOUNDS="minLat,maxLat,minLon,maxLon", else trip.map.bounds, else the world."""
    destination = (trip or {}).get('destination', {})
    words = (destination.get('nameEn'), destination.get('addressSuffix'), destination.get('countryCode'))
    postcode = destination.get('postcodePattern', '')
    override = os.environ.get('TRIP_MAP_BOUNDS', '').strip()
    if override:
        try:
            min_lat, max_lat, min_lon, max_lon = (float(v) for v in override.split(','))
        except ValueError:
            raise ValueError('TRIP_MAP_BOUNDS must be minLat,maxLat,minLon,maxLon') from None
        return Region(min_lat, max_lat, min_lon, max_lon, words, postcode)
    if trip is None:
        return Region()
    b = trip['map']['bounds']
    return Region(b['minLat'], b['maxLat'], b['minLon'], b['maxLon'], words, postcode)
