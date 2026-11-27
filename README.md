# NOVA PHOTOS

An original, premium Android photo app (Flutter, Dart, Material 3) that uses an **Immich server** as its media backend — a Google Photos-level experience: timeline, viewer, automatic backup, smart search, albums, memories, map, library, sharing, real-time sync and offline-first caching.

> **NOVA PHOTOS is a separate client.** It talks to Immich only through its public REST API (OpenAPI spec at https://api.immich.app/). No Immich mobile/server/web code is copied into this project. Immich is AGPL-3.0; this app's own code is original. The Immich repository is cloned read-only under `research/immich` for investigation only.

## Status

**Code complete (2026-11-22). Cloud build pending repo creation — no APK yet.**

- `flutter analyze`: clean. `flutter test`: 82 passed, 0 failed. Live smoke test vs demo server (Immich 3.4.2): passed — 32,892 images, 52 videos, 205 timeline buckets.
- Local `flutter build apk` does NOT work in this VM (Gradle daemon handshake failure — see `BUILD_INSTRUCTIONS.md`). The APK is built by the GitHub Actions workflow (`.github/workflows/build-apk.yml`) once the owner creates the `nova-photos` repo on GitHub and grants the Muse GitHub App access.
- The app has never run on a real device yet — first install + tap-through is the first job once the cloud APK exists.

## Features (planned)

- **Photos** — chronological timeline grouped by day/month/year, virtualized grid, lazy thumbnails, pull-to-refresh, multi-select.
- **Viewer** — pinch/double-tap zoom, swipe, video playback, metadata, favorite/archive/share/download/delete.
- **Backup** — automatic camera backup via WorkManager, Wi-Fi-only / charging-only options, duplicate prevention, resumable uploads, progress + failure reporting.
- **Search** — objects, people/faces, places, dates, camera, filename, smart (CLIP) search via the server.
- **Collections** — albums (create/rename/delete, add/remove, shared albums), people, places.
- **Memories** — "this day in previous years", highlights, travel.
- **Map** — photos grouped by location.
- **Library** — favorites, archive, trash, device folders, backup settings.
- **Sync** — WebSocket events + API reconciliation, offline-first local cache (SQLite), upload queue.

## Connect to your server

1. Run your own Immich server (Docker, see https://docs.immich.app) or use the public demo: `https://demo.immich.app` (demo@immich.app / demo).
2. Open NOVA PHOTOS → Settings → Server → enter the server URL and sign in (email + password, or API key).
3. The app stores credentials securely on-device and never sends them anywhere except your server.

## Documentation

- `IMMICH_REVERSE_ENGINEERING_REPORT.md` — Immich architecture map
- `IMMICH_API_CATALOGUE.md` — REST API catalogue (from the real OpenAPI spec)
- `MCP_INTEGRATION_REPORT.md` — Immich MCP servers/tools actually found (none invented)
- `API_VERSION_COMPATIBILITY.md` — server-version compatibility notes
- `ARCHITECTURE.md` — app architecture (layers, state management, data flow)
- `DATABASE_SCHEMA.md` — local SQLite schema
- `SECURITY.md` — security and privacy model
- `TESTING_REPORT.md` — real test results
- `BUILD_INSTRUCTIONS.md` — how to build the APK (local + GitHub Actions cloud build)
- `CHANGELOG.md` — release notes
- `DEVELOPMENT_LOG.md` — running build log

## Build

See `BUILD_INSTRUCTIONS.md`. Local Gradle builds are known to be unreliable in this VM; a GitHub Actions workflow (`.github/workflows/build-apk.yml`) builds the APK in the cloud on push.

## License

NOVA PHOTOS app code: original work, MIT (see `LICENSE` when added). Immich is a separate project under AGPL-3.0 — not included here.
