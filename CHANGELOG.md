# NOVA PHOTOS — Changelog

## [Unreleased] — 2026-11-22 — v1.0.0+1 (code complete, cloud build pending)

First build of NOVA PHOTOS: an original Flutter (Dart, Material 3) Android client for Immich servers, built against the public Immich REST API (spec v3.4.2).

### Added

- **Foundation:** Flutter project (`com.novaphotos.app`), pinned dependencies, hand-written typed API client (auth, server, assets, search, timeline, albums, people, memories, tags, trash, shared links, sync, Socket.IO), auth service with secure token storage, Riverpod clean layers, original deep indigo/violet + aurora Material 3 theme (light + dark), original app icon, 5-tab shell (Photos, Collections, Search, Memories, Library), login + server settings screens.
- **Photos timeline:** day/month/year grouping, fast-scroll month indicator, month-jump sheet, pull-to-refresh, infinite scroll, scroll preservation, multi-select with action bar (favorite, archive, add to album, share, download, delete).
- **Viewer:** swipeable pages, pinch + double-tap zoom, video playback, metadata sheet, favorite/archive/share/download/delete/add-to-album.
- **Search:** smart (CLIP) search, metadata filters, recent searches, people/places/cities.
- **Collections:** albums CRUD, add/remove assets, shared badges, people grid, tags.
- **Memories:** server lanes + locally derived "This day in previous years" / "Recent highlights" (labelled as on-device generated).
- **Library:** favorites, archive, trash (restore/empty), device-folder scan, backup settings.
- **Backup engine:** local media scan, SHA-1 dedup, bulk-upload-check, multipart upload, retry with backoff, WorkManager periodic task, foreground service, Backup Dashboard, live app-bar backup status.
- **Offline-first:** Drift/SQLite mirror, sync-stream engine with checkpoints, Socket.IO invalidation, pending-operations queue with server-wins replay, thumbnail + metadata caching.
- **Docs:** reverse-engineering report, API catalogue (287 operations), MCP report, version compatibility, architecture, database schema, security, testing report, build instructions, development log.

### Verified

- `flutter analyze`: clean. `flutter test`: 82 passed, 0 failed. Live smoke test vs demo server (Immich 3.4.2): passed — 32,892 images, 52 videos, 205 timeline buckets.

### Known limitations

- **No APK yet.** Local Gradle builds fail in this VM (daemon handshake); the APK is built by the GitHub Actions workflow once the owner creates the `nova-photos` repo.
- No on-device testing performed (no device/emulator in the VM).
- No live sync/backup run against a real server yet (unit-tested with mocks only).
- Downloads save to the app documents directory, not the public Downloads folder (needs a MediaStore/SAF flow).
- No resumable/chunked uploads — the Immich v3.4.2 server has no chunked-upload endpoint; interrupted uploads restart from byte 0.
- Release APK from CI is unsigned (debug-signed); a release keystore is not yet configured.
