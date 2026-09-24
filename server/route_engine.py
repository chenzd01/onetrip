"""Bounded, read-only regional routing. No plan data or coordinates are persisted."""
import json
import math
import os
from pathlib import Path
import subprocess
import threading
import time
from trip_catalog import region_for

DEFAULT_ROUTE_ROOT = '/opt/trip-journal/routes/current'


def route_root():
    return Path(os.environ.get('TRIP_ROUTE_ROOT') or DEFAULT_ROUTE_ROOT)


class RoutingError(Exception):
    def __init__(self, status, message):
        self.status, self.message = status, message
        super().__init__(message)


class RouteEngine:
    def __init__(self, binary=None, config=None, region=None):
        root = route_root()
        self.binary = str(binary or os.environ.get('TRIP_ROUTE_BINARY') or root / 'valhalla/bin/valhalla_service')
        self.config = str(config or os.environ.get('TRIP_ROUTE_CONFIG') or root / 'valhalla.json')
        self.region = region or region_for()
        self.slots = threading.BoundedSemaphore(2)

    def calculate(self, payload):
        if not isinstance(payload, dict) or set(payload) != {'from', 'to', 'mode'} or payload['mode'] not in ('walking', 'driving'):
            raise RoutingError(422, '路线请求无效')
        locations = []
        for key in ('from', 'to'):
            point = payload[key]
            if not isinstance(point, list) or len(point) != 2 or any(type(n) not in (int, float) or not math.isfinite(n) for n in point):
                raise RoutingError(422, '地图坐标无效')
            lat, lon = point
            if not self.region.contains(lat, lon):
                raise RoutingError(422, '目前仅支持旅行目的地范围内的路线')
            # Never silently move a selected place far away to find a route.
            locations.append({'lat': lat, 'lon': lon, 'search_cutoff': 100, 'radius': 25})
        if not Path(self.binary).is_file() or not Path(self.config).is_file():
            raise RoutingError(503, '路线服务正在准备，请稍后刷新')
        if not self.slots.acquire(blocking=False):
            raise RoutingError(429, '路线请求较多，请稍后重试')
        try:
            request = {'locations': locations, 'costing': 'auto' if payload['mode'] == 'driving' else 'pedestrian',
                       'units': 'kilometers', 'directions_options': {'units': 'kilometers'}}
            try:
                result = subprocess.run([self.binary, self.config, 'route', json.dumps(request)],
                                        capture_output=True, text=True, timeout=12, check=False)
            except subprocess.TimeoutExpired:
                raise RoutingError(504, '此段计算超时，请重试') from None
            except OSError:
                raise RoutingError(503, '路线服务暂时不可用') from None
            # The CLI can precede its JSON with diagnostic lines. Never return those logs.
            response = None
            for line in result.stdout.splitlines():
                if line.startswith('{'):
                    try:
                        candidate = json.loads(line)
                        if isinstance(candidate, dict): response = candidate
                    except ValueError:
                        pass
            if result.returncode or not response or 'trip' not in response:
                code = (response or {}).get('error_code')
                if code in (170, 171, 172, 442, 443, 444):
                    raise RoutingError(422, '未找到可通行路线，请核对地点入口或切换交通方式')
                raise RoutingError(503, '暂未算出此段路线，请稍后重试')
            try:
                trip = response['trip']; legs = trip['legs']; summary = trip['summary']
                shape = legs[0]['shape']; distance = float(summary['length']) * 1000; seconds = float(summary['time'])
                if len(legs) != 1 or not isinstance(shape, str) or not 2 <= len(shape) <= 200000:
                    raise ValueError()
                if not math.isfinite(distance) or not math.isfinite(seconds) or distance < 0 or seconds < 0:
                    raise ValueError()
            except (ValueError, KeyError, TypeError, IndexError):
                raise RoutingError(502, '路线结果无效，请重试') from None
            return {'shape': shape, 'precision': 6, 'distance': distance, 'seconds': seconds,
                    'calculatedAt': time.time(), 'source': 'Valhalla / OpenStreetMap'}
        finally:
            self.slots.release()
