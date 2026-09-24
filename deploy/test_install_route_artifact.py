import json
from pathlib import Path
import tempfile
import unittest
from install_route_artifact import sha, stage


class RouteArtifactTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.bundle = self.root / 'bundle'; self.bundle.mkdir()
        for name in ['valhalla/bin/valhalla_service', 'valhalla.template.json', 'places.json', 'admins.sqlite', 'sources.json', 'tiles/0.gph']:
            p = self.bundle / name; p.parent.mkdir(parents=True, exist_ok=True)
            p.write_text(json.dumps({'mjolnir': {}}) if name.endswith('template.json') else 'fixture')
        self.manifest = {str(p.relative_to(self.bundle)): sha(p) for p in self.bundle.rglob('*') if p.is_file()}
        self.save_manifest()

    def tearDown(self): self.tmp.cleanup()
    def save_manifest(self):
        (self.bundle / 'manifest.json').write_text(json.dumps(self.manifest))
        self.expected = sha(self.bundle / 'manifest.json')

    def test_staging_is_inactive_until_explicit_atomic_activation(self):
        result = stage(self.bundle, self.root / 'routes', self.expected)
        self.assertFalse((self.root / 'routes/current').exists())
        path = Path(result['release'])
        self.assertEqual(json.loads((path / 'valhalla.json').read_text())['mjolnir']['tile_dir'], str(path / 'tiles'))
        stage(self.bundle, self.root / 'routes', self.expected, True)
        self.assertEqual((self.root / 'routes/current').resolve(), path.resolve())
        (path / 'places.json').write_text('changed')
        with self.assertRaises(ValueError): stage(self.bundle, self.root / 'routes', self.expected, True)

    def test_tampering_and_path_escape_fail_before_activation(self):
        (self.bundle / 'places.json').write_text('changed')
        with self.assertRaises(ValueError): stage(self.bundle, self.root / 'routes', self.expected, True)
        self.assertFalse((self.root / 'routes/current').exists())
        self.manifest['../outside'] = 'ignored'; self.save_manifest()
        with self.assertRaises(ValueError): stage(self.bundle, self.root / 'routes', self.expected)
