import copy
import os
import tempfile
import unittest
from unittest.mock import patch
from route_preferences import RoutePreferencesService, validate_preferences
from trip_catalog import Region


class EnglishAddressTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.service = RoutePreferencesService(self.tmp.name + '/routes.db')
        self.address = {'kind': 'englishAddress', 'title': '酒店 · 英文地址', 'englishAddress': {'name': 'Hotel A', 'address': '1 Test Road, Unit 5, Sample Bay 10001'}}
        self.state = {'tripID': 'trip', 'values': {'address:test': self.address}}

    def test_two_phase_gate_preserves_legacy_snapshot_shape(self):
        with patch.dict(os.environ, {'TRIP_ROUTE_ENGLISH_ADDRESS_SHARING': '0'}):
            self.assertFalse(self.service.english_address_sharing)
            self.assertEqual(set(self.service.snapshot('trip')), {'revision', 'state', 'updatedAt'})
            with self.assertRaises(ValueError): self.service.update(0, self.state, 'trip')
            self.assertEqual(self.service.snapshot('trip')['revision'], 0)
        with patch.dict(os.environ, {'TRIP_ROUTE_ENGLISH_ADDRESS_SHARING': '1'}):
            self.assertTrue(self.service.update(0, self.state, 'trip')[0])
            self.assertEqual(self.service.snapshot('trip')['state'], self.state)
        with patch.dict(os.environ, {'TRIP_ROUTE_ENGLISH_ADDRESS_SHARING': '0'}):
            # Disabling the gate still permits unrelated route edits and preserves saved addresses.
            state = copy.deepcopy(self.state)
            state['values']['mode:x'] = {'kind': 'mode', 'title': 'A → B', 'value': 'walking'}
            self.assertTrue(self.service.update(1, state, 'trip')[0])
            with self.assertRaises(ValueError): self.service.update(2, {'tripID': 'trip', 'values': {}}, 'trip')

    def test_schema_rejects_chinese_missing_and_coordinate_fields(self):
        region = Region(19.94, 20.06, -150.08, -149.92, ('Sample Bay', 'XS'), r'\d{5}')
        validate_preferences(self.state, 'trip', region)
        for value in ['', 'Sample Bay', 'Sample Bay 10001', 'sample bay, XS 10001', '中文地址', 'https://example.com', '20.0, -150.0']:
            state = copy.deepcopy(self.state); state['values']['address:test']['englishAddress']['address'] = value
            with self.subTest(value=value), self.assertRaises(ValueError): validate_preferences(state, 'trip', region)
        # Without destination words only a blank address is generic.
        state = copy.deepcopy(self.state); state['values']['address:test']['englishAddress']['address'] = 'Sample Bay'
        validate_preferences(state, 'trip')
        location = {'kind': 'location', 'title': 'x', 'location': {'name': 'x', 'address': '', 'latitude': 20.0, 'longitude': -150.0}}
        validate_preferences({'tripID': 'trip', 'values': {'x': location}}, 'trip', region)
        location['location']['latitude'] = 31.2
        with self.assertRaises(ValueError): validate_preferences({'tripID': 'trip', 'values': {'x': location}}, 'trip', region)
        state = copy.deepcopy(self.state); state['values']['address:test']['location'] = {}
        with self.assertRaises(ValueError): validate_preferences(state, 'trip')

    def test_conflict_does_not_overwrite_other_phone(self):
        with patch.dict(os.environ, {'TRIP_ROUTE_ENGLISH_ADDRESS_SHARING': '1'}):
            self.assertTrue(self.service.update(0, self.state, 'trip')[0])
            state = copy.deepcopy(self.state); state['values']['address:test']['englishAddress']['name'] = 'Hotel B'
            ok, latest = self.service.update(0, state, 'trip')
            self.assertFalse(ok); self.assertEqual(latest['state'], self.state)
