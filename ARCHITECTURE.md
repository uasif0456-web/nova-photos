# NOVA PHOTOS — Architecture

Original Flutter (Dart) Android client for an Immich server. Talks to Immich **only through its public REST API** (OpenAPI spec v3.4.2, `spec-v3.4.2.json`). No Immich code is copied into this project.

## Design decisions (from research)

1. **Hand-written typed API client, not generated.** Immich generates its Dart client with openapi-generator-cli at build time; NOVA's client is hand-written from the same spec, covering only the endpoints the app uses (~40 of 287). This keeps the build simple (no codegen step) and the client auditable. Pin the spec version (3.4.2) and re-verify endpoints when targeting a new server major.
2. **Local-first timeline (Immich's own pattern).** The official mobile app does not REST-paginate the timeline: it keeps a Drift (SQLite) mirror fed by `POST /sync/stream` (JSON Lines + `/sync/ack` checkpoints), with Socket.IO (`/api/socket.io`) as the invalidation trigger. NOVA follows the same pattern: local DB is the source of truth for the timeline; the API reconciles it. MVP may start from `GET /timeline/buckets` + `/timeline/bucket` (marked `Internal` in the spec — use with care, feature-gate on server version), then move to the sync-stream mirror.
3. **Upload = SHA-1 + bulk-check + multipart.** No chunked/resumable upload exists on the server in v3.4.2. Flow: compute SHA-1 of the file → `POST /assets/bulk-upload-check` → skip if 200 (duplicate) → multipart `POST /assets` (201 = created). Interrupted uploads restart from the beginning; the queue records this honestly.
4. **Auth: login JWT.** `POST /auth/login` returns a Bearer token (no refresh token in the spec) stored in `flutter_secure_storage`. API-key auth is for secondary integrations only. Session cookie (`immich_access_token`) is the alternative the official mobile app uses; NOVA uses the Bearer token.
5. **Version gating.** Target servers `>= 3.0.0`, develop against 3.4.2. On connect, call `GET /server/version` (block major < 3, warn on major > 3) and `GET /server/features` to gate features. `featureLevel` is the designed compatibility signal.
6. **No MCP in v1.** No official Immich MCP exists; third-party MCP servers are a reference/future AI-assistant surface only (see `MCP_INTEGRATION_REPORT.md`). All data flows go through the REST API.
7. **State management: Riverpod** (`flutter_riverpod`). Clean layers, dependency injection via providers. No business logic in widgets.

## Layers

```
lib/
  main.dart                 — entry, provider scope, theme, router
  src/
    api/                    — ImmichApiClient (hand-written, typed), endpoint builders,
                              error types, pagination helpers. NO UI imports.
    models/                 — hand-written DTOs with fromJson/toJson:
                              Asset, Album, Person, Tag, Memory, SearchResult,
                              ServerVersion, ServerFeatures, User, SyncDelta.
    services/               — AuthService, SyncService, UploadService, BackupService,
                              ThumbnailCacheService, SearchService, SocketService.
                              Services own orchestration; they call the API client
                              and the local store, never widgets.
    store/                  — local persistence: Drift (SQLite) database, DAOs,
                              upload queue table, sync checkpoint, settings.
                              (See DATABASE_SCHEMA.md.)
    providers/              — Riverpod providers wiring services + UI state
                              (timeline, selection, search query, backup status).
    ui/
      theme.dart            — Material 3, Nova branding, light + dark
      screens/              — Photos, Collections, Search, Memories, Library,
                              Viewer, Login, Settings, BackupDashboard
      widgets/              — AssetGrid, AssetTile, SelectionBar, BackupBadge,
                              SearchBar, MemoryCard, AlbumCard, ErrorView, EmptyView
    utils/                  — date formatting, file hashing (SHA-1), mime helpers,
                              logging (no tokens, no PII)
```

Dependency rule: `ui` → `providers` → `services` → `api`/`store` → `models`. `api` and `models` never import Flutter UI. `store` never imports `api`.

## Data flow

- **Timeline read:** UI → timeline provider → local Drift DB (fast, offline) → SyncService reconciles via `/sync/stream` deltas + Socket.IO events → DB updates → provider rebuilds UI.
- **Thumbnail:** `AssetTile` → `cached_network_image` with URL from `ImmichApiClient.thumbnailUrl(id, size)` + `Authorization: Bearer` header → disk cache. Never download originals for the grid (thumbnail 360px WebP / preview 1440px JPEG).
- **Upload:** BackupService scans local media (`photo_manager`) → SHA-1 → bulk-upload-check → multipart upload → server confirms 201 → mark uploaded in DB. Failures stay queued with retry count; never mark success before the server confirms.
- **Search:** query → `POST /search/smart` (CLIP) or `POST /search/metadata` (filters) → results grid. People via `GET /people`; faces are server-side (InsightFace) — the app never runs ML locally.
- **Realtime:** `SocketService` (socket_io_client) connects to `/api/socket.io/` with the Bearer token, subscribes to asset/album events, triggers targeted reconciliation. If the socket drops, polling reconciliation is the fallback — never rely on the socket alone.

## API surface used (v3.4.2)

Auth: `POST /auth/login`, `POST /auth/logout`, `GET /auth/validate`. Server: `GET /server/ping`, `GET /server/version`, `GET /server/features`, `GET /server/statistics`. Assets: `POST /search/metadata` (list + filters + pagination via `nextPage`/`nextCursor`), `GET /assets/{id}`, `POST /assets` (upload), `POST /assets/bulk-upload-check`, `PUT /assets` (bulk update — favorite/archive), `DELETE /assets` (bulk), `GET /assets/{id}/thumbnail`, `GET /assets/{id}/original`, `GET /assets/{id}/video/playback`, `GET /assets/{id}/video/stream/main.m3u8`, `GET /assets/{id}/ocr`. Timeline: `GET /timeline/buckets`, `GET /timeline/bucket` (Internal — feature-gated). Sync: `POST /sync/stream`, `POST /sync/ack`. Albums: `GET /albums`, `POST /albums`, `GET /albums/{id}`, `PATCH /albums/{id}`, `DELETE /albums/{id}`, `PUT /albums/{id}/assets`, `DELETE /albums/{id}/assets`. People: `GET /people`, `GET /people/{id}`, `PUT /people/{id}`. Search: `POST /search/smart`, `POST /search/metadata`, `GET /search/places`, `GET /search/cities`. Memories: `GET /memories`. Tags: `GET /tags`, `POST /tags`, `PUT /tags/{id}/assets`. Trash: `POST /trash/restore`, `POST /trash/empty`. Sharing: `POST /shared-links`, `GET /shared-links`. Notifications: `GET /notifications`.

Gotchas (from `IMMICH_API_CATALOGUE.md`): no `GET /assets` list; no single-asset DELETE; albums don't embed assets in v3 (fetch via search with `albumIds`); video `duration` is a string in v3; `total` is deprecated; error shapes and rate limits are undocumented — treat every error generically and surface it.

## Offline-first rules

- The local DB is the timeline source of truth; the network reconciles it.
- Uploads are queued durably; a photo is "backed up" only after the server returns 201.
- Cached thumbnails, album metadata and settings survive offline; actions taken offline (favorite, archive, delete) are queued as pending operations and replayed on reconnect.
- Never mark a photo as backed up until the server confirms success.

## Security

See `SECURITY.md`. Headlines: tokens in `flutter_secure_storage` only; HTTPS only, full TLS validation (never disabled); no tokens/keys/passwords in logs; server URL is user-configurable; no hardcoded credentials.

## Testing

- Unit: API client parsing, models, pagination, SHA-1 dedup, upload queue, sync engine, DB.
- Integration (against demo server): login, timeline fetch, thumbnail load, upload, search, album ops.
- UI: navigation, grid scroll, viewer, selection, settings, backup dashboard.
- Results recorded in `TESTING_REPORT.md` — real pass/fail, never claimed without running.

## Build

See `BUILD_INSTRUCTIONS.md`. Local Gradle builds are unreliable in this VM (known daemon handshake failure); a GitHub Actions workflow builds the APK in the cloud on push.
