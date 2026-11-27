# API Version Compatibility — Immich Server vs NOVA PHOTOS Client

> Research date: **2026-11-22**.
> Spec source: `open-api/immich-openapi-specs.json`, tag **v3.4.2**
> (OpenAPI 3.1.0, 199 paths / 287 ops), plus `main` at the same date
> (**3.4.0-rc.0**, 202 paths / 290 ops).
> Latest stable release: **v3.4.2** (2026-11-18).
> Demo server `https://demo.immich.app`: **3.4.2, featureLevel 2**
> (live check, no login).

## 1. What the spec targets

| Item | Value |
|---|---|
| Spec `info.version` (v3.4.2 tag) | `3.4.2` |
| Spec `info.version` (`main` branch) | `3.4.0-rc.0` |
| OpenAPI version | 3.1.0 |
| Base path | `/api` (default port 2283) |
| Latest GitHub release | `v3.4.2` (2026-11-18T20:14:51Z) |
| Release cadence | Roughly monthly minors; patches as needed |
| Versioning scheme | SemVer-ish `major.minor.patch`; **major bumps are the breaking ones** (v1 → v2 → v3). There is **no `/v1` vs `/v2` URL versioning** — one `/api` namespace, behaviour gated by the server version. |
| Downgrades | **Not supported** by Immich. A server upgraded to v3 cannot go back to v2 (database migrations are one-way). |

**NOVA target: Immich server `>= 3.0.0`, developed and tested against
`3.4.2`.** v2.x is explicitly *not* a target (see §3 for why).

## 2. How to detect the server version at runtime (feature detection)

Do this on **every launch and after every login** — never hard-code
assumed behaviour.

### 2.1 The two endpoints

| Endpoint | Auth | Returns |
|---|---|---|
| `GET /server/ping` | none | `{"res":"pong"}` — use as the connectivity check (only no-auth op in the spec). |
| `GET /server/version` | auth (any scheme) | `ServerVersionResponseDto`: `major`, `minor`, `patch`, `prerelease`, **`featureLevel`**. Demo: `{major:3, minor:4, patch:2, prerelease:null, featureLevel:2}`. |
| `GET /server/features` | auth | `ServerFeaturesDto` booleans: `smartSearch`, `facialRecognition`, `map`, `trash`, `oauth`, `passwordLogin`, `email`, `search`, `sidecar`, `ocr`, `duplicateDetection`, `reverseGeocoding`, `backups`, `configFile`, `importFaces`, `oauthAutoLaunch`, `realtimeTranscoding`. |
| `GET /server/about` | auth | Full build info incl. `version` string, `repository`, `sourceRef`, component versions (ffmpeg, exiftool, …). |

### 2.2 The rules

1. **`featureLevel` is the compatibility signal, not the version
   number.** The spec's own description: *"Highest feature level
   supported by the server, which increments independently of the
   release version."* A client should branch on `featureLevel` for
   capability checks where the spec defines one, and on
   `major`/`minor` otherwise. (The exact featureLevel→feature mapping
   is **not published in the spec** — UNKNOWN; in practice v3.4.2
   reports 2. Treat `featureLevel` as a monotonic "newer than" value
   and combine it with `/server/features`.)
2. **Gate every optional feature on `/server/features`.**
   Smart search, facial recognition, map, trash, OCR, duplicate
   detection, reverse geocoding and sidecar can all be off (or
   unsupported on the server's hardware/build). If `smartSearch` is
   false, hide semantic search and fall back to metadata search. If
   `trash` is false, deletes are permanent — warn the user.
3. **Minimum supported server: v3.0.0.** If `major < 3`, show a
   blocking "server too old — please upgrade your Immich server to
   v3.x" screen. Do not attempt v2 compatibility shims (see §3).
4. **Warn, don't block, on newer majors.** If `major > 3`, the client
   may be talking to a future v4: show a non-blocking "this app was
   built for Immich v3; some features may not work" banner and keep
   working — the client must tolerate unknown fields (see §4).
5. **Re-check after `on_server_version` / `on_config_update` socket
   events** — the server can be upgraded under a running client.

## 3. Breaking changes you must know about

### 3.1 v2 → v3 (v3.0.0, released 2026-07-02) — the big one

The v3.0.0 release notes state that many breaking changes "affect only
third-party tools" using the API. For a client author, they are the
whole story. Sources: Immich v3.0.0 release notes / "Migrating to v3"
guide (via third-party summaries — softwares-academy.com, gjcourt
homelab runbook, immich-go PR #1377, Immich-Android-TV CLAUDE.md;
the official release notes themselves were not re-fetched verbatim
here — **treat the list below as corroborated-by-multiple-independent-
clients, not as a quote of the official notes**).

| Change in v3 | Impact on a client |
|---|---|
| **Server only works with its matching major version of the client.** v3 server ⇔ v3-era client. The official mobile app enforces this; NOVA must do the same check itself. | Enforce `major == 3` (see §2.2 rule 3). |
| **Removed endpoints**: `/assets/random`, `/sync/full-sync`, `/server/theme`, … (exact full list UNKNOWN from the sources consulted — the v3.4.2 spec is the authority for what exists *now*). | Never call an endpoint that isn't in the v3.4.2 spec. |
| **`GET /albums/{id}` no longer embeds `assets`.** Only `assetCount`. | List album contents via `POST /search/metadata` with `albumIds`. |
| **`AlbumResponseDto` lost `owner`/`ownerId`.** Ownership is in `albumUsers[]` (first entry = owner). | Read ownership from `albumUsers`. |
| **`GET /albums` query param `shared` removed** (no alias). Replaced by `isShared` + new `isOwned`. | Use `isShared`/`isOwned`. |
| **`deviceId` and `deviceAssetId` removed from `AssetMediaCreateDto`** (upload). | Do not send them. (Server currently ignores unknown fields, but strict validation may land.) |
| **`replaceAsset` removed.** | No asset-replace flow; upload a new asset instead. |
| **`duration` changed type: number → string** (`"HH:MM:SS.mmm"`), in both requests and responses. | Parse as a duration string; do not assume numeric. |
| **Error response shape changed**: class-validator → Zod. `{error, statusCode}` removed; structured Zod issues; correlation id moved to the `X-Correlation-ID` response header. | Parse errors defensively (§4). |
| **Legacy timeline removed from the official mobile app** (replaced by the time-bucket timeline). | NOVA uses time buckets — the current mechanism. |
| **OAuth: insecure HTTP requests blocked by default**; `oauth.issuerUrl` must parse as a valid URL. | Only offer OAuth on `https://` servers. |
| **pgvecto.rs vector extension dropped** (server-side, VectorChord required); ML needs x86-64-v2 CPU. | Server-admin concern, not client — but a v3 server that failed its DB migration will not serve smart search; gate on `/server/features`. |
| **Metric names changed** (underscores → dots). | Observability only; irrelevant to NOVA. |
| **Env-var removals** (`IMMICH_MACHINE_LEARNING_PING_TIMEOUT`, `MACHINE_LEARNING_PRELOAD__CLIP`, …). | Server-admin concern. |

### 3.2 v3.x minors (3.0 → 3.4.2) — additive, with deprecations

Within v3, changes have been additive plus deprecations tracked in the
spec's `x-immich-history` extension. Notable items visible in the
v3.4.2 spec:

- **`SearchAssetResponseDto.total` deprecated (v3.0.0)** — page with
  `nextPage`/`nextCursor`, never with `total`.
- **Thumbnail `size=original` deprecated (v3)** — use
  `GET /assets/{id}/original`.
- **`ApiKeyCreateResponseDto.apiKey` deprecated (v3.2.0)**.
- **`AssetResponseDto.resized` deprecated (v1.113.0)** and
  `libraryId` deprecated (v1) — still present, do not use.
- **125 deprecated schema fields** in total across the spec.
- **New in v3.4**: `Workflows` + `Plugins` (8 + 4 ops, Alpha) — the
  automation system. NOVA v1 ignores these.
- **`main` (3.4.0-rc.0) vs v3.4.2 diff**: `main` contains 3 extra
  operations that are **not** in the v3.4.2 release spec —
  `GET /admin/config/storage-template`,
  `POST /admin/config/storage-template/preview`,
  `POST /admin/notifications/templates/{name}/preview`. They were
  presumably added after the 3.4.2 cut (or reverted). **Do not use
  them** until they appear in a release spec.

### 3.3 Announced future breakage (already in the spec text)

Several operations carry this description verbatim in v3.4.2:

> "This endpoint now also supports PATCH, in addition to PUT. PATCH
> will become the default in v4, and then PUT will be dropped in v5.
> Please migrate accordingly."

Affected: album update, person update, tag update, and related PUT
endpoints (the note appears on 5 operations in the spec). **NOVA
should prefer `PATCH` wherever both verbs exist**, so the v4
transition is a non-event. Where only `PUT` exists, keep using it
and expect a v4 migration note later.

### 3.4 v1 → v2 (historical, for context only)

v2 (2024–2025 era) introduced granular API-key permissions
(v1.138.0), the sync-stream API, and the current search pagination.
NOVA does not target v2, so no v2 compatibility work is needed. If a
user reports a v2 server, the answer is "upgrade the server", not a
client shim.

## 4. What a client must do to stay compatible

1. **Pin the spec per release; regenerate models per release.**
   Keep the fetched spec (`spec-v3.4.2.json`) in the repo. When Immich
   cuts a new release, diff the new spec against the old one
   (`main` vs `v3.4.2` diffed cleanly in this research: 3 ops) and
   review every `Deprecated`/`Removed` marker before bumping the
   supported version.
2. **Tolerate unknown fields.** Decode DTOs leniently (ignore unknown
   JSON keys; treat every field as optional with a sane default where
   the spec allows). Immich adds fields in minors constantly.
3. **Never use deprecated fields.** The 125 deprecated fields and 10
   deprecated operations can disappear in the next major. The
   catalogue flags them; CI should grep generated models for
   `deprecated: true` in the spec.
4. **Branch on `major` + `/server/features`, never on a version
   string.** Version strings include `-rc` suffixes; `featureLevel`
   and feature flags are the designed signals.
5. **Handle the Zod error shape tolerantly.** Read the status code,
   then `message` (string or array), then raw body; log
   `X-Correlation-ID` for bug reports. Never assert an exact error
   JSON structure.
6. **Prefer `PATCH` over `PUT`** where both exist (§3.3).
7. **Use the sync stream, not polling, for change tracking**
   (`POST /sync/stream` + ack) — it is versioned by server-side
   checkpoints, so it survives minor upgrades.
8. **Test against at least two server versions** before release: the
   latest stable (3.4.2 now) and the oldest supported (3.0.x).
   The drolosoft MCP project's live-test rig (real Immich in Docker,
   every tool exercised) is a good template.
9. **Surface version mismatch to the user in plain language.**
   "Your server is Immich 2.7.5 — NOVA needs 3.0 or newer. Ask your
   server admin to upgrade." — with a link to the release notes.
10. **Watch the release notes feed.** Immich publishes release notes
    on GitHub (`immich-app/immich/releases`) and a migration guide
    for each major. Subscribe (or have the Stage-4/ops work add a
    monthly check) — a v4 announcement is the trigger to start the
    PUT→PATCH migration and re-verify the whole catalogue.

## 5. Compatibility matrix (NOVA v1)

| Server version | Support | Notes |
|---|---|---|
| v1.x | ❌ No | Ancient; no granular permissions, no sync stream. |
| v2.x (incl. 2.7.5) | ❌ No (blocked with message) | Albums embed assets; `duration` is a number; old error shape; `deviceId`/`deviceAssetId` in upload; `GET /assets/random` exists. Supporting both v2 and v3 doubles the client. |
| **v3.0.x – v3.4.2** | ✅ **Supported** | Target range. Behaviour differences inside the range are handled by `/server/features` + `featureLevel` gating. |
| v3.5+ (future minors) | ✅ Expected (verify) | Additive by policy; re-diff the spec per release, check for new deprecations. |
| v4.x (future major) | ⚠️ Unknown — warn, don't crash | Expect PUT→PATCH removal (§3.3) and further removals. Re-catalogue before claiming support. |

## 6. Open questions / unknowns (do not guess — verify in Stage 4)

- **Exact `featureLevel` → feature mapping.** The spec defines the
  field but no published table maps levels to capabilities. NOVA
  should log the value and rely on `/server/features` instead.
- **Full v3.0 removed-endpoint list.** The official v3.0.0 release
  notes were consulted via third-party summaries only; if NOVA needs
  the exhaustive list (e.g. for a v2-compat audit), fetch the release
  notes from GitHub directly.
- **WebSocket auth handshake.** The Socket.IO auth mechanism is not
  in the OpenAPI spec; verify against a live server (see catalogue
  §5.17).
- **Server-enforced upload size limit / rate limits.** Neither is
  documented in the spec; probe against the target server during QA.
- **Whether `main`-only admin operations** (storage-template preview,
  notification-template preview) land in v3.5 or were reverted —
  check the next release spec.

## 7. Sources

- Spec: `https://raw.githubusercontent.com/immich-app/immich/v3.4.2/open-api/immich-openapi-specs.json`
  (974,791 bytes, HTTP 200, 2026-11-22) and `main`
  (`3.4.0-rc.0`, 990,700 bytes).
- Latest release: GitHub API `repos/immich-app/immich/releases/latest`
  → `v3.4.2`, 2026-11-18T20:14:51Z.
- Demo server: `GET https://demo.immich.app/api/server/version` →
  `{"major":3,"minor":4,"patch":2,"prerelease":null,"featureLevel":2}`.
- v3 breaking changes: Immich v3.0.0 release notes / "Migrating to v3"
  guide as summarised by softwares-academy.com ("Immich 3.0 Upgrade:
  Breaking Changes and Safe Steps"), gjcourt/homelab runbook
  (v2.7.5 → v3.0.1), simulot/immich-go PR #1377 ("fix: immich v3
  support"), Dos2Locos/Immich-Android-TV CLAUDE.md (v3.0.0
  compatibility notes). These are independent client authors
  corroborating the same changes; the official notes should be
  re-read verbatim before any v2-support decision.
- `x-immich-history` / deprecation counts computed from the v3.4.2
  spec itself (125 deprecated fields, 10 deprecated operations, 154
  distinct permissions).
