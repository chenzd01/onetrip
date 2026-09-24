"""Search a deployment-owned OSM snapshot; no external geocoder or user data."""
import json
import os
from pathlib import Path
import threading
import unicodedata
from route_engine import RoutingError, route_root


def normalized(value):
    return ''.join(c for c in unicodedata.normalize('NFKD', value.casefold()) if not unicodedata.combining(c))


class RoutePlaces:
    def __init__(self, path=None):
        self.path = Path(path or os.environ.get('TRIP_ROUTE_PLACES') or route_root() / 'places.json')
        self.index = None
        self.lock = threading.Lock()

    def search(self, query):
        if not isinstance(query, str) or not 2 <= len(query.strip()) <= 160:
            raise RoutingError(422, '请输入至少两个字母或汉字的地点名或地址')
        with self.lock:
            if self.index is None:
                try:
                    data = json.loads(self.path.read_text())['places']
                    self.index = [(p, normalized(p['name'] + ' ' + p['address'] + ' ' + p.get('aliases', ''))) for p in data]
                except (OSError, ValueError, KeyError, TypeError):
                    raise RoutingError(503, '地点搜索暂时不可用，请稍后重试') from None
        phrase = normalized(query.strip())
        words = phrase.split()
        matches = [(p, text) for p, text in self.index if all(w in text for w in words)]
        matches.sort(key=lambda item: (phrase not in [normalized(part) for part in item[0]['name'].split(' · ')], phrase not in normalized(item[0]['name']), len(item[0]['name'])))
        return {'places': [{k: p[k] for k in ('name', 'address', 'latitude', 'longitude')} for p, _ in matches[:20]],
                'source': 'OpenStreetMap'}
