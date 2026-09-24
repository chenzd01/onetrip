import json
import tempfile
import unittest
from pathlib import Path
from route_engine import RoutingError
from route_places import RoutePlaces

class RoutePlacesTests(unittest.TestCase):
    def test_search_matches_multilingual_names_addresses_and_limits_results(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'places.json'
            points = [{'name': 'Night Market · 夜市', 'address': '8 Market Lane, Sample Bay', 'aliases': '', 'latitude': 20.004, 'longitude': -150.006}]
            points += [dict(points[0], name='Night Market nearby ' + str(i)) for i in range(25)]
            path.write_text(json.dumps({'places': points}))
            service = RoutePlaces(path)
            self.assertEqual(service.search('夜市')['places'][0]['name'], points[0]['name'])
            self.assertEqual(len(service.search('night market')['places']), 20)
            self.assertEqual(service.search('Night Market')['places'][0]['name'], points[0]['name'])
            self.assertEqual(service.search('market Sample Bay')['places'][0]['address'], points[0]['address'])
            self.assertEqual(service.search('unknown')['places'], [])
            with self.assertRaises(RoutingError): service.search(' ')
            with self.assertRaises(RoutingError): service.search('a' * 161)

    def test_missing_index_is_retryable_without_leaking_paths(self):
        with self.assertRaises(RoutingError) as caught: RoutePlaces('/nonexistent/private-path').search('Sample Bay')
        self.assertEqual(caught.exception.status, 503)
        self.assertNotIn('private-path', caught.exception.message)
