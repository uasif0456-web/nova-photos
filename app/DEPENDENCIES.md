# NOVA PHOTOS — Dependencies

All versions are **pinned exactly** in `pubspec.yaml` (and locked in
`pubspec.lock`). Nothing is added that the app does not use. Target
spec: Immich OpenAPI v3.4.2. Flutter 3.50.1 / Dart 3.14.0.

## Runtime dependencies

| Package | Pinned | Why it is here |
|---|---|---|
| `flutter_riverpod` (+ `riverpod`) | 3.5.0 | State management. Compile-safe providers, no codegen, testable via overrides. Every service and the session/photos state hang off it (`lib/src/providers/`). |
| `material_ui` | 1.11.1 | Material 3 widgets. Flutter 3.50 moved them out of `package:flutter/material.dart` into this package; the analyzer flags the old import as deprecated. |
| `http` | 1.6.0 | The API transport. Chosen over `dio` deliberately: the client is a thin typed wrapper over REST + multipart + JSONL streaming, and `http` covers all three with no extra interceptors, no codegen, and the smallest API surface to audit. `MockClient` from the same package powers the unit tests. |
| `drift` | 2.35.4 | Offline cache (Track B): the local mirror of assets/albums/people/memories fed by `POST /sync/stream`. Chosen over `sqflite` because Drift gives typed, compile-checked queries and streams, which is what a sync mirror needs; `sqflite` would mean hand-rolled SQL strings for every sync record type. |
| `sqlite3_flutter_libs` | 0.5.42 | Bundles the native SQLite library Drift needs on Android. 0.5.42 is the last normal release (0.6.0 was published only as an end-of-life marker). |
| `flutter_secure_storage` | 11.2.0 | Session JWT + cookie + server URL in the Android Keystore (AES-GCM, RSA-wrapped key by default in v11). Tokens never touch plain files, logs, or SharedPreferences. |
| `cached_network_image` | 4.0.7 | Authenticated, disk-cached thumbnails/previews in the Photos grid. Plain `Image.network` cannot send the `Authorization` header, and the server's thumbnails must not be re-fetched on every scroll. |
| `photo_manager` | 3.12.0 | Local media scan for backup (Track C): enumerate the device camera roll to find upload candidates. |
| `workmanager` | 0.10.10 | Background backup work (Track C): periodic/constrained upload jobs that survive the app being killed. |
| `socket_io_client` | 3.1.6 | Live-update socket (`/api/socket.io`): server push events (`on_upload_success`, `on_asset_*`, `on_server_version`) as the invalidation trigger for sync. A raw WebSocket cannot speak Socket.IO. |
| `video_player` | 2.14.0 | Video playback in the viewer (Track B), pointed at `/assets/{id}/video/playback` (byte-range) or the HLS playlist. |
| `share_plus` | 13.3.1 | Android share sheet (Track B): share downloaded originals from the viewer / selection bar via the system `ACTION_SEND` sheet. No other package in the set opens the share sheet; a hand-rolled MethodChannel would duplicate its plugin. |
| `intl` | 0.20.3 | Date/time formatting in the timeline UI. |
| `uuid` | 4.6.0 | Ids for sync checkpoints / upload dedup keys. |
| `crypto` | 3.0.7 | SHA-1 file checksums — the server's duplicate-detection checksum (`x-immich-checksum`, `POST /assets/bulk-upload-check`). |
| `path_provider` | 2.1.6 | App-support / cache directories (Drift database file, thumbnail cache). |

## Dev dependencies

| Package | Pinned | Why it is here |
|---|---|---|
| `flutter_lints` | 6.0.0 | Recommended lint set (enforced by `flutter analyze`). |
| `flutter_launcher_icons` | 0.14.4 | Generates the Android launcher/adaptive icons from `assets/icons/icon.png` (original art, `tools/generate_icon.py`). Dev-only. |
| `flutter_test` (SDK) | — | Unit + live smoke tests. |

## Track C note (2026-11-22) — no new dependencies added

The backup engine, sync engine and offline cache were built entirely
from the already-installed set above (`drift` + `sqlite3_flutter_libs`
for the mirror/queues, `photo_manager` for the media scan,
`workmanager` for background backup, `socket_io_client` for the
invalidation trigger, `crypto` for SHA-1, `path_provider` for the DB /
cache paths, `flutter_secure_storage` for the session the background
worker restores). No `connectivity_plus` / `battery_plus` (Wi-Fi-only
and charging-only are enforced by WorkManager `Constraints` for
background work instead) and no `flutter_cache_manager` direct
dependency (the thumbnail cache is cleared through
`CachedNetworkImageProvider.defaultCacheManager`, which is the same
manager the grid writes through).

## Deliberately NOT included

- `dio` — `http` covers the client's needs; see above.
- `sqflite` — Drift (above) is the cache layer; two SQLite wrappers would be redundant.
- `json_serializable` / `build_runner` / `drift_dev` — all models are hand-written `fromJson`/`toJson` (lenient parsing is a compatibility requirement, and codegen would add a build step for zero benefit at this size).
- `freezed` — plain immutable model classes with `copyWith` are enough.
- `flutter_secure_storage` is the only secrets store; no `shared_preferences` (nothing non-secret needs persisting yet — the server URL lives in secure storage alongside the session so logout wipes everything in one place).
