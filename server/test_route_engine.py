import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch
from route_engine import RouteEngine, RoutingError
from trip_catalog import Region
import trip_fixture


class RouteEngineTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.path = Path(self.tmp.name) / 'engine'
        self.path.touch()
        b = trip_fixture.BOUNDS
        self.engine = RouteEngine(self.path, self.path, Region(b['minLat'], b['maxLat'], b['minLon'], b['maxLon']))
        self.payload = {'from': trip_fixture.INSIDE, 'to': trip_fixture.INSIDE_OTHER, 'mode': 'walking'}

    def tearDown(self):
        self.tmp.cleanup()

    def test_actual_geometry_is_preserved_and_request_is_bounded(self):
        output = {'trip': {'legs': [{'shape': 'abcDEF'}], 'summary': {'length': 1.23, 'time': 912.4}}}
        with patch('route_engine.subprocess.run', return_value=subprocess.CompletedProcess([], 0, 'log\n' + json.dumps(output), '')) as run:
            answer = self.engine.calculate(self.payload)
        self.assertEqual(answer['shape'], 'abcDEF')
        self.assertEqual(answer['distance'], 1230)
        self.assertEqual(answer['precision'], 6)
        self.assertEqual(run.call_args.kwargs['timeout'], 12)
        sent = json.loads(run.call_args.args[0][-1])
        self.assertEqual(sent['costing'], 'pedestrian')
        self.assertEqual(sent['locations'][0]['search_cutoff'], 100)

    def test_invalid_points_modes_and_extra_fields_never_launch_engine(self):
        with patch('route_engine.subprocess.run') as run:
            for changes in ({'from': [True, -150.0]}, {'to': [float('nan'), -150.0]}, {'from': [31, 121]}, {'to': [20.0, -149.5]},
                            {'mode': 'transit'}, {'extra': 'argument'}, {'to': '1,2'}):
                with self.assertRaises(RoutingError) as caught:
                    self.engine.calculate(dict(self.payload, **changes))
                self.assertEqual(caught.exception.status, 422)
            run.assert_not_called()

    def test_capacity_is_shared_and_released_after_timeout(self):
        self.engine.slots.acquire(); self.engine.slots.acquire()
        with self.assertRaises(RoutingError) as caught: self.engine.calculate(self.payload)
        self.assertEqual(caught.exception.status, 429)
        self.engine.slots.release(); self.engine.slots.release()
        with patch('route_engine.subprocess.run', side_effect=subprocess.TimeoutExpired('engine', 12)):
            with self.assertRaises(RoutingError) as caught: self.engine.calculate(self.payload)
        self.assertEqual(caught.exception.status, 504)
        self.assertTrue(self.engine.slots.acquire(blocking=False))
        self.assertTrue(self.engine.slots.acquire(blocking=False))

    def test_no_path_is_not_zero_or_fabricated_geometry(self):
        with patch('route_engine.subprocess.run', return_value=subprocess.CompletedProcess([], 1, '{"error_code":442,"error":"internal"}', 'private log')):
            with self.assertRaises(RoutingError) as caught: self.engine.calculate(self.payload)
        self.assertEqual(caught.exception.status, 422)
        self.assertNotIn('internal', caught.exception.message)

    def test_missing_installation_does_not_affect_trip_service(self):
        self.path.unlink()
        with self.assertRaises(RoutingError) as caught: self.engine.calculate(self.payload)
        self.assertEqual(caught.exception.status, 503)

    def test_malformed_result_is_not_published(self):
        for summary in ({'length': float('nan'), 'time': 1}, {'length': 1, 'time': -1}):
            result = {'trip': {'legs': [{'shape': 'ab'}], 'summary': summary}}
            with patch('route_engine.subprocess.run', return_value=subprocess.CompletedProcess([], 0, json.dumps(result), '')):
                with self.assertRaises(RoutingError) as caught: self.engine.calculate(self.payload)
            self.assertEqual(caught.exception.status, 502)
