# Optional backend: self-hosted shared sync, routes and interaction push

The app is fully usable without a backend. Only the following features need it:

| Feature | Required components |
| --- | --- |
| Two (or more) phones sharing one plan, syncing original ticket files | `server/trip_server.py` + Nginx (HTTPS) |
| Full-day routes (walking / driving routes, place search, English address sharing) | The above + a Valhalla road network and an OSM place index |
| Companion interactions ("poke", heart push notifications) | The above + `server/touch_push.py` + an APNs key |

For endpoints, table schemas and the sync model see [architecture.md](architecture.md); for a quick reference of commands and environment variables see `server/README.md`.

## 1. Run it locally first

```bash
python3 scripts/build_ios_resources.py
python3 server/trip_server.py init --data-dir /tmp/trip-dev
TRIP_NATIVE_KEY_SHA256=$(printf %s tttttttttttttttttttttttttttttttttttttttttttttttt | shasum -a 256 | cut -d' ' -f1) \
  python3 server/trip_server.py serve --data-dir /tmp/trip-dev --port 8765
curl -s http://127.0.0.1:8765/healthz
```

iOS integration tests: set the environment variable `TRIP_INTEGRATION_URL=http://127.0.0.1:8765/` in the Xcode test scheme. When a Debug build detects a URL pointing to the local machine it uses 48 `t` characters as the test key; only `127.0.0.1` / `localhost` are accepted — **never let tests that write data connect to a real service**.

## 2. Prepare the server

A Linux server that can run Python 3.10+ (systemd, Nginx, a domain with an HTTPS certificate already set up). The backend listens only on `127.0.0.1`, behind an Nginx reverse proxy.

```bash
sudo useradd --system --home /var/lib/trip-journal --shell /usr/sbin/nologin trip-journal
sudo install -d -o trip-journal -g trip-journal -m 700 /var/lib/trip-journal
sudo install -d -m 755 /opt/trip-journal
# Upload: the server/ directory, and the locally generated ios/TripJournal/Resources/Content/catalog.json → /opt/trip-journal/catalog.json
```

## 3. Generate the shared key

```bash
key=$(openssl rand -base64 36 | tr '+/' '-_' | tr -d '=')
printf %s "$key" | shasum -a 256     # on Linux use sha256sum
```

- Put `$key` in your local `ios/SharedAccess.xcconfig` (`TRIP_SHARED_ACCESS_KEY`); it ships to your testers inside the app build.
- Put the 64-character hex hash in `TRIP_NATIVE_KEY_SHA256` in `/etc/trip-journal.env` on the server. The server stores only the hash.
- This is an "install-level" key: anyone holding this app build can access the shared plan. Distribute it to your travel companions only through TestFlight.

## 4. Configure and start

1. Copy `deploy/trip-server.env.example` to `/etc/trip-journal.env` (`chmod 600`) and fill in each item:
   - `TRIP_ORIGIN`: the origin of the app's requests, e.g. `https://trip.example.com`;
   - `TRIP_COOKIE_PATH`: a random path, e.g. `/onetrip/<random-string>/`;
   - `TRIP_NATIVE_KEY_SHA256`, `TRIP_CATALOG=/opt/trip-journal/catalog.json`.
2. Initialize the database (uses the default plan from the catalog; refuses to overwrite an existing one):

   ```bash
   sudo -u trip-journal TRIP_CATALOG=/opt/trip-journal/catalog.json \
     python3 /opt/trip-journal/server/trip_server.py init --data-dir /var/lib/trip-journal
   ```

3. Install the systemd units `deploy/trip-journal.service`, `trip-journal-backup.service` and `trip-journal-backup.timer` (daily backup), then run `sudo systemctl enable --now trip-journal.service trip-journal-backup.timer`.
4. Nginx: following `deploy/nginx-location.example.conf`, add a `location ^~ /onetrip/<random-string>/` block inside the HTTPS `server {}` (rate limiting, `client_max_body_size 12m`, `proxy_pass http://127.0.0.1:8765/`), run `nginx -t`, then reload. Back up the original file before editing the Nginx config.
5. App side: in `ios/SharedAccess.xcconfig`

   ```
   TRIP_SERVER_URL = https:/$()/trip.example.com/onetrip/<random-string>/
   TRIP_SHARED_ACCESS_KEY = <$key>
   ```

   (In xcconfig `//` starts a comment, so it has to be written as `https:/$()/`.) Rebuild the app.

**Verify**: `curl https://trip.example.com/onetrip/<random-string>/healthz` returns `{"ok":true}`; edit different stops on the same day on two devices, and each change shows up on the other within a few seconds.

On startup the server checks that the plan ID in the database matches `trip.id` in `catalog.json`; for a new trip, use a new data directory and run `init` again.

## 5. Isolated database for App Review (optional)

When TestFlight external testing requires Apple's review, the reviewer will also open the app. You can give the reviewer a **different** key that points to a separate demo database, so they never see or change your real plan:

```bash
sudo -u trip-journal python3 /opt/trip-journal/server/trip_server.py init --db /var/lib/trip-journal/review.sqlite3
# /etc/trip-journal.env: TRIP_REVIEW_DB=…/review.sqlite3, TRIP_REVIEW_KEY_SHA256=<hash of the review key>
```

The server refuses to start if the two keys have the same hash.

## 6. Full-day routes (optional)

1. Pick regional data: for the road network, use an OSM extract covering the trip area (Geofabrik / BBBike, etc.); for administrative areas and place search, use an extract that includes the **complete national border**.
2. Build the road network with Valhalla (tiles, admins database) and prepare the pyvalhalla 3.8.3 Linux wheel (no Python packages need to be installed on the server).
3. Place index:

   ```bash
   python3 scripts/build_route_places.py region.osm.pbf places-region.json --country <ISO two-letter code> --native-name name:zh
   ```

   Only places inside the `trip.json` bounds and inside that country's border are kept, so identically named places in neighboring countries don't sneak in.
4. Package and install (every file is hashed, installed as an immutable versioned directory, `--activate` switches atomically, and the previous version is kept for rollback):

   ```bash
   python3 deploy/build_route_artifact.py --probe probe --output artifact \
     --routing-pbf-url <extract URL> --bounds <minLat,maxLat,minLon,maxLon> --drive-on-left|--drive-on-right --snapshot-date <date>
   python3 deploy/install_route_artifact.py …   # see --help
   ```

5. Default route directory: `/opt/trip-journal/routes/current` (`TRIP_ROUTE_ROOT`).
6. English address sharing (`TRIP_ROUTE_ENGLISH_ADDRESS_SHARING`): set it to `1` only after every phone has an app version that supports it; otherwise older versions will refuse to sync because they don't recognize the new field.

Measured reference: a route usually takes well under a second, with memory in the low hundreds of MiB. Segments that cannot be computed are honestly labeled "partially computed"; no fake straight lines are drawn.

## 7. Companion interaction push (optional)

1. Apple Developer → Keys: create an APNs authentication key and download the `.p8` (it can only be downloaded once). Put it on the server, readable only by the `trip-journal` user. **Never commit it to the repository.**
2. Enable Push Notifications on the App ID; `project.yml` already sets `aps-environment` per Debug / Release.
3. Dependencies for the push process:

   ```bash
   python3 -m venv /opt/trip-journal/.venv-touch
   /opt/trip-journal/.venv-touch/bin/pip install -r /opt/trip-journal/server/requirements-touch.txt
   ```

4. Copy `deploy/trip-touch.env.example` to `/etc/trip-journal-touch.env` (Team ID, key ID, `.p8` path, `TOUCH_APNS_TOPIC` = the app's Bundle ID) and enable `deploy/trip-journal-touch-push.service`.
5. Pairing requires an invite code: the first device generates it, the second enters and confirms it. This keeps an external-testing review device from taking a pairing slot (a pitfall we actually hit). To reset: `trip_server.py reset-touch` (clears pairing only, leaves the plan untouched).

"Accepted by APNs" only means Apple received the request, not that the other phone actually rang; the app's diagnostics screen shows the status of each event.

## 8. Publishing updates (code only, never data)

`deploy/publish.py` provides an auditable release flow:

```bash
# Server: record hashes of the files currently live
python3 deploy/publish.py hashes --root /opt/trip-journal > base.json
# Local: bundle from the allowlist, generate a manifest, note its SHA-256
python3 deploy/publish.py bundle --source . --base base.json --output release/
# Upload release/ to the server, dry-run first, then run for real
python3 deploy/publish.py publish --bundle release --expected-manifest <sha256> --dry-run
python3 deploy/publish.py publish --bundle release --expected-manifest <sha256>
```

`publish` will: verify the uploaded files against the manifest, verify that the live files are still the baseline captured at bundle time (so parallel releases can't overwrite each other), back up every database and compare fingerprints, stop the service, atomically replace files, restart, and poll `/healthz`. On failure it **rolls back only the code replaced in this release and never rolls back the database**; if it finds a file someone else has changed, it stops and reports instead of overwriting.

## 9. After the trip

1. `systemctl stop` and `disable` the three units; run a WAL checkpoint and an integrity check on the database.
2. Archive `/var/lib/trip-journal`, `/opt/trip-journal` (the road network can be left out), `/etc/trip-journal*.env`, the `.p8`, the systemd units and the Nginx snippet; download them to your machine and verify the SHA-256.
3. Remove the `location` block from Nginx (back it up first), run `nginx -t`, reload, and confirm the public path now returns 404.
4. Revoke the APNs key in Apple Developer.
5. Whether to keep or delete the data on the server is up to you; the backup contains keys, so store it only somewhere private.
