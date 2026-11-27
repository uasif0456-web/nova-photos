# Immich Reverse-Engineering Report — for NOVA PHOTOS (Stages 1–2)

> **Purpose:** deep repository investigation + architecture map of Immich, to inform the design of NOVA PHOTOS — an *original* Flutter Android app that talks to an Immich server via its **public REST API**.
> **Method:** read-only inspection of a shallow clone (`--depth 1`) of the official repo. No code was copied into any app project, no sign-in, no money spent.
> **Clone location (investigation only):** `~/workspace/nova-photos/research/immich`
> **Repo inspected:** https://github.com/immich-app/immich
> **Commit inspected:** `9b3d3d861ccf5f52f05a2a53c3a8bfb5b9bb2aee` — 2026-11-21, `fix(mobile): report unsupported files as upload errors in backup (#33532)`
> **Version in repo:** `3.4.0-rc.0` (root `package.json`, `server/package.json`, `mobile/pubspec.yaml`, `web/package.json` all agree)
> **License:** GNU Affero General Public License v3 (AGPL-3.0) — `LICENSE` at repo root. This matters: see §12.
> **Date of investigation:** 2026-11-22

---

## 1. Repository root — structure at a glance

| Path | What it is |
|---|---|
| `server/` | NestJS (TypeScript) API + job workers. The Immich server. |
| `mobile/` | Flutter/Dart app (`immich_mobile`, Flutter 3.47.9, Dart SDK `>=3.12 <4.0`). |
| `web/` | SvelteKit web app (`immich-web`). |
| `machine-learning/` | Python FastAPI service (`immich-ml`): CLIP, face detection/recognition, OCR. |
| `open-api/` | The single source of truth for the API: `immich-openapi-specs.json` (OpenAPI 3.1.0, **202 paths**), plus the Dart SDK generator script. |
| `packages/sdk/` | Auto-generated **TypeScript** SDK (`@immich/sdk`, oazapfts runtime). |
| `packages/cli/` | Immich CLI (TypeScript). |
| `packages/plugin-sdk/`, `packages/plugin-core/` | Plugin system (Extism/WASM-based — server dep `@extism/extism`). |
| `packages/e2e-auth-server/` | Helper for e2e tests. |
| `packages/scripts/` | Release-notes / repo scripts. |
| `docker/` | `docker-compose.yml` (prod), `.dev`, `.rootless`, `hwaccel.*.yml`, `example.env`, `prometheus.yml`. |
| `docs/` | Docusaurus docs site (`docs.immich.app`). |
| `deployment/` | Terraform/OpenTofu-style deployment modules (`modules/`, `state.hcl`). |
| `native/` | Rust crates (`native_core`) shared by mobile via FFI. |
| `e2e/`, `i18n/`, `fastlane/`, `misc/`, `design/`, `install.sh` | Tests, translations, store metadata, misc tooling. |

Monorepo tooling: `pnpm` workspace (`pnpm-workspace.yaml`, pnpm 12.20.0), `mise.toml` for tool versions. Root `package.json` is almost empty (only prettier for `i18n/`).

---

## 2. Server — `server/` (NestJS)

### 2.1 Runtime shape

- **Framework:** NestJS 12 + Express 5 (`@nestjs/platform-express`), TypeScript.
- **Entry point:** `server/src/main.ts` — a supervisor process (`class Workers`) that forks **three worker processes**:
  - `ImmichWorker.Api` (`server/src/workers/api.ts`) — HTTP API, Nest `ApiModule`.
  - `ImmichWorker.Microservices` (`server/src/workers/microservices.ts`) — background job processing.
  - `ImmichWorker.Maintenance` (`server/src/workers/maintenance.ts`) — maintenance tasks.
  - Worker type enum: `ImmichWorker` in `server/src/enum.ts` (`Api`, `Maintenance`, `Microservices`).
- **Port:** default **2283** (`server/src/repositories/config.repository.ts:282` — `port: dto.IMMICH_PORT || 2283`). Docker maps `2283:2283`.
- **API base path:** `/api` (mobile probes `<url>/api` — see §7.1). Swagger UI served at `/doc` (`server/src/utils/misc.ts:364`, `SwaggerModule.setup('doc', ...)`); the checked-in spec `open-api/immich-openapi-specs.json` is generated from the NestJS Swagger document (`server/src/utils/misc.ts:317–371`, output path `../open-api/immich-openapi-specs.json`).
- **Validation/DTOs:** Zod schemas via `@immich/nestjs-standard-schema` (`createZodDto`), not class-validator. DTOs live in `server/src/dtos/` (~50 files, one per domain).
- **DB access:** **Kysely** query builder over `postgres` driver (`kysely-postgres-js`, `postgres@3.4.9`) — *not* TypeORM/Prisma. Schema defined in `server/src/schema/tables/` (60 table files) + `server/src/schema/migrations/` (**106 migrations**); migrations generated/run with `@immich/sql-tools` (`sql-tools … migrations generate/run`, see `server/package.json` scripts). `server/src/schema/index.ts` exports the `DB` type.
- **Config:** env-driven, `server/src/repositories/config.repository.ts` (`getEnv()`), incl. Redis options (`ioredis`, `REDIS_HOSTNAME` default `redis`, or `REDIS_URL` with `ioredis://` base64 JSON).
- **Observability:** OpenTelemetry (`@opentelemetry/*` — http, pg, ioredis, nestjs-core instrumentations, Prometheus exporter).

### 2.2 Layering (the pattern NOVA should steal conceptually)

```
controllers/   — thin HTTP layer, @Authenticated() guard, DTO in/out
services/      — business logic, one service per domain (+ services/shared/)
repositories/  — infrastructure adapters (DB, storage, ML, media, websocket, job, …)
schema/        — Kysely table definitions + migrations
middleware/    — AuthGuard, global exception filter, websocket adapter
cores/         — storage.core.ts (path layout)
workers/       — api / microservices / maintenance entry points
```

- **Controllers** (~45 files in `server/src/controllers/`): `asset`, `asset-media`, `asset-file`, `album`, `api-key`, `auth`, `auth-admin`, `cluster-group`, `config*` (public/user/admin), `database-backup`, `download`, `duplicate`, `face`, `job`, `library`, `maintenance`, `map`, `memory`, `notification*`, `oauth`, `partner`, `passkey`, `person`, `plugin`, `queue`, `search`, `server`, `session`, `shared-link`, `stack`, `sync`, `system-config`, `system-metadata`, `tag`, `timeline`, `trash`, `user`, `view`, `workflow`, `app`, `activity`, `integrity-admin`, `server-info` (via `server.controller`).
- **Services** (~55 files in `server/src/services/`): same domains plus `media.service.ts`, `metadata.service.ts`, `transcoding.service.ts`, `hls.service.ts`, `smart-info.service.ts`, `storage.service.ts`, `storage-template.service.ts`, `sync.service.ts`, `timeline.service.ts`, `version.service.ts`, `telemetry.service.ts`, `futo-backups.service.ts`, `workflow.service.ts` / `workflow-execution.service.ts`, `cli.service.ts`, `api.service.ts`.
- **Repositories** (~65 files in `server/src/repositories/`): `asset`, `album`, `album-user`, `api-key`, `app`, `auth-challenge`, `config`, `crypto`, `database`, `download`, `duplicate`, `email`, `event`, `job`, `library`, `logging`, `machine-learning`, `map`, `media`, `memory`, `metadata`, `move`, `notification`, `oauth`, `ocr`, `partner`, `passkey`, `person`, `person-user`, `plugin`, `process`, `resource`, `search`, `server-info`, `session`, `shared-link*`, `stack`, `storage`, `sync`, `sync-checkpoint`, `system-metadata`, `tag`, `telemetry`, `trash`, `user`, `version-history`, `video-stream`, `view-repository`, `webauthn`, `websocket`, `workflow`, `access`, `activity`, `asset-edit`, `asset-file`, `asset-job`, `cluster-group`, `cron`, `integrity`, `job`, `storage`.

### 2.3 Auth — `server/src/services/auth.service.ts`, `server/src/middleware/auth.guard.ts`

- Every route must declare `@Authenticated()` (guard throws if a handler lacks it — `auth.guard.ts`: *"Route … does not declare @Authenticated()"*).
- `@Authenticated()` options: `{ permission?: Permission, admin?: true, sharedLink?: true, public?: true, setup?: true }`. Non-public routes get Swagger `ApiBearerAuth + ApiCookieAuth + ApiKeySecurity`.
- **Three credential types**, resolved in `AuthService.authenticate()` (`auth.service.ts:219`):
  1. **Session** — header `x-immich-session-token` (`ImmichHeader.SessionToken`) or `x-immich-user-token`, or the `immich_access_token` cookie (`ImmichCookie.AccessToken`). Validated against the `session` table (`sessionRepository.getByToken(hashed)`); session `updatedAt`/`appVersion` refreshed if >1h stale. This is what the mobile app uses after password login.
  2. **API key** — header `x-api-key` (`ImmichHeader.ApiKey`) or query param `?key=` (`ImmichQuery.ApiKey`). SHA-256 hashed, looked up in `api-key` table; **permissions are scoped** — a request is rejected if the key lacks the route's required `Permission` (`auth.service.ts:235–237`). API keys are created/rotated at `POST /api-keys`, `POST /api-keys/{id}/rotate`, `GET /api-keys/me`.
  3. **Shared link** — headers `x-immich-share-key` / `x-immich-share-slug` or query `?key=&slug=` for `sharedLink: true` routes.
- **Auth endpoints** (`server/src/controllers/auth.controller.ts`, base `auth`): `POST /auth/login`, `POST /auth/admin-sign-up`, `POST /auth/validateToken`, `POST /auth/change-password`, `POST /auth/logout`, `GET /auth/status`, `POST /auth/pin-code`, `POST /auth/session/unlock`, `POST /auth/session/lock`.
- Also: OAuth (`oauth.controller.ts`: authorize/callback/link/unlink/backchannel-logout/mobile-redirect), Passkeys/WebAuthn (`passkey.controller.ts`, `@simplewebauthn/server`), sessions CRUD (`sessions.controller.ts`).
- **Permissions enum** — `Permission` in `server/src/enum.ts` (large enum, e.g. `AssetUpload`, `AssetDownload`, `AssetView`, `AssetDelete`, `AssetEditGet/Delete`, `SyncStream`, `SyncCheckpointRead/Update/Delete`, …). This is the server-side authorization model NOVA inherits for free by using the API.

### 2.4 Asset model & storage layout

- **Core table** `server/src/schema/tables/asset.table.ts` — key columns (verified by inspection): `id` (uuid), `ownerId`, `libraryId`, `checksum` (+ `checksumAlgorithm`), `duplicateId`, `type` (`AssetType`: `IMAGE | VIDEO | AUDIO | OTHER`), `status` (`AssetStatus`), `originalPath`, `originalFileName`, `fileCreatedAt`, `fileModifiedAt`, `localDateTime`, `isFavorite`, `isExternal`, `isOffline`, `visibility`, `livePhotoVideoId`, `stackId`, `thumbhash`, `duration`, `width/height`, `updateId`. Indexes on `(ownerId, checksum)`, `(ownerId, libraryId, checksum)`, `(originalPath, libraryId)`, `(id, stackId)`, `(ownerId, updateId)`.
- Related tables: `asset-exif` (EXIF), `asset-file` (derived files), `asset-face`, `asset-ocr`, `asset-edit`, `asset-metadata`, `asset-av`, `asset-job-status`, plus audit tables (`asset-audit`, `asset-face-audit`, … — every domain has an `*-audit` table), `face-search` / `smart-search` (vector embeddings), `ocr-search`, `sync-checkpoint`, `stack`, `tag`/`tag-asset`/`tag-closure`, `person`/`person-group`/`person-user`, `memory`/`memory-asset`, `album`/`album-user`/`album-asset`, `shared-link`/`shared-link-asset`, `partner`, `library`, `session`, `api-key`, `user`/`user-metadata`, `system-metadata`, `notification`, `move`, `cluster-group*`, `geodata-places`, `natural-earth-countries`, `integrity-report`, `version-history`, `workflow`/`plugin*`.
- **On-disk layout** — `server/src/cores/storage.core.ts` (`StorageCore`): folders from `StorageFolder` enum (`Library`, `Thumbnails`, `EncodedVideo`, …); per-user library folder `<base>/library/<storageLabel || userId>`; thumbnails nested `<ownerId>/<assetId>.<format>`; encoded video `<ownerId>/<assetId>.mp4`; person thumbnails `<ownerId>/<personGroupId>.<format>`. `getNestedPath/getNestedFolder` shard by owner id.
- **Asset response DTO** — `AssetResponseDto` (`server/src/dtos/asset-response.dto.ts`): full shape incl. `exifInfo`, `faces` → `people`, `files[]`, `stack`, `tags[]`, `thumbhash` (binary), `isEdited`, `edits[]`, `livePhotoVideoId`, `duration`, `localDateTime`, `originalFileName`, `owner`, `visibility`, `isOffline`, `isExternal`.

### 2.5 Upload pipeline — `asset-media.controller.ts` + `asset-media.service.ts`

- `POST /assets` — `multipart/form-data`, interceptors `AssetUploadInterceptor` + `FileUploadInterceptor`. Fields (from `AssetMediaCreateDto`, `server/src/dtos/asset-media.dto.ts`):
  - file part **`assetData`** (required), optional **`sidecarData`** (XMP sidecar);
  - text fields: `fileCreatedAt`, `fileModifiedAt` (ISO datetimes), `duration` (ms, videos), `filename`, `isFavorite`, `visibility`, `livePhotoVideoId` (uuid), `metadata` (JSON array).
  - optional header **`x-immich-checksum`** — *"sha1 checksum that can be used for duplicate detection before the file is uploaded"*.
  - Response: **201** created, **200** with `status: DUPLICATE` if the checksum already exists (`AssetMediaStatus.DUPLICATE` → controller sets status 200). `AssetMediaResponseDto` carries `id` + `status`.
- **Duplicate detection = SHA-1 of whole file contents** (`ChecksumAlgorithm.sha1File = 'sha1'`; legacy `sha1-path` deprecated). Server: `assetRepository.getUploadAssetIdByChecksum(userId, checksum)`.
- **Bulk pre-check:** `POST /assets/bulk-upload-check` — body `{ assets: [{ id, checksum }] }` (checksum base64- or hex-encoded SHA-1; `id` is a client-side echo identifier, e.g. filename); response maps each to `{ id, isTrashed }`/duplicate info. This is how the mobile client avoids uploading files the server already has.
- **No chunked/resumable upload observed** in this version — single multipart POST per asset (see §7.4 for the mobile side). Large-file failure surfaces as HTTP 413 ("File is too large") in the mobile upload repo.
- After upload, processing is **asynchronous via jobs** (see §2.7): metadata extraction → thumbnails → (video) transcode → face detection/recognition → CLIP embedding → duplicate detection → OCR.

### 2.6 Media endpoints — `asset-media.controller.ts` (base `/assets`)

| Method & path | Purpose |
|---|---|
| `POST /assets` | Upload (above) |
| `GET /assets/{id}/original` | Download original file (`Permission.AssetDownload`) |
| `GET /assets/{id}/thumbnail?size=thumbnail\|preview\|fullsize&edited=true/false` | Thumbnail/preview. `size=original` is **deprecated** — redirects to `/original`. May 302-redirect to a different size/original for cache efficiency. (`Permission.AssetView`) |
| `GET /assets/{id}/video/playback` | Video stream, byte-range requests supported (`Permission.AssetView`) |
| `GET /assets/{id}/video/stream/main.m3u8`, `…/{sessionId}/{variantIndex}/playlist.m3u8`, `…/{filename}`, `DELETE …/{sessionId}` | HLS adaptive streaming sessions (`hls.service.ts`) |
| `POST /assets/bulk-upload-check` | Duplicate pre-check (above) |

- **Thumbnail sizes** (`AssetMediaSize` enum): `thumbnail`, `preview`, `fullsize`, `original`. Defaults (`server/src/dtos/config.dto.ts`, `image:` section): thumbnail **WebP 360px, q80**; preview **JPEG 1440px, q80**; fullsize disabled by default (JPEG q80); colorspace P3.
- **Other asset endpoints** (`asset.controller.ts`, base `/assets`): `GET /assets/statistics`, `POST /assets/jobs`, `PUT /assets` (bulk update), `PATCH /assets`, `DELETE /assets` (bulk delete), `GET /assets/{id}`, `PUT /assets/{id}`, `PATCH /assets/{id}`, `PUT /assets/copy`, `PUT|DELETE /assets/metadata`, `GET /assets/{id}/metadata[/{key}]`, `PUT|DELETE /assets/{id}/metadata[/{key}]`, `GET /assets/{id}/ocr`, `GET|PUT|DELETE /assets/{id}/edits`.
- **Download/archive:** `POST /download/archive`, `POST /download/info` (`download.controller.ts`, `archiver` dep).

### 2.7 Jobs / queues — BullMQ + Redis (Valkey)

- `server/src/repositories/job.repository.ts` — BullMQ (`bullmq@6`, `@nestjs/bullmq`), Redis-backed. Handlers registered with `@OnJob({ name: JobName.X, queue: QueueName.Y })`; missing-handler check at boot.
- **Queues** (`QueueName`, `server/src/enum.ts:861`): `thumbnailGeneration`, `metadataExtraction`, `videoConversion`, `faceDetection`, `facialRecognition`, `smartSearch`, `duplicateDetection`, `backgroundTask`, `storageTemplateMigration`, `migration`, `search`, `sidecar`, `library`, `notifications`, `backupDatabase`, `ocr`, `workflow`, `integrityCheck`, `editor`.
- **Job names** (`JobName`, `enum.ts:895+`): `AssetDelete`, `AssetDetectFaces(QueueAll)`, `AssetDetectDuplicates(QueueAll)`, `AssetGenerateThumbnails(QueueAll)`, `AssetEncodeVideo(QueueAll)`, `AssetExtractMetadata…`, plus `NotifyAlbumUpdate`, `StorageTemplateMigrationSingle`, `PersonGenerateThumbnail`, `FacialRecognitionQueueAll`, `VersionCheck`, `DatabaseBackup`, … (list continues past the inspected range — see enum file).
- **Queue admin API:** `GET /queues`, `GET|PUT /queues/{name}`, `GET|DELETE /queues/{name}/jobs`; `GET|POST /jobs`, `PUT /jobs/{name}`.
- **Cron:** `@nestjs/schedule` + `cron` package; `cron.repository.ts`; nightly tasks config in `config.dto.ts`.

### 2.8 Media processing — `media.service.ts`, `metadata.service.ts`, `transcoding.service.ts`, `repositories/media.repository.ts`

- **Thumbnails** (`media.service.ts:handleGenerateThumbnails`): decode via **sharp** (`media.repository.ts`: `sharp`, concurrency 0, cache off), generate **thumbnail + preview** (+ optional fullsize for RAW/HIF) via `mediaRepository.generateThumbnail(decoded, options, path)`; compute **thumbhash** (placeholder blur hash) and store on the asset. Video thumbnails: extract frame with **ffmpeg** (`fluent-ffmpeg`) transcode to stills at preview/thumbnail resolutions, then thumbhash from the preview.
- **Video transcode** (`handleVideoConversion`): target decided by `getTranscodeTarget` from ffmpeg config (policy `TranscodePolicy`, codecs `VideoCodec`/`AudioCodec`, container `VideoContainer`, HW accel `TranscodeHardwareAcceleration` — nvenc/quicksync/vaapi/rkmpp, tone mapping, CQ mode, HLS resolutions in `enum.ts`). Retries: HW-accel → software decode → accel disabled. Output `.mp4` under `EncodedVideo/`.
- **Metadata extraction** (`metadata.service.ts`, `repositories/metadata.repository.ts`): **`exiftool-vendored`** (persistent ExifTool batch cluster, LFS enabled for >2GB files) — reads/writes EXIF/XMP; also extracts embedded preview/thumbnail binary tags. `media.repository.ts` also uses exiftool for orientation/write-back.
- **Face/person pipeline:** `person.service.ts`, `duplicate.service.ts`, `ocr.service.ts`, `smart-info.service.ts` — each enqueues ML calls via `machine-learning.repository.ts` (HTTP to the ML service).
- **Search:** `search.service.ts` — metadata search (`POST /search/metadata`), smart/CLIP search (`POST /search/smart`: text → `machineLearningRepository.encodeText(query, {modelName})` with a 100-entry LRU embedding cache, or image-query via an asset's stored embedding), random (`POST /search/random`), large-assets, statistics, explore (`GET /search/explore`), person/places/cities/suggestions. Vector search is server-side (pgvector/VectorChord — see §2.9); the mobile client only sends the query string.

### 2.9 Database & caching

- **PostgreSQL 14** with **VectorChord + pgvector** extensions: docker image `ghcr.io/immich-app/postgres:14-vectorchord0.4.3-pgvectors0.2.0`. Vector columns back `smart-search` / `face-search` tables. `DB_STORAGE_TYPE` env tunes HDD vs SSD.
- **Redis/Valkey 9** (`docker.io/valkey/valkey:9`): BullMQ queues + Socket.IO Redis adapter (`@socket.io/redis-adapter`) + config cache.
- **No server-side HTTP cache for media observed** beyond `CacheControl` enum (`private_with_cache`, `private_without_cache`, `none`) on file responses.

### 2.10 WebSocket — `server/src/repositories/websocket.repository.ts`

- **Socket.IO** (`@nestjs/websockets`, `@nestjs/platform-socket.io`), gateway at path **`/api/socket.io`**, transports `['websocket']` only, CORS on. Clients join rooms = `user.id` (+ `session.id`); auth via the same `AuthService` (auth fn injected with `setAuthFn`).
- **Server→client events** (`ClientEventMap`): `on_upload_success`, `on_user_delete`, `on_asset_delete`, `on_asset_trash`, `on_asset_update`, `on_asset_hidden`, `on_asset_restore`, `on_asset_stack_update`, `on_album_update`, `on_person_thumbnail`, `on_server_version`, `on_config_update`, `on_new_release`, `on_notification`, `on_session_delete`, plus sync events `AssetUploadReadyV1/V2` (`{asset: SyncAssetV2, exif: SyncAssetExifV1}`), `AssetEditReadyV1/V2`, `ResourceEventV1` (`{changed[], deleted[], correlationId?}`), `AppRestartV1`.
- **Server-internal events** (`serverEvents`): `ConfigUpdate`, `AppRestart`, `LibraryCreate/Update/Delete`, `HlsSegmentRequest/Result`, `HlsHeartbeat`, `HlsSessionRequest/Result/End` (HLS coordination between API and microservices workers via `serverSideEmit`).
- Event bus: `server/src/repositories/event.repository.ts` (`EventRepository.emit/onEvent`).

### 2.11 Other server subsystems (brief)

- **Libraries / external files:** `library.service.ts` — watched folders (`chokidar`), scan/validate/statistics (`POST /libraries/{id}/scan|validate`); external assets (`isExternal`).
- **Albums:** `album.service.ts` — CRUD, add/remove assets, shared users + roles (`AlbumUserRole`: owner/editor/viewer), map markers, album-update websocket fan-out.
- **Memories:** `memory.service.ts` — `MemoryType`: `on_this_day`, `birthday`.
- **People/faces:** `person.service.ts`, `face.controller.ts` — merge/reassign, statistics, person thumbnail (`GET /people/{id}/thumbnail`), cluster groups (`cluster-group.controller.ts`: merge requests, regenerate).
- **Trash:** `trash.service.ts` — restore/empty (`POST /trash/restore[/assets]`, `POST /trash/empty`).
- **Stacks / duplicates:** `stack.service.ts`, `duplicate.service.ts` (`GET /duplicates`, `POST /duplicates/resolve`).
- **Tags:** `tag.service.ts` — hierarchical tags (`tag-closure` table).
- **Shared links:** `shared-link.service.ts` — password/expiry, asset scoping, `POST /shared-links/login`.
- **Partners:** `partner.service.ts` — shared-with/shared-by timelines.
- **Map:** `map.service.ts` — markers, reverse-geocode (`GET /map/reverse-geocode`, geodata tables).
- **Notifications:** `notification.service.ts` + `notification-admin` (email via `email.repository.ts`, templates).
- **Workflows/plugins:** `workflow.service.ts`, `plugin.controller.ts` — Extism WASM plugins (`@immich/plugin-sdk`, `packages/plugin-sdk`).
- **Admin:** user admin, config admin, database backup (`database-backup.service.ts`, FUTO backups orchestrator dep), integrity checks, maintenance mode, version/license (`server.service.ts`, `version.service.ts`).
- **Timeline:** `timeline.service.ts` — `GET /timeline/buckets` (time buckets) + `GET /timeline/bucket` (assets in a bucket). DTOs in `time-bucket.dto.ts`.

---

## 3. Full REST API inventory (from `open-api/immich-openapi-specs.json`)

OpenAPI 3.1.0, title "Immich", version `3.4.0-rc.0`, **202 paths**. Grouped by first segment (methods in the spec file; full list verified by script — see §11):

| Group | Paths (highlights) |
|---|---|
| `server` | `GET /server/ping`, `/server/version`, `/server/version-check`, `/server/features`, `/server/config`, `/server/statistics`, `/server/storage`, `/server/media-types`, `/server/about`, `/server/apk-links`, `/server/license`, `/server/version-history` |
| `auth` | login, logout, validateToken, change-password, admin-sign-up, status, pin-code, session lock/unlock |
| `users` | `GET /users/me`, `PUT /users/me`, profile-image, calendar-heatmap, preferences, onboarding, license |
| `assets` | upload, original, thumbnail, video/playback, HLS stream, bulk-upload-check, statistics, jobs, copy, metadata, edits, ocr |
| `timeline` | `GET /timeline/buckets`, `GET /timeline/bucket` |
| `search` | metadata, smart, random, large-assets, statistics, explore, person, places, cities, suggestions |
| `sync` | `POST /sync/stream` (JSONL), `GET/POST/DELETE /sync/ack` |
| `albums` | CRUD, assets add/remove, users/roles, statistics, map-markers |
| `people` / `faces` | CRUD, merge, reassign, statistics, thumbnail; face CRUD |
| `memories` | CRUD, assets, statistics |
| `tags` | CRUD, assets |
| `stacks`, `duplicates`, `trash` | CRUD/resolve/restore/empty |
| `shared-links`, `partners`, `activities` | CRUD + login/me |
| `libraries`, `map`, `view`, `download` | scan/validate, markers/reverse-geocode, folder views, archive/info |
| `api-keys`, `sessions`, `passkeys`, `oauth` | key/session lifecycle, WebAuthn, OAuth |
| `jobs`, `queues` | job/queue status + control |
| `config`, `system-config`, `system-metadata`, `cluster-groups`, `notifications`, `plugins`, `workflows` | config + admin + extensibility |
| `admin/*` | users, config, database-backups, integrity, maintenance, notifications |
| `public/config` | unauthenticated server config |

> **For NOVA, the load-bearing subset is:** `server/ping`, `server/version`, `server/features`, `auth/*`, `users/me`, `assets/*` (upload/thumbnail/original/playback/bulk-upload-check), `timeline/*`, `search/*`, `sync/*`, `albums/*`, `people/*`, `memories/*`, `tags/*`, `trash/*`, `shared-links/*`. Everything else is admin/advanced and can be deferred.

---

## 4. Machine learning — `machine-learning/` (FastAPI, Python ≥3.12)

- **Service:** `immich_ml` package, FastAPI + gunicorn/uvicorn (`main.py`: `GET /` , `GET /ping`, `POST /predict`). Models are **ONNX** (`onnx`, `onnxruntime` incl. OpenVINO/CUDA builds) loaded lazily with TTL (`model_ttl: 300`, `model_ttl_poll_s: 10`, `config.py`), cached in `models/cache.py`, downloaded from Hugging Face (`huggingface-hub`).
- **Endpoints consumed by the server** via `machine-learning.repository.ts`: text encode, image encode, face detect/recognize, OCR. Exact HTTP contract between server and ML service was **not** fully traced (see §11) — the ML service is an internal sidecar, not part of the public API NOVA uses.
- **CLIP / smart search** (`models/clip/visual.py`, `textual.py`; `models/constants.py`): OpenCLIP model zoo — `ViT-B-32__openai`, `ViT-B-32__laion2b-s34b-b79k`, `ViT-L-14__openai`, `ViT-H-14-quickgelu__dfn5b`, SigLIP variants (`ViT-B-16-SigLIP-256__webli`, `ViT-SO400M-14-SigLIP-384__webli`, …), multilingual `XLM-Roberta-Base-ViT-B-32__laion5b_s13b_b90k`, etc. Default model revision env: `MACHINE_LEARNING_MODEL_REVISION: v2` (docker-compose). Server validates the configured model at boot (`smart-info.service.ts`: `getCLIPModelInfo`, dimension-size lock `DatabaseLock.CLIPDimSize` — changing CLIP model requires a DB migration of embedding dimensions).
- **Face detection/recognition** (`models/facial_recognition/detection.py`, `recognition.py`, `_ops.py`): InsightFace-derived (Apache-2.0, `deepinsight/insightface` — decode/NMS/Umeyama ports noted in `_ops.py`). Buffalo/Antelope-style detection + embedding models (exact model file names not enumerated here — see §11).
- **OCR** (`models/ocr/`): RapidOCR (`rapidocr>=3.1.0`) — detection + CTC recognition + post-processing; `max_resolution: 736` must match the server OCR setting or the preloaded model is skipped (`config.py:34`).
- **Other deps:** `opencv-python-headless`, `pillow` (+ `pillow-jxl-plugin` for JPEG-XL), `tokenizers`, `numpy`, `orjson`, `pydantic-settings`. Hardware-accel image flavours: `-cuda`, `-openvino`, `-armnn`, `-rocm`, `-rknn` (docker-compose comments).
- **NOVA implication:** none of this runs in the app. Face/CLIP/OCR are server-side capabilities NOVA gets *for free* by calling `POST /search/smart`, `GET /people`, `GET /assets/{id}/ocr`, etc. Do **not** bundle ONNX models in the app.

---

## 5. Web — `web/` (brief)

- **Stack:** SvelteKit + Vite (`immich-web`, dev port 3000). `web/src/routes/` (incl. `(user)` group, `admin/`, `auth/`, `link/`), `web/src/lib/` (`components/`, `stores/`, `managers/`, `services/`, `queries/`, `workers/`, `utils/`).
- Uses the same generated TypeScript SDK (`packages/sdk`) / OpenAPI spec as the server contract. Upload UI: `UploadPanel.svelte`, `UploadAssetPreview.svelte`.
- **NOVA implication:** the web app is a second reference client for the same REST API; its upload panel and timeline queries are useful cross-checks, but NOVA is mobile-only, so web was not traced in depth.

---

## 6. SDKs & code generation — `open-api/`, `packages/sdk/`

- **Spec generation:** server code is the source — NestJS Swagger (`DocumentBuilder`/`SwaggerModule`, `server/src/utils/misc.ts:317–371`) emits `open-api/immich-openapi-specs.json` (OpenAPI 3.1.0, 202 paths). CI enforces it (`/.github/workflows/check-openapi.yml` — diffs the checked-in spec against main; mobile has a patch-coverage test `flutter test test/openapi_patches_coverage.dart`).
- **TypeScript SDK:** `packages/sdk/` (`@immich/sdk`) — generated from the spec with **oazapfts** (`@oazapfts/runtime`), `src/index.ts`, `fetch-client.ts`, `fetch-errors.ts`. Built with `tsc`. Used by web + CLI.
- **Dart SDK (mobile):** `open-api/bin/generate-dart-sdk.sh` — `openapi-generator-cli` (v7.26.0, `openapitools.json`) generator `dart`, input `immich-openapi-specs.json`, output `mobile/generated/openapi`, with a custom mustache template patch (`open-api/templates/mobile/`) and post-generation source patches (`open-api/patch/*.patch` — `api_client.dart`, `api.dart`, `pubspec_immich_mobile.yaml`, model patches). The generated dir is **gitignored** (`mobile/generated` in `.gitignore`) — it does not exist in a fresh clone and is regenerated at build time. `mobile/pubspec.yaml` depends on it as a path package: `openapi: { path: generated/openapi }`.
- **NOVA implication (important):** the same pipeline is directly reusable — point `openapi-generator-cli` (dart) at the *server's own* `immich-openapi-specs.json` (or the live server's `/doc` JSON) and generate a fresh Dart client for NOVA. That is the intended, license-clean way to get a typed API client. Do not hand-copy Immich's generated output; regenerate it.

---

## 7. Mobile — `mobile/` (Flutter) — the most important section for NOVA

### 7.1 Connection & endpoint resolution — `mobile/lib/services/api.service.dart`

- `ApiService` holds one `ApiClient` (from generated `openapi` package) and instantiates a typed API class per domain: `UsersApi`, `AuthenticationApi`, `AlbumsApi`, `AssetsApi`, `SearchApi`, `ServerApi`, `MapApi`, `PartnersApi`, `PeopleApi`, `SharedLinksApi`, `SyncApi`, `SystemConfigApi`, `ActivitiesApi`, `DownloadApi`, `TrashApi`, `StacksApi`, `ViewsApi`, `MemoriesApi`, `SessionsApi`, `TagsApi`, `PasskeysApi`, `ConfigPublicApi`.
- **Endpoint resolution** (`resolveAndSetEndpoint` / `_resolveEndpoint`):
  1. Normalize user-typed URL (scheme default https).
  2. `GET /.well-known/immich` — if 200, read `data['api']['endpoint']` (relative paths resolved against base); if redirect to https, retry as https.
  3. Probe `<url>/api` with `ServerApi.pingServer()` (5 s timeout) — `GET /server/ping`; unreachable → `ApiException(503, "Server is not reachable")`.
  4. Persist resolved endpoint in local store (`StoreKey.serverEndpoint`).
- **Multiple endpoints:** `getServerUrls()` returns stored endpoint + configured local endpoint + external endpoint list (auto-switch local/external by Wi-Fi — `network` settings). Custom headers per server (`getRequestHeaders()`).
- **Device headers:** `setDeviceInfoHeader()` sends `deviceModel` + `deviceType` (`iOS`/`Android`/`Unknown`) on the auth API client (via `device_info_plus`).
- **HTTP stack:** `package:http` client wrapped by `NetworkRepository` (`mobile/lib/infrastructure/repositories/network.repository.dart`) — shared client injected into the generated `ApiClient` (`_apiClient.client = NetworkRepository.client`); `updateHeaders()` re-applies custom headers + server URLs. Native side has its own HTTP manager: `mobile/android/app/src/main/kotlin/app/alextran/immich/core/HttpClientManager.kt`.

### 7.2 Auth flow (mobile) — `mobile/lib/services/auth.service.dart`, `repositories/auth_api.repository.dart`

- Login: `POST /auth/login` with email + password → returns access token + user. Token stored via `StoreKey.accessToken` (Drift-backed `Store`, see §7.6) and `currentUser`; cookies cleared on logout via `networkApi.clearCookies()`.
- Session auth from then on (cookie/session-token), **not** API keys — the mobile app is a first-party session client. API keys are for third-party/CLI use.
- OAuth login via `oauth.service.dart` (`flutter_web_auth_2`); passkeys via `PasskeysApi` + native `PasskeyPlugin.kt`.
- `validateServerUrl()` → resolve endpoint → set device headers → store `StoreKey.serverUrl`.
- Auxiliary endpoint validation: `GET {url}/users/me` must return 200.
- Logout: server logout attempt (failures logged, not fatal) → `clearLocalData()`: cancel background sync, delete auth repo data, `currentUser`, `accessToken`, cookies, and network endpoint settings; backup disabled.
- Local app lock: `local_auth.service.dart` (`local_auth` — biometrics) + PIN page (`pages/common/pin_auth.page.dart`, `POST /auth/pin-code`, session lock/unlock).

### 7.3 Timeline & pagination — the key architectural decision

Immich mobile does **NOT** paginate the timeline through the REST list endpoints on every scroll. It uses a **local-first sync architecture**:

- **Server side:** `POST /sync/stream` returns a **JSON Lines** stream (`Content-Type: application/jsonlines+json`) of typed change records (`SyncStreamDto`); `GET/POST/DELETE /sync/ack` manages per-session checkpoints (`sync-checkpoint` table). Sync DTOs (`server/src/dtos/sync.dto.ts`): `SyncAssetV1/V2`, `SyncAssetExifV1`, `SyncAssetEditV1`, `SyncAssetMetadataV1`, `SyncAssetOcrV1`, `SyncAssetFaceV1/V3`, `SyncAlbumV1/V2`, `SyncAlbumToAssetV1`, `SyncMemoryV1/V2`, `SyncPersonV1`, `SyncStackV1`, `SyncUserV1`, `SyncAuthUserV1/V2`, `SyncPartnerV1`, plus `*DeleteV1` tombstones for each type. `ResourceEventV1` over websocket carries `{changed[], deleted[], correlationId?}` for incremental invalidation.
- **Client side:** `mobile/lib/infrastructure/repositories/sync_stream.repository.dart` (`SyncStreamRepository`, a Drift accessor) applies the stream into local tables (`updateAuthUsersV1`, …; `reset()` wipes all remote entities on `SyncResetV1`). `mobile/lib/domain/services/sync_stream.service.dart`, `mobile/lib/domain/utils/background_sync.dart`, `providers/background_sync.provider.dart` orchestrate it.
- **Timeline reads are local:** `mobile/lib/infrastructure/repositories/timeline.repository.dart` (`TimelineRepository`, Drift) — `watchTimelineUserIds` (own id + partners with `inTimeline`), `_watchMainBucket` (group by day via `mergedAssetDrift.mergedBucket`), `_getMainBucketAssets(offset, count)` — bucketed, offset/limit queries over a **merged local+remote asset view** (`mergedAsset` / `mergedBucket`). Local and remote assets are unified in the UI (`RemoteAsset` vs `LocalAsset` models).
- **Server-side bucket API still exists** for clients that want it: `GET /timeline/buckets` + `GET /timeline/bucket` (`timeline.service.ts` → `assetRepository.getTimeBucket`). NOVA can start with these two endpoints and add sync-stream later — see §12.
- Search pagination: `POST /search/metadata` and `POST /search/smart` are POST-with-body queries returning `SearchResponseDto` (page-based via DTO fields — exact paging fields not enumerated here; see §11).

### 7.4 Thumbnails, originals & images — URL patterns

- REST pattern (from §2.6): thumbnails `GET /api/assets/{id}/thumbnail?size=thumbnail|preview` (360px WebP / 1440px JPEG), original `GET /api/assets/{id}/original`, video `GET /api/assets/{id}/video/playback` (range requests), HLS `GET /api/assets/{id}/video/stream/main.m3u8`.
- **Mobile image pipeline** (`mobile/lib/infrastructure/loaders/`): `image_request.dart` (base `ImageRequest`), `remote_image_request.dart` (`RemoteImageRequest` — fetches via native `remoteImageApi.requestImage(uri, preferEncoded, width, height)`), `local_image_request.dart`, `thumbhash_image_request.dart`. Images are decoded **natively** where possible: Android Kotlin `RemoteImagesImpl.kt`, `LocalImagesImpl.kt`, `NativeImage.kt`, `ThumbHash.kt`; `mobile/lib/utils/cache/custom_image_cache.dart`. **ThumbHash** (compact blur placeholder, stored as `thumbhash` bytes on the asset) is rendered instantly while the real thumbnail loads — `thumbhash_image_request.dart`, `asset_extensions.dart`.
- **Native core (Rust):** `native/native_core` (path dep `native_core` in pubspec) + `mobile/pigeon/*.dart` (Pigeon-generated platform channels: `background_worker_api`, `native_sync_api`, `local_image_api`, `network_api`, `connectivity_api`, `background_worker_lock_api`).
- **Video:** `native_video_player` (git dep `immich-app/native_video_player`) for playback; Cast support via `cast` package + `gcast.service.dart`.

### 7.5 Upload & background backup — the backup engine

- **Candidate discovery:** `photo_manager: 3.9.0` reads the device media library; `LocalAssetRepository` / `BackupRepository` (Drift) track local assets and backup state. Backup selection UI: `pages/backup/` (album selection, options, upload detail).
- **Pre-upload dedup:** `POST /assets/bulk-upload-check` with SHA-1 checksums (see §2.5) — only not-yet-present assets are queued.
- **Foreground upload** (`mobile/lib/services/foreground_upload.service.dart`): sequential or worker-pool concurrent uploads via `UploadRepository.uploadFile` (`mobile/lib/repositories/upload.repository.dart`):
  - `POST {endpoint}/assets` as **multipart** (`ProgressMultipartRequest`, a `MultipartRequest` with abort + progress callbacks), file part `assetData`, text fields incl. `deviceAssetId` (= local asset id) and `deviceId` — with a code comment: *"deviceAssetId/deviceId required by server v2.7.5 and below (drop in v4.0 per #27818)"* — i.e. legacy fields, still sent.
  - Fields built in `uploadSingleAsset` / `_uploadSingleFile` (`fileCreatedAt`, `fileModifiedAt`, `duration`, `filename`, `isFavorite`, …); live photos upload the video part first (hidden visibility), then the still, then stack them (`assetService.stackEditedUpload`).
  - Retry: on `ClientException` before any response, the request is rebuilt and sent **once** more. 413 → "File is too large". Non-2xx → error message parsed from JSON body. Success → `responseBody['id']` = remote asset id. Cancellation via `Completer` token.
  - Upload callbacks update `providers/backup/asset_upload_progress.provider.dart`.
- **Background upload** (`mobile/lib/services/background_upload.service.dart`): iOS-first — uses `background_downloader: ^9.5.6` (iOS `URLSession`-backed) so uploads continue while suspended; `UploadTaskMetadata` (`localAssetId`, `isLivePhotos`, `livePhotoVideoId`, `checksum`) is attached to each task. Android background work: native `BackgroundWorker.kt`, `PeriodicWorker.kt`, `MediaObserver.kt` (observes new media), `BackgroundWorkerApiImpl.kt`, `BackgroundEngineLock.kt` under `mobile/android/app/src/main/kotlin/app/alextran/immich/background/`.
- **Backup orchestration** (`mobile/lib/providers/backup/backup.provider.dart` — `BackupNotifier`): `getBackupStatus`, `startForegroundBackup` / `stopForegroundBackup`, `startBackupWithURLSession` (iOS), Wi-Fi-only gating, cancel tokens, progress counts (`backupCount`/`remainderCount`).
- **Download (offline copies):** `mobile/lib/services/download.service.dart` + `background_downloader`; `download` models/providers.
- **No chunked upload** in this version (single multipart POST; see §2.5). Checksums are SHA-1 of the whole file (`crypto` package on mobile).

### 7.6 Local database & offline behavior

- **Drift (SQLite)** — `drift: ^2.34.0`, `drift_sqlite_async`, `sqlite3`, `sqlite_async`, `sqlite3_connection_pool`. Schema in `mobile/lib/data/db/main/`:
  - `database.dart` (the `Drift` database), `table/app/`, `table/asset/` (incl. `edit`, `ocr`), `table/local/` (`album`, `album_asset`, `asset`, `trashed_asset`), `table/remote/` (`album`, `album_asset`, `album_user`, `asset`, `cloud_id`, `exif`, `stack`), `table/memory/`, `table/people/` (`person`, `asset_face`), `table/user/` (`auth_user`, `metadata`, `partner`, `user`).
  - Generated `*.drift.dart` files accompany the tables (build_runner).
  - `Store` (`mobile/lib/entities/store.entity.dart`, `StoreKey` in `domain/models/store.model.dart`) is the key-value store (endpoint, tokens, user, settings).
- **Offline model:** the app is **usable offline for already-synced content** — timeline, albums, people, memories are read from Drift; remote images need network; uploads queue and retry. No explicit "offline mode" flag was found in the inspected files; connectivity is observed via `connectivity_plus` + native `ConnectivityApiImpl.kt`, and `NetworkRepository`/`network.service.dart` gate requests. (Deeper offline/queue semantics — e.g. what happens to an upload queued with no network — were not fully traced; see §11.)
- **State management:** Riverpod (`hooks_riverpod`, `flutter_hooks`) + Freezed models; routing `auto_route`; i18n `easy_localization` (generated keys via `mobile/bin/generate_keys.dart`); secure storage `flutter_secure_storage` (tokens); local notifications `flutter_local_notifications`; maps `maplibre_gl`; `photo_manager` for device media.

### 7.7 Albums / search / memories / people — API usage (mobile)

- Repositories per domain under `mobile/lib/repositories/` (`album_api_repository.dart`, `asset_api.repository.dart`, `auth_api.repository.dart`, `folder_api.repository.dart`, `partner_api.repository.dart`, `sessions_api.repository.dart`) and `mobile/lib/infrastructure/repositories/` (`remote_album`, `remote_asset`, `remote_exif`, `search_api`, `sync_api`, `memory`, `partner`, `map`, `user_api`, `local_album`, `local_asset`, `backup`, `storage`, `store`, `settings`, `cached_key_value`, `log`).
- **Albums:** `AlbumsApi` (generated) — list/create/get/update/delete, add/remove assets, manage users/roles. Local mirror in Drift `remote_album*` tables; timeline can be scoped per album (`timeline.repository.dart`: `localAlbum(...)`).
- **Search:** `SearchApi` via `search.service.dart` + `search_api.repository.dart` — metadata search, smart (CLIP) search, suggestions, explore, people/places. Search pages under `mobile/lib/pages/search/`, providers under `providers/search/`.
- **Memories:** `MemoriesApi` + `memory.repository.dart`; widgets `widgets/memories/`; memory assets synced via `SyncMemoryV1/V2` stream records.
- **People:** `PeopleApi`; faces/persons synced via `SyncPersonV1`, `SyncAssetFaceV1/V3`; person thumbnails via `GET /people/{id}/thumbnail`.
- **Trash/stacks/tags/views:** `TrashApi`, `StacksApi`, `TagsApi`, `ViewsApi` (`GET /view/folder`, `/view/folder/unique-paths` — folder-based browsing of external libraries).
- **Activities/comments:** `ActivitiesApi` (`/activities`).

### 7.8 WebSocket (mobile) — `mobile/lib/providers/websocket.provider.dart`

- `socket_io_client` (Dart) — `io(endpoint.origin, OptionBuilder().setPath("${endpoint.path}/socket.io").setTransports(['websocket']).setWebSocketConnector(NetworkRepository.createWebSocket).enableReconnection().enableForceNew()…)`.
- Connects only when authenticated; on connect refreshes server info; on disconnect marks disconnected.
- Listens: `AssetUploadReadyV1/V2` (batched with a 5 s debouncer, max 10 s — `_batchDebouncer`, `_batchedAssetUploadReady`), `AssetEditReadyV1/V2`, `on_album_update`, `on_asset_stack_update`, `on_asset_delete`, `on_asset_trash`, `on_asset_restore`, `on_asset_hidden`, `on_asset_update` (all → remote-change handler → triggers sync), `on_config_update` (refresh server info), `on_new_release`.
- This is the **live-update** path: websocket tells the app *something changed*; the app then pulls the authoritative delta via `POST /sync/stream` + ack. NOVA should copy this pattern (event → sync), not poll.

### 7.9 Android specifics

- Kotlin sources under `mobile/android/app/src/main/kotlin/app/alextran/immich/`: `MainActivity.kt`, `ImmichApp.kt`, `AppGlideModule.kt` (Glide), `NativeImage.kt`, `NativeBuffer.kt`, `background/` (Worker, PeriodicWorker, MediaObserver, engine lock), `connectivity/`, `core/` (ImmichPlugin, HttpClientManager, NetworkApiPlugin), `images/` (Local/RemoteImages, RawOrientation, ThumbHash), `passkey/`, `permission/`, `sync/`, `viewintent/`, `widget/` (home-screen widget via `home_widget`).
- Pigeon interfaces in `mobile/pigeon/` define the Flutter↔native contract.
- Share intent: `share_handler`, `share_intent_service.dart`, `pages/share_intent/`.

---

## 8. Deployment — `docker/`

- **Compose** (`docker/docker-compose.yml`, image tags `${IMMICH_VERSION:-release}`): 4 services —
  - `immich-server` (`ghcr.io/immich-app/immich-server`) — port 2283, volume `${UPLOAD_LOCATION}:/data`, depends on redis + database.
  - `immich-machine-learning` (`ghcr.io/immich-app/immich-machine-learning`) — volume `model-cache:/cache`, env `MACHINE_LEARNING_MODEL_REVISION: v2`.
  - `redis` — `docker.io/valkey/valkey:9`.
  - `database` — `ghcr.io/immich-app/postgres:14-vectorchord0.4.3-pgvectors0.2.0`, `POSTGRES_INITDB_ARGS: '--data-checksums'`, volume `${DB_DATA_LOCATION}:/var/lib/postgresql/data`, `shm_size: 128mb`.
  - Env via `.env` (`docker/example.env`): `UPLOAD_LOCATION`, `DB_USERNAME/PASSWORD/DATABASE_NAME`, `DB_DATA_LOCATION`, `IMMICH_VERSION`, etc.
- HW-accel overlays: `hwaccel.transcoding.yml` (nvenc/quicksync/rkmpp/vaapi/vaapi-wsl), `hwaccel.ml.yml` (armnn/cuda/rocm/openvino/rknn).
- `docker-compose.rootless.yml`, `docker-compose.dev.yml`, `prometheus.yml` (metrics).
- **NOVA implication:** NOVA needs *no* deployment of its own server — it talks to an existing Immich server. But the compose file is the canonical answer to "what is the server I'm talking to" (port 2283, `/api`, Postgres+Valkey+ML sidecar).

---

## 9. Key data structures (cheat sheet for NOVA)

| Structure | Where defined | Notes for NOVA |
|---|---|---|
| `AssetResponseDto` | `server/src/dtos/asset-response.dto.ts` | The asset JSON. `id` uuid, `type`, `thumbhash`, `localDateTime`, `fileCreatedAt`, `duration`, `isFavorite`, `livePhotoVideoId`, `stackId`, `exifInfo`, `files[]`, `people[]` (from faces) |
| `AssetMediaCreateDto` | `server/src/dtos/asset-media.dto.ts` | Upload fields; `assetData`/`sidecarData` parts |
| `AssetMediaSize` | same | `thumbnail` (360 WebP) / `preview` (1440 JPEG) / `fullsize` / `original` |
| `AssetBulkUploadCheckDto` | same | `{assets:[{id, checksum}]}` SHA-1 |
| `TimeBucketDto` / `TimeBucketAssetDto` | `server/src/dtos/time-bucket.dto.ts` | Timeline buckets |
| `MetadataSearchDto` / `SmartSearchDto` / `SearchResponseDto` | `server/src/dtos/search.dto.ts` | Search request/response |
| `Sync*V1/V2` | `server/src/dtos/sync.dto.ts` | Sync-stream record types + tombstones |
| `AlbumResponseDto`, `MemoryResponseDto`, `PersonResponseDto`, `TagResponseDto` | `server/src/dtos/*.dto.ts` | Albums/memories/people/tags |
| `LoginResponseDto` / `AuthDto` | `server/src/dtos/auth.dto.ts` | Session login |
| `ServerVersionResponseDto`, `ServerFeaturesDto`, `ServerConfigDto` | `server/src/dtos/server.dto.ts`, `config.dto.ts` | Feature detection — **check these before calling newer endpoints** |
| `JobName` / `QueueName` | `server/src/enum.ts` | Background pipeline |
| `Permission` | `server/src/enum.ts` | AuthZ model for API keys |
| Drift tables (mobile) | `mobile/lib/data/db/main/table/**` | Local mirror schema |

---

## 10. What NOVA PHOTOS can reuse (license-clean)

1. **The public REST API itself** — everything in `open-api/immich-openapi-specs.json` (OpenAPI 3.1.0, 202 paths). Talking to it over HTTP is normal use of the server, not copying code. Base: `{server}/api`; auth via session login (`POST /auth/login`) or API key (`x-api-key` header).
2. **The SDK-generation approach** — run `openapi-generator-cli` (dart generator, as in `open-api/bin/generate-dart-sdk.sh`) against the spec to produce NOVA's own typed Dart client. Regenerate, don't copy Immich's generated output (it's gitignored upstream anyway).
3. **The endpoint + auth patterns** — `/.well-known/immich` discovery → `GET /server/ping` probe → login → session; API-key auth with scoped permissions for headless/CLI use; `x-immich-checksum` + `POST /assets/bulk-upload-check` (SHA-1) for duplicate-safe upload; thumbnail size ladder (`thumbnail`/`preview`/`original`); HLS for video.
4. **The sync architecture pattern** — `POST /sync/stream` (JSONL) + `/sync/ack` checkpoints + Socket.IO (`/api/socket.io`, `AssetUploadReadyV2`, `ResourceEventV1`, `on_asset_*`) for live updates; local Drift mirror with time-bucketed timeline reads. *Pattern* reuse is fine; the implementation must be NOVA's own.
5. **The upload flow design** — multipart `assetData` + metadata fields; live-photo two-part upload then stack; retry-once on pre-response failure; 413 handling; progress + cancel tokens.
6. **The media-size defaults** — 360px WebP thumbs, 1440px JPEG previews, thumbhash placeholders — as *configuration choices* for what NOVA requests, not copied code.
7. **The feature-detection habit** — `GET /server/version`, `/server/features`, `/server/config` before using version-gated endpoints (the spec carries `HistoryBuilder` version annotations: added v1 / stable v2 / v3 changes).
8. **The layered architecture shape** (controllers → services → repositories; typed DTOs; job queues for heavy work) — as *design inspiration* for NOVA's own (much smaller) codebase.
9. **Docs** — `docs/docs/api.md` and the live OpenAPI spec are the contract reference. The demo server `https://demo.immich.app` (demo@immich.app / demo) is documented in the repo README — useful for read-only API probing without touching the user's server. (Not used in this investigation.)

## 11. What NOVA PHOTOS must NOT copy

1. **No Immich mobile code** — no Dart files from `mobile/lib/`, no Kotlin from `mobile/android/`, no Rust from `native/`, no generated `mobile/generated/openapi` output. NOVA is written from scratch against the API spec.
2. **No Immich server code** — no NestJS controllers/services/repositories, no Kysely schema/migrations, no storage-core path code. NOVA has no server component at all.
3. **No ML code/models** — no ONNX models, no `machine-learning/` Python, no InsightFace/CLIP code. ML stays server-side.
4. **No branding/assets** — name "Immich", logos, translations (`i18n/`), UI copy, or the exact UI layout/flows of the Immich app. NOVA gets its own name, branding, and UI.
5. **No AGPL-3.0 contamination by reference** — the investigation clone stays in `research/` only. If NOVA ever *did* incorporate AGPL code, the whole app would have to be AGPL-licensed with source offered; the project intent is a clean-room client, so keep the boundary: **API + spec in, code out**.
6. **Do not re-implement server-only features in-app** (transcoding, face clustering, CLIP embedding, EXIF extraction) — call the server endpoints that already do them.

---

## 12. What this changes about how NOVA should be built

1. **Start from the spec, not from screens.** Generate the Dart client from `immich-openapi-specs.json` first; the typed client (`AssetsApi`, `SearchApi`, `SyncApi`, …) *is* the app's data layer. Pin the spec version (3.4.0-rc.0 here) and check `/server/version` at runtime.
2. **Local-first timeline, not REST pagination.** The biggest design decision Immich made: timeline reads come from a local Drift mirror fed by `POST /sync/stream` + websocket invalidation — not from paging `GET /timeline/bucket` on scroll. NOVA should do the same (MVP: `/timeline/buckets` + `/timeline/bucket` first, then add sync-stream + Drift mirror; do not build an infinite-scroll REST pager as the permanent design).
3. **Upload = SHA-1 + bulk-check + multipart.** Compute SHA-1 per file, `POST /assets/bulk-upload-check`, upload only the missing ones as single multipart POSTs. No chunked upload exists server-side in this version — don't design for resumable chunks; design for retry-once + queue persistence instead.
4. **Session auth for the app; API keys for automation.** Mobile uses password login → session (cookie/token). NOVA should do the same for its interactive app, and reserve API keys (scoped permissions) for any headless/backup-agent mode.
5. **Thumbnails are cheap, originals are explicit.** Grid = `?size=thumbnail` (360 WebP), viewer = `?size=preview` (1440 JPEG), full file = `/original`. Render thumbhash placeholders while loading. Video = `/video/playback` (range) or HLS for long/adaptive playback.
6. **Background backup is the hard part — budget for it.** Foreground upload is straightforward HTTP; reliable background backup needs Android `WorkManager`/foreground service + `MediaObserver`-style new-media detection (Immich's Android side is native Kotlin + Pigeon + Rust, not pure Dart). Plan NOVA's backup engine as its own workstream, not an afterthought.
7. **Search is a server call, not local.** Smart (CLIP) search, metadata search, people/places — all `POST /search/*`. No on-device ML needed in v1.
8. **Feature-gate by server version.** The API evolves (v1→v2→v3 annotations; e.g. `deviceAssetId`/`deviceId` upload fields are legacy, slated for removal in v4.0; `size=original` on the thumbnail endpoint is deprecated). NOVA should read `/server/version` + `/server/features` and degrade gracefully.
9. **Keep NOVA's scope tight:** auth + server discovery, timeline (buckets), asset viewer, upload/backup, albums, search, memories, people, trash, shared links. Admin, libraries, jobs/queues, workflows/plugins, OAuth/passkeys are out of scope for v1.

---

## 13. What I could NOT verify (honest gaps)

- **Exact JSON shapes of several DTOs** — I verified endpoint paths/methods from the spec and key DTO files, but did not dump every request/response schema (e.g. exact paging fields of `SearchResponseDto`, `TimeBucketDto` query params, `SyncStreamDto` request body). These are all in `open-api/immich-openapi-specs.json` and should be read from the generated client, not assumed.
- **Server↔ML HTTP contract** — the exact endpoints/payloads between `machine-learning.repository.ts` and the FastAPI ML service were not fully traced; irrelevant for NOVA (internal sidecar), but noted.
- **Exact face-recognition model file names** (e.g. which Buffalo/Antelope ONNX files) — InsightFace lineage confirmed (`_ops.py`), specific model filenames not enumerated.
- **Mobile offline/queue edge semantics** — e.g. what precisely happens to queued uploads when the network drops mid-backup, and retry/backoff policy details beyond the single retry in `upload.repository.dart`. The offline model is "local Drift mirror + queued uploads", but failure-path details need runtime testing.
- **Runtime behavior** — nothing was run: no server started, no login performed, no API call made against a live Immich instance. All findings are static inspection of the 2026-11-21 `main` snapshot. Live verification (ping/login/upload/thumbnail against a real server) is a Stage-3 task.
- **Web app internals** — only a brief structural pass (`web/src/lib`, `web/src/routes`); web was not traced endpoint-by-endpoint.
- **Plugin/workflow system** — existence confirmed (Extism, `plugin.controller.ts`, `workflow.service.ts`), semantics not traced.
- **iOS-specific backup path** (`background_downloader` / URLSession) — read at the Dart level only; Android is NOVA's target, so this is acceptable, but the iOS code was not the focus.
- **Full `JobName` enum** — the list in `server/src/enum.ts` continues past the range I printed; the queue names are complete, individual job names should be re-read from the file if NOVA ever needs job control.

---

## Appendix — file index (where to look next)

| Topic | Start here |
|---|---|
| API contract (authoritative) | `research/immich/open-api/immich-openapi-specs.json` |
| Server entry / workers | `research/immich/server/src/main.ts`, `server/src/workers/` |
| Auth | `research/immich/server/src/services/auth.service.ts`, `server/src/middleware/auth.guard.ts` |
| Upload / media | `research/immich/server/src/controllers/asset-media.controller.ts`, `server/src/services/asset-media.service.ts`, `server/src/services/media.service.ts` |
| Jobs / queues | `research/immich/server/src/repositories/job.repository.ts`, `server/src/enum.ts` (`QueueName`, `JobName`) |
| Sync | `research/immich/server/src/controllers/sync.controller.ts`, `server/src/dtos/sync.dto.ts`, `server/src/services/sync.service.ts` |
| WebSocket | `research/immich/server/src/repositories/websocket.repository.ts` |
| Storage layout | `research/immich/server/src/cores/storage.core.ts` |
| DB schema | `research/immich/server/src/schema/tables/` (60 files), `server/src/schema/migrations/` (106) |
| ML | `research/immich/machine-learning/immich_ml/main.py`, `models/`, `config.py` |
| Mobile API layer | `research/immich/mobile/lib/services/api.service.dart`, `mobile/lib/services/auth.service.dart` |
| Mobile backup | `research/immich/mobile/lib/services/foreground_upload.service.dart`, `background_upload.service.dart`, `mobile/lib/providers/backup/backup.provider.dart`, `mobile/lib/repositories/upload.repository.dart` |
| Mobile sync/timeline | `research/immich/mobile/lib/infrastructure/repositories/sync_stream.repository.dart`, `timeline.repository.dart`, `mobile/lib/providers/websocket.provider.dart` |
| Mobile local DB | `research/immich/mobile/lib/data/db/main/` |
| Dart SDK generation | `research/immich/open-api/bin/generate-dart-sdk.sh`, `open-api/templates/`, `open-api/patch/` |
| Deployment | `research/immich/docker/docker-compose.yml` |
