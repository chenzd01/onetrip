import json
from pathlib import Path
import sqlite3
import tempfile
import unittest
from unittest.mock import patch
import publish as release


class PublishTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)/'live'
        self.source = Path(self.tmp.name)/'source'
        self.bundle = Path(self.tmp.name)/'bundle'
        self.db = Path(self.tmp.name)/'trip.sqlite3'
        with sqlite3.connect(self.db) as db:
            for table in ('trip', 'revisions', 'attachments', 'sessions'):
                db.execute('CREATE TABLE '+table+'(id INTEGER, value TEXT)')
                db.execute('INSERT INTO '+table+' VALUES(1,?)', ('keep '+table,))
        for name in release.DEFAULT_FILES:
            origin = self.source/(release.CATALOG_SOURCE if name == 'catalog.json' else name)
            origin.parent.mkdir(parents=True, exist_ok=True)
            origin.write_text('new '+name)
        live = self.root/'server/trip_server.py'
        live.parent.mkdir(parents=True, exist_ok=True)
        live.write_text('old server')
        self.expected = release.bundle(self.source, release.hashes(self.root), self.bundle, commit='a'*40)

    def test_bundle_records_base_and_copies_catalog(self):
        manifest = json.loads((self.bundle/'manifest.json').read_text())
        self.assertEqual(set(manifest['files']), set(release.DEFAULT_FILES))
        self.assertIsNone(manifest['base']['server/touch_service.py'])
        self.assertEqual((self.bundle/'catalog.json').read_text(), 'new catalog.json')
        with self.assertRaises(ValueError):
            release.bundle(self.source, {}, Path(self.tmp.name)/'other')

    def test_publish_preserves_data_and_keeps_backup(self):
        before = release.state(self.db)
        self.assertEqual(set(before), {'trip', 'revisions', 'attachments'})
        with patch.object(release, 'service') as service, patch.object(release, 'healthy') as healthy:
            result = release.publish(self.bundle, self.root, [self.db], self.expected,
                                     services=('trip-journal', 'trip-journal-touch-push'), health_url='http://127.0.0.1:1/healthz')
        service.assert_any_call('stop', ('trip-journal', 'trip-journal-touch-push'))
        healthy.assert_called_once_with('http://127.0.0.1:1/healthz')
        self.assertTrue(result['sharedDataUnchanged'])
        self.assertEqual(result['commit'], 'a'*40)
        self.assertEqual(before, release.state(self.db))
        self.assertEqual(before, release.state(Path(result['backup'])/'trip.sqlite3'))
        self.assertTrue(all(release.sha(self.root/n) == release.sha(self.bundle/n) for n in release.DEFAULT_FILES))

    def test_dry_run_and_custom_scope(self):
        with patch.object(release, 'service') as service:
            self.assertTrue(release.publish(self.bundle, self.root, [self.db], self.expected, dry_run=True)['dryRun'])
            with self.assertRaises(ValueError):
                release.publish(self.bundle, self.root, [self.db], self.expected, files=frozenset({'server/trip_server.py'}))
        service.assert_not_called()

    def test_drift_stops_before_stopping_service(self):
        (self.root/'server/trip_server.py').write_text('concurrent release')
        with patch.object(release, 'service') as service, self.assertRaises(ValueError):
            release.publish(self.bundle, self.root, [self.db], self.expected)
        service.assert_not_called()

    def test_health_failure_restores_only_code(self):
        before = release.state(self.db)
        with patch.object(release, 'service'), patch.object(release, 'healthy', side_effect=RuntimeError('failed')):
            with self.assertRaises(RuntimeError):
                release.publish(self.bundle, self.root, [self.db], self.expected)
        self.assertEqual((self.root/'server/trip_server.py').read_text(), 'old server')
        self.assertEqual(before, release.state(self.db))
        self.assertFalse((self.root/'server/touch_service.py').exists())
        self.assertFalse((self.root/'catalog.json').exists())
