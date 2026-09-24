"""Independent, revisioned route settings. Never rewrites the shared trip document."""
import json
import math
import os
import re
import sqlite3
import time
import unicodedata
from trip_catalog import Region


def validate_preferences(state, trip_id, region=None):
    region = region or Region()
    def text(value, limit=500):
        return isinstance(value, str) and 0 < len(value) <= limit
    if not isinstance(state, dict) or set(state) != {'tripID', 'values'} or state['tripID'] != trip_id:
        raise ValueError('路线设置不属于这次旅行')
    values = state['values']
    if not isinstance(values, dict) or len(values) > 2000:
        raise ValueError('路线设置数量无效')
    for key, entry in values.items():
        if not text(key) or not isinstance(entry, dict) or not {'kind', 'title'} <= set(entry) or set(entry) - {'kind', 'title', 'value', 'location', 'englishAddress'}:
            raise ValueError('路线设置无效')
        kind = entry['kind']
        if kind not in ('startHotel', 'endHotel', 'mode', 'location', 'englishAddress') or not text(entry['title']):
            raise ValueError('路线设置类型无效')
        if kind != 'englishAddress' and 'englishAddress' in entry:
            raise ValueError('英文地址记录无效')
        if kind == 'englishAddress':
            address = entry.get('englishAddress')
            if not key.startswith('address:') or 'value' in entry or 'location' in entry or not isinstance(address, dict) or set(address) != {'name', 'address'}:
                raise ValueError('英文地址记录无效')
            for field, limit in (('name', 500), ('address', 1000)):
                value = address[field]
                if not text(value, limit) or not re.search('[A-Za-z]', value) or any(c.isalpha() and 'LATIN' not in unicodedata.name(c, '') for c in value) or '://' in value:
                    raise ValueError('请填写英文地点名和地址')
            if region.is_generic_address(address['address']):
                raise ValueError('请填写具体英文地址')
        elif kind == 'location':
            point = entry.get('location')
            if 'value' in entry or not isinstance(point, dict) or set(point) != {'name', 'address', 'latitude', 'longitude'}:
                raise ValueError('地点位置无效')
            if not text(point['name']) or not isinstance(point['address'], str) or len(point['address']) > 1000:
                raise ValueError('地点名称或地址无效')
            lat, lon = point['latitude'], point['longitude']
            if any(type(v) not in (int, float) or not math.isfinite(v) for v in (lat, lon)) or not region.contains(lat, lon):
                raise ValueError('请选择旅行地图范围内的位置')
        elif 'location' in entry or not text(entry.get('value'), 120) or (kind == 'mode' and entry['value'] not in ('walking', 'driving')):
            raise ValueError('酒店或交通方式无效')


class RoutePreferencesService:
    def __init__(self, database):
        self.database = database
        with self.connect() as db:
            db.execute('CREATE TABLE IF NOT EXISTS route_preferences(id INTEGER PRIMARY KEY CHECK(id=1), revision INTEGER NOT NULL, document TEXT NOT NULL, updated_at INTEGER NOT NULL)')

    def connect(self):
        db = sqlite3.connect(self.database, timeout=10)
        db.row_factory = sqlite3.Row
        return db

    @property
    def english_address_sharing(self):
        # Enable only after both phones have installed a reader supporting englishAddress.
        return os.environ.get('TRIP_ROUTE_ENGLISH_ADDRESS_SHARING') == '1'

    def snapshot(self, trip_id):
        with self.connect() as db:
            row = db.execute('SELECT * FROM route_preferences WHERE id=1').fetchone()
            return self.decode(row, trip_id)

    @staticmethod
    def decode(row, trip_id):
        if row is None:
            return {'revision': 0, 'state': {'tripID': trip_id, 'values': {}}, 'updatedAt': 0}
        return {'revision': row['revision'], 'state': json.loads(row['document']), 'updatedAt': row['updated_at']}

    def update(self, expected, state, trip_id, region=None):
        if type(expected) is not int or expected < 0:
            raise ValueError('路线设置版本无效')
        validate_preferences(state, trip_id, region)
        with self.connect() as db:
            db.execute('BEGIN IMMEDIATE')
            latest = self.decode(db.execute('SELECT * FROM route_preferences WHERE id=1').fetchone(), trip_id)
            if not self.english_address_sharing:
                addresses = lambda values: {k: v for k, v in values.items() if v.get('kind') == 'englishAddress'}
                if addresses(state['values']) != addresses(latest['state']['values']):
                    raise ValueError('英文地址共享尚未启用，请等待两部手机更新完成')
            if latest['revision'] != expected:
                return False, latest
            now = int(time.time() * 1000)
            db.execute('INSERT OR REPLACE INTO route_preferences VALUES(1,?,?,?)',
                       (expected + 1, json.dumps(state, ensure_ascii=False, allow_nan=False), now))
            return True, {'revision': expected + 1, 'updatedAt': now}
