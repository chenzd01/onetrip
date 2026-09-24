import concurrent.futures
import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import Mock, patch
from touch_service import TouchService, TouchError, RETENTION
from touch_push import APNs, PushWorker, retry_after_seconds


class TouchTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.now = 1000000.
        self.service = TouchService(Path(self.tmp.name)/'test.sqlite', lambda: self.now)
        self.a, self.b, self.c = 'a'*48, 'b'*48, 'c'*48
        for key, name in ((self.a, '旅伴甲'), (self.b, '旅伴乙'), (self.c, '新手机')):
            self.service.post('enroll', key, {'nickname': name})

    def tearDown(self): self.tmp.cleanup()
    def post(self, action, key, **data): return self.service.post(action, key, data)
    def get(self, action, key, **query): return self.service.get(action, key, {k: [str(v)] for k,v in query.items()})
    def pair(self):
        code = self.post('invite', self.a)['code']
        self.post('join', self.b, code=code)
        self.post('confirm', self.a)
    def token(self, key): self.post('device', key, token=key[:40], environment='production')
    def rows(self, table):
        with self.service.connect() as db: return [dict(r) for r in db.execute('SELECT * FROM '+table)]

    def test_auto_binding_is_idempotent_and_reciprocal(self):
        first = self.post('bind', self.a)
        self.assertIsNone(first['partnerID'])
        self.assertEqual(first, self.post('bind', self.a))
        # The second slot is never claimable by a tap; only a pairing code opens it.
        with self.assertRaises(TouchError) as blocked: self.post('bind', self.b)
        self.assertEqual(blocked.exception.status, 409)
        self.assertIsNone(self.rows('touch_pair')[0]['second'])
        self.pair()
        second = self.get('status', self.b)
        self.assertEqual(second['partnerID'], first['memberID'])
        self.assertEqual(self.get('status', self.a)['partnerID'], second['memberID'])
        self.token(self.a); self.token(self.b)
        for key, recipient, identifier in [(self.a, second['memberID'], 'forward'), (self.b, first['memberID'], 'back')]:
            event = self.post('send', key, id=identifier, kind='poke')['event']
            self.assertEqual(event['recipient'], recipient)
            self.assertNotEqual(event['sender'], recipient)
        self.assertEqual(len(self.rows('touch_push')), 2)
        with self.assertRaises(TouchError) as error: self.post('bind', self.c)
        self.assertEqual(error.exception.status, 409)
        with self.assertRaises(TouchError): self.post('bind', 'd'*48)
        self.assertEqual(len(self.rows('touch_members')), 3)
        self.assertEqual(self.get('events', self.c)['events'], [])

    def test_auto_binding_serializes_simultaneous_devices(self):
        def bind(key):
            try: return self.post('bind', key)
            except TouchError as error: return error.status
        with concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool:
            results = list(pool.map(bind, [self.a, self.b, self.c]))
        self.assertEqual(sum(isinstance(result, dict) for result in results), 1)
        self.assertEqual([r for r in results if not isinstance(r, dict)], [409, 409])
        pair = self.rows('touch_pair')[0]
        self.assertIsNone(pair['second'])

    def test_second_slot_needs_a_pairing_code_from_the_first_phone(self):
        self.post('bind', self.a)
        for stranger in (self.b, self.c):
            with self.assertRaises(TouchError) as blocked: self.post('bind', stranger)
            self.assertEqual(blocked.exception.status, 409)
        self.assertEqual(len(self.rows('touch_members')), 3)
        with self.assertRaises(TouchError): self.post('join', self.b, code='00000000')
        code = self.post('invite', self.a)['code']
        with self.assertRaises(TouchError): self.post('join', self.b, code=code[:-1] + ('0' if code[-1] != '0' else '1'))
        self.post('join', self.b, code=code)
        self.assertIsNone(self.rows('touch_pair')[0]['second'])
        self.post('confirm', self.a)
        self.assertEqual(self.get('status', self.b)['partnerID'], self.get('status', self.a)['memberID'])
        with self.assertRaises(TouchError): self.post('bind', self.c)

    def test_send_reports_queue_state_without_claiming_device_delivery(self):
        self.pair()
        self.assertEqual(self.post('send', self.a, id='quiet', kind='poke')['alert'], 'silent')
        self.token(self.b)
        self.assertEqual(self.post('send', self.a, id='first', kind='poke')['alert'], 'ring')
        self.assertEqual(self.post('send', self.a, id='first', kind='poke')['alert'], 'ring')
        self.assertEqual(self.post('send', self.a, id='second', kind='poke')['alert'], 'ring')
        self.now += 60
        self.assertEqual(self.post('send', self.a, id='third', kind='poke')['alert'], 'ring')

    def test_operator_reset_clears_only_interaction_identity(self):
        self.pair(); self.token(self.b)
        self.post('send', self.a, id='before-reset', kind='poke')
        counts = self.service.reset()
        self.assertEqual(counts['touch_members'], 3)
        self.assertEqual(self.rows('touch_pair'), [])
        self.assertEqual(self.rows('touch_events'), [])
        self.assertEqual(self.rows('touch_push'), [])
        self.assertIsNone(self.post('bind', self.c)['partnerID'])

    def test_existing_pair_and_replacement_survive_auto_binding(self):
        self.pair()
        before = self.rows('touch_pair')
        self.post('bind', self.a); self.post('bind', self.b)
        self.assertEqual(before, self.rows('touch_pair'))
        code = self.post('invite', self.a, replace=True)['code']
        self.post('join', self.c, code=code); self.post('confirm', self.a)
        with self.assertRaises(TouchError): self.post('bind', self.b)
        self.assertEqual(self.post('bind', self.c)['partnerID'], before[0]['first'])

    def test_test_database_never_occupies_private_pair(self):
        isolated = TouchService(Path(self.tmp.name)/'development.sqlite', lambda: self.now)
        isolated.post('bind', self.a, {})
        with self.assertRaises(TouchError): isolated.post('bind', self.b, {})
        self.assertEqual(self.rows('touch_pair'), [])
        self.assertIsNone(self.post('bind', self.c)['partnerID'])

    def test_both_confirm_and_third_device_cannot_impersonate(self):
        code = self.post('invite', self.a)['code']
        self.post('join', self.b, code=code)
        with self.assertRaises(TouchError): self.post('send', self.b, id='early', kind='heart')
        self.assertEqual(self.get('status', self.a)['candidateName'], '旅伴乙')
        self.post('confirm', self.a)
        with self.assertRaises(TouchError): self.post('invite', self.c)
        with self.assertRaises(TouchError): self.post('send', self.c, id='outsider', kind='poke')
        self.post('send', self.a, id='private', kind='heart')
        self.assertEqual(self.get('events', self.c)['events'], [])
        self.assertIsNone(self.get('events/private', self.c)['event'])

    def test_expired_invite_and_failed_code_rate_limit(self):
        code = self.post('invite', self.a)['code']
        self.now += 601
        with self.assertRaises(TouchError): self.post('join', self.b, code=code)
        for _ in range(9):
            with self.assertRaises(TouchError): self.post('join', self.b, code='FFFFFFFF')
        with self.assertRaises(TouchError) as ctx: self.post('join', self.b, code=code)
        self.assertEqual(ctx.exception.status, 429)

    def test_replacement_revokes_old_device_and_preserves_history(self):
        self.pair(); self.token(self.b)
        self.post('send', self.a, id='one', kind='heart')
        with self.assertRaises(TouchError): self.post('invite', self.a)
        code = self.post('invite', self.a, replace=True)['code']
        self.post('join', self.c, code=code)
        self.post('confirm', self.a)
        with self.assertRaises(TouchError): self.get('status', self.b)
        with self.assertRaises(TouchError): self.post('enroll', self.b, nickname='冒认')
        self.assertEqual(self.get('events', self.c)['events'][0]['id'], 'one')
        self.assertEqual(self.rows('touch_push')[0]['state'], 'cancelled')

    def test_idempotent_send_and_concurrent_burst(self):
        self.pair(); self.token(self.b)
        def send(_): return self.post('send', self.a, id='same', kind='poke')
        with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
            results = list(pool.map(send, range(8)))
        self.assertTrue(all(r == results[0] for r in results))
        self.assertEqual(len(self.rows('touch_push')), 1)
        with self.assertRaises(TouchError): self.post('send', self.b, id='same', kind='poke')
        with self.assertRaises(TouchError): self.post('send', self.a, id='same', kind='heart')
        for i in range(4): self.post('send', self.a, id=str(i), kind='heart')
        self.assertEqual(len(self.rows('touch_push')), 5)
        self.now += 60
        self.post('send', self.a, id='later', kind='heart')
        self.assertEqual(len(self.rows('touch_push')), 6)

    def test_disabled_notifications_events_cursor_and_retention(self):
        self.pair()
        self.post('send', self.a, id='quiet', kind='heart')
        self.assertEqual(self.rows('touch_push'), [])
        feed = self.get('events', self.b)
        self.assertEqual(len(feed['events']), 1)
        self.assertEqual(self.get('events', self.b, after=feed['cursor'])['events'], [])
        self.now += RETENTION+1
        self.assertEqual(self.get('events', self.b)['events'], [])

    def test_notification_copy_variants_are_stable_and_have_no_names(self):
        from touch_push import notification_alert, HEART_TITLE, HEART_VARIANTS, POKE_TITLE, POKE_VARIANTS
        for kind, title, variants in [('poke', POKE_TITLE, set(POKE_VARIANTS)), ('heart', HEART_TITLE, set(HEART_VARIANTS))]:
            seen = set()
            for i in range(100):
                alert = notification_alert(kind, str(i))
                self.assertEqual(alert, notification_alert(kind, str(i)))
                self.assertEqual(alert['title'], title)
                self.assertIn(alert['body'], variants)
                seen.add(alert['body'])
            self.assertEqual(seen, variants)

    def test_push_payload_expiry_and_invalid_token(self):
        self.pair(); self.token(self.b)
        self.post('send', self.a, id='one', kind='heart')
        delivered = []
        worker = PushWorker(self.service, lambda row,payload: (delivered.append(payload) or 200, ''), lambda: self.now)
        self.assertTrue(worker.tick()); self.assertFalse(worker.tick())
        self.assertEqual(delivered[0]['touchEventID'], 'one')
        from touch_push import HEART_TITLE, HEART_VARIANTS
        self.assertEqual(delivered[0]['aps']['alert']['title'], HEART_TITLE)
        self.assertIn(delivered[0]['aps']['alert']['body'], HEART_VARIANTS)
        self.assertNotIn('badge', delivered[0]['aps'])
        self.assertEqual(delivered[0]['aps']['interruption-level'], 'active')
        self.assertEqual(delivered[0]['aps']['sound'], 'default')
        self.assertEqual(self.rows('touch_push')[0]['expires'], self.now + 3600)
        self.assertEqual(self.rows('touch_push')[0]['state'], 'accepted')
        self.now += 60
        self.post('send', self.a, id='expired', kind='poke'); self.now += 3601
        worker.tick()
        self.assertEqual(len(delivered), 1)
        self.post('send', self.a, id='invalid', kind='poke')
        PushWorker(self.service, lambda *_: (410, 'Unregistered'), lambda: self.now).tick()
        self.assertIsNone(next(m for m in self.rows('touch_members') if m['name']=='旅伴乙')['push_token'])

    def test_transport_failure_and_worker_restart_never_repeat(self):
        self.pair(); self.token(self.b)
        self.post('send', self.a, id='one', kind='poke')
        def fail(*_): raise TimeoutError()
        worker = PushWorker(self.service, fail, lambda: self.now)
        worker.tick()
        self.assertEqual(self.rows('touch_push')[0]['state'], 'uncertain')
        self.assertFalse(worker.tick())
        self.now += 60
        self.post('send', self.a, id='two', kind='heart')
        with self.service.connect() as db:
            db.execute("UPDATE touch_push SET state='sending',lease=? WHERE event_id='two'", (self.now-1,))
        self.assertFalse(worker.tick())
        self.assertEqual(self.rows('touch_push')[1]['state'], 'uncertain')

    def test_device_clear_accepts_null_and_empty_string(self):
        for token in (None, ''):
            self.token(self.b)
            self.post('device', self.b, token=token, environment='production')
            self.assertIsNone(next(m for m in self.rows('touch_members') if m['name'] == '旅伴乙')['push_token'])
        for token in (False, 1, 'bad'):
            with self.assertRaises(TouchError):
                self.post('device', self.b, token=token, environment='production')

    def test_receipt_reports_actual_push_state_on_send_and_lookup(self):
        self.pair()
        receipt = self.post('send', self.a, id='quiet', kind='poke')
        self.assertEqual(receipt['notificationState'], 'not-queued')
        self.token(self.b)
        self.post('send', self.a, id='one', kind='poke')
        for state in ('pending', 'sending', 'accepted', 'failed', 'uncertain', 'expired', 'cancelled'):
            with self.service.connect() as db:
                db.execute('UPDATE touch_push SET state=? WHERE event_id=?', (state, 'one'))
            receipt = self.get('events/one', self.a)
            self.assertEqual(receipt['notificationState'], state)
            self.assertEqual(receipt['alert'], 'ring' if state in ('pending', 'sending', 'accepted') else 'silent')
            self.assertEqual(receipt, self.post('send', self.a, id='one', kind='poke'))
        self.assertEqual(self.get('events/one', self.c), {'event': None})
        with self.service.connect() as db:
            db.execute("UPDATE touch_push SET state='pending' WHERE event_id='one'")
        self.now += 3600
        self.assertEqual(self.get('events/one', self.a)['notificationState'], 'expired')

    def test_transient_rejections_retry_five_times_with_backoff(self):
        self.pair(); self.token(self.b)
        for status in (429, 500, 503):
            self.post('send', self.a, id=str(status), kind='poke')
            calls = []
            worker = PushWorker(self.service, lambda *_: (calls.append(self.now) or status, 'Transient'), lambda: self.now)
            for attempt in range(1, 6):
                self.assertTrue(worker.tick())
                row = self.rows('touch_push')[-1]
                self.assertEqual(row['attempts'], attempt)
                self.assertEqual(row['state'], 'pending' if attempt < 5 else 'failed')
                self.assertFalse(worker.tick())
                if attempt < 5:
                    self.assertEqual(row['next_attempt'], self.now + 5 * 3 ** (attempt - 1))
                    self.now = row['next_attempt']
            self.assertEqual(len(calls), 5)

    def test_retry_after_is_respected_and_cannot_extend_expiry(self):
        self.pair(); self.token(self.b)
        self.post('send', self.a, id='one', kind='poke')
        worker = PushWorker(self.service, lambda *_: (429, 'TooManyRequests', 90), lambda: self.now)
        worker.tick()
        self.assertEqual(self.rows('touch_push')[0]['next_attempt'], self.now + 90)
        self.now += 89
        self.assertFalse(worker.tick())
        self.now += 1
        PushWorker(self.service, lambda *_: (200, ''), lambda: self.now).tick()
        self.assertEqual(self.rows('touch_push')[0]['state'], 'accepted')
        self.post('send', self.a, id='two', kind='poke')
        PushWorker(self.service, lambda *_: (503, 'Unavailable', 3600), lambda: self.now).tick()
        self.assertEqual(self.rows('touch_push')[1]['state'], 'expired')
        self.assertEqual(retry_after_seconds('60', 0), 60)
        self.assertEqual(retry_after_seconds('Thu, 01 Jan 1970 00:02:00 GMT', 30), 90)
        self.assertEqual(retry_after_seconds('invalid', 0), 0)
        self.assertEqual(retry_after_seconds('-1', 0), 0)

    def test_apns_adapter_preserves_http_rejections_with_non_object_bodies(self):
        self.pair(); self.token(self.b)
        for index, (status, content) in enumerate(((503, b'<html>Unavailable</html>'),
                                                  (429, b'Too many requests'),
                                                  (503, b'[]'), (429, b'null'))):
            identifier = 'http-' + str(index)
            self.post('send', self.a, id=identifier, kind='poke')
            response = Mock(status_code=status, content=content, headers={'retry-after': '120'})
            response.json.side_effect = lambda: json.loads(content)
            # Avoid credentials and sockets: exercise the real adapter with a fake HTTP client.
            apns = APNs.__new__(APNs)
            apns.client = Mock(); apns.client.post.return_value = response
            apns.token = 'test-token'; apns.issued = self.now; apns.topic = 'test.topic'
            with patch('touch_push.time.time', return_value=self.now):
                self.assertTrue(PushWorker(self.service, apns, lambda: self.now).tick())
            row = next(row for row in self.rows('touch_push') if row['event_id'] == identifier)
            self.assertEqual(row['state'], 'pending')
            self.assertEqual(row['attempts'], 1)
            self.assertEqual(row['next_attempt'], self.now + 120)
            request = apns.client.post.call_args.kwargs
            self.assertEqual(request['headers']['apns-priority'], '10')
            self.assertEqual(request['headers']['apns-expiration'], str(int(self.now + 3600)))

    def test_permanent_rejection_never_retries(self):
        self.pair(); self.token(self.b)
        self.post('send', self.a, id='one', kind='poke')
        worker = PushWorker(self.service, lambda *_: (403, 'InvalidProviderToken'), lambda: self.now)
        worker.tick(); self.now += 100
        self.assertFalse(worker.tick())
        self.assertEqual(self.rows('touch_push')[0]['attempts'], 1)
        self.assertEqual(self.rows('touch_push')[0]['state'], 'failed')

    def test_enroll_retry_and_cancel(self):
        first = self.get('status', self.a)
        second = self.post('enroll', self.a, nickname='旅伴甲')
        self.assertEqual(first, second)
        code = self.post('invite', self.a)['code']
        self.post('join', self.b, code=code)
        self.post('cancel-invite', self.b)
        self.assertIsNone(self.get('status', self.a)['candidateName'])
        with self.assertRaises(TouchError): self.post('confirm', self.a)

    def test_new_device_bound_by_tap_gets_generic_nickname(self):
        from touch_service import DEFAULT_NICKNAME
        service = TouchService(Path(self.tmp.name)/'fresh.sqlite', lambda: self.now)
        self.assertEqual(service.post('bind', 'd'*48, {})['nickname'], DEFAULT_NICKNAME)

    def test_apns_topic_has_no_default(self):
        key = Path(self.tmp.name)/'key.p8'; key.write_text('fixture')
        env = {'TOUCH_APNS_TEAM_ID': 'TEAM', 'TOUCH_APNS_KEY_ID': 'KEY', 'TOUCH_APNS_KEY_PATH': str(key)}
        with patch.dict('os.environ', env, clear=True), patch.dict('sys.modules', {'httpx': Mock(), 'jwt': Mock()}):
            with self.assertRaises(KeyError): APNs()
            with patch.dict('os.environ', {'TOUCH_APNS_TOPIC': 'com.example.tripjournal'}):
                self.assertEqual(APNs().topic, 'com.example.tripjournal')


if __name__ == '__main__': unittest.main()
