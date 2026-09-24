#!/usr/bin/env python3
"""APNs worker. Run separately from the standard-library trip HTTP process."""
import argparse
import hashlib
import json
import os
import time
from pathlib import Path
from email.utils import parsedate_to_datetime
from touch_service import TouchService, log, short

# Notification copy never names the sender; edit these to change the tone of the feature.
HEART_TITLE, HEART_VARIANTS = '给你比心', ('❤️', '想你了', '抱抱你')
POKE_TITLE, POKE_VARIANTS = '戳了戳你', ('戳一下，在干嘛呢', '拍了拍你')


def notification_alert(kind, event_id):
    # Event IDs are random; hashing gives each event a stable random variant across retries.
    variants = HEART_VARIANTS if kind == 'heart' else POKE_VARIANTS
    index = int.from_bytes(hashlib.sha256(event_id.encode()).digest()[:8], 'big') % len(variants)
    return {'title': HEART_TITLE if kind == 'heart' else POKE_TITLE, 'body': variants[index]}


def retry_after_seconds(value, now):
    if not value:
        return 0
    try:
        return max(0, int(value))
    except ValueError:
        try:
            return max(0, parsedate_to_datetime(value).timestamp() - now)
        except (ValueError, TypeError, OverflowError):
            return 0


class PushWorker:
    def __init__(self, service, deliver, clock=time.time):
        self.service, self.deliver, self.clock = service, deliver, clock

    def tick(self):
        now = self.clock()
        with self.service.connect() as db:
            db.execute('BEGIN IMMEDIATE')
            self.service.prune(db)
            expired = db.execute("UPDATE touch_push SET state='expired' WHERE state='pending' AND expires<=?", (now,)).rowcount
            # Never replay a potentially accepted APNs request after a worker crash.
            stranded = db.execute("UPDATE touch_push SET state='uncertain' WHERE state='sending' AND lease<?", (now,)).rowcount
            if expired or stranded:
                log('push.reap', expired=expired or None, uncertain=stranded or None)
            row = db.execute('''SELECT q.*,e.kind,e.name,m.push_token,m.environment,m.revoked
                FROM touch_push q JOIN touch_events e ON q.event_id=e.id
                JOIN touch_members m ON q.recipient=m.id
                WHERE q.state='pending' AND q.next_attempt<=? ORDER BY e.seq LIMIT 1''', (now,)).fetchone()
            if not row:
                return False
            row = dict(row)
            if row['revoked'] or not row['push_token']:
                log('push.cancel', event=short(row['event_id']), recipient=short(row['recipient']),
                    reason='revoked' if row['revoked'] else 'no-token')
                db.execute("UPDATE touch_push SET state='cancelled' WHERE event_id=?", (row['event_id'],))
                return True
            db.execute("UPDATE touch_push SET state='sending',attempts=attempts+1,lease=? WHERE event_id=?", (now+30, row['event_id']))
        payload = {'aps': {'alert': notification_alert(row['kind'], row['event_id']),
            'sound': 'default', 'category': 'TOUCH', 'thread-id': 'couple-touch',
            'interruption-level': 'active'},
            'touchEventID': row['event_id']}
        # Retry explicit transient rejections only; ambiguous failures must not ring twice.
        started = self.clock()
        retry_after = 0
        try:
            result = self.deliver(row, payload)
            status, reason = result[:2]
            if len(result) > 2:
                retry_after = result[2]
        except Exception as failure:
            status, reason = 0, 'TransportFailure'
            log('push.transport', event=short(row['event_id']), failure=type(failure).__name__)
        with self.service.connect() as db:
            state = 'accepted' if status == 200 else ('uncertain' if status == 0 else 'failed')
            next_attempt = row['next_attempt']
            attempt = row['attempts'] + 1
            if status in (429, 500, 503) and attempt < 5:
                next_attempt = self.clock() + max(5 * 3 ** (attempt - 1), retry_after)
                state = 'pending' if next_attempt < row['expires'] else 'expired'
            log('push.result', event=short(row['event_id']), recipient=short(row['recipient']),
                kind=row['kind'], environment=row['environment'], attempt=row['attempts'] + 1,
                status=status, reason=reason or None, state=state, ms=round((self.clock() - started) * 1000))
            db.execute("UPDATE touch_push SET state=?,next_attempt=? WHERE event_id=? AND state='sending'", (state, next_attempt, row['event_id']))
            if status == 410 or reason in ('BadDeviceToken', 'DeviceTokenNotForTopic', 'Unregistered'):
                log('push.token-dropped', recipient=short(row['recipient']), reason=reason or status)
                db.execute('UPDATE touch_members SET push_token=NULL WHERE id=? AND push_token=?', (row['recipient'], row['push_token']))
        return True


class APNs:
    def __init__(self):
        import httpx
        import jwt
        self.jwt = jwt
        self.team = os.environ['TOUCH_APNS_TEAM_ID']
        self.key_id = os.environ['TOUCH_APNS_KEY_ID']
        self.key = Path(os.environ['TOUCH_APNS_KEY_PATH']).read_text()
        # The app's bundle identifier; there is deliberately no default.
        self.topic = os.environ['TOUCH_APNS_TOPIC']
        self.client = httpx.Client(http2=True, timeout=10)
        self.token, self.issued = '', 0
        log('push.start', topic=self.topic, team=self.team, key=self.key_id)

    def __call__(self, row, payload):
        now = time.time()
        if now-self.issued >= 3000:
            self.token = self.jwt.encode({'iss': self.team, 'iat': int(now)}, self.key,
                                         algorithm='ES256', headers={'kid': self.key_id})
            self.issued = now
        host = 'api.sandbox.push.apple.com' if row['environment'] == 'sandbox' else 'api.push.apple.com'
        response = self.client.post(f'https://{host}/3/device/{row["push_token"]}',
            headers={'authorization': 'bearer ' + self.token, 'apns-topic': self.topic,
                     'apns-push-type': 'alert', 'apns-priority': '10',
                     'apns-expiration': str(int(row['expires']))},
            content=json.dumps(payload, ensure_ascii=False).encode())
        reason = ''
        if response.content:
            try:
                body = response.json()
            except ValueError:
                body = None
            if isinstance(body, dict) and isinstance(body.get('reason'), str):
                reason = body['reason']
        log('push.apns', host=host, apns_id=response.headers.get('apns-id'), status=response.status_code, reason=reason or None)
        return response.status_code, reason, retry_after_seconds(response.headers.get('retry-after'), time.time())


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--db', required=True, type=Path)
    args = parser.parse_args()
    if not args.db.is_file():
        parser.error('database must already exist')
    worker = PushWorker(TouchService(args.db), APNs())
    while True:
        if not worker.tick():
            time.sleep(1)


if __name__ == '__main__':
    main()
