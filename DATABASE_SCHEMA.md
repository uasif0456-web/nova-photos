# NOVA PHOTOS — Local Database Schema

Drift (SQLite) offline mirror + queues. Schema version **1**.
File: `nova_photos.db` in the app-support directory
(`openNovaDatabase()` in `app/lib/src/store/nova_database.dart`).
No codegen: tables are raw `CREATE TABLE` statements in
`novaSchemaV1Statements` (that list is the schema of record — this
document quotes it); DAOs in `app/lib/src/store/daos.dart` query them
with Drift `customSelect` / `customStatement`.

## Tables

### `assets_mirror` — the timeline source of truth (offline)
| Column | Type | Notes |
|---|---|---|
| `id` | TEXT PK | Server asset id (UUID) |
| `owner_id` | TEXT | `ownerId` |
| `type` | TEXT | `IMAGE` / `VIDEO` / `AUDIO` / `OTHER` |
| `original_file_name`, `original_path` | TEXT | Server originals |
| `checksum` | TEXT | Hex SHA-1 (indexed — dedup lookups) |
| `file_created_at`, `file_modified_at`, `local_date_time`, `created_at`, `updated_at` | INTEGER | Epoch ms (UTC). Timeline sorts on `local_date_time DESC` (indexed) |
| `width`, `height` | INTEGER | |
| `is_favorite`, `is_archived`, `is_trashed` | INTEGER 0/1 | |
| `visibility` | TEXT | `timeline` / `archive` / `hidden` / `locked` |
| `thumbhash` | TEXT | |
| `duration_ms` | INTEGER NULL | Videos only |
| `mime_type` | TEXT NULL | |
| `local_path` | TEXT NULL | Device path of the backed-up original, when known |
| `sync_state` | TEXT | `synced` (server state) / `pending` (local optimistic change awaiting replay) |
| `updated_locally_at` | INTEGER NULL | Reserved for future conflict metadata |

Fed by `POST /sync/stream` (`AssetV2` upsert, `AssetDeleteV1`
delete). Server-wins: an upsert replaces the row wholesale.

### `albums_mirror` + `album_assets`
`albums_mirror(id PK, name, description, owner_id, asset_count,
shared, has_shared_link, thumbnail_asset_id, created_at, updated_at)`.
Membership is the join table `album_assets(album_id, asset_id)` with
a composite PK and an index on `asset_id` (v3 albums do not embed
assets — membership comes from `AlbumToAssetV1` /
`AlbumToAssetDeleteV1` sync records).

### `people_cache` + `tags_cache` + `asset_tags`
`people_cache(id PK, name, is_hidden, birth_date, color,
is_favorite, thumbnail_path)` — from `PersonV1` sync records and
asset payloads. `tags_cache(id PK, value, name, color, parent_id)`
— hierarchical (`value` is the full `Parent/Child` path).
`asset_tags(asset_id, tag_id)` composite PK. Read-only cache: the
app never edits people/tags locally.

### `upload_queue` — durable backup queue
| Column | Type | Notes |
|---|---|---|
| `id` | TEXT PK | `local-<photo_manager id>` |
| `local_path` | TEXT | Device file path |
| `filename`, `sha1` | TEXT | `sha1` indexed — scan dedup |
| `size_bytes` | INTEGER | |
| `state` | TEXT | `pending` / `uploading` / `failed` / `done` (see state machine below) |
| `retry_count` | INTEGER | Attempts used; max 3 (see below) |
| `last_error` | TEXT NULL | Last failure message, shown in the Dashboard |
| `server_asset_id` | TEXT NULL | Set on 201 `created` |
| `file_created_at`, `file_modified_at`, `created_at` | INTEGER | Epoch ms |

State machine (`app/lib/src/store/upload_queue.dart`, unit-tested):
`pending → uploading → done`, `uploading → failed`,
`failed → pending` (retry), `failed → uploading` (manual retry),
`uploading → pending` (crash recovery — `resetStuckUploading()` runs
at the start of every backup run). All other transitions are refused
by `UploadQueueDao.setState`. Retry: exponential backoff 2s → 4s →
8s (cap 60s), max 3 attempts total, then the item stays `failed`.

### `pending_ops` — offline operations, FIFO replay
`(id INTEGER PK AUTOINCREMENT, kind TEXT, asset_id TEXT NULL,
album_id TEXT NULL, payload TEXT JSON, created_at INTEGER,
attempts INTEGER, last_error TEXT NULL)`. Kinds: `favorite`,
`archive`, `delete`, `add_to_album`, `remove_from_album`. Replay is
strictly by ascending `id` (the order the user did the actions).
Conflicts resolve **server-wins**: a 404/403 on replay drops the op
(the next sync re-asserts server state) and logs it; transient
failures keep the op queued with `attempts + 1` and stop the replay
(later ops may depend on the failed one).

### `sync_checkpoints`
`(entity_type TEXT PK, ack TEXT, updated_at INTEGER)` — last acked
checkpoint token per sync entity type, saved after each record is
applied and acked with `POST /sync/ack`.

### `settings`
`(key TEXT PK, value TEXT)` — backup preferences only:
`backup.enabled`, `backup.wifi_only` (default true),
`backup.charging_only` (default false), `backup.camera_only`
(default true), `backup.included_folders` / `backup.excluded_folders`
(JSON arrays). Server URL + session stay in secure storage, never
here.

## What is deliberately NOT mirrored in v1
- **EXIF details** (`AssetExifV1`): no EXIF columns — the `AssetV2`
  record already carries the fields the timeline needs.
- **Memories, stacks, auth user** (`MemoryV2`, `StackV1`,
  `AuthUserV2`): records are acked but not stored; add tables when a
  UI needs them offline.
- **Originals**: never stored locally beyond the device's own camera
  roll; the mirror holds metadata + `local_path` only.

## Sync wire-format note
`POST /sync/stream` takes **SyncRequestType** values in its `types`
field (`AssetsV2`, `AlbumsV2`, `AlbumToAssetsV1`, `PeopleV1`,
`MemoriesV2`, …) while the records it returns carry
**SyncEntityType** values (`AssetV2`, `AssetDeleteV1`, …) — verified
in `spec-v3.4.2.json` (`SyncStreamDto.types` → `SyncRequestType`).
`SyncService.syncRequestTypesFor` translates Track A's entity-type
list before sending; the ack still uses the record's entity type.
Live verification against the demo server is still pending (needs
`DEMO_USER`/`DEMO_PASS` env vars — see DEVELOPMENT_LOG 2026-11-22).

## Resumable uploads — honest limitation
The server has **no chunked/resumable upload** in v3.4.2: an
interrupted multipart upload restarts from byte 0. The queue records
that (item → `pending`, retry counter bumped); nothing is marked
backed up until the server returns 201 `created` or 200 `duplicate`.

## Upgrade path
- Schema version is `novaSchemaVersion` (= 1) in
  `nova_database.dart`; `MigrationStrategy.onUpgrade` handles
  `from → to`.
- Rule: upgrades are **additive only** (new tables / columns via
  `ALTER TABLE`, `CREATE TABLE IF NOT EXISTS`) — never a destructive
  rewrite, so an interrupted upgrade cannot lose the mirror or the
  queue. `onUpgrade` re-runs the v1 creates defensively (all are
  `IF NOT EXISTS`).
- v2 candidates (not yet designed): EXIF columns on `assets_mirror`,
  a `memories_mirror` table, per-album sync cursors.
- Downgrades are unsupported: a newer DB opened by an older build
  fails loudly (Drift throws on schema mismatch) instead of silently
  corrupting data.
- `PRAGMA journal_mode = WAL` is set in `beforeOpen` so sync bursts
  do not block timeline reads.
