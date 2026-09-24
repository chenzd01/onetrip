import datetime, json, shutil, tempfile, unittest
from pathlib import Path
from build_ios_resources import ROOT, build
import verify_content


class ContentPipelineTests(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.content = self.tmp / 'content'
        shutil.copytree(ROOT / 'content', self.content)

    def tearDown(self):
        shutil.rmtree(self.tmp)

    def edit(self, name, change):
        path = self.content / name
        data = json.loads(path.read_text()); change(data)
        path.write_text(json.dumps(data, ensure_ascii=False))

    def run_build(self):
        return build(self.content, self.tmp / 'out', self.tmp / 'Generated.xcconfig')

    def trip(self):
        return json.loads((self.content / 'trip.json').read_text())

    def test_sample_content_builds_and_verifies(self):
        summary, trip = self.run_build(), self.trip()
        days = (datetime.date.fromisoformat(trip['endDate']) - datetime.date.fromisoformat(trip['startDate'])).days + 1
        self.assertEqual(summary['days'], days)
        catalog = json.loads((self.tmp / 'out/catalog.json').read_text())
        self.assertEqual(catalog['defaults']['id'], catalog['trip']['id'])
        self.assertEqual({p['id'] for p in catalog['catalog']['places'] if p['kind'] == '餐饮'}, {r['id'] for r in catalog['dining']['restaurants']})
        manifest = json.loads((self.tmp / 'out/manifest.json').read_text())
        self.assertTrue(all((self.tmp / 'out' / f['path']).is_file() for f in manifest))
        self.assertIn('APP_DISPLAY_NAME = ' + catalog['trip']['appName'], (self.tmp / 'Generated.xcconfig').read_text())
        report, _ = verify_content.validate(self.content, built=catalog)
        self.assertEqual(report.errors, [])

    def test_itinerary_must_cover_trip_dates(self):
        end = datetime.date.fromisoformat(self.trip()['endDate']) + datetime.timedelta(days=1)
        self.edit('trip.json', lambda t: t.update(endDate=end.isoformat()))
        with self.assertRaises(ValueError): self.run_build()
        report, _ = verify_content.validate(self.content)
        self.assertTrue(any('itinerary.json' in e for e in report.errors))

    def test_coordinates_outside_bounds_are_rejected(self):
        bounds = self.trip()['map']['bounds']
        self.edit('locations.json', lambda l: next(iter(l['locations'].values())).update(coordinates=[bounds['maxLat'] + 1, bounds['maxLon'] + 1]))
        with self.assertRaises(ValueError): self.run_build()

    def test_unknown_place_reference_is_rejected(self):
        self.edit('itinerary.json', lambda i: i['days'][0]['items'][0].update(place='nowhere'))
        with self.assertRaises(ValueError): self.run_build()

    def test_complete_gate_rejects_sample_text(self):
        self.edit('places.json', lambda p: p['places'][0].update(desc='【示例】' + p['places'][0]['desc']))
        report, _ = verify_content.validate(self.content, require_complete=True)
        self.assertTrue(any('placeholder' in e for e in report.errors))

    def test_snapshot_cannot_claim_live_availability(self):
        trip = self.trip()
        observation = {'date': trip['startDate'], 'meal': 'dinner', 'partySize': trip['partySize'], 'status': 'available',
                       'detail': '保证有位', 'checkedAt': trip['startDate'], 'sourceURL': 'https://booking.example.com/'}
        self.edit('dining.json', lambda d: d['restaurants'][0]['booking'].update(availability='available', observations=[observation]))
        report, _ = verify_content.validate(self.content)
        self.assertTrue(any('live' in e for e in report.errors))


if __name__ == '__main__':
    unittest.main()
