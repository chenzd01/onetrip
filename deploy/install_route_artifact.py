"""Verify and stage an immutable routing artifact, then optionally switch its pointer.

Never starts a public service, changes trip data, or downloads code. Run smoke tests
on the staged config before --activate; activation requires the release lease.
"""
import argparse
import hashlib
import json
from pathlib import Path
import shutil


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def stage(bundle, root, expected, activate=False):
    manifest_path = bundle / 'manifest.json'
    if sha(manifest_path) != expected: raise ValueError('Manifest checksum differs')
    manifest = json.loads(manifest_path.read_text())
    required = {'valhalla/bin/valhalla_service', 'valhalla.template.json', 'places.json', 'admins.sqlite', 'sources.json'}
    if not required <= set(manifest): raise ValueError('Missing artifact contents')
    for name, digest in manifest.items():
        relative = Path(name)
        if relative.is_absolute() or '..' in relative.parts or (bundle / relative).is_symlink(): raise ValueError('Unsafe artifact path')
        if sha(bundle / relative) != digest: raise ValueError('Artifact content changed: ' + name)
    target = root / 'releases' / expected[:16]
    if not target.exists():
        target.mkdir(parents=True)
        for name in manifest:
            destination = target / name
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(bundle / name, destination)
            destination.chmod(0o755 if name == 'valhalla/bin/valhalla_service' else 0o644)
        shutil.copyfile(manifest_path, target / 'manifest.json')
    # Reruns must verify installed bytes too, including libraries and graph tiles.
    for name, digest in manifest.items():
        if (target / name).is_symlink() or sha(target / name) != digest: raise ValueError('Staged artifact changed: ' + name)
    config = json.loads((target / 'valhalla.template.json').read_text())
    config['mjolnir'].update(tile_dir=str(target / 'tiles'), tile_extract='', admin=str(target / 'admins.sqlite'), timezone='')
    (target / 'valhalla.json').write_text(json.dumps(config))
    previous = None
    current = root / 'current'
    if current.is_symlink(): previous = str(current.readlink())
    elif current.exists(): raise ValueError('Current routing path must be a symlink')
    if activate:
        temporary = root / 'current.next'
        if temporary.exists() or temporary.is_symlink(): raise ValueError('Another activation may be running')
        temporary.symlink_to(target)
        temporary.replace(current)
    return {'release': str(target), 'manifestSHA256': expected, 'activated': activate, 'previous': previous}


DEFAULT_ROOT = Path('/opt/trip-journal/routes')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--bundle', type=Path, required=True, help='Artifact directory from build_route_artifact.py')
    parser.add_argument('--root', type=Path, default=DEFAULT_ROOT,
                        help=f'Routing root (default {DEFAULT_ROOT}); releases go to <root>/releases and the server reads '
                             '<root>/current, so set TRIP_ROUTE_ROOT=<root>/current if you change it')
    parser.add_argument('--expected-manifest', required=True, help='SHA-256 printed by build_route_artifact.py')
    parser.add_argument('--activate', action='store_true', help='Atomically point <root>/current at the staged release')
    args = parser.parse_args()
    print(json.dumps(stage(args.bundle.resolve(), args.root.resolve(), args.expected_manifest, args.activate)))
