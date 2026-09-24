"""Private, device-authenticated couple interactions, separate from trip revisions."""
from contextlib import contextmanager
import hashlib
import re
import secrets
import sqlite3
import sys
import time

RETENTION = 7 * 86400
DEFAULT_NICKNAME = '我'
PUSH_TTL = 3600


def log(name, /, **fields):
    # One diagnostic line per decision. Never device tokens, secrets or payloads.
    sys.stderr.write(' '.join(['touch.' + name] + [f'{k}={v}' for k, v in fields.items() if v is not None]) + '\n')
    sys.stderr.flush()


def short(value):
    return value[:8] if isinstance(value, str) else value


class TouchError(Exception):
    def __init__(self, status, message):
        self.status, self.message = status, message


def digest(value):
    return hashlib.sha256(value.encode()).hexdigest()


def nickname(value):
    if not isinstance(value, str) or not 1 <= len(value.strip()) <= 16 or any(ord(c) < 32 for c in value):
        raise TouchError(422, '昵称请填写 1 到 16 个字')
    return value.strip()


class TouchService:
    def __init__(self, database, clock=time.time):
        self.database, self.clock = str(database), clock
        with self.connect() as db:
            db.executescript('''
            CREATE TABLE IF NOT EXISTS touch_members(
                id TEXT PRIMARY KEY, secret TEXT UNIQUE NOT NULL, name TEXT NOT NULL,
                created REAL NOT NULL, revoked INTEGER NOT NULL DEFAULT 0,
                push_token TEXT, environment TEXT, last_alert REAL NOT NULL DEFAULT 0);
            CREATE TABLE IF NOT EXISTS touch_pair(
                id INTEGER PRIMARY KEY CHECK(id=1), first TEXT NOT NULL, second TEXT);
            CREATE TABLE IF NOT EXISTS touch_invites(
                owner TEXT PRIMARY KEY, code TEXT UNIQUE NOT NULL, expires REAL NOT NULL,
                candidate TEXT, replacing TEXT);
            CREATE TABLE IF NOT EXISTS touch_events(
                seq INTEGER PRIMARY KEY AUTOINCREMENT, id TEXT UNIQUE NOT NULL,
                sender TEXT NOT NULL, recipient TEXT NOT NULL, kind TEXT NOT NULL,
                name TEXT NOT NULL, created REAL NOT NULL);
            CREATE INDEX IF NOT EXISTS touch_events_recipient ON touch_events(recipient,seq);
            CREATE TABLE IF NOT EXISTS touch_push(
                event_id TEXT PRIMARY KEY, recipient TEXT NOT NULL, expires REAL NOT NULL,
                state TEXT NOT NULL DEFAULT 'pending', attempts INTEGER NOT NULL DEFAULT 0,
                next_attempt REAL NOT NULL, lease REAL NOT NULL DEFAULT 0);
            CREATE TABLE IF NOT EXISTS touch_limits(key TEXT NOT NULL, created REAL NOT NULL);
            CREATE INDEX IF NOT EXISTS touch_limits_key ON touch_limits(key,created);
            ''')

    @contextmanager
    def connect(self):
        db = sqlite3.connect(self.database, timeout=10)
        db.row_factory = sqlite3.Row
        try:
            with db:
                yield db
        finally:
            db.close()

    def member(self, db, secret):
        if not isinstance(secret, str) or not re.fullmatch(r'[A-Za-z0-9_-]{40,128}', secret):
            raise TouchError(403, '这部手机尚未绑定，请重新配对')
        row = db.execute('SELECT * FROM touch_members WHERE secret=? AND revoked=0', (digest(secret),)).fetchone()
        if not row:
            raise TouchError(403, '这部手机的绑定已失效，请让对方重新邀请')
        return row

    def limit(self, key, maximum, window):
        # Commit failed-attempt counters independently of the operation transaction.
        now = self.clock()
        with self.connect() as db:
            db.execute('BEGIN IMMEDIATE')
            db.execute('DELETE FROM touch_limits WHERE created<?', (now - 86400,))
            count = db.execute('SELECT COUNT(*) FROM touch_limits WHERE key=? AND created>?', (key, now-window)).fetchone()[0]
            if count >= maximum:
                raise TouchError(429, '先歇一小会儿，再试一次吧')
            db.execute('INSERT INTO touch_limits VALUES(?,?)', (key, now))

    def partner(self, db, member_id):
        pair = db.execute('SELECT * FROM touch_pair WHERE first=? OR second=?', (member_id, member_id)).fetchone()
        if not pair:
            return None
        other = pair['second'] if pair['first'] == member_id else pair['first']
        return db.execute('SELECT * FROM touch_members WHERE id=? AND revoked=0', (other,)).fetchone()

    def status_in(self, db, me):
        other = self.partner(db, me['id'])
        invite = db.execute('SELECT * FROM touch_invites WHERE owner=? AND expires>?', (me['id'], self.clock())).fetchone()
        candidate = db.execute('SELECT name FROM touch_members WHERE id=?', (invite['candidate'],)).fetchone() if invite and invite['candidate'] else None
        waiting = db.execute('SELECT 1 FROM touch_invites WHERE candidate=? AND expires>?', (me['id'], self.clock())).fetchone()
        return {'memberID': me['id'], 'nickname': me['name'],
                'partnerName': other['name'] if other else None,
                'partnerID': other['id'] if other else None,
                'candidateName': candidate['name'] if candidate else None,
                'inviteExpires': invite['expires'] if invite else None,
                'waiting': bool(waiting)}

    def prune(self, db):
        cutoff = self.clock() - RETENTION
        db.execute('DELETE FROM touch_push WHERE event_id IN (SELECT id FROM touch_events WHERE created<?)', (cutoff,))
        db.execute('DELETE FROM touch_events WHERE created<?', (cutoff,))
        db.execute('DELETE FROM touch_invites WHERE expires<?', (self.clock(),))

    def receipt(self, db, event):
        if event is None:
            return {'event': None}
        push = db.execute('SELECT state,expires FROM touch_push WHERE event_id=?', (event['id'],)).fetchone()
        # Older events may also lack a queue item because the previous server throttled them.
        state = push['state'] if push else 'not-queued'
        if push and state == 'pending' and push['expires'] <= self.clock():
            state = 'expired'
        # Keep the legacy field, but never equate APNs acceptance with device display.
        return {'event': dict(event), 'alert': 'ring' if state in ('pending', 'sending', 'accepted') else 'silent',
                'notificationState': state}

    def reset(self):
        # Operator recovery only: clears interaction identity, never trip data.
        with self.connect() as db:
            db.execute('BEGIN IMMEDIATE')
            counts = {table: db.execute('SELECT COUNT(*) FROM ' + table).fetchone()[0]
                      for table in ('touch_members', 'touch_events', 'touch_push', 'touch_invites')}
            for table in ('touch_push', 'touch_events', 'touch_invites', 'touch_pair', 'touch_members'):
                db.execute('DELETE FROM ' + table)
        log('reset', **counts)
        return counts

    def get(self, action, secret, query):
        with self.connect() as db:
            me = self.member(db, secret)
            self.prune(db)
            if action == 'status':
                return self.status_in(db, me)
            if action == 'events':
                try: cursor = max(0, int(query.get('after', ['0'])[0]))
                except (ValueError, TypeError): raise TouchError(422, '互动游标无效')
                rows = db.execute('SELECT * FROM touch_events WHERE (recipient=? OR sender=?) AND seq>? ORDER BY seq LIMIT 200', (me['id'], me['id'], cursor)).fetchall()
                return {'events': [dict(r) for r in rows], 'cursor': rows[-1]['seq'] if rows else cursor, 'hasMore': len(rows) == 200}
            if action.startswith('events/'):
                row = db.execute('SELECT * FROM touch_events WHERE id=? AND (sender=? OR recipient=?)', (action[7:], me['id'], me['id'])).fetchone()
                return self.receipt(db, row)
            raise TouchError(404, '互动接口不存在')

    def post(self, action, secret, data, ip='local'):
        if not isinstance(data, dict):
            raise TouchError(422, '互动数据无效')
        if action in ('enroll', 'join', 'bind'):
            self.limit(action + ':' + digest(ip), 20 if action in ('enroll', 'bind') else 10, 900)
        now = self.clock()
        with self.connect() as db:
            db.execute('BEGIN IMMEDIATE')
            self.prune(db)
            if action == 'bind':
                if not isinstance(secret, str) or not re.fullmatch(r'[A-Za-z0-9_-]{40,128}', secret):
                    raise TouchError(422, '设备凭证无效')
                row = db.execute('SELECT * FROM touch_members WHERE secret=?', (digest(secret),)).fetchone()
                if row and row['revoked']:
                    raise TouchError(403, '这部手机已解绑，请通过换机邀请重新加入')
                pair = db.execute('SELECT * FROM touch_pair WHERE id=1').fetchone()
                if pair and row and row['id'] in (pair['first'], pair['second']):
                    return self.status_in(db, row)
                if pair and pair['second']:
                    raise TouchError(409, '已经绑定了两部手机；换手机请使用下方的换机入口')
                # Only the empty pair is claimable by a tap. The second phone must present a
                # pairing code, so anyone else running this build cannot take the other slot.
                if pair:
                    raise TouchError(409, '第一部手机已经绑定了。请让 TA 生成配对码，在下面输入就能加入。')
                if not row:
                    db.execute('INSERT INTO touch_members(id,secret,name,created) VALUES(?,?,?,?)',
                               (secrets.token_hex(16), digest(secret), DEFAULT_NICKNAME, now))
                me = self.member(db, secret)
                db.execute('INSERT INTO touch_pair VALUES(1,?,NULL)', (me['id'],))
                log('bind', member=short(me['id']), slot='first', member_new=int(not row))
                return self.status_in(db, me)
            if action == 'enroll':
                if not isinstance(secret, str) or not re.fullmatch(r'[A-Za-z0-9_-]{40,128}', secret):
                    raise TouchError(422, '设备凭证无效')
                name = nickname(data.get('nickname'))
                row = db.execute('SELECT * FROM touch_members WHERE secret=?', (digest(secret),)).fetchone()
                if row and row['revoked']:
                    raise TouchError(403, '旧设备已解绑，请重新邀请')
                if not row:
                    db.execute('INSERT INTO touch_members(id,secret,name,created) VALUES(?,?,?,?)', (secrets.token_hex(16), digest(secret), name, now))
                else:
                    db.execute('UPDATE touch_members SET name=? WHERE id=?', (name, row['id']))
                me = self.member(db, secret)
                log('enroll', member=short(me['id']), member_new=int(not row))
                return self.status_in(db, me)
            me = self.member(db, secret)
            if action == 'invite':
                pair = db.execute('SELECT * FROM touch_pair WHERE id=1').fetchone()
                if pair and me['id'] not in (pair['first'], pair['second']):
                    raise TouchError(403, '这里已经有一对绑定了，请输入对方给你的邀请码')
                if not pair:
                    db.execute('INSERT INTO touch_pair VALUES(1,?,NULL)', (me['id'],))
                other = self.partner(db, me['id'])
                if other and data.get('replace') is not True:
                    raise TouchError(422, '换机邀请需要明确确认')
                code = secrets.token_hex(4).upper()
                db.execute('INSERT OR REPLACE INTO touch_invites VALUES(?,?,?,NULL,?)', (me['id'], digest(code), now+600, other['id'] if other else None))
                log('invite', member=short(me['id']), replacing=short(other['id']) if other else None)
                return {'code': code, 'expires': now+600}
            if action == 'join':
                code = data.get('code')
                if not isinstance(code, str) or not re.fullmatch(r'[A-Fa-f0-9]{8}', code.strip()):
                    raise TouchError(422, '请输入 8 位邀请码')
                invite = db.execute('SELECT * FROM touch_invites WHERE code=? AND expires>?', (digest(code.strip().upper()), now)).fetchone()
                if not invite or invite['owner'] == me['id']:
                    raise TouchError(422, '邀请码已失效，请让对方重新生成')
                pair = db.execute('SELECT * FROM touch_pair WHERE id=1').fetchone()
                if pair and me['id'] in (pair['first'], pair['second']):
                    raise TouchError(422, '这部手机已经绑定，不需要再加入')
                if invite['candidate'] and invite['candidate'] != me['id']:
                    raise TouchError(422, '邀请正在等待确认，请让对方重新生成')
                db.execute('UPDATE touch_invites SET candidate=? WHERE owner=?', (me['id'], invite['owner']))
                # Joining only proposes; the pair stays incomplete until the owner confirms.
                log('join', member=short(me['id']), owner=short(invite['owner']), awaiting='confirm')
                return self.status_in(db, me)
            if action == 'confirm':
                invite = db.execute('SELECT * FROM touch_invites WHERE owner=? AND expires>?', (me['id'], now)).fetchone()
                if not invite or not invite['candidate']:
                    raise TouchError(422, '还没有待确认的邀请')
                pair = db.execute('SELECT * FROM touch_pair WHERE id=1').fetchone()
                if invite['replacing']:
                    old = invite['replacing']
                    db.execute('UPDATE touch_members SET revoked=1,push_token=NULL WHERE id=?', (old,))
                    db.execute("UPDATE touch_push SET state='cancelled' WHERE recipient=? AND state IN ('pending','sending')", (old,))
                    column = 'first' if pair['first'] == old else 'second'
                    db.execute(f'UPDATE touch_pair SET {column}=? WHERE id=1', (invite['candidate'],))
                    # The replacement is the same person; retain seven-day history, never replay old pushes.
                    db.execute('UPDATE touch_events SET sender=? WHERE sender=?', (invite['candidate'], old))
                    db.execute('UPDATE touch_events SET recipient=? WHERE recipient=?', (invite['candidate'], old))
                else:
                    db.execute('UPDATE touch_pair SET second=? WHERE id=1', (invite['candidate'],))
                log('confirm', member=short(me['id']), candidate=short(invite['candidate']), revoked=short(invite['replacing']))
                db.execute('DELETE FROM touch_invites')
                return self.status_in(db, me)
            if action == 'cancel-invite':
                db.execute('DELETE FROM touch_invites WHERE owner=? OR candidate=?', (me['id'], me['id']))
                log('cancel-invite', member=short(me['id']))
                return self.status_in(db, me)
            if action == 'device':
                token, env = data.get('token'), data.get('environment')
                if token == '':
                    token = None
                if token is not None and (not isinstance(token, str) or not re.fullmatch(r'[a-f0-9]{32,256}', token)):
                    raise TouchError(422, '通知设备令牌无效')
                if env not in ('sandbox', 'production'):
                    raise TouchError(422, '通知环境无效')
                if token:
                    db.execute('UPDATE touch_members SET push_token=NULL WHERE push_token=? AND id<>?', (token, me['id']))
                db.execute('UPDATE touch_members SET push_token=?,environment=? WHERE id=?', (token, env, me['id']))
                log('device', member=short(me['id']), token=short(digest(token)) if token else 'cleared', environment=env)
                return {'ok': True}
            if action == 'send':
                identifier, kind = data.get('id'), data.get('kind')
                if not isinstance(identifier, str) or not re.fullmatch(r'[A-Za-z0-9_-]{1,100}', identifier) or kind not in ('poke', 'heart'):
                    raise TouchError(422, '小动作无效')
                old = db.execute('SELECT * FROM touch_events WHERE id=?', (identifier,)).fetchone()
                if old:
                    if old['sender'] != me['id'] or old['kind'] != kind:
                        raise TouchError(422, '互动编号已被使用')
                    return self.receipt(db, old)
                other = self.partner(db, me['id'])
                if not other:
                    raise TouchError(422, '先和对方完成配对吧')
                count = db.execute('SELECT COUNT(*) FROM touch_events WHERE sender=? AND created>?', (me['id'], now-60)).fetchone()[0]
                if count >= 30:
                    raise TouchError(429, '发得有点快，稍等一下再试')
                db.execute('INSERT INTO touch_events(id,sender,recipient,kind,name,created) VALUES(?,?,?,?,?,?)', (identifier, me['id'], other['id'], kind, me['name'], now))
                if not other['push_token']:
                    alert = 'no-token'
                else:
                    alert = 'queued'
                    db.execute('INSERT INTO touch_push(event_id,recipient,expires,next_attempt) VALUES(?,?,?,?)', (identifier, other['id'], now+PUSH_TTL, now))
                log('send', event=short(identifier), sender=short(me['id']), recipient=short(other['id']), kind=kind, alert=alert)
                row = db.execute('SELECT * FROM touch_events WHERE id=?', (identifier,)).fetchone()
                return self.receipt(db, row)
            raise TouchError(404, '互动接口不存在')
