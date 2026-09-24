"""A small inline trip catalog for tests, shaped like the generated catalog.json."""
import copy
from datetime import date, timedelta
import json
from pathlib import Path

from trip_catalog import load_catalog

BOUNDS = {'minLat': 19.94, 'maxLat': 20.06, 'minLon': -150.08, 'maxLon': -149.92}
INSIDE = [20.01, -150.02]
INSIDE_OTHER = [20.02, -150.01]

PLACES = [
    {'id': 'harbor-light', 'name': '灯塔', 'en': 'Harbor Light', 'zone': 'North', 'kind': '地标', 'hours': 1, 'budget': 0,
     'desc': '', 'tip': '', 'travel': '', 'rain': '', 'food': '', 'link': 'https://example.com/light'},
    {'id': 'maritime-museum', 'name': '博物馆', 'en': 'Maritime Museum', 'zone': 'North', 'kind': '博物馆', 'hours': 2, 'budget': 20,
     'desc': '', 'tip': '', 'travel': '', 'rain': '', 'food': '', 'link': ''},
    {'id': 'harbor-noodles', 'name': '面馆', 'en': 'Harbor Noodles', 'zone': 'North', 'kind': '餐饮', 'hours': 1, 'budget': 0,
     'desc': '', 'tip': '', 'travel': '', 'rain': '', 'food': '', 'link': ''},
]


def document(days=3, start='2030-05-01', trip_id='fixture-trip-v1'):
    first = date.fromisoformat(start)
    dates = [(first + timedelta(days=i)).isoformat() for i in range(days)]
    trip = {'id': trip_id, 'timezone': 'Pacific/Honolulu', 'startDate': dates[0], 'endDate': dates[-1],
            'departureDate': (first - timedelta(days=1)).isoformat(), 'partySize': 2,
            'destination': {'name': '示例城', 'nameEn': 'Sample Bay', 'countryCode': 'XS',
                            'addressSuffix': 'Sample Bay', 'postcodePattern': r'\d{5}'},
            'currency': {'local': 'USD', 'home': 'CNY'},
            'map': {'center': [20.0, -150.0], 'span': [0.12, 0.16], 'bounds': dict(BOUNDS)}}
    itinerary = [{'date': d, 'title': f'Day {i + 1}', 'area': '', 'note': '',
                  'items': [{'uid': f'd{i + 1}-a', 'place': PLACES[i % 2]['id'], 'time': '10:00', 'note': ''}]}
                 for i, d in enumerate(dates)]
    defaults = {'version': 1, 'id': trip_id, 'days': copy.deepcopy(itinerary), 'custom': [], 'checks': {},
                'budget': {'flightOut': 0, 'flightReturn': 0, 'hotel': 600, 'food': 300, 'transport': 80, 'other': 0},
                'hotelFavorites': [], 'stays': [], 'tickets': {}}
    return {'trip': trip, 'catalog': {'places': copy.deepcopy(PLACES), 'days': itinerary}, 'defaults': defaults}


def write_catalog(directory, **options):
    path = Path(directory) / 'catalog.json'
    path.write_text(json.dumps(document(**options), ensure_ascii=False))
    return path


def catalog(directory, **options):
    return load_catalog(write_catalog(directory, **options))
