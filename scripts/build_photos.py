#!/usr/bin/env python3
"""Download and optimize openly licensed place photos listed in content/photo-sources.json.

For each photo entry that has a "downloadUrl", fetch the original into a local cache
(never committed), then write an optimized JPEG to the entry's "file" path:
EXIF orientation applied, metadata stripped, longest side <= 1200 px, <= 180 KB.
Duplicate images across the library are rejected by SHA-256. Requires Pillow.
Usage: python3 scripts/build_photos.py [--download-missing] [--cache .photo-cache]
"""
import argparse, hashlib, io, json, time, urllib.request
from pathlib import Path
from PIL import Image, ImageOps

ROOT = Path(__file__).resolve().parents[1]


def jpeg(image, limit=1200, quality=78, budget=180_000):
    image = ImageOps.exif_transpose(image).convert('RGB')
    image.thumbnail((limit, limit), Image.Resampling.LANCZOS)
    while True:
        output = io.BytesIO()
        image.save(output, 'JPEG', quality=quality, optimize=True, progressive=True)
        data = output.getvalue()
        if len(data) <= budget: return data
        if quality > 62: quality -= 4
        else: image.thumbnail((int(image.width * .9), int(image.height * .9)), Image.Resampling.LANCZOS)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--content', type=Path, default=ROOT / 'content')
    parser.add_argument('--cache', type=Path, default=ROOT / '.photo-cache')
    parser.add_argument('--download-missing', action='store_true')
    parser.add_argument('--user-agent', default='TripJournalPhotoImport/1.0 (personal travel app)')
    args = parser.parse_args()
    args.cache.mkdir(parents=True, exist_ok=True)
    albums = json.loads((args.content / 'photo-sources.json').read_text())['albums']
    hashes, written = set(), 0
    for place_id, album in albums.items():
        for index, photo in enumerate(album['photos']):
            if not photo.get('downloadUrl'): continue
            cached = args.cache / f'{place_id}-{index}{Path(photo["downloadUrl"]).suffix or ".jpg"}'
            if not cached.exists():
                if not args.download_missing: raise SystemExit(f'missing {cached}; rerun with --download-missing')
                time.sleep(2)  # be polite to image hosts
                request = urllib.request.Request(photo['downloadUrl'], headers={'User-Agent': args.user_agent})
                cached.write_bytes(urllib.request.urlopen(request, timeout=45).read())
            with Image.open(cached) as image:
                data = jpeg(image)
            digest = hashlib.sha256(data).hexdigest()
            if digest in hashes: raise SystemExit(f'duplicate photo: {place_id} #{index}')
            hashes.add(digest)
            target = args.content / photo['file']
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(data); written += 1
    print(f'wrote {written} optimized photos')


if __name__ == '__main__':
    main()
