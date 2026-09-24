"""Package a verified regional graph and pinned Linux runtime for read-only installation.

The probe directory is prepared beforehand (on any machine) and must contain:
  linux.whl               pyvalhalla 3.8.3 manylinux wheel (checked against RUNTIME_SHA)
  tiles-final/            Valhalla graph tiles built from the routing PBF
  admins-region.sqlite    Valhalla admin database built from the admin PBF
  valhalla-region.json    the Valhalla config used for the build
  places-region.json      {"places": [{name, address, aliases, latitude, longitude}, ...]}
                          (see scripts/build_route_places.py)
  <routing PBF>, <admin PBF>  the exact extracts downloaded from --routing-pbf-url / --admin-pbf-url

Example:
  python3 deploy/build_route_artifact.py --probe probe --output artifact \\
    --routing-pbf-url https://download.geofabrik.de/<continent>/<region>-latest.osm.pbf \\
    --bounds 19.94,20.06,-150.08,-149.92 --drive-on-right --snapshot-date 2030-04-01
"""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import zipfile

RUNTIME_SHA = '7dd3277502451df842f7e13f123b607e9a8380352e80c0cdff2bc4411b5c9fea'


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def parse_bounds(value):
    try:
        min_lat, max_lat, min_lon, max_lon = (float(v) for v in value.split(','))
    except ValueError:
        raise argparse.ArgumentTypeError('expected minLat,maxLat,minLon,maxLon') from None
    if not (-90 <= min_lat < max_lat <= 90 and -180 <= min_lon < max_lon <= 180):
        raise argparse.ArgumentTypeError('bounds out of range or inverted')
    return {'minLat': min_lat, 'maxLat': max_lat, 'minLon': min_lon, 'maxLon': max_lon}


def build(probe, output, *, routing_url, bounds, drive_on_right, snapshot_date,
          admin_url=None, routing_pbf='routing.osm.pbf', admin_pbf='region.osm.pbf'):
    if output.exists(): raise ValueError('Use a fresh artifact directory')
    wheel = probe / 'linux.whl'
    if sha(wheel) != RUNTIME_SHA: raise ValueError('Unverified Linux Valhalla 3.8.3 wheel')
    places = probe / 'places-region.json'
    points = json.loads(places.read_text())['places']
    if not points: raise ValueError('Missing places for the region')
    outside = [p['name'] for p in points if not (bounds['minLat'] <= p['latitude'] <= bounds['maxLat'] and bounds['minLon'] <= p['longitude'] <= bounds['maxLon'])]
    if outside: raise ValueError(f'{len(outside)} places lie outside --bounds, e.g. {outside[0]}')
    output.mkdir(parents=True)
    with zipfile.ZipFile(wheel) as archive:
        for name in archive.namelist():
            if name == 'valhalla/bin/valhalla_service' or name.startswith(('pyvalhalla.libs/', 'pyvalhalla-3.8.3.dist-info/')):
                if '..' in Path(name).parts or Path(name).is_absolute(): raise ValueError('Unsafe wheel member')
                archive.extract(name, output)
    (output / 'valhalla/bin/valhalla_service').chmod(0o755)
    shutil.copytree(probe / 'tiles-final', output / 'tiles')
    shutil.copyfile(probe / 'admins-region.sqlite', output / 'admins.sqlite')
    shutil.copyfile(places, output / 'places.json')
    config = json.loads((probe / 'valhalla-region.json').read_text())
    # Relative graph paths are resolved by the installer before any activation.
    config['mjolnir'].update(tile_dir='tiles', tile_extract='', admin='admins.sqlite', timezone='')
    config['mjolnir']['logging'] = {'type': 'std_out', 'color': False}
    for costing in ('auto', 'pedestrian'):
        config['service_limits'][costing].update(max_locations=2, max_distance=150000)
    (output / 'valhalla.template.json').write_text(json.dumps(config, indent=2))
    sources = {'engine': 'Valhalla 3.8.3 (MIT)', 'runtimeSHA256': RUNTIME_SHA,
               'routingPBF': {'url': routing_url, 'sha256': sha(probe / routing_pbf)},
               'adminAndSearchPBF': {'url': admin_url or routing_url, 'sha256': sha(probe / (admin_pbf if admin_url else routing_pbf))},
               'bounds': bounds, 'driveOnRight': drive_on_right,
               'attribution': '© OpenStreetMap contributors', 'license': 'ODbL 1.0',
               'copyrightURL': 'https://www.openstreetmap.org/copyright', 'snapshotDate': snapshot_date,
               'buildDependencies': {'pyvalhalla': '3.8.3', 'osmium': '4.3.1', 'shapely': '2.1.2'}}
    (output / 'sources.json').write_text(json.dumps(sources, indent=2))
    manifest = {str(p.relative_to(output)): sha(p) for p in sorted(output.rglob('*')) if p.is_file()}
    (output / 'manifest.json').write_text(json.dumps(manifest, indent=2))
    print('Artifact manifest SHA256:', sha(output / 'manifest.json'))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--probe', type=Path, required=True, help='Prepared build directory (see above)')
    parser.add_argument('--output', type=Path, required=True, help='Fresh artifact directory to create')
    parser.add_argument('--routing-pbf-url', required=True, help='Source URL of the OSM extract the graph tiles were built from')
    parser.add_argument('--routing-pbf', default='routing.osm.pbf', help='File name of that extract inside --probe')
    parser.add_argument('--admin-pbf-url', help='Source URL of a separate (usually larger) extract used for admin areas and place search; defaults to the routing extract')
    parser.add_argument('--admin-pbf', default='region.osm.pbf', help='File name of that extract inside --probe')
    parser.add_argument('--bounds', type=parse_bounds, required=True, help='minLat,maxLat,minLon,maxLon; use the same values as content/trip.json map.bounds')
    side = parser.add_mutually_exclusive_group(required=True)
    side.add_argument('--drive-on-right', dest='drive_on_right', action='store_true', help='Traffic drives on the right (recorded in sources.json)')
    side.add_argument('--drive-on-left', dest='drive_on_right', action='store_false', help='Traffic drives on the left (recorded in sources.json)')
    parser.add_argument('--snapshot-date', required=True, help='Date of the OSM snapshot, YYYY-MM-DD')
    args = parser.parse_args()
    build(args.probe, args.output, routing_url=args.routing_pbf_url, bounds=args.bounds, drive_on_right=args.drive_on_right,
          snapshot_date=args.snapshot_date, admin_url=args.admin_pbf_url, routing_pbf=args.routing_pbf, admin_pbf=args.admin_pbf)
