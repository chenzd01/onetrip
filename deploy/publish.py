"""Narrow, hash-checked code release for the trip server; never replaces trip data.

Workflow (nothing here downloads code or touches the database contents):
  1. On the server:  python3 deploy/publish.py hashes --root /opt/trip-journal > base.json
  2. Locally:        python3 deploy/publish.py bundle --source . --base base.json --output release/
                     (copies the allowlisted files and writes release/manifest.json; note its SHA-256)
  3. Upload release/ to the server, then:
                     python3 deploy/publish.py publish --bundle release --expected-manifest <sha256> [--dry-run]

publish refuses to run unless the uploaded files and the live files still match the manifest,
backs up every database (read-only copy) before touching code, stops the services, swaps files
atomically, restarts, polls /healthz, and on any failure restores only the code it replaced.
"""
import argparse
from contextlib import closing
import hashlib
import json
from pathlib import Path
import shutil
import sqlite3
import subprocess
import sys
import time
from urllib.request import urlopen

DEFAULT_FILES = frozenset({
    'server/trip_server.py', 'server/trip_catalog.py', 'server/touch_service.py', 'server/touch_push.py',
    'server/route_engine.py', 'server/route_places.py', 'server/route_preferences.py',
    'server/requirements-touch.txt', 'catalog.json',
})
# Where 'catalog.json' is read from when bundling; the server reads it via TRIP_CATALOG.
CATALOG_SOURCE = 'ios/TripJournal/Resources/Content/catalog.json'
SHARED_TABLES = ('trip', 'revisions', 'attachments', 'route_preferences')
DEFAULT_ROOT = Path('/opt/trip-journal')
DEFAULT_DATABASES = (Path('/var/lib/trip-journal/trip.sqlite3'),)
DEFAULT_SERVICES = ('trip-journal',)
DEFAULT_HEALTH_URL = 'http://127.0.0.1:8765/healthz'


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest() if path.exists() else None


def state(path):
    """Fingerprint of the shared tables; sessions and interaction queues may change freely."""
    with closing(sqlite3.connect(path.as_uri() + '?mode=ro', uri=True)) as db:
        db.execute('BEGIN')
        present = {row[0] for row in db.execute("SELECT name FROM sqlite_master WHERE type='table'")}
        return {table: hashlib.sha256(repr(db.execute('SELECT * FROM ' + table + ' ORDER BY 1').fetchall()).encode()).hexdigest()
                for table in SHARED_TABLES if table in present}


def hashes(root, files=DEFAULT_FILES):
    return {name: sha(root / name) for name in sorted(files)}


def bundle(source, base, output, files=DEFAULT_FILES, commit=''):
    if output.exists():
        raise ValueError('Use a fresh bundle directory')
    if set(base) != set(files):
        raise ValueError('Base hashes must cover exactly the release files')
    manifest = {'commit': commit, 'files': {}, 'base': dict(base)}
    for name in sorted(files):
        origin = source / (CATALOG_SOURCE if name == 'catalog.json' else name)
        if not origin.is_file():
            raise ValueError('Missing release file: ' + name)
        target = output / name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(origin, target)
        manifest['files'][name] = sha(target)
    (output / 'manifest.json').write_text(json.dumps(manifest, indent=2, sort_keys=True))
    return sha(output / 'manifest.json')


def verify(bundle, root, expected, files=DEFAULT_FILES):
    if sha(bundle / 'manifest.json') != expected:
        raise ValueError('Manifest checksum differs')
    manifest = json.loads((bundle / 'manifest.json').read_text())
    if set(manifest['files']) != set(files) or set(manifest['base']) != set(files):
        raise ValueError('Unexpected release scope')
    for name in files:
        if sha(bundle / name) != manifest['files'][name] or sha(root / name) != manifest['base'][name]:
            raise ValueError('Uploaded or production file changed: ' + name)
    return manifest


def service(action, names=DEFAULT_SERVICES):
    for name in names:
        subprocess.run(['systemctl', action, name], check=True)


def healthy(url=DEFAULT_HEALTH_URL):
    for attempt in range(15):
        try:
            with urlopen(url, timeout=3) as response:
                if json.load(response).get('ok') is True:
                    return
        except (OSError, ValueError):
            pass
        time.sleep(1)
    raise RuntimeError('Service failed health check')


def publish(bundle, root, databases, expected, dry_run=False, files=DEFAULT_FILES, services=DEFAULT_SERVICES,
            health_url=DEFAULT_HEALTH_URL, backup_prefix='pre-release-'):
    if len({p.name for p in databases}) != len(databases):
        raise ValueError('Database file names must be unique')
    manifest = verify(bundle, root, expected, files)
    before = {str(p): state(p) for p in databases}
    if dry_run:
        return {'baselineMatches': True, 'databases': before, 'dryRun': True}
    backup = databases[0].parent / (backup_prefix + str(time.time_ns()))
    backup.mkdir(mode=0o700)
    installed = []
    service('stop', services)
    try:
        verify(bundle, root, expected, files)
        before = {str(p): state(p) for p in databases}
        for path in databases:
            target = backup / path.name
            with closing(sqlite3.connect(path.as_uri() + '?mode=ro', uri=True)) as source:
                with closing(sqlite3.connect(target)) as destination:
                    source.backup(destination)
            target.chmod(0o600)
            if state(target) != before[str(path)]:
                raise ValueError('Database changed during backup')
        for name in sorted(files):
            target = root / name
            if target.exists():
                saved = backup / name
                saved.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(target, saved)
            target.parent.mkdir(parents=True, exist_ok=True)
            temporary = target.with_suffix(target.suffix + '.release-next')
            shutil.copyfile(bundle / name, temporary)
            temporary.chmod(0o644)
            temporary.replace(target)
            installed.append(name)
        if before != {str(p): state(p) for p in databases}:
            raise ValueError('Shared data changed; never restore old database')
        service('start', services)
        healthy(health_url)
    except BaseException:
        service('stop', services)
        for name in reversed(installed):
            if sha(root / name) != manifest['files'][name]:
                raise RuntimeError('Concurrent source change; stopped without overwriting: ' + name)
            if manifest['base'][name] is None:
                (root / name).unlink()
            else:
                shutil.copy2(backup / name, root / name)
        service('start', services)
        raise
    receipt = {'backup': str(backup), 'commit': manifest['commit'],
               'files': {name: sha(root / name) for name in sorted(files)},
               'sharedDataUnchanged': before == {str(p): state(p) for p in databases}}
    (backup / 'receipt.json').write_text(json.dumps(receipt, indent=2))
    return receipt


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    commands = parser.add_subparsers(dest='command', required=True)
    for name in ('hashes', 'bundle', 'publish'):
        sub = commands.add_parser(name)
        sub.add_argument('--file', action='append', dest='files', help='Release path relative to --root (repeatable; default: server modules + catalog.json)')
        if name != 'bundle':
            sub.add_argument('--root', type=Path, default=DEFAULT_ROOT, help=f'Live install directory (default {DEFAULT_ROOT})')
    sub = commands.choices['bundle']
    sub.add_argument('--source', type=Path, default=Path(__file__).resolve().parents[1], help='Repository checkout to release from')
    sub.add_argument('--base', type=Path, required=True, help='Output of the hashes command on the server')
    sub.add_argument('--output', type=Path, required=True)
    sub.add_argument('--commit', default='', help='Recorded in the manifest and receipt')
    sub = commands.choices['publish']
    sub.add_argument('--bundle', type=Path, required=True)
    sub.add_argument('--expected-manifest', required=True, help='SHA-256 printed by the bundle command')
    sub.add_argument('--db', type=Path, action='append', dest='databases', help='Database to fingerprint and back up (repeatable; default /var/lib/trip-journal/trip.sqlite3)')
    sub.add_argument('--service', action='append', dest='services', help='systemd unit to stop/start (repeatable; default trip-journal)')
    sub.add_argument('--health-url', default=DEFAULT_HEALTH_URL)
    sub.add_argument('--dry-run', action='store_true')
    args = parser.parse_args(argv)
    files = frozenset(args.files) if args.files else DEFAULT_FILES
    if args.command == 'hashes':
        result = hashes(args.root.resolve(), files)
    elif args.command == 'bundle':
        result = {'manifestSHA256': bundle(args.source.resolve(), json.loads(args.base.read_text()), args.output, files, args.commit)}
    else:
        result = publish(args.bundle.resolve(), args.root.resolve(), [p.resolve() for p in (args.databases or DEFAULT_DATABASES)],
                         args.expected_manifest, args.dry_run, files, tuple(args.services or DEFAULT_SERVICES), args.health_url)
    json.dump(result, sys.stdout, indent=2)
    print()


if __name__ == '__main__':
    main()
