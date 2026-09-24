#!/usr/bin/env python3
"""Optional sync backend for the iOS travel journal; Python standard library + SQLite.

Serves a JSON API only. The trip (dates, places, map bounds, default plan) comes from the
generated catalog.json; see server/README.md for endpoints and configuration.
"""
import argparse
import copy
from datetime import datetime
import hashlib
import hmac
import json
import os
import re
import secrets
import sqlite3
import sys
import time
from http.cookies import SimpleCookie, CookieError
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlsplit, unquote, parse_qs
from touch_service import TouchService, TouchError, digest as touch_digest, log as touch_log, short as touch_short

from route_preferences import RoutePreferencesService
from route_engine import RouteEngine, RoutingError
from route_places import RoutePlaces
from trip_catalog import ROOT, load_catalog, region_for

MAX_BODY = 2_000_000
MAX_ATTACHMENT = 10 * 1024 * 1024
MAX_ATTACHMENT_TOTAL = 100 * 1024 * 1024
ATTACHMENT_TYPES = {'image/jpeg', 'image/png', 'image/webp', 'application/pdf'}
COOKIE = 'trip_session'
REVIEW_TOKEN_PREFIX = 'review.'
DEFAULT_PORT = 8765
MAX_BUDGET = 10_000_000  # per budget line / place, local or home currency; fits JPY- or KRW-scale totals
BUDGET_KEYS = {'flightOut', 'flightReturn', 'hotel', 'food', 'transport', 'other'}
TIME = r'(?:[01]\d|2[0-3]):[0-5]\d'


def encode(value):
    return json.dumps(value, ensure_ascii=False, separators=(',', ':'))


def preserve_legacy_fields(state, previous):
    """Missing optional data in older clients is not an explicit deletion."""
    if not isinstance(state, dict):
        return
    for key in ('hotelFavorites', 'stays', 'tickets'):
        if key not in state and key in previous:
            state[key] = previous[key]
    previous_stays = {hotel['id']: hotel for hotel in previous.get('stays', [])}
    if isinstance(state.get('stays'), list):
        for hotel in state['stays']:
            if not isinstance(hotel, dict) or not isinstance(hotel.get('id'), str):
                continue
            old = previous_stays.get(hotel['id'], {})
            if 'nameEnglish' not in hotel and 'nameEnglish' in old:
                hotel['nameEnglish'] = old['nameEnglish']
    meals = {item['uid']: item for day in previous['days'] for item in day['items'] if 'meal' in item}
    if isinstance(state.get('days'), list):
        for day in state['days']:
            if not isinstance(day, dict) or not isinstance(day.get('items'), list):
                continue
            for item in day['items']:
                if isinstance(item, dict) and isinstance(item.get('uid'), str) and 'meal' not in item and item['uid'] in meals:
                    old = meals[item['uid']]
                    if item.get('place') != old['place']:
                        raise ValueError('更换餐饮地点前，请在最新版 App 中核对并更新预约记录')
                    item['meal'] = old['meal']


def validate_plan(plan, catalog, plan_id):
    def text(value, limit=5000):
        if not isinstance(value, str) or len(value) > limit:
            raise ValueError('文字字段无效或过长')
    def number(value, maximum):
        if type(value) not in (int, float) or not 0 <= value <= maximum:
            raise ValueError('预算或时长无效')
    trip = catalog['trip']
    trip_dates = [day['date'] for day in catalog['days']]
    if not isinstance(plan, dict) or plan.get('version') != 1 or plan.get('id') != plan_id or plan_id != trip['id']:
        raise ValueError('不是这个共享行程的有效数据')
    custom = plan.get('custom')
    if not isinstance(custom, list) or len(custom) > 200:
        raise ValueError('自定义地点无效')
    ids = {p['id'] for p in catalog['places']}
    for p in custom:
        if not isinstance(p, dict):
            raise ValueError('地点无效')
        text(p.get('id'), 120)
        if p['id'] in ids:
            raise ValueError('地点编号重复')
        ids.add(p['id'])
        for key in ('name', 'en', 'zone', 'kind', 'desc', 'tip', 'travel', 'rain', 'food', 'link'):
            text(p.get(key))
        if p['link'] and not p['link'].startswith(('https://', 'http://')):
            raise ValueError('地点网址无效')
        number(p.get('hours'), 24); number(p.get('budget'), MAX_BUDGET)
    days = plan.get('days')
    dining_ids = {p['id'] for p in catalog['places'] + custom if p.get('kind') == '餐饮'}
    if not isinstance(days, list) or len(days) != len(trip_dates) or not 1 <= len(days) <= 60:
        raise ValueError(f'必须保留全部 {len(trip_dates)} 天行程')
    uids = set()
    for i, day in enumerate(days):
        if not isinstance(day, dict) or day.get('date') != trip_dates[i]:
            raise ValueError('旅行日期无效')
        for key in ('title', 'area', 'note'):
            text(day.get(key))
        items = day.get('items')
        if not isinstance(items, list) or len(items) > 100:
            raise ValueError('行程卡片无效')
        for item in items:
            if not isinstance(item, dict):
                raise ValueError('行程卡片无效')
            text(item.get('uid'), 120); text(item.get('note')); text(item.get('time'), 5)
            if item['uid'] in uids or item.get('place') not in ids:
                raise ValueError('卡片编号或地点无效')
            if item['time'] and not re.fullmatch(TIME, item['time']):
                raise ValueError('开始时间无效')
            if 'meal' in item:
                if item['place'] not in dining_ids:
                    raise ValueError('用餐安排须选择餐饮地点')
                meal = item['meal']
                if not isinstance(meal, dict) or meal.get('kind') not in ('breakfast', 'lunch', 'dinner', 'snack'):
                    raise ValueError('餐次无效')
                reservation = meal.get('reservation')
                if not isinstance(reservation, dict) or reservation.get('status') not in ('notRequired', 'planned', 'booked', 'cancelled'):
                    raise ValueError('餐厅预订状态无效')
                if type(reservation.get('partySize')) is not int or not 1 <= reservation['partySize'] <= 20:
                    raise ValueError('用餐人数须为 1 到 20 人')
                for key, maximum in (('date', 10), ('time', 5), ('reference', 500), ('notes', 3000)):
                    text(reservation.get(key), maximum)
                if reservation['date'] and reservation['date'] not in trip_dates:
                    raise ValueError('餐厅预订日期须在旅行日期内')
                if reservation['time'] and not re.fullmatch(TIME, reservation['time']):
                    raise ValueError('餐厅预订时间无效')
                if reservation['status'] == 'booked' and (not reservation['date'] or not reservation['time']):
                    raise ValueError('已预订的餐厅须填写预订日期与时间')
            uids.add(item['uid'])
    checks = plan.get('checks')
    if not isinstance(checks, dict) or len(checks) > 100 or any(type(v) is not bool for v in checks.values()):
        raise ValueError('清单状态无效')
    for key in checks:
        text(key, 120)
    if 'hotelFavorites' in plan:
        favorites = plan['hotelFavorites']
        if not isinstance(favorites, list) or len(favorites) > 100 or any(not isinstance(v, str) or not re.fullmatch(r'[a-z0-9-]{1,80}', v) for v in favorites) or len(set(favorites)) != len(favorites):
            raise ValueError('酒店收藏无效')
    if 'stays' in plan:
        stays = plan['stays']
        if not isinstance(stays, list) or len(stays) > 20:
            raise ValueError('酒店安排无效')
        stay_ids = set()
        first_night, last_day = min(trip.get('departureDate') or trip['startDate'], trip['startDate']), trip['endDate']
        for hotel in stays:
            if not isinstance(hotel, dict):
                raise ValueError('酒店资料无效')
            text(hotel.get('id'), 80)
            if not re.fullmatch(r'[a-z0-9-]{1,80}', hotel['id']) or hotel['id'] in stay_ids:
                raise ValueError('酒店编号无效')
            stay_ids.add(hotel['id'])
            for key in ('name', 'address', 'phone', 'checkIn', 'checkOut', 'checkInTime', 'checkOutTime'):
                text(hotel.get(key), 300)
            if 'nameEnglish' in hotel:
                text(hotel['nameEnglish'], 300)
            text(hotel.get('notes'), 3000)
            if not hotel['name'].strip() or not all(iso_date(hotel[k]) and first_night <= hotel[k] <= last_day for k in ('checkIn', 'checkOut')) or hotel['checkIn'] >= hotel['checkOut']:
                raise ValueError('入住与退房日期无效')
            if type(hotel.get('lateArrival')) is not bool or any(t and not re.fullmatch(TIME, t) for t in (hotel['checkInTime'], hotel['checkOutTime'])):
                raise ValueError('入住信息无效')
        ordered = sorted(stays, key=lambda h: h['checkIn'])
        if any(a['checkOut'] > b['checkIn'] for a, b in zip(ordered, ordered[1:])):
            raise ValueError('酒店入住日期重叠')
    if 'tickets' in plan:
        tickets = plan['tickets']
        if not isinstance(tickets, dict) or len(tickets) > len(ids):
            raise ValueError('门票资料无效')
        ticket_ids = set()
        for place_id, records in tickets.items():
            if place_id not in ids or not isinstance(records, list) or len(records) > 12:
                raise ValueError('门票地点或数量无效')
            for ticket in records:
                if not isinstance(ticket, dict):
                    raise ValueError('门票资料无效')
                for key in ('id', 'title', 'date', 'time', 'provider', 'reference', 'url', 'deadline', 'notes'):
                    text(ticket.get(key), 3000 if key == 'notes' else 500)
                if not re.fullmatch(r'[a-z0-9-]{1,80}', ticket['id']) or ticket['id'] in ticket_ids or not ticket['title'].strip():
                    raise ValueError('门票编号或名称无效')
                ticket_ids.add(ticket['id'])
                if ticket.get('status') not in ('planned', 'booked', 'used', 'cancelled') or type(ticket.get('quantity')) is not int or not 1 <= ticket['quantity'] <= 20:
                    raise ValueError('门票状态或人数无效')
                if ticket['date'] and ticket['date'] not in trip_dates:
                    raise ValueError('门票日期须在旅行日期内')
                if ticket['time'] and not re.fullmatch(TIME, ticket['time']):
                    raise ValueError('门票时间无效')
                if ticket['deadline']:
                    try:
                        datetime.strptime(ticket['deadline'], '%Y-%m-%dT%H:%M')
                    except ValueError:
                        raise ValueError('退改截止时间无效')
                if ticket['url'] and not re.match(r'https?://[^\s]+$', ticket['url']):
                    raise ValueError('门票链接无效')
                files = ticket.get('files')
                if not isinstance(files, list) or len(files) > 8:
                    raise ValueError('每张门票最多 8 个附件')
                file_ids = set()
                for file in files:
                    if not isinstance(file, dict):
                        raise ValueError('门票附件无效')
                    text(file.get('name'), 200)
                    if not isinstance(file.get('id'), str) or not re.fullmatch(r'[a-f0-9]{64}', file['id']) or file['id'] in file_ids or file.get('type') not in ATTACHMENT_TYPES or type(file.get('size')) is not int or not 0 < file['size'] <= MAX_ATTACHMENT:
                        raise ValueError('门票附件无效')
                    file_ids.add(file['id'])
    budget = plan.get('budget')
    if not isinstance(budget, dict) or set(budget) != BUDGET_KEYS:
        raise ValueError('预算无效')
    for key in BUDGET_KEYS:
        number(budget[key], MAX_BUDGET)


def iso_date(value):
    try:
        return re.fullmatch(r'\d{4}-\d{2}-\d{2}', value) is not None and bool(datetime.strptime(value, '%Y-%m-%d'))
    except ValueError:
        return False


class Store:
    def __init__(self, database):
        self.database = str(database)
        with self.connect() as db:
            db.execute('CREATE TABLE IF NOT EXISTS attachments(id TEXT PRIMARY KEY, type TEXT NOT NULL, content BLOB NOT NULL)')
        self.touch = TouchService(self.database)
        self.routes = RoutePreferencesService(self.database)

    def connect(self):
        conn = sqlite3.connect(self.database, timeout=10)
        conn.row_factory = sqlite3.Row
        conn.execute('PRAGMA foreign_keys=ON')
        return conn

    def attachment(self, identifier):
        with self.connect() as db:
            row = db.execute('SELECT type,content FROM attachments WHERE id=?', (identifier,)).fetchone()
            return dict(row) if row else None

    def put_attachment(self, content, content_type):
        valid = ((content_type == 'image/png' and content.startswith(b'\x89PNG\r\n\x1a\n')) or
                 (content_type == 'image/jpeg' and content.startswith(b'\xff\xd8\xff')) or
                 (content_type == 'image/webp' and content.startswith(b'RIFF') and content[8:12] == b'WEBP') or
                 (content_type == 'application/pdf' and content.startswith(b'%PDF-')))
        if not valid or not 0 < len(content) <= MAX_ATTACHMENT:
            raise ValueError('仅支持有效的 JPG、PNG、WebP 图片或 PDF，单个不超过 10 MB')
        identifier = hashlib.sha256(content).hexdigest()
        with self.connect() as db:
            db.execute('BEGIN IMMEDIATE')
            if not db.execute('SELECT 1 FROM attachments WHERE id=?', (identifier,)).fetchone():
                total = db.execute('SELECT COALESCE(SUM(length(content)),0) FROM attachments').fetchone()[0]
                if total + len(content) > MAX_ATTACHMENT_TOTAL:
                    raise ValueError('附件空间已满（100 MB），请联系站点维护者')
                db.execute('INSERT INTO attachments VALUES(?,?,?)', (identifier, content_type, content))
        return identifier

    def snapshot(self):
        with self.connect() as db:
            row = db.execute('SELECT revision, document, updated_at FROM trip WHERE id=1').fetchone()
            return {'revision': row['revision'], 'state': json.loads(row['document']), 'updatedAt': row['updated_at']}

    def session(self, token):
        if not token or len(token) > 100:
            return None
        with self.connect() as db:
            row = db.execute('SELECT csrf, expires FROM sessions WHERE token_hash=? AND expires>?', (hashlib.sha256(token.encode()).hexdigest(), time.time())).fetchone()
            return dict(row) if row else None

    def native_session(self):
        now = time.time()
        token, csrf = secrets.token_urlsafe(32), secrets.token_urlsafe(32)
        with self.connect() as db:
            db.execute('DELETE FROM sessions WHERE expires<?', (now,))
            db.execute('INSERT INTO sessions VALUES(?,?,?)', (hashlib.sha256(token.encode()).hexdigest(), csrf, now+7*86400))
        return token

    def update(self, expected, state, device, validate=None):
        with self.connect() as db:
            db.execute('BEGIN IMMEDIATE')
            current = db.execute('SELECT revision, document FROM trip WHERE id=1').fetchone()
            if current['revision'] != expected:
                return None
            previous = json.loads(current['document'])
            preserve_legacy_fields(state, previous)
            if validate is not None:
                validate(state)
            now, revision, document = int(time.time()*1000), expected+1, encode(state)
            db.execute('UPDATE trip SET revision=?,document=?,updated_at=? WHERE id=1', (revision, document, now))
            db.execute('INSERT INTO revisions VALUES(?,?,?,?,?)', (revision, document, now, device, 'edit'))
            db.execute('DELETE FROM revisions WHERE revision<?', (max(0, revision-100),))
            return {'revision':revision, 'updatedAt':now}


def initialize(database, catalog):
    """Create a fresh database whose plan is the catalog's default plan."""
    database.parent.mkdir(parents=True, exist_ok=True)
    if database.exists():
        raise ValueError('数据库已存在，不会重置共享行程')
    plan = copy.deepcopy(catalog['defaults'])
    validate_plan(plan, catalog, catalog['trip']['id'])
    with sqlite3.connect(database) as db:
        db.execute('PRAGMA journal_mode=WAL')
        db.executescript('''
        CREATE TABLE trip(id INTEGER PRIMARY KEY CHECK(id=1),revision INTEGER NOT NULL,document TEXT NOT NULL,updated_at INTEGER NOT NULL);
        CREATE TABLE sessions(token_hash TEXT PRIMARY KEY,csrf TEXT NOT NULL,expires REAL NOT NULL);
        CREATE TABLE revisions(revision INTEGER PRIMARY KEY,document TEXT NOT NULL,updated_at INTEGER NOT NULL,device TEXT NOT NULL,reason TEXT NOT NULL);
        ''')
        db.execute('INSERT INTO trip VALUES(1,0,?,?)',(encode(plan),int(time.time()*1000)))
    os.chmod(database, 0o600)


class TripHandler(BaseHTTPRequestHandler):
    server_version = 'TripPlanner'

    def log_message(self, fmt, *args):
        # No request bodies, cookies, query strings, access keys, or referrers.
        sys.stderr.write('%s %s %s\n' % (self.command, urlsplit(self.path).path, args[1] if len(args)>1 else ''))

    def touch_refused(self, action, status, message):
        # Refusals carry the phone's stable fingerprint so a failed pairing can be traced later.
        secret = self.headers.get('X-Touch-Device', '')
        touch_log('refused', action=action, status=status, device=touch_short(touch_digest(secret)) if secret else 'none',
                  client=self.headers.get('User-Agent', '-').split(' ')[0], reason=message)

    def send(self, code, body=b'', content_type='application/json', headers=None):
        if isinstance(body, str): body=body.encode()
        self.send_response(code)
        self.send_header('Content-Type', content_type)
        self.send_header('Content-Length', str(len(body)))
        self.send_header('Cache-Control', 'no-store')
        self.send_header('X-Content-Type-Options', 'nosniff')
        self.send_header('Referrer-Policy', 'same-origin')
        self.send_header('Content-Security-Policy', "default-src 'none'; base-uri 'none'; frame-ancestors 'none'; form-action 'none'")
        for key, value in (headers or {}).items(): self.send_header(key,value)
        self.end_headers()
        if self.command != 'HEAD':
            try: self.wfile.write(body)
            except (BrokenPipeError, ConnectionResetError): pass

    def json(self, code, value): self.send(code, encode(value))

    @property
    def store(self):
        return getattr(self, 'authenticated_store', self.server.store)

    def session(self):
        self.authenticated_store = self.server.store
        try:
            cookie=SimpleCookie(self.headers.get('Cookie',''));token=cookie.get(self.server.cookie_name)
            value = token.value if token else ''
            if value.startswith(REVIEW_TOKEN_PREFIX):
                review_store = getattr(self.server, 'review_store', None)
                if review_store is None: return None
                self.authenticated_store = review_store
                value = value[len(REVIEW_TOKEN_PREFIX):]
            return self.store.session(value)
        except CookieError: return None

    def read_json(self):
        try: size=int(self.headers.get('Content-Length','0'))
        except ValueError: raise ValueError('请求大小无效')
        if not 0 < size <= MAX_BODY: raise ValueError('请求过大或为空')
        if self.headers.get('Content-Type','').split(';')[0] != 'application/json': raise ValueError('需要 JSON 数据')
        return json.loads(self.rfile.read(size))

    def do_GET(self):
        route=unquote(urlsplit(self.path).path)
        if route == '/healthz': self.json(200,{'ok':True});return
        session=self.session()
        if not session:
            self.json(401,{'error':'登录已过期，请重新连接'})
            return
        if route == '/api/route-places':
            try:
                query = parse_qs(urlsplit(self.path).query).get('query', [''])[0]
                self.json(200, self.server.route_places.search(query))
            except RoutingError as exc:
                self.json(exc.status, {'error': exc.message})
            return
        if route.startswith('/api/touch/'):
            action = route[len('/api/touch/'):]
            try:
                self.json(200, self.store.touch.get(action, self.headers.get('X-Touch-Device', ''), parse_qs(urlsplit(self.path).query)))
            except TouchError as exc:
                self.touch_refused(action, exc.status, exc.message)
                self.json(exc.status, {'error': exc.message})
            return
        if route == '/api/route-address-status':
            self.json(200, {'enabled': self.store.routes.english_address_sharing})
            return
        if route == '/api/route-preferences':
            snapshot = self.store.routes.snapshot(self.server.plan_id)
            if parse_qs(urlsplit(self.path).query).get('since') == [str(snapshot['revision'])]: self.send(204)
            else: self.json(200, snapshot)
            return
        if route == '/api/session':
            self.json(200, {'csrf': session['csrf'], 'expiresAt': session['expires']})
            return
        match = re.fullmatch(r'/api/attachments/([a-f0-9]{64})', route)
        if match:
            file = self.store.attachment(match[1])
            if not file:
                self.json(404, {'error':'附件不存在'});return
            headers = {'Content-Disposition': 'attachment; filename="ticket.pdf"'} if file['type'] == 'application/pdf' else {}
            self.send(200, file['content'], file['type'], headers);return
        if route == '/api/plan':
            snapshot=self.store.snapshot()
            if parse_qs(urlsplit(self.path).query).get('since') == [str(snapshot['revision'])]: self.send(204)
            else: self.json(200,snapshot)
            return
        self.json(404,{'error':'页面不存在'})

    def do_POST(self): self.write_request()
    def do_PUT(self): self.write_request()

    def write_request(self):
        if self.headers.get('Origin') != self.server.origin:
            self.json(403,{'error':'请求来源不匹配'});return
        route=urlsplit(self.path).path
        if route == '/api/native-session' and self.command == 'POST':
            expected = getattr(self.server, 'native_key_hash', '')
            if not expected:
                self.json(503, {'error':'自动共享暂未启用，请稍后重试'});return
            try:
                data = self.read_json()
                key = data.get('accessKey', '')
                if not isinstance(key, str) or not 32 <= len(key) <= 256:
                    raise ValueError('无效的 App 访问凭证')
            except (ValueError, AttributeError):
                self.json(400, {'error':'无效的 App 访问凭证'});return
            key_hash = hashlib.sha256(key.encode()).hexdigest()
            review_store = getattr(self.server, 'review_store', None)
            review_hash = getattr(self.server, 'review_key_hash', '')
            if hmac.compare_digest(key_hash, expected):
                token = self.server.store.native_session()
            elif review_store is not None and review_hash and hmac.compare_digest(key_hash, review_hash):
                # A separate key opens the isolated review database, never the real trip.
                token = REVIEW_TOKEN_PREFIX + review_store.native_session()
            else:
                self.json(403, {'error':'此版本无法自动共享，请更新 App'});return
            cookie = f'{self.server.cookie_name}={token}; Path={self.server.cookie_path}; HttpOnly; SameSite=Strict; Max-Age=604800'
            if self.server.origin.startswith('https://'): cookie += '; Secure'
            self.send(200, '{"ok":true}', headers={'Set-Cookie':cookie});return
        session=self.session()
        if not session: self.json(401,{'error':'登录已过期，请重新连接'});return
        if not hmac.compare_digest(self.headers.get('X-Trip-CSRF',''),session['csrf']):
            self.json(403,{'error':'会话校验失败，请重试'});return
        if route == '/api/routes' and self.command == 'POST':
            try:
                self.json(200, self.server.route_engine.calculate(self.read_json()))
            except RoutingError as exc:
                self.json(exc.status, {'error': exc.message})
            except ValueError:
                self.json(422, {'error': '路线请求无效'})
            return
        if route.startswith('/api/touch/') and self.command == 'POST':
            action = route[len('/api/touch/'):]
            try:
                ip = self.headers.get('X-Real-IP', self.client_address[0]) if self.client_address[0] in ('127.0.0.1', '::1') else self.client_address[0]
                result = self.store.touch.post(action, self.headers.get('X-Touch-Device', ''), self.read_json(), ip)
                self.json(200, result)
            except TouchError as exc:
                self.touch_refused(action, exc.status, exc.message)
                self.json(exc.status, {'error': exc.message})
            except (ValueError, TypeError) as exc:
                self.touch_refused(action, 422, type(exc).__name__)
                self.json(422, {'error': '互动数据无效'})
            return
        if route == '/api/attachments' and self.command == 'POST':
            try:
                size = int(self.headers.get('Content-Length', '0'))
                content_type = self.headers.get('Content-Type', '').split(';')[0]
                if content_type not in ATTACHMENT_TYPES or not 0 < size <= MAX_ATTACHMENT:
                    raise ValueError('仅支持 JPG、PNG、WebP 或 PDF，单个不超过 10 MB')
                content = self.rfile.read(size)
                if len(content) != size:
                    raise ValueError('附件上传未完成，请重试')
                identifier = self.store.put_attachment(content, content_type)
            except ValueError as exc:
                self.json(422, {'error':str(exc)});return
            self.json(200, {'id':identifier, 'type':content_type, 'size':size});return
        if route == '/api/route-preferences' and self.command == 'PUT':
            try:
                data = self.read_json()
                if not isinstance(data, dict): raise ValueError('路线设置无效')
                saved, result = self.store.routes.update(data.get('revision'), data.get('state'), self.server.plan_id, self.server.region)
                self.json(200 if saved else 409, result if saved else {'latest': result})
            except ValueError as exc:
                self.json(422, {'error': str(exc)})
            return
        if route == '/api/plan' and self.command == 'PUT':
            try:
                data=self.read_json()
                if not isinstance(data,dict) or type(data.get('revision')) is not int or data['revision']<0: raise ValueError('版本无效')
                plan=data.get('state')
                def validate(state):
                    validate_plan(state,self.server.catalog,self.server.plan_id)
                    for records in state.get('tickets', {}).values():
                        for ticket in records:
                            for file in ticket['files']:
                                stored = self.store.attachment(file['id'])
                                if not stored or stored['type'] != file['type'] or len(stored['content']) != file['size']:
                                    raise ValueError('门票附件未上传完成，请重新添加')
                device=data.get('device','')
                if not isinstance(device,str) or len(device)>100: raise ValueError('设备标识无效')
                result=self.store.update(data['revision'],plan,device,validate)
            except (ValueError,KeyError,TypeError) as exc: self.json(422,{'error':str(exc)});return
            if result is None: self.json(409,{'error':'另一台设备已更新行程','latest':self.store.snapshot()})
            else: self.json(200,result)
            return
        self.json(404,{'error':'接口不存在'})


def make_server(store, catalog, *, port=0, origin=None, cookie_name=COOKIE, cookie_path='/',
                native_key_hash='', review_store=None, review_key_hash='', route_engine=None, route_places=None):
    """Bind 127.0.0.1 only; a reverse proxy terminates TLS and applies request limits."""
    for value in (native_key_hash, review_key_hash):
        if value and not re.fullmatch(r'[a-f0-9]{64}', value):
            raise ValueError('Access key hashes must be 64 lowercase hex characters')
    if native_key_hash and native_key_hash == review_key_hash:
        raise ValueError('The review key must differ from the shared key')
    if not re.fullmatch(r'[A-Za-z0-9_]{1,64}', cookie_name):
        raise ValueError('Invalid cookie name')
    plan_id = catalog['trip']['id']
    if store.snapshot()['state'].get('id') != plan_id:
        raise ValueError('数据库属于另一个行程，请检查 catalog.json 与 --db')
    if review_store is not None:
        if Path(review_store.database).resolve() == Path(store.database).resolve():
            raise ValueError('审核数据库必须独立存在')
        validate_plan(review_store.snapshot()['state'], catalog, plan_id)
    server = ThreadingHTTPServer(('127.0.0.1', port), TripHandler)
    server.store, server.catalog, server.plan_id = store, catalog, plan_id
    server.origin = (origin or f'http://127.0.0.1:{server.server_address[1]}').rstrip('/')
    server.cookie_name, server.cookie_path = cookie_name, cookie_path
    server.native_key_hash, server.review_key_hash = native_key_hash, review_key_hash
    server.region = region_for(catalog['trip'])
    server.route_engine = route_engine or RouteEngine(region=server.region)
    server.route_places = route_places or RoutePlaces()
    if review_store is not None:
        server.review_store = review_store
    return server


def main():
    env = os.environ.get
    parser = argparse.ArgumentParser(description='Trip journal sync server (JSON API, loopback only).')
    parser.add_argument('command', choices=('init', 'serve', 'backup', 'reset-touch'))
    parser.add_argument('--data-dir', type=Path, default=Path(env('TRIP_DATA_DIR') or ROOT / 'data'),
                        help='Directory for trip.sqlite3 (env TRIP_DATA_DIR, default <repo>/data)')
    parser.add_argument('--db', type=Path, help='Database path (default <data-dir>/trip.sqlite3)')
    parser.add_argument('--review-db', type=Path, default=Path(env('TRIP_REVIEW_DB')) if env('TRIP_REVIEW_DB') else None,
                        help='Optional isolated App Review database, opened by TRIP_REVIEW_KEY_SHA256 (env TRIP_REVIEW_DB)')
    parser.add_argument('--catalog', help='Generated catalog.json (env TRIP_CATALOG, default ios/TripJournal/Resources/Content/catalog.json)')
    parser.add_argument('--port', type=int, default=int(env('TRIP_PORT') or DEFAULT_PORT), help='Loopback port (env TRIP_PORT)')
    parser.add_argument('--origin', default=env('TRIP_ORIGIN'), help='Public origin the app sends, e.g. https://example.com (env TRIP_ORIGIN)')
    parser.add_argument('--cookie-name', default=env('TRIP_COOKIE_NAME') or COOKIE, help='Session cookie name (env TRIP_COOKIE_NAME)')
    parser.add_argument('--cookie-path', default=env('TRIP_COOKIE_PATH') or '/', help='Cookie path, e.g. /onetrip/<random>/ (env TRIP_COOKIE_PATH)')
    parser.add_argument('--output', type=Path, help='Backup destination for the backup command')
    args = parser.parse_args()
    database = args.db or args.data_dir / 'trip.sqlite3'
    if args.command == 'reset-touch':
        if not database.is_file(): raise ValueError('数据库不存在')
        print(json.dumps(TouchService(database).reset()));print('Interaction identity cleared; trip data untouched.');return
    if args.command == 'backup':
        if not args.output: parser.error('--output is required')
        with sqlite3.connect(database) as source, sqlite3.connect(args.output) as target: source.backup(target)
        os.chmod(args.output,0o600);print('Backup complete.');return
    catalog = load_catalog(args.catalog)
    if args.command == 'init':
        initialize(database, catalog);print('Initialized shared trip.');return
    review_store = None
    if args.review_db:
        if not args.review_db.is_file(): raise ValueError('审核数据库必须独立存在')
        review_store = Store(args.review_db)
    server = make_server(Store(database), catalog, port=args.port, origin=args.origin,
                         cookie_name=args.cookie_name, cookie_path=args.cookie_path,
                         native_key_hash=env('TRIP_NATIVE_KEY_SHA256', ''), review_store=review_store,
                         review_key_hash=env('TRIP_REVIEW_KEY_SHA256', ''))
    print(f'Listening on 127.0.0.1:{args.port}',flush=True)
    server.serve_forever()

if __name__ == '__main__': main()
