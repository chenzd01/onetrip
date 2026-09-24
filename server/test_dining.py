import copy
import tempfile
import unittest
from pathlib import Path

from dining_content import merge_dining_places
from trip_server import Store, initialize, validate_plan
import trip_fixture


class DiningTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.db = Path(self.tmp.name) / 'trip.sqlite3'
        self.catalog = trip_fixture.catalog(self.tmp.name)
        initialize(self.db, self.catalog)
        self.store = Store(self.db)
        self.plan = self.store.snapshot()['state']
        self.plan_id = self.plan['id']
        self.catalog['places'].append({**self.catalog['places'][0], 'id': 'dining-test-venue', 'kind': '餐饮'})
        self.plan['days'][0]['items'][0]['place'] = 'dining-test-venue'

    def validate(self, state):
        validate_plan(state, self.catalog, self.plan_id)

    def meal(self):
        return {'kind': 'dinner', 'reservation': {
            'status': 'booked', 'date': '2030-05-02', 'time': '19:00',
            'partySize': 2, 'reference': 'our-confirmation', 'notes': 'Window table requested',
        }}

    def test_old_save_preserves_meal_across_day_move_and_explicit_clear(self):
        original = copy.deepcopy(self.plan)
        item = self.plan['days'][0]['items'][0]
        item['meal'] = self.meal()
        self.store.update(0, self.plan, 'new-app', self.validate)
        legacy = copy.deepcopy(self.plan)
        moved = legacy['days'][0]['items'].pop(0)
        del moved['meal']
        moved['time'] = '18:30'
        legacy['days'][1]['items'].append(moved)
        self.store.update(1, legacy, 'old-browser', self.validate)
        result = self.store.snapshot()['state']
        self.assertEqual(result['days'][1]['items'][-1]['meal'], self.meal())
        self.assertEqual(result['budget'], original['budget'])
        self.assertEqual(result['checks'], original['checks'])
        self.assertEqual(result['days'][0]['note'], original['days'][0]['note'])
        # Clearing a reservation is an explicit known state, never an omitted object.
        cleared = result['days'][1]['items'][-1]['meal']['reservation']
        cleared.update(status='planned', date='', time='', reference='', notes='')
        self.store.update(2, result, 'new-app', self.validate)
        result = self.store.snapshot()['state']
        self.assertEqual(result['days'][1]['items'][-1]['meal']['reservation']['reference'], '')
        result['days'][1]['items'].pop()
        self.store.update(3, result, 'old-browser', self.validate)
        self.assertFalse(any(i['uid'] == item['uid'] for d in self.store.snapshot()['state']['days'] for i in d['items']))

    def test_old_save_cannot_transfer_omitted_reservation_to_another_venue(self):
        self.plan['days'][0]['items'][0]['meal'] = self.meal()
        self.store.update(0, self.plan, 'new-app', self.validate)
        before = self.store.snapshot()
        self.catalog['places'].append({**self.catalog['places'][0], 'id': 'another-dining-venue', 'kind': '餐饮'})
        for destination in ('another-dining-venue', 'harbor-light'):
            with self.subTest(destination=destination):
                legacy = copy.deepcopy(self.plan)
                item = legacy['days'][0]['items'][0]
                item['place'] = destination
                del item['meal']
                with self.assertRaisesRegex(ValueError, '更换餐饮地点'):
                    self.store.update(1, legacy, 'old-browser', self.validate)
                self.assertEqual(self.store.snapshot(), before)
                with self.store.connect() as db:
                    self.assertEqual(db.execute('SELECT MAX(revision) FROM revisions').fetchone()[0], 1)

        # A current client can explicitly replace the old restaurant's booking record.
        updated = copy.deepcopy(self.plan)
        item = updated['days'][0]['items'][0]
        item['place'] = 'another-dining-venue'
        item['meal']['reservation'].update(status='planned', date='', time='', reference='', notes='')
        self.store.update(1, updated, 'new-app', self.validate)
        self.assertEqual(self.store.snapshot()['state'], updated)

    def test_invalid_meal_write_is_atomic_and_legacy_omission_validates_after_preserve(self):
        self.plan['days'][0]['items'][0]['meal'] = self.meal()
        self.store.update(0, self.plan, 'new-app', self.validate)
        before = self.store.snapshot()
        mutations = [
            lambda m: m.update(kind='brunch'),
            lambda m: m.update(reservation=None),
            lambda m: m['reservation'].update(status='available'),
            lambda m: m['reservation'].update(partySize=True),
            lambda m: m['reservation'].update(partySize=0),
            lambda m: m['reservation'].update(partySize=21),
            lambda m: m['reservation'].update(date='2030-05-30'),
            lambda m: m['reservation'].update(date='2030-04-30'),
            lambda m: m['reservation'].update(time='24:00'),
            lambda m: m['reservation'].update(time=''),
            lambda m: m['reservation'].update(date=''),
            lambda m: m['reservation'].update(reference='x' * 501),
            lambda m: m['reservation'].update(notes='x' * 3001),
        ]
        for mutation in mutations:
            with self.subTest(mutation=mutation):
                state = copy.deepcopy(self.plan)
                mutation(state['days'][0]['items'][0]['meal'])
                with self.assertRaises(ValueError):
                    self.store.update(1, state, 'bad-client', self.validate)
                self.assertEqual(self.store.snapshot(), before)
        state = copy.deepcopy(self.plan)
        state['days'][0]['items'][0]['place'] = 'harbor-light'
        with self.assertRaises(ValueError):
            self.store.update(1, state, 'bad-client', self.validate)
        state = copy.deepcopy(self.plan)
        state['days'][0]['items'][0]['meal'] = None
        with self.assertRaises(ValueError):
            self.store.update(1, state, 'bad-client', self.validate)
        legacy = copy.deepcopy(self.plan)
        del legacy['days'][0]['items'][0]['meal']
        def requires_preserved(state):
            self.assertEqual(state['days'][0]['items'][0]['meal'], self.meal())
            self.validate(state)
        self.store.update(1, legacy, 'old-browser', requires_preserved)
        self.assertIsNone(self.store.update(1, self.plan, 'stale-client', self.validate))
        self.assertEqual(self.store.snapshot()['revision'], 2)

    def test_catalog_projection_preserves_existing_stop_ids_and_defaults(self):
        restaurant = {
            'id': 'harbor-noodles', 'name': '码头面馆', 'en': 'Harbor Noodles', 'zone': '北岸',
            'type': 'stall', 'description': 'Try nearby stalls', 'tips': [],
            'address': '12 Pier Road, Sample Bay 10001', 'cuisines': ['小吃'], 'hours': '各摊不同',
            'booking': {'url': ''}, 'sources': [{'url': 'https://example.com'}],
        }
        merged = merge_dining_places(self.catalog, {'restaurants': [restaurant, {**restaurant, 'id': 'new-restaurant', 'type': 'restaurant'}]})
        self.assertEqual(merged['days'], self.catalog['days'])
        self.assertEqual(len([p for p in merged['places'] if p['id'] == 'harbor-noodles']), 1)
        self.assertEqual(next(p for p in merged['places'] if p['id'] == 'harbor-noodles')['budget'], 0)
        self.assertEqual([p['id'] for p in merged['places']][:3], [p['id'] for p in self.catalog['places']][:3])
        self.assertEqual(next(p for p in merged['places'] if p['id'] == 'new-restaurant')['hours'], 2)


if __name__ == '__main__':
    unittest.main()
