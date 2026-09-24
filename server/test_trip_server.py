import hashlib
import concurrent.futures
import copy
import http.client
import json
import os
import sqlite3
import tempfile
import threading
import subprocess
import sys
import unittest
from pathlib import Path
from unittest.mock import patch
from trip_catalog import DEFAULT_CATALOG, load_catalog
from trip_server import MAX_BUDGET, initialize, make_server, Store, validate_plan
import trip_fixture

KEY = 't' * 48
REVIEW_KEY = 'r' * 48


def key_hash(key):
    return hashlib.sha256(key.encode()).hexdigest()


class SharedTripTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.catalog = trip_fixture.catalog(self.tmp.name)
        self.db = Path(self.tmp.name)/'trip.sqlite3'
        initialize(self.db, self.catalog)
        self.store = Store(self.db)
        self.start(self.make())

    def make(self, **options):
        options.setdefault('origin', 'https://example.com')
        options.setdefault('cookie_path', '/trip/test/')
        options.setdefault('native_key_hash', key_hash(KEY))
        return make_server(self.store, self.catalog, **options)

    def start(self, server):
        self.server = server
        threading.Thread(target=self.server.serve_forever, daemon=True).start()

    def tearDown(self):
        self.server.shutdown(); self.server.server_close(); self.tmp.cleanup()

    def request(self,method,path,data=None,headers=None):
        c=http.client.HTTPConnection(*self.server.server_address)
        h={'Origin':self.server.origin,'Content-Type':'application/json',**(headers or {})}
        c.request(method,path,data if isinstance(data,bytes) else json.dumps(data) if data is not None else None,h)
        r=c.getresponse(); result=(r.status,dict(r.getheaders()),r.read()); c.close(); return result

    def cookie(self, key=KEY):
        code, headers, _ = self.request('POST', '/api/native-session', {'accessKey': key})
        self.assertEqual(code, 200)
        return {'Cookie': headers['Set-Cookie'].split(';')[0]}

    def authenticate(self, key=KEY):
        h = self.cookie(key)
        code, _, raw = self.request('GET', '/api/session', headers=h)
        self.assertEqual(code, 200)
        h['X-Trip-CSRF'] = json.loads(raw)['csrf']
        return h

    def validate(self, plan):
        validate_plan(plan, self.catalog, self.server.plan_id)

    def test_touch_http_auth_pairing_and_trip_preservation(self):
        original = self.store.snapshot()
        self.assertEqual(self.request('POST', '/api/touch/enroll', {'nickname':'甲'})[0], 401)
        auth = dict(self.cookie(), **{'X-Touch-Device': 'a'*48})
        self.assertEqual(self.request('POST', '/api/touch/enroll', {'nickname':'甲'}, auth)[0], 403)
        session = json.loads(self.request('GET', '/api/session', headers=auth)[2])
        auth['X-Trip-CSRF'] = session['csrf']
        self.assertEqual(self.request('POST', '/api/touch/enroll', {'nickname':'甲'}, dict(auth, Origin='https://evil.example'))[0], 403)
        self.assertEqual(self.request('POST', '/api/touch/enroll', {'nickname':'甲'}, auth)[0], 200)
        other = dict(auth, **{'X-Touch-Device': 'b'*48})
        self.assertEqual(self.request('POST', '/api/touch/enroll', {'nickname':'乙'}, other)[0], 200)
        code = json.loads(self.request('POST', '/api/touch/invite', {}, auth)[2])['code']
        self.assertEqual(self.request('POST', '/api/touch/join', {'code':code}, other)[0], 200)
        self.assertEqual(self.request('POST', '/api/touch/confirm', {}, auth)[0], 200)
        status, _, raw = self.request('POST', '/api/touch/send', {'id':'test','kind':'heart'}, auth)
        self.assertEqual(status, 200)
        received = json.loads(self.request('GET', '/api/touch/events?after=0', headers=other)[2])
        self.assertEqual(received['events'][0], json.loads(raw)['event'])
        self.assertEqual(self.request('GET', '/api/touch/events', headers=dict(auth, **{'X-Touch-Device': 'c'*48}))[0], 403)
        self.assertEqual(self.request('POST', '/api/touch/send', ['invalid'], auth)[0], 422)
        self.assertEqual(self.store.snapshot(), original)

    def test_route_place_search_is_authenticated_and_does_not_write_shared_data(self):
        from unittest.mock import Mock
        self.server.route_places = Mock()
        self.server.route_places.search.return_value = {'places': []}
        original = self.store.snapshot()
        self.assertEqual(self.request('GET', '/api/route-places?query=Harbor')[0], 401)
        self.server.route_places.search.assert_not_called()
        auth = self.cookie()
        self.assertEqual(self.request('GET', '/api/route-places?query=Harbor', headers=auth)[0], 200)
        self.server.route_places.search.assert_called_once_with('Harbor')
        self.assertEqual(self.store.snapshot(), original)

    def test_routes_require_session_origin_csrf_and_do_not_write_plan(self):
        from unittest.mock import Mock
        from route_engine import RoutingError
        self.server.route_engine = Mock()
        self.server.route_engine.calculate.return_value = {'shape': 'encoded', 'distance': 1230}
        original = self.store.snapshot()
        body = {'from': trip_fixture.INSIDE, 'to': trip_fixture.INSIDE_OTHER, 'mode': 'walking'}
        self.assertEqual(self.request('POST', '/api/routes', body)[0], 401)
        auth = self.cookie()
        self.assertEqual(self.request('POST', '/api/routes', body, auth)[0], 403)
        auth['X-Trip-CSRF'] = json.loads(self.request('GET', '/api/session', headers=auth)[2])['csrf']
        self.assertEqual(self.request('POST', '/api/routes', body, dict(auth, Origin='https://evil.example'))[0], 403)
        self.server.route_engine.calculate.assert_not_called()
        self.assertEqual(self.request('POST', '/api/routes', body, auth)[0], 200)
        self.server.route_engine.calculate.assert_called_once_with(body)
        self.server.route_engine.calculate.side_effect = RoutingError(422, '没有可通行路线')
        self.assertEqual(self.request('POST', '/api/routes', body, auth)[0], 422)
        self.assertEqual(self.store.snapshot(), original)

    def test_default_route_engine_uses_catalog_bounds(self):
        region = self.server.route_engine.region
        self.assertTrue(region.contains(*trip_fixture.INSIDE))
        self.assertFalse(region.contains(31.2, 121.5))

    def test_route_address_capability_is_authenticated_and_does_not_change_snapshot(self):
        self.assertEqual(self.request('GET', '/api/route-address-status')[0], 401)
        auth = self.cookie()
        original = self.store.routes.snapshot(self.server.plan_id)
        for enabled in ('0', '1'):
            with patch.dict(os.environ, {'TRIP_ROUTE_ENGLISH_ADDRESS_SHARING': enabled}):
                status, _, raw = self.request('GET', '/api/route-address-status', headers=auth)
                self.assertEqual(status, 200)
                self.assertEqual(json.loads(raw), {'enabled': enabled == '1'})
                self.assertEqual(self.store.routes.snapshot(self.server.plan_id), original)

    def test_route_preferences_are_independent_authenticated_and_revisioned(self):
        original = self.store.snapshot()
        path = '/api/route-preferences'
        self.assertEqual(self.request('GET', path)[0], 401)
        auth = self.cookie()
        state = {'tripID': self.server.plan_id, 'values': {'mode:test': {'kind': 'mode', 'title': 'A → B', 'value': 'driving'}}}
        body = {'revision': 0, 'state': state}
        self.assertEqual(self.request('PUT', path, body, auth)[0], 403)
        auth['X-Trip-CSRF'] = json.loads(self.request('GET', '/api/session', headers=auth)[2])['csrf']
        self.assertEqual(self.request('PUT', path, body, dict(auth, Origin='https://evil.example'))[0], 403)
        self.assertEqual(self.request('GET', path + '?since=0', headers=auth)[0], 204)
        with concurrent.futures.ThreadPoolExecutor(2) as pool:
            results = list(pool.map(lambda _: self.request('PUT', path, body, auth)[0], range(2)))
        self.assertEqual(sorted(results), [200, 409])
        self.assertEqual(self.store.snapshot(), original)
        latest = json.loads(self.request('GET', path, headers=auth)[2])
        self.assertEqual(latest['state'], state)
        self.assertEqual(Store(self.db).routes.snapshot(self.server.plan_id), latest)
        self.assertEqual(self.request('GET', path + '?since=1', headers=auth)[0], 204)
        # A legacy plan write cannot erase independent route settings.
        self.assertEqual(self.request('PUT', '/api/plan', {'revision': original['revision'], 'state': original['state']}, auth)[0], 200)
        self.assertEqual(self.store.routes.snapshot(self.server.plan_id), latest)
        location = lambda lat, lon: {'tripID': self.server.plan_id, 'values': {'x': {'kind': 'location', 'title': 'x', 'location': {'name': 'x', 'address': '', 'latitude': lat, 'longitude': lon}}}}
        for bad in [[], {'tripID': 'other', 'values': {}},
                    {'tripID': self.server.plan_id, 'values': {'x': {'kind': 'mode', 'title': 'x', 'value': 'flight'}}},
                    location(True, -150.0), location(31.2, 121.5)]:
            self.assertEqual(self.request('PUT', path, {'revision': 1, 'state': bad}, auth)[0], 422)
        self.assertEqual(self.store.routes.snapshot(self.server.plan_id), latest)
        self.assertEqual(self.request('PUT', path, {'revision': 1, 'state': location(*trip_fixture.INSIDE)}, auth)[0], 200)
        self.assertEqual(self.request('PUT', path, {'revision': 2, 'state': {'tripID': self.server.plan_id, 'values': {}}}, auth)[0], 200)

    def test_auth_schema_and_cas(self):
        self.assertEqual(self.request('GET','/api/plan')[0],401)
        for path in ['/', '/index.html', '/assets/app.js']:
            self.assertEqual(self.request('GET',path)[0],401)
        code,headers,_=self.request('POST','/api/native-session',{'accessKey':KEY})
        self.assertEqual(code,200)
        cookie=headers['Set-Cookie']
        self.assertTrue(cookie.startswith('trip_session='))
        for flag in ('Secure','HttpOnly','SameSite=Strict','Path=/trip/test/'): self.assertIn(flag,cookie)
        self.assertNotIn('unsafe-inline',headers['Content-Security-Policy'])
        h={'Cookie':cookie.split(';')[0]}
        plan=self.store.snapshot()['state'];body={'revision':0,'state':plan}
        self.assertEqual(self.request('PUT','/api/plan',body,h)[0],403)
        h['X-Trip-CSRF']=json.loads(self.request('GET','/api/session',headers=h)[2])['csrf']
        bad=copy.deepcopy(body);bad['state']['days'][0]['items'][0]['place']='unknown'
        self.assertEqual(self.request('PUT','/api/plan',bad,h)[0],422)
        with concurrent.futures.ThreadPoolExecutor(2) as pool:
            results=list(pool.map(lambda _:self.request('PUT','/api/plan',body,h)[0],range(2)))
        self.assertEqual(sorted(results),[200,409])
        self.assertEqual(Store(self.db).snapshot()['revision'],1)
        self.assertEqual(self.request('GET','/api/plan?since=1',headers=h)[0],204)
        for path in ['/','/index.html','/server/trip_server.py','/assets/../server/trip_server.py','/assets/%2e%2e/index.html','/api/login']:
            self.assertEqual(self.request('GET',path,headers=h)[0],404)
        self.assertEqual(self.request('POST','/api/login',{'password':'1234'})[0],401)
        self.assertEqual(self.request('POST','/api/login',{'password':'1234'},h)[0],404)
        with self.store.connect() as db:
            db.execute('UPDATE sessions SET expires=0')
        self.assertEqual(self.request('GET','/api/plan',headers=h)[0],401)

    def test_native_session_bootstrap(self):
        self.assertEqual(self.request('GET', '/api/session')[0], 401)
        cookie = self.cookie()
        code, headers, body = self.request('GET', '/api/session', headers=cookie)
        self.assertEqual(code, 200)
        self.assertEqual(headers['Cache-Control'], 'no-store')
        session = json.loads(body)
        self.assertEqual(set(session), {'csrf', 'expiresAt'})
        self.assertGreater(session['expiresAt'], 0)
        payload = {'revision': 0, 'state': self.store.snapshot()['state'], 'device': 'ios-test'}
        auth = dict(cookie, **{'X-Trip-CSRF': session['csrf']})
        self.assertEqual(self.request('PUT', '/api/plan', payload, auth)[0], 200)
        self.assertEqual(self.request('PUT', '/api/plan', payload, dict(auth, Origin='https://evil.example'))[0], 403)
        with self.store.connect() as db:
            db.execute('UPDATE sessions SET expires=0')
        self.assertEqual(self.request('GET', '/api/session', headers=cookie)[0], 401)

    def test_native_automatic_shared_access(self):
        self.server.native_key_hash = ''
        self.assertEqual(self.request('POST', '/api/native-session', {'accessKey':KEY})[0], 503)
        self.server.native_key_hash = key_hash(KEY)
        before = self.store.snapshot()
        for bad in ({'accessKey':'x'*48}, {'accessKey':'short'}, {'accessKey':48}, ['x']):
            self.assertIn(self.request('POST', '/api/native-session', bad)[0], (400, 403))
        self.assertEqual(self.request('POST', '/api/native-session', {'accessKey':KEY}, {'Origin':'https://other.example'})[0], 403)
        sessions = [self.authenticate(), self.authenticate()]
        self.assertNotIn('review.', sessions[0]['Cookie'])
        self.assertEqual(self.store.snapshot(), before)
        updated = copy.deepcopy(before['state']); updated['checks']['passport'] = True
        payload = {'revision':before['revision'], 'state':updated, 'device':'native-test'}
        self.assertEqual(self.request('PUT', '/api/plan', payload, sessions[0])[0], 200)
        self.assertEqual(json.loads(self.request('GET', '/api/plan', headers=sessions[1])[2])['state'], updated)
        self.assertEqual(self.request('PUT', '/api/plan', payload, sessions[1])[0], 409)
        self.assertEqual(self.request('GET', '/api/plan')[0], 401)

    def test_site_constants_are_configurable(self):
        server = self.make(cookie_name='journal_sid', cookie_path='/', origin='http://127.0.0.1:9999')
        self.server.shutdown(); self.server.server_close(); self.start(server)
        code, headers, _ = self.request('POST', '/api/native-session', {'accessKey': KEY})
        self.assertEqual(code, 200)
        self.assertTrue(headers['Set-Cookie'].startswith('journal_sid='))
        self.assertNotIn('Secure', headers['Set-Cookie'])
        h = {'Cookie': headers['Set-Cookie'].split(';')[0]}
        self.assertEqual(self.request('GET', '/api/session', headers=h)[0], 200)
        self.assertEqual(self.request('GET', '/api/session', headers={'Cookie': h['Cookie'].replace('journal_sid', 'trip_session')})[0], 401)
        for options in ({'cookie_name': 'bad name'}, {'native_key_hash': 'abc'}, {'native_key_hash': key_hash(KEY), 'review_key_hash': key_hash(KEY)}):
            with self.assertRaises(ValueError):
                self.make(**options)

    def test_plan_must_belong_to_catalog_trip(self):
        with tempfile.TemporaryDirectory() as directory:
            other = trip_fixture.catalog(directory, trip_id='another-trip')
        with self.assertRaises(ValueError):
            make_server(self.store, other)
        plan = self.store.snapshot()['state']
        with self.assertRaises(ValueError):
            validate_plan(dict(plan, id='another-trip'), self.catalog, 'another-trip')
        with self.assertRaises(ValueError):
            validate_plan(plan, self.catalog, 'another-trip')

    def test_days_follow_catalog_length_and_dates(self):
        plan = self.store.snapshot()['state']
        self.validate(plan)
        for bad_days in (plan['days'][:-1], plan['days'] + [dict(plan['days'][0], date='2030-05-04')], []):
            with self.assertRaises(ValueError):
                self.validate(dict(plan, days=copy.deepcopy(bad_days)))
        shifted = copy.deepcopy(plan); shifted['days'][1]['date'] = '2030-05-09'
        with self.assertRaises(ValueError):
            self.validate(shifted)
        for count in (1, 7, 60):
            with tempfile.TemporaryDirectory() as directory:
                catalog = trip_fixture.catalog(directory, days=count)
                validate_plan(copy.deepcopy(catalog['defaults']), catalog, catalog['trip']['id'])
                self.assertEqual(len(catalog['days']), count)
        with tempfile.TemporaryDirectory() as directory, self.assertRaises(ValueError):
            trip_fixture.catalog(directory, days=61)

    def test_budget_is_trip_totals_with_exact_keys(self):
        plan = self.store.snapshot()['state']
        self.assertEqual(set(plan['budget']), {'flightOut', 'flightReturn', 'hotel', 'food', 'transport', 'other'})
        for key in plan['budget']:
            for invalid in [None, True, -1, float('inf'), float('nan'), MAX_BUDGET + 1, '10']:
                bad = copy.deepcopy(plan)
                bad['budget'][key] = invalid
                with self.assertRaises(ValueError):
                    self.validate(bad)
        missing = copy.deepcopy(plan); del missing['budget']['other']
        extra = copy.deepcopy(plan); extra['budget']['airport'] = 100
        for bad in (missing, extra, dict(plan, budget=[])):
            with self.assertRaises(ValueError):
                self.validate(bad)
        plan['budget'].update(flightOut=1880, flightReturn=1765.5, hotel=150000)  # JPY-scale amounts must fit
        self.validate(plan)
        self.store.update(0, plan, 'client', self.validate)
        self.assertEqual(self.store.snapshot()['state']['budget']['flightReturn'], 1765.5)

    def test_hotel_favorites_legacy_preservation(self):
        original = self.store.snapshot()['state']
        plan = copy.deepcopy(original)
        for invalid in [None, {}, ['harbor-inn', 'harbor-inn'], [True], ['<script>']]:
            bad = copy.deepcopy(plan)
            bad['hotelFavorites'] = invalid
            with self.assertRaises(ValueError):
                self.validate(bad)
        plan['hotelFavorites'] = ['harbor-inn']
        self.validate(plan)
        self.store.update(0, plan, 'new client')
        legacy = copy.deepcopy(original); del legacy['hotelFavorites']
        self.store.update(1, legacy, 'legacy client')
        saved = self.store.snapshot()['state']
        self.assertEqual(saved['hotelFavorites'], ['harbor-inn'])
        for key in ('budget', 'days', 'checks'):
            self.assertEqual(saved[key], original[key])
        saved['hotelFavorites'] = []
        self.store.update(2, saved, 'explicit clear')
        self.assertEqual(self.store.snapshot()['state']['hotelFavorites'], [])

    def test_stay_dates_follow_trip_window_and_legacy_preservation(self):
        original = self.store.snapshot()['state']
        # The first night may start on the departure date, before the first itinerary day.
        hotel = dict(id='hotel-a', name='Test hotel', address='Test address', phone='+1 555 0100', checkIn='2030-04-30', checkOut='2030-05-02', checkInTime='15:00', checkOutTime='12:00', lateArrival=True, notes='')
        next_hotel = dict(hotel, id='hotel-b', checkIn='2030-05-02', checkOut='2030-05-03')
        plan = dict(original, stays=[hotel, next_hotel])
        self.validate(plan)
        for changes in [dict(checkIn='2030-05-01'), dict(checkOut='2030-05-02'), dict(checkOut='2030-05-04'),
                        dict(checkIn='2030-04-29'), dict(checkIn='2030-05-99'), dict(checkIn='2030-5-2'), dict(checkOutTime='25:00')]:
            bad = dict(plan, stays=[hotel, dict(next_hotel, **changes)])
            with self.subTest(changes=changes), self.assertRaises(ValueError):
                self.validate(bad)
        with self.assertRaises(ValueError):
            self.validate(dict(plan, stays=[dict(hotel, checkIn='2030-04-29')]))
        self.store.update(0, plan, 'new client')
        legacy = copy.deepcopy(original); del legacy['stays']
        self.store.update(1, legacy, 'legacy client')
        self.assertEqual(self.store.snapshot()['state']['stays'], [hotel, next_hotel])
        self.store.update(2, dict(plan, stays=[]), 'clear stays')
        self.assertEqual(self.store.snapshot()['state']['stays'], [])

    def test_stay_english_name_survives_legacy_edits_and_can_be_cleared(self):
        plan = self.store.snapshot()['state']
        hotel = dict(id='hotel-a', name='测试酒店', nameEnglish='Test & Hotel', address='1 Test Road', phone='+1 555 0100', checkIn='2030-05-01', checkOut='2030-05-03', checkInTime='', checkOutTime='', lateArrival=False, notes='')
        plan['stays'] = [hotel]
        self.validate(plan)
        self.store.update(0, copy.deepcopy(plan), 'new client')
        legacy = copy.deepcopy(plan)
        del legacy['stays'][0]['nameEnglish']
        legacy['stays'][0]['notes'] = 'Updated by old app'
        self.store.update(1, legacy, 'old app')
        self.assertEqual(self.store.snapshot()['state']['stays'][0]['nameEnglish'], 'Test & Hotel')
        for invalid in [None, 42, 'x' * 301]:
            bad = copy.deepcopy(plan)
            bad['stays'][0]['nameEnglish'] = invalid
            with self.assertRaises(ValueError):
                self.validate(bad)
        plan['stays'][0]['nameEnglish'] = ''
        self.store.update(2, plan, 'clear name')
        self.assertEqual(self.store.snapshot()['state']['stays'][0]['nameEnglish'], '')

    def test_ticket_attachments_auth_and_validation(self):
        content = b'%PDF-1.4\n test attachment'
        self.assertEqual(self.request('POST', '/api/attachments', content, {'Content-Type':'application/pdf'})[0], 401)
        h = self.cookie()
        upload_headers = dict(h, **{'Content-Type':'application/pdf'})
        self.assertEqual(self.request('POST', '/api/attachments', content, upload_headers)[0], 403)
        h['X-Trip-CSRF'] = json.loads(self.request('GET', '/api/session', headers=h)[2])['csrf']; upload_headers.update(h)
        self.assertEqual(self.request('POST', '/api/attachments', b'not pdf', upload_headers)[0], 422)
        self.assertEqual(self.request('POST', '/api/attachments', content, dict(upload_headers, Origin='https://evil.example'))[0], 403)
        code, _, raw = self.request('POST', '/api/attachments', content, upload_headers)
        self.assertEqual(code, 200)
        file = dict(json.loads(raw), name='two tickets.pdf')
        self.assertEqual(self.request('GET', '/api/attachments/'+file['id'])[0], 401)
        self.assertEqual(self.request('GET', '/api/attachments/'+file['id'], headers=h)[2], content)
        plan = self.store.snapshot()['state']
        pid = self.catalog['places'][0]['id']
        ticket = dict(id='ticket-1', title='Adult tickets', status='booked', quantity=2, date='2030-05-02', time='13:00', provider='', reference='', url='', deadline='2030-04-28T23:59', notes='', files=[file])
        plan['tickets'] = {pid:[ticket]}
        self.assertEqual(self.request('PUT', '/api/plan', {'revision':0,'state':plan}, h)[0], 200)
        for changes in [dict(date='2030-05-31'),dict(date='2030-04-30'),dict(url='javascript:alert(1)'),dict(quantity=True),dict(deadline='soon'),dict(files=[dict(file, id='f'*64)])]:
            bad = copy.deepcopy(plan);bad['tickets'][pid][0].update(changes)
            self.assertEqual(self.request('PUT', '/api/plan', {'revision':1,'state':bad}, h)[0], 422)
        legacy = copy.deepcopy(plan);del legacy['tickets']
        self.assertEqual(self.request('PUT', '/api/plan', {'revision':1,'state':legacy}, h)[0], 200)
        self.assertEqual(self.store.snapshot()['state']['tickets'], {pid:[ticket]})
        plan['tickets'][pid] = []
        self.assertEqual(self.request('PUT', '/api/plan', {'revision':2,'state':plan}, h)[0], 200)
        self.assertEqual(self.store.snapshot()['state']['tickets'][pid], [])
        # Existing revision / draft references keep working after a record is removed.
        self.assertEqual(self.request('GET', '/api/attachments/'+file['id'], headers=h)[2], content)


class ReviewIsolationTest(SharedTripTest):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.catalog = trip_fixture.catalog(self.tmp.name)
        self.db = Path(self.tmp.name)/'trip.sqlite3'
        self.review_db = Path(self.tmp.name)/'review.sqlite3'
        for path, label in [(self.db, 'PRIVATE'), (self.review_db, 'DEMO')]:
            initialize(path, self.catalog)
            # Keep revision zero so the inherited protocol tests also run with review enabled.
            with sqlite3.connect(path) as db:
                plan = json.loads(db.execute('SELECT document FROM trip').fetchone()[0])
                plan['days'][0]['title'] = label
                db.execute('UPDATE trip SET document=?', (json.dumps(plan),))
        self.store = Store(self.db)
        self.review_store = Store(self.review_db)
        self.start(self.make(review_store=self.review_store, review_key_hash=key_hash(REVIEW_KEY)))

    def test_review_plan_session_and_conflict_isolation(self):
        private = self.authenticate(KEY)
        review = self.authenticate(REVIEW_KEY)
        self.assertIn('=review.', review['Cookie'])
        for h, own in [(private, 'PRIVATE'), (review, 'DEMO')]:
            code, _, raw = self.request('GET', '/api/plan', headers=h)
            self.assertEqual(code, 200)
            snapshot = json.loads(raw)
            self.assertEqual(snapshot['state']['days'][0]['title'], own)
            snapshot['state']['checks']['passport'] = True
            self.assertEqual(self.request('PUT', '/api/plan', snapshot, h)[0], 200)
            code, _, raw = self.request('PUT', '/api/plan', snapshot, h)
            self.assertEqual(code, 409)
            self.assertEqual(json.loads(raw)['latest']['state']['days'][0]['title'], own)
        self.assertEqual(self.request('PUT', '/api/plan', {}, dict(review, **{'X-Trip-CSRF': private['X-Trip-CSRF']}))[0], 403)
        for cookie in [review['Cookie'].replace('=review.', '='), private['Cookie'].replace('=', '=review.', 1)]:
            self.assertEqual(self.request('GET', '/api/plan', headers={'Cookie': cookie})[0], 401)
        # Recreated Store objects still recognize persisted sessions in the correct database.
        self.server.store = Store(self.db)
        self.server.review_store = Store(self.review_db)
        self.assertEqual(self.request('GET', '/api/plan', headers=review)[0], 200)
        with self.review_store.connect() as db: db.execute('UPDATE sessions SET expires=0')
        self.assertEqual(self.request('GET', '/api/plan', headers=review)[0], 401)
        self.assertEqual(self.request('GET', '/api/plan', headers=private)[0], 200)

    def test_review_attachments_and_ticket_references_isolated(self):
        private, review = self.authenticate(KEY), self.authenticate(REVIEW_KEY)
        uploaded = []
        for h, data in [(private, b'%PDF-1.4\n PRIVATE'), (review, b'%PDF-1.4\n DEMO')]:
            code, _, raw = self.request('POST', '/api/attachments', data, dict(h, **{'Content-Type': 'application/pdf'}))
            self.assertEqual(code, 200)
            file = dict(json.loads(raw), name='example.pdf')
            uploaded.append(file)
            self.assertEqual(self.request('GET', '/api/attachments/' + file['id'], headers=h)[2], data)
        for h, foreign in [(review, uploaded[0]), (private, uploaded[1])]:
            self.assertEqual(self.request('GET', '/api/attachments/' + foreign['id'], headers=h)[0], 404)
            snapshot = json.loads(self.request('GET', '/api/plan', headers=h)[2])
            pid = self.catalog['places'][0]['id']
            snapshot['state']['tickets'] = {pid: [dict(id='ticket-demo', title='Example', status='planned', quantity=2, date='', time='', provider='', reference='', url='', deadline='', notes='', files=[foreign])]}
            self.assertEqual(self.request('PUT', '/api/plan', snapshot, h)[0], 422)

    def test_review_key_requires_review_database(self):
        del self.server.review_store
        self.assertEqual(self.request('POST', '/api/native-session', {'accessKey': REVIEW_KEY})[0], 403)
        self.assertEqual(self.request('POST', '/api/native-session', {'accessKey': KEY})[0], 200)
        with self.assertRaises(ValueError):
            self.make(review_store=Store(self.db), review_key_hash=key_hash(REVIEW_KEY))

    def test_review_concurrent_requests_do_not_switch_other_handlers(self):
        private, review = self.authenticate(KEY), self.authenticate(REVIEW_KEY)
        def read(pair):
            headers, title = pair
            code, _, raw = self.request('GET', '/api/plan', headers=headers)
            return code == 200 and json.loads(raw)['state']['days'][0]['title'] == title
        with concurrent.futures.ThreadPoolExecutor(8) as pool:
            self.assertTrue(all(pool.map(read, [(private, 'PRIVATE'), (review, 'DEMO')] * 20)))
        del self.server.review_store
        self.assertEqual(self.request('GET', '/api/plan', headers=review)[0], 401)
        self.assertEqual(self.request('GET', '/api/plan', headers=private)[0], 200)


class CommandLineTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.dir = Path(self.tmp.name)
        self.catalog_path = trip_fixture.write_catalog(self.dir)
        self.command = [sys.executable, str(Path(__file__).resolve().parent / 'trip_server.py')]

    def run_cli(self, *args, env=None):
        return subprocess.run(self.command + list(args), capture_output=True, text=True,
                              env=dict(os.environ, **(env or {})))

    def test_init_backup_and_reset_touch(self):
        data = self.dir / 'data'
        result = self.run_cli('init', '--data-dir', str(data), env={'TRIP_CATALOG': str(self.catalog_path)})
        self.assertEqual(result.returncode, 0, result.stderr)
        database = data / 'trip.sqlite3'
        self.assertEqual(database.stat().st_mode & 0o777, 0o600)
        state = Store(database).snapshot()
        self.assertEqual(state['revision'], 0)
        self.assertEqual(state['state'], load_catalog(self.catalog_path)['defaults'])
        # init never overwrites an existing trip.
        self.assertNotEqual(self.run_cli('init', '--db', str(database), '--catalog', str(self.catalog_path)).returncode, 0)
        backup = self.dir / 'backup.sqlite3'
        self.assertEqual(self.run_cli('backup', '--db', str(database), '--output', str(backup)).returncode, 0)
        self.assertEqual(Store(backup).snapshot(), state)
        result = self.run_cli('reset-touch', '--db', str(database))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(Store(database).snapshot(), state)
        for removed in ('rotate-password', 'update-flight-notes'):
            self.assertNotEqual(self.run_cli(removed, '--db', str(database)).returncode, 0)

    @unittest.skipUnless(DEFAULT_CATALOG.is_file(), 'run scripts/build_ios_resources.py first')
    def test_generated_catalog_defaults_are_a_valid_plan(self):
        catalog = load_catalog(DEFAULT_CATALOG)
        database = self.dir / 'generated.sqlite3'
        initialize(database, catalog)
        validate_plan(Store(database).snapshot()['state'], catalog, catalog['trip']['id'])


if __name__=='__main__':unittest.main()
