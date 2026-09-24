# Optional sync server

A small JSON API that lets two phones share one trip plan. Python 3.10+ standard library and
SQLite only; the APNs worker (`touch_push.py`) additionally needs `requirements-touch.txt`.
The app works fully offline without it. The server binds `127.0.0.1` only; put nginx in front
(`deploy/nginx-location.example.conf`, systemd units and env examples in `deploy/`).

The trip comes from the generated catalog: run `python3 scripts/build_ios_resources.py` first.
Plan validation (day count and dates, stay window, places, map bounds) is derived from it.

## Run locally (iOS integration tests)

```sh
python3 scripts/build_ios_resources.py
python3 server/trip_server.py init --data-dir /tmp/trip-dev
TRIP_NATIVE_KEY_SHA256=$(printf %s tttttttttttttttttttttttttttttttttttttttttttttttt | shasum -a 256 | cut -d' ' -f1) \
  python3 server/trip_server.py serve --data-dir /tmp/trip-dev --port 8765
# In the Xcode test scheme: TRIP_INTEGRATION_URL=http://127.0.0.1:8765/
# (debug builds use the 48 x "t" access key when that variable points at loopback)
```

Tests: `python3 -m unittest discover -s server -p 'test_*.py'`.

## Endpoints

All `/api/*` routes need the session cookie. POST/PUT additionally need `Origin` equal to
`TRIP_ORIGIN` and `X-Trip-CSRF` from `/api/session` (except `native-session`, which needs Origin only).

| Method | Path | Purpose |
| --- | --- | --- |
| GET | `/healthz` | `{"ok":true}`, no auth |
| POST | `/api/native-session` | `{"accessKey"}` whose SHA-256 matches `TRIP_NATIVE_KEY_SHA256` (or `TRIP_REVIEW_KEY_SHA256` for the review DB); sets the cookie |
| GET | `/api/session` | `{csrf, expiresAt}` |
| GET / PUT | `/api/plan` | snapshot (`?since=<rev>` → 204 if unchanged); PUT `{revision, state, device}`, 409 `{latest}` on conflict |
| POST / GET | `/api/attachments`, `/api/attachments/<sha256>` | ticket files: JPG/PNG/WebP/PDF, 10 MB each, 100 MB total |
| GET / PUT | `/api/route-preferences` | independent revisioned route settings, 409 `{latest}` on conflict |
| GET | `/api/route-address-status` | `{enabled}` from `TRIP_ROUTE_ENGLISH_ADDRESS_SHARING` |
| POST | `/api/routes` | `{from:[lat,lon], to:[lat,lon], mode:"walking"|"driving"}` via Valhalla, inside map bounds |
| GET | `/api/route-places?query=` | search the deployed OSM place index |
| GET / POST | `/api/touch/<action>` | couple pairing and pokes (`X-Touch-Device` header) |

## Configuration (flag / env, default)

`--port` `TRIP_PORT` 8765 · `--data-dir` `TRIP_DATA_DIR` `<repo>/data` (`--db` overrides the file) ·
`--catalog` `TRIP_CATALOG` `ios/TripJournal/Resources/Content/catalog.json` · `--origin` `TRIP_ORIGIN`
`http://127.0.0.1:<port>` · `--cookie-name` `TRIP_COOKIE_NAME` `trip_session` · `--cookie-path`
`TRIP_COOKIE_PATH` `/` · `--review-db` `TRIP_REVIEW_DB` (none) · `TRIP_NATIVE_KEY_SHA256`,
`TRIP_REVIEW_KEY_SHA256` (empty = disabled) · `TRIP_MAP_BOUNDS` (catalog `trip.map.bounds`) ·
`TRIP_ROUTE_ROOT` `/opt/trip-journal/routes/current` (+ `TRIP_ROUTE_BINARY`, `TRIP_ROUTE_CONFIG`,
`TRIP_ROUTE_PLACES`) · `TRIP_ROUTE_ENGLISH_ADDRESS_SHARING` `0`.
APNs worker: `TOUCH_APNS_TEAM_ID`, `TOUCH_APNS_KEY_ID`, `TOUCH_APNS_KEY_PATH`, `TOUCH_APNS_TOPIC` (all required).

Commands: `init` (new DB from the catalog's default plan; never overwrites), `serve`,
`backup --output <file>`, `reset-touch` (clears pairing only). Logs never contain bodies,
cookies, query strings or secrets.
