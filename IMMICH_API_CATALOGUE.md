# Immich API Catalogue — NOVA PHOTOS (Stage 3)

> **Source of truth:** the official OpenAPI specification
> `open-api/immich-openapi-specs.json` from the Immich monorepo
> (`immich-app/immich`), **tag `v3.4.2`**, fetched 2026-11-22.
> Every endpoint in §3 below was generated mechanically from that file —
> nothing was hand-typed, so method/path/summary/permission/state match the
> spec exactly. Where the spec is silent, the entry says **UNKNOWN** rather
> than guessing.
>
> - Spec info: OpenAPI **3.1.0**, title `Immich`, version **`3.4.2`**
> - **199 paths, 287 operations, 457 schemas**, 43 tags
> - Latest stable release at research time: **v3.4.2** (published 2026-11-18)
> - Public demo server `https://demo.immich.app` reports
>   `GET /api/server/version` → `{"major":3,"minor":4,"patch":2,"prerelease":null,"featureLevel":2}`
>   (checked live, no login, 2026-11-22)
> - Live docs: https://api.immich.app/ (interactive reference);
>   source docs: https://docs.immich.app/
> - Raw spec URLs (fetched, HTTP 200):
>   - `https://raw.githubusercontent.com/immich-app/immich/v3.4.2/open-api/immich-openapi-specs.json`
>   - `main` branch at fetch time was `3.4.0-rc.0` (202 paths, 290 ops) — it
>     contains 3 extra admin operations not in v3.4.2 (see
>     `API_VERSION_COMPATIBILITY.md`); this catalogue uses the **v3.4.2
>     release spec** as canonical.
> - Base URL: every server exposes the API under **`/api`** on port **2283**
>   by default, i.e. `http(s)://<host>:2283/api`. The spec's `servers` field
>   is just `[{ "url": "/api" }]`.
> - Local copies kept with this research: `spec-v3.4.2.json`,
>   `spec-main.json`, `endpoints-v342.txt` (full machine dump),
>   `key-schemas.txt`, `key-schemas2.txt`, `websocket.ts`.

## 1. How to read this catalogue

- **Permission** = the `x-immich-permission` value on the operation, e.g.
  `asset.read`. Immich has had **granular API-key permissions since
  v1.138.0**; the v3.4.2 spec declares **154 distinct permissions**. A key
  (or session) lacking the permission gets **403** — the client must request
  the permissions it needs when the key is created (see §2.1).
- **State** = `x-immich-state`: `Stable` (200 ops), `Alpha` (43),
  `Beta` (9), `Deprecated` (10), `Internal` (2), blank (23). Prefer
  `Stable`; treat `Alpha` as subject to change without notice.
- **Auth** — every operation except one accepts all three schemes
  (bearer / cookie / api_key). The single no-auth operation is
  `GET /server/ping` (returns `{"res":"pong"}`).
- **Error responses are NOT documented in the spec.** The spec only
  declares `200` (202 ops), `201` (31), `204` (55) and a single `404`.
  Real error shapes (400 validation, 401, 403, 404) come from the NestJS/Zod
  runtime and must be handled defensively — see §4.
- **Rate limits: UNKNOWN / none documented.** No rate-limit headers,
  `429` responses, or limits appear anywhere in the spec. Assume the
  server does not rate-limit the API, but do not hammer it — bulk work
  belongs in the bulk endpoints.
- **IDs are UUIDv4** (the spec enforces the UUID pattern on path params).
- **`key` / `slug` query params** appear on many asset/album endpoints:
  they carry a shared-link key/slug so the same endpoint can serve
  public shared links. A normal client omits them.

## 2. Authentication & sessions

### 2.1 The three auth schemes (spec `components.securitySchemes`)

| Scheme | Where | Notes |
|---|---|---|
| `bearer` | `Authorization: Bearer <JWT>` | Access token from `POST /auth/login`. Short-lived session JWT. |
| `cookie` | Cookie `immich_access_token` | Same JWT as a cookie; what the web UI uses. |
| `api_key` | Header `x-api-key: <secret>` | Long-lived key created in Account Settings → API Keys, or via the API itself. **Granular permissions** (154 scopes). Secret is shown **once** at creation (`ApiKeyCreateResponseDto.secret`). |

All three are accepted on (almost) every authenticated operation — the
server does not force one scheme per endpoint.

### 2.2 Auth endpoints (`Authentication`, 17 ops)

| Method & path | Purpose / notes |
|---|---|
| `POST /auth/login` | Email + password (`LoginCredentialDto`: `email`, `password`) → `LoginResponseDto`: `accessToken`, `userId`, `userEmail`, `name`, `isAdmin`, `isOnboarded`, `shouldChangePassword`, `profileImagePath`. **No refresh token in the response** — see §6.1. |
| `POST /auth/logout` | Invalidate current session. |
| `POST /auth/validateToken` | Validate the current auth method; returns `ValidateAccessTokenResponseDto`. Use on app start to check a stored token. |
| `GET /auth/status` | Current session info: whether the user has a password, whether the session can access locked assets. |
| `POST /auth/change-password` | Change password (`auth.changePassword`). |
| `POST /auth/admin-sign-up` | Create the first (admin) account on a fresh server. |
| `POST /auth/pin-code`, `PUT /auth/pin-code`, `DELETE /auth/pin-code` | PIN code for locked assets (`pinCode.*` permissions). |
| `POST /auth/session/lock`, `POST /auth/session/unlock` | Lock/unlock the session against locked (hidden) assets. |
| `POST /oauth/authorize`, `POST /oauth/callback`, `GET /oauth/mobile-redirect`, `POST /oauth/link`, `POST /oauth/unlink`, `POST /oauth/backchannel-logout` | OAuth/OIDC login flow (server must have OAuth configured; `GET /server/config` reports `oauthEnabled`). Mobile uses `oauth/mobile-redirect`. |
| `POST /admin/auth/unlink-all` | Admin: unlink all OAuth accounts. |

### 2.3 API keys (`API keys`, 7 ops)

`GET /api-keys` · `POST /api-keys` (body `ApiKeyCreateDto`: `name`,
`permissions[]` — **required**) · `GET /api-keys/me` ·
`GET /api-keys/{id}` · `PUT /api-keys/{id}` (`ApiKeyUpdateDto`) ·
`DELETE /api-keys/{id}` → 204 · `POST /api-keys/{id}/rotate` → 201
(new secret, old one invalidated immediately).

### 2.4 Sessions (`Sessions`, 6 ops) & passkeys (`Passkeys`, 8 ops)

- `GET /sessions` (list own sessions), `POST /sessions` (create a
  **child session**, used for casting), `DELETE /sessions` (delete all),
  `GET/PUT/DELETE /sessions/{id}`, `POST /sessions/{id}/lock`.
  Sessions are the server-side record of logins/devices — **there is no
  separate "devices" API in v3.4.2** (no path contains `device`).
- Passkeys (WebAuthn): `GET /passkeys`, registration
  `start`/`finish`, authentication `start`/`finish`,
  `GET/PATCH/DELETE /passkeys/{id}`. Relevant to NOVA only if we add
  biometric/passkey login later; not needed for v1.

### 2.5 User profile (`Users`, 16 ops)

- `GET /users/me` → `UserResponseDto` (id, email, name, profile image,
  quota, admin flag, etc.). **First call after login.**
- `PUT /users/me` (update own profile), `POST /users/profile-image`
  (upload avatar), `DELETE /users/profile-image`,
  `GET /users/{id}/profile-image` (fetch any user's avatar).
- `GET /users/me/preferences`, `PUT /users/me/preferences`
  (timeline/album preferences), `GET /users/me/onboarding`,
  `PUT /users/me/onboarding`, `DELETE /users/me/onboarding`.
- `GET /users/me/license`, `PUT /users/me/license` (Immich license).
- `GET /users/me/calendar-heatmap` — per-day asset counts for a
  calendar heatmap (also `/admin/users/{id}/calendar-heatmap`).
- Admin user management lives under `Users (admin)` (11 ops):
  `GET /users`, `POST /users`, `GET/PUT/DELETE /users/{id}`,
  `GET /users/{id}/sessions`, `POST /users/{id}/restore`, etc.
  **NOVA v1 does not need admin user management.**

## 3. Endpoint catalogue (generated from spec v3.4.2)

The table below is generated from the spec — one row per operation. **Permission** is `x-immich-permission` (blank = no permission declared in the spec; auth is still required unless noted). **State** is `x-immich-state`. `(no-auth)` marks the single operation with empty `security`.

### API keys — 7 operations

| Method | Path | Summary | Permission | State |
|---|---|---|---|---|
| GET | `/api-keys` | List all API keys | `apiKey.read` | Stable |
| POST | `/api-keys` | Create an API key | `apiKey.create` | Stable |
| GET | `/api-keys/me` | Retrieve the current API key | `—` | Stable |
| DELETE | `/api-keys/{id}` | Delete an API key | `apiKey.delete` | Stable |
| GET | `/api-keys/{id}` | Retrieve an API key | `apiKey.read` | Stable |
| PUT | `/api-keys/{id}` | Update an API key | `apiKey.update` | Stable |
| POST | `/api-keys/{id}/rotate` | Rotate an API key | `apiKey.rotate` | — |

### Activities — 4 operations

| Method | Path | Summary | Permission | State |
|---|---|---|---|---|
| GET | `/activities` | List all activities | `activity.read` | Stable |
| POST | `/activities` | Create an activity | `activity.create` | Stable |
| GET | `/activities/statistics` | Retrieve activity statistics | `activity.statistics` | Stable |
| DELETE | `/activities/{id}` | Delete an activity | `activity.delete` | Stable |

### Albums — 13 operations

| Method | Path | Summary | Permission | State |
|---|---|---|---|---|
| GET | `/albums` | List all albums | `album.read` | Stable |
| POST | `/albums` | Create an album | `album.create` | Stable |
| PUT | `/albums/assets` | Add assets to albums | `albumAsset.create` | Stable |
| GET | `/albums/statistics` | Retrieve album statistics | `album.statistics` | Stable |
| DELETE | `/albums/{id}` | Delete an album | `album.delete` | Stable |
| GET | `/albums/{id}` | Retrieve an album | `album.read` | Stable |
| PATCH | `/albums/{id}` | Update an album | `album.update` | Stable |
| DELETE | `/albums/{id}/assets` | Remove assets from an album | `albumAsset.delete` | Stable |
| PUT | `/albums/{id}/assets` | Add assets to an album | `albumAsset.create` | Stable |
| GET | `/albums/{id}/map-markers` | Retrieve album map markers | `album.read` | — |
| DELETE | `/albums/{id}/user/{userId}` | Remove user from album | `albumUser.delete` | Stable |
| PUT | `/albums/{id}/user/{userId}` | Update user role | `albumUser.update` | Stable |
| PUT | `/albums/{id}/users` | Share album with users | `albumUser.create` | Stable |

### Asset files — 4 operations

| Method | Path | Summary | Permission | State |
|---|---|---|---|---|
| GET | `/asset-files` | Search asset files | `assetFile.read` | Alpha |
| DELETE | `/asset-files/{id}` | Delete an asset file | `assetFile.delete` | Alpha |
| GET | `/asset-files/{id}` | Retrieve an asset file | `assetFile.read` | Alpha |
| GET | `/asset-files/{id}/download` | Download an asset file | `assetFile.download` | Alpha |

### Assets — 26 operations

| Method | Path | Summary | Permission | State |
|---|---|---|---|---|
| DELETE | `/assets` | Delete assets | `asset.delete` | Stable |
| POST | `/assets` | Upload asset | `asset.upload` | Stable |
| PUT | `/assets` | Update assets | `asset.update` | Stable |
| POST | `/assets/bulk-upload-check` | Check bulk upload | `asset.upload` | Stable |
| PUT | `/assets/copy` | Copy asset | `asset.copy` | Stable |
| POST | `/assets/jobs` | Run an asset job | `job.create` | Stable |
| DELETE | `/assets/metadata` | Delete asset metadata | `asset.update` | Beta |
| PUT | `/assets/metadata` | Upsert asset metadata | `asset.update` | Beta |
| GET | `/assets/statistics` | Get asset statistics | `asset.statistics` | Stable |
| GET | `/assets/{id}` | Retrieve an asset | `asset.read` | Stable |
| PUT | `/assets/{id}` | Update an asset | `asset.update` | Stable |
| DELETE | `/assets/{id}/edits` | Remove edits from an existing asset | `asset.edit.delete` | Beta |
| GET | `/assets/{id}/edits` | Retrieve edits for an existing asset | `asset.edit.get` | Beta |
| PUT | `/assets/{id}/edits` | Apply edits to an existing asset | `asset.edit.create` | Beta |
| GET | `/assets/{id}/metadata` | Get asset metadata | `asset.read` | Stable |
| PUT | `/assets/{id}/metadata` | Update asset metadata | `asset.update` | Stable |
| DELETE | `/assets/{id}/metadata/{key}` | Delete asset metadata by key | `asset.update` | Stable |
| GET | `/assets/{id}/metadata/{key}` | Retrieve asset metadata by key | `asset.read` | Stable |
| GET | `/assets/{id}/ocr` | Retrieve asset OCR data | `asset.read` | Stable |
| GET | `/assets/{id}/original` | Download original asset | `asset.download` | Stable |
| GET | `/assets/{id}/thumbnail` | View asset thumbnail | `asset.view` | Stable |
| GET | `/assets/{id}/video/playback` | Play asset video | `asset.view` | Stable |
| GET | `/assets/{id}/video/stream/main.m3u8` | Get HLS main playlist | `asset.view` | Alpha |
| DELETE | `/assets/{id}/video/stream/{sessionId}` | End HLS streaming session | `asset.view` | Alpha |
| GET | `/assets/{id}/video/stream/{sessionId}/{variantIndex}/playlist.m3u8` | Get HLS media playlist | `asset.view` | Alpha |
| GET | `/assets/{id}/video/stream/{sessionId}/{variantIndex}/{filename}` | Get HLS segment or init file | `asset.view` | Alpha |

### Authentication — 17 operations

| Method | Path | Summary | Permission | State |
|---|---|---|---|---|
| POST | `/auth/admin-sign-up` | Register admin | `—` | Stable |
| POST | `/auth/change-password` | Change password | `auth.changePassword` | Stable |
| POST | `/auth/login` | Login | `—` | Stable |
| POST | `/auth/logout` | Logout | `—` | Stable |
| DELETE | `/auth/pin-code` | Reset pin code | `pinCode.delete` | Stable |
| POST | `/auth/pin-code` | Setup pin code | `pinCode.create` | Stable |
| PUT | `/auth/pin-code` | Change pin code | `pinCode.update` | Stable |
| POST | `/auth/session/lock` | Lock auth session | `—` | Stable |
| POST | `/auth/session/unlock` | Unlock auth session | `—` | Stable |
| GET | `/auth/status` | Retrieve auth status | `—` | Stable |
| POST | `/auth/validateToken` | Validate access token | `—` | Stable |
| POST | `/oauth/authorize` | Start OAuth | `—` | Stable |
| POST | `/oauth/backchannel-logout` | Backchannel OAuth logout | `—` | — |
| POST | `/oauth/callback` | Finish OAuth | `—` | Stable |
| POST | `/oauth/link` | Link OAuth account | `—` | Stable |
| GET | `/oauth/mobile-redirect` | Redirect OAuth to mobile | `—` | Stable |
| POST | `/oauth/unlink` | Unlink OAuth account | `—` | Stable |

### Authentication (admin) — 1 operations

| Method | Path | Summary | Permission | State |
|---|---|---|---|---|
| POST | `/admin/auth/unlink-all` | Unlink all OAuth accounts | `adminAuth.unlinkAll` | Stable |

### Cluster groups — 8 operations

| Method | Path | Summary | Permission | State |
|---|---|---|---|---|
| GET | `/cluster-groups/requests` | Retrieve cluster group requests | `clusterGroupRequest.read` | — |
| DELETE | `/cluster-groups/requests/{id}` | Decline a cluster group request | `clusterGroupRequest.delete` | — |
| POST | `/cluster-groups/requests/{id}/accept` | Accept a cluster group request | `clusterGroupRequest.create` | — |
| POST | `/cluster-groups/{id}/leave` | Leave a cluster group | `clusterGroup.leave` | — |
| POST | `/cluster-groups/{id}/regenerate-people` | Regenerate people of users in cluster group | `clusterGroup.admin` | — |
| GET | `/cluster-groups/{id}/requests` | Retrieve the requests sent by a cluster group | `clusterGroupRequest.read` | — |
| PUT | `/cluster-groups/{id}/requests` | Create a cluster group request | `clusterGroupRequest.create` | — |
| GET | `/cluster-groups/{id}/users` | Retrieve the users of a cluster group | `clusterGroup.read` | — |

### Config (admin) — 3 operations

| Method | Path | Summary | Permission | State |
|---|---|---|---|---|
| GET | `/admin/config` | Get the admin configuration | `adminConfig.read` | Alpha |
| PUT | `/admin/config` | Update the system configuration | `adminConfig.update` | Alpha |
| GET | `/admin/config/defaults` | Get the system configuration defaults | `adminConfig.read` | Alpha |

### Config (public) — 2 operations

| Method | Path | Summary | Permission | State |
|---|---|---|---|---|
| GET | `/public/config` | Get the public configuration | `—` | Alpha |
| GET | `/public/config/defaults` | Get the public configuration defaults | `—` | Alpha |

### Config (user) — 2 operations

| Method | Path | Summary | Permission | State |
|---|---|---|---|---|
| GET | `/config` | Get the configuration with user visibility | `userConfig.read` | Alpha |
| GET | `/config/defaults` | Get the default configuration with user visibility | `userConfig.read` | Alpha |

### Database Backups (admin) — 5 operations

| Method | Path | Summary | Permission | State |
|---|---|---|---|---|
| DELETE | `/admin/database-backups` | Delete database backup | `backup.delete` | Alpha |
| GET | `/admin/database-backups` | List database backups | `maintenance` | Alpha |
| POST | `/admin/database-backups/start-restore` | Start database backup restore flow | `—` | Alpha |
| POST | `/admin/database-backups/upload` | Upload database backup | `backup.upload` | Alpha |
| GET | `/admin/database-backups/{filename}` | Download database backup | `backup.download` | Alpha |

### Download — 2 operations

| Method | Path | Summary | Permission | State |
|---|---|---|---|---|
| POST | `/download/archive` | Download asset archive | `asset.download` | Stable |
| POST | `/download/info` | Retrieve download information | `asset.download` | Stable |

### Duplicates — 4 operations

| Method | Path | Summary | Permission | State |
|---|---|---|---|---|
| DELETE | `/duplicates` | Delete duplicates | `duplicate.delete` | Stable |
| GET | `/duplicates` | Retrieve duplicates | `duplicate.read` | Stable |
| POST | `/duplicates/resolve` | Resolve duplicate groups | `duplicate.delete` | Alpha |
| DELETE | `/duplicates/{id}` | Dismiss a duplicate group | `duplicate.delete` | Stable |

### Faces — 4 operations

| Method | Path | Summary | Permission | State |
|---|---|---|---|---|
| GET | `/faces` | Retrieve faces for asset | `face.read` | Stable |
| POST | `/faces` | Create a face | `face.create` | Stable |
| DELETE | `/faces/{id}` | Delete a face | `face.delete` | Stable |
| PUT | `/faces/{id}` | Re-assign a face to another person | `face.update` | Stable |

### Jobs — 3 operations

| Method | Path | Summary | Permission | State |
|---|---|---|---|---|
| GET | `/jobs` | Retrieve queue counts and status ⚠️ DEPRECATED | `job.read` | Deprecated |
| POST | `/jobs` | Create a manual job | `job.create` | Stable |
| PUT | `/jobs/{name}` | Run jobs ⚠️ DEPRECATED | `job.create` | Deprecated |

### Libraries — 8 operations

| Method | Path | Summary | Permission | State |
|---|---|---|---|---|
| GET | `/libraries` | Retrieve libraries | `library.read` | Stable |
| POST | `/libraries` | Create a library | `library.create` | Stable |
| DELETE | `/libraries/{id}` | Delete a library | `library.delete` | Stable |
| GET | `/libraries/{id}` | Retrieve a library | `library.read` | Stable |
| PUT | `/libraries/{id}` | Update a library | `library.update` | Stable |
| POST | `/libraries/{id}/scan` | Scan a library | `library.update` | Stable |
| GET | `/libraries/{id}/statistics` | Retrieve library statistics | `library.statistics` | Stable |
| POST | `/libraries/{id}/validate` | Validate library settings | `—` | Stable |

### Maintenance (admin) — 9 operations

| Method | Path | Summary | Permission | State |
|---|---|---|---|---|
| GET | `/admin/integrity/report` | Get integrity report by type | `maintenance` | Alpha |
| DELETE | `/admin/integrity/report/{id}` | Delete integrity report item | `maintenance` | Alpha |
| GET | `/admin/integrity/report/{id}/file` | Download flagged file | `maintenance` | Alpha |
| GET | `/admin/integrity/report/{type}/csv` | Export integrity report by type as CSV | `maintenance` | Alpha |
| GET | `/admin/integrity/summary` | Get integrity report summary | `maintenance` | Alpha |
| POST | `/admin/maintenance` | Set maintenance mode | `maintenance` | Alpha |
| GET | `/admin/maintenance/detect-install` | Detect existing install | `maintenance` | Alpha |
| POST | `/admin/maintenance/login` | Log into maintenance mode | `—` | Alpha |
| GET | `/admin/maintenance/status` | Get maintenance mode status | `—` | Alpha |

### Map — 2 operations

| Method | Path | Summary | Permission | State |
|---|---|---|---|---|
| GET | `/map/markers` | Retrieve map markers | `map.read` | Stable |
| GET | `/map/reverse-geocode` | Reverse geocode coordinates | `map.search` | Stable |

### Memories — 8 operations

| Method | Path | Summary | Permission | State |
|---|---|---|---|---|
| GET | `/memories` | Retrieve memories | `memory.read` | Stable |
| POST | `/memories` | Create a memory | `memory.create` | Stable |
| GET | `/memories/statistics` | Retrieve memories statistics | `memory.statistics` | Stable |
| DELETE | `/memories/{id}` | Delete a memory | `memory.delete` | Stable |
| GET | `/memories/{id}` | Retrieve a memory | `memory.read` | Stable |
| PUT | `/memories/{id}` | Update a memory | `memory.update` | Stable |
| DELETE | `/memories/{id}/assets` | Remove assets from a memory | `memoryAsset.delete` | Stable |
| PUT | `/memories/{id}/assets` | Add assets to a memory | `memoryAsset.create` | Stable |

### Notifications — 6 operations

| Method | Path | Summary | Permission | State |
|---|---|---|---|---|
| DELETE | `/notifications` | Delete notifications | `notification.delete` | Stable |
| GET | `/notifications` | Retrieve notifications | `notification.read` | Stable |
| PUT | `/notifications` | Update notifications | `notification.update` | Stable |
| DELETE | `/notifications/{id}` | Delete a notification | `notification.delete` | Stable |
| GET | `/notifications/{id}` | Get a notification | `notification.read` | Stable |
| PUT | `/notifications/{id}` | Update a notification | `notification.update` | Stable |

### Notifications (admin) — 3 operations

| Method | Path | Summary | Permission | State |
|---|---|---|---|---|
| POST | `/admin/notifications` | Create a notification | `notification.create` | Stable |
| POST | `/admin/notifications/templates/{name}` | Render email template | `notification.create` | Stable |
| POST | `/admin/notifications/test-email` | Send test email | `notification.create` | Stable |

### Partners — 5 operations

| Method | Path | Summary | Permission | State |
|---|---|---|---|---|
| GET | `/partners` | Retrieve partners | `partner.read` | Stable |
| POST | `/partners` | Create a partner | `partner.create` | Stable |
| DELETE | `/partners/{id}` | Remove a partner | `partner.delete` | Stable |
| POST | `/partners/{id}` | Create a partner ⚠️ DEPRECATED | `partner.create` | Deprecated |
| PUT | `/partners/{id}` | Update a partner | `partner.update` | Stable |

### Passkeys — 8 operations

| Method | Path | Summary | Permission | State |
|---|---|---|---|---|
| GET | `/passkeys` | Search passkeys | `passkey.read` | Alpha |
| POST | `/passkeys/authentication/finish` | Finish passkey authentication | `—` | Alpha |
| POST | `/passkeys/authentication/start` | Start passkey authentication | `—` | Alpha |
| POST | `/passkeys/registration/finish` | Finish passkey registration | `—` | Alpha |
| POST | `/passkeys/registration/start` | Start passkey registration | `—` | Alpha |
| DELETE | `/passkeys/{id}` | Delete a passkey | `passkey.delete` | Alpha |
| GET | `/passkeys/{id}` | Retrieve a passkey | `passkey.read` | Alpha |
| PATCH | `/passkeys/{id}` | Update a passkey | `passkey.update` | Alpha |

### People — 15 operations

| Method | Path | Summary | Permission | State |
|---|---|---|---|---|
| DELETE | `/people` | Delete people | `person.delete` | Stable |
| GET | `/people` | Get all people | `person.read` | Stable |
| POST | `/people` | Create a person | `person.create` | Stable |
| PUT | `/people` | Update people | `person.update` | Stable |
| POST | `/people/merge` | Merge people | `person.merge` | Stable |
| DELETE | `/people/users` | Remove users from people | `person.update` | Beta |
| GET | `/people/users` | Get people access | `person.read` | Beta |
| PUT | `/people/users` | Upsert user access | `person.update` | Beta |
| DELETE | `/people/{id}` | Delete person | `person.delete` | Stable |
| GET | `/people/{id}` | Get a person | `person.read` | Stable |
| PUT | `/people/{id}` | Update person | `person.update` | Stable |
| POST | `/people/{id}/merge` | Merge people ⚠️ DEPRECATED | `person.merge` | Deprecated |
| PUT | `/people/{id}/reassign` | Reassign faces | `person.reassign` | Stable |
| GET | `/people/{id}/statistics` | Get person statistics | `person.statistics` | Stable |
| GET | `/people/{id}/thumbnail` | Get person thumbnail | `person.read` | Stable |

### Plugins — 4 operations

| Method | Path | Summary | Permission | State |
|---|---|---|---|---|
| GET | `/plugins` | List all plugins | `plugin.read` | — |
| GET | `/plugins/methods` | Retrieve plugin methods | `plugin.read` | — |
| GET | `/plugins/templates` | Retrieve workflow templates | `plugin.read` | — |
| GET | `/plugins/{id}` | Retrieve a plugin | `plugin.read` | — |

### Queues — 5 operations

| Method | Path | Summary | Permission | State |
|---|---|---|---|---|
| GET | `/queues` | List all queues | `queue.read` | Alpha |
| GET | `/queues/{name}` | Retrieve a queue | `queue.read` | Alpha |
| PUT | `/queues/{name}` | Update a queue | `queue.update` | Alpha |
| DELETE | `/queues/{name}/jobs` | Empty a queue | `queueJob.delete` | Alpha |
| GET | `/queues/{name}/jobs` | Retrieve queue jobs | `queueJob.read` | Alpha |

### Search — 10 operations

| Method | Path | Summary | Permission | State |
|---|---|---|---|---|
| GET | `/search/cities` | Retrieve assets by city | `asset.read` | Stable |
| GET | `/search/explore` | Retrieve explore data | `asset.read` | Stable |
| POST | `/search/large-assets` | Search large assets ⚠️ DEPRECATED | `asset.read` | Deprecated |
| POST | `/search/metadata` | Search assets by metadata | `asset.read` | Stable |
| GET | `/search/person` | Search people | `person.read` | Stable |
| GET | `/search/places` | Search places | `asset.read` | Stable |
| POST | `/search/random` | Search random assets | `asset.read` | Stable |
| POST | `/search/smart` | Smart asset search | `asset.read` | Stable |
| POST | `/search/statistics` | Search asset statistics | `asset.statistics` | Stable |
| GET | `/search/suggestions` | Retrieve search suggestions | `asset.read` | Stable |

### Server — 14 operations

| Method | Path | Summary | Permission | State |
|---|---|---|---|---|
| GET | `/server/about` | Get server information | `server.about` | Stable |
| GET | `/server/apk-links` | Get APK links | `server.apkLinks` | Stable |
| GET | `/server/config` | Get config ⚠️ DEPRECATED | `—` | Deprecated |
| GET | `/server/features` | Get features ⚠️ DEPRECATED | `—` | Deprecated |
| DELETE | `/server/license` | Delete server product key | `serverLicense.delete` | Stable |
| GET | `/server/license` | Get product key | `serverLicense.read` | Stable |
| PUT | `/server/license` | Set server product key | `serverLicense.update` | Stable |
| GET | `/server/media-types` | Get supported media types | `—` | Stable |
| GET | `/server/ping` | Ping | `—` | Stable |
| GET | `/server/statistics` | Get statistics | `server.statistics` | Stable |
| GET | `/server/storage` | Get storage | `server.storage` | Stable |
| GET | `/server/version` | Get server version | `—` | Stable |
| GET | `/server/version-check` | Get version check status | `server.versionCheck` | Stable |
| GET | `/server/version-history` | Get version history | `—` | Stable |

### Sessions — 6 operations

| Method | Path | Summary | Permission | State |
|---|---|---|---|---|
| DELETE | `/sessions` | Delete all sessions | `session.delete` | Stable |
| GET | `/sessions` | Retrieve sessions | `session.read` | Stable |
| POST | `/sessions` | Create a session | `session.create` | Stable |
| DELETE | `/sessions/{id}` | Delete a session | `session.delete` | Stable |
| PUT | `/sessions/{id}` | Update a session | `session.update` | Stable |
| POST | `/sessions/{id}/lock` | Lock a session | `session.lock` | Stable |

### Shared links — 9 operations

| Method | Path | Summary | Permission | State |
|---|---|---|---|---|
| GET | `/shared-links` | Retrieve all shared links | `sharedLink.read` | Stable |
| POST | `/shared-links` | Create a shared link | `sharedLink.create` | Stable |
| POST | `/shared-links/login` | Shared link login | `—` | Beta |
| GET | `/shared-links/me` | Retrieve current shared link | `—` | Stable |
| DELETE | `/shared-links/{id}` | Delete a shared link | `sharedLink.delete` | Stable |
| GET | `/shared-links/{id}` | Retrieve a shared link | `sharedLink.read` | Stable |
| PATCH | `/shared-links/{id}` | Update a shared link | `sharedLink.update` | Stable |
| DELETE | `/shared-links/{id}/assets` | Remove assets from a shared link | `sharedLink.update` | Stable |
| PUT | `/shared-links/{id}/assets` | Add assets to a shared link | `sharedLink.update` | Stable |

### Stacks — 7 operations

| Method | Path | Summary | Permission | State |
|---|---|---|---|---|
| DELETE | `/stacks` | Delete stacks | `stack.delete` | Stable |
| GET | `/stacks` | Retrieve stacks | `stack.read` | Stable |
| POST | `/stacks` | Create a stack | `stack.create` | Stable |
| DELETE | `/stacks/{id}` | Delete a stack | `stack.delete` | Stable |
| GET | `/stacks/{id}` | Retrieve a stack | `stack.read` | Stable |
| PUT | `/stacks/{id}` | Update a stack | `stack.update` | Stable |
| DELETE | `/stacks/{id}/assets/{assetId}` | Remove an asset from a stack | `stack.update` | Stable |

### Sync — 4 operations

| Method | Path | Summary | Permission | State |
|---|---|---|---|---|
| DELETE | `/sync/ack` | Delete acknowledgements | `syncCheckpoint.delete` | Stable |
| GET | `/sync/ack` | Retrieve acknowledgements | `syncCheckpoint.read` | Stable |
| POST | `/sync/ack` | Acknowledge changes | `syncCheckpoint.update` | Stable |
| POST | `/sync/stream` | Stream sync changes | `sync.stream` | Stable |

### System config — 4 operations

| Method | Path | Summary | Permission | State |
|---|---|---|---|---|
| GET | `/system-config` | Get system configuration ⚠️ DEPRECATED | `systemConfig.read` | Deprecated |
| PUT | `/system-config` | Update system configuration ⚠️ DEPRECATED | `systemConfig.update` | Deprecated |
| GET | `/system-config/defaults` | Get system configuration defaults ⚠️ DEPRECATED | `systemConfig.read` | Deprecated |
| GET | `/system-config/storage-template-options` | Get storage template options | `systemConfig.read` | Stable |

### System metadata — 4 operations

| Method | Path | Summary | Permission | State |
|---|---|---|---|---|
| GET | `/system-metadata/admin-onboarding` | Retrieve admin onboarding | `systemMetadata.read` | Stable |
| POST | `/system-metadata/admin-onboarding` | Update admin onboarding | `systemMetadata.update` | Stable |
| GET | `/system-metadata/reverse-geocoding-state` | Retrieve reverse geocoding state | `systemMetadata.read` | Stable |
| GET | `/system-metadata/version-check-state` | Retrieve version check state | `systemMetadata.read` | Stable |

### Tags — 9 operations

| Method | Path | Summary | Permission | State |
|---|---|---|---|---|
| GET | `/tags` | Retrieve tags | `tag.read` | Stable |
| POST | `/tags` | Create a tag | `tag.create` | Stable |
| PUT | `/tags` | Upsert tags | `tag.create` | Stable |
| PUT | `/tags/assets` | Tag assets | `tag.asset` | Stable |
| DELETE | `/tags/{id}` | Delete a tag | `tag.delete` | Stable |
| GET | `/tags/{id}` | Retrieve a tag | `tag.read` | Stable |
| PUT | `/tags/{id}` | Update a tag | `tag.update` | Stable |
| DELETE | `/tags/{id}/assets` | Untag assets | `tag.asset` | Stable |
| PUT | `/tags/{id}/assets` | Tag assets | `tag.asset` | Stable |

### Timeline — 2 operations

| Method | Path | Summary | Permission | State |
|---|---|---|---|---|
| GET | `/timeline/bucket` | Get time bucket | `asset.read` | Internal |
| GET | `/timeline/buckets` | Get time buckets | `asset.read` | Internal |

### Trash — 3 operations

| Method | Path | Summary | Permission | State |
|---|---|---|---|---|
| POST | `/trash/empty` | Empty trash | `asset.delete` | Stable |
| POST | `/trash/restore` | Restore trash | `asset.delete` | Stable |
| POST | `/trash/restore/assets` | Restore assets | `asset.delete` | Stable |

### Users — 16 operations

| Method | Path | Summary | Permission | State |
|---|---|---|---|---|
| GET | `/users` | Get all users | `user.read` | Stable |
| GET | `/users/me` | Get current user | `user.read` | Stable |
| PUT | `/users/me` | Update current user | `user.update` | Stable |
| GET | `/users/me/calendar-heatmap` | Retrieve calendar heatmap activity | `user.read` | Stable |
| DELETE | `/users/me/license` | Delete user product key | `userLicense.delete` | Stable |
| GET | `/users/me/license` | Retrieve user product key | `userLicense.read` | Stable |
| PUT | `/users/me/license` | Set user product key | `userLicense.update` | Stable |
| DELETE | `/users/me/onboarding` | Delete user onboarding | `userOnboarding.delete` | Stable |
| GET | `/users/me/onboarding` | Retrieve user onboarding | `userOnboarding.read` | Stable |
| PUT | `/users/me/onboarding` | Update user onboarding | `userOnboarding.update` | Stable |
| GET | `/users/me/preferences` | Get my preferences | `userPreference.read` | Stable |
| PUT | `/users/me/preferences` | Update my preferences | `userPreference.update` | Stable |
| DELETE | `/users/profile-image` | Delete user profile image | `userProfileImage.delete` | Stable |
| POST | `/users/profile-image` | Create user profile image | `userProfileImage.update` | Stable |
| GET | `/users/{id}` | Retrieve a user | `user.read` | Stable |
| GET | `/users/{id}/profile-image` | Retrieve user profile image | `userProfileImage.read` | Stable |

### Users (admin) — 11 operations

| Method | Path | Summary | Permission | State |
|---|---|---|---|---|
| GET | `/admin/users` | Search users | `adminUser.read` | Stable |
| POST | `/admin/users` | Create a user | `adminUser.create` | Stable |
| DELETE | `/admin/users/{id}` | Delete a user | `adminUser.delete` | Stable |
| GET | `/admin/users/{id}` | Retrieve a user | `adminUser.read` | Stable |
| PUT | `/admin/users/{id}` | Update a user | `adminUser.update` | Stable |
| GET | `/admin/users/{id}/calendar-heatmap` | Retrieve calendar heatmap activity | `adminUser.read` | Stable |
| GET | `/admin/users/{id}/preferences` | Retrieve user preferences | `adminUser.read` | Stable |
| PUT | `/admin/users/{id}/preferences` | Update user preferences | `adminUser.update` | Stable |
| POST | `/admin/users/{id}/restore` | Restore a deleted user | `adminUser.delete` | Stable |
| GET | `/admin/users/{id}/sessions` | Retrieve user sessions | `adminSession.read` | Stable |
| GET | `/admin/users/{id}/statistics` | Retrieve user statistics | `adminUser.read` | Stable |

### Views — 2 operations

| Method | Path | Summary | Permission | State |
|---|---|---|---|---|
| GET | `/view/folder` | Retrieve assets by original path | `folder.read` | Stable |
| GET | `/view/folder/unique-paths` | Retrieve unique paths | `folder.read` | Stable |

### Workflows — 8 operations

| Method | Path | Summary | Permission | State |
|---|---|---|---|---|
| GET | `/workflows` | List all workflows | `workflow.read` | — |
| POST | `/workflows` | Create a workflow | `workflow.create` | — |
| GET | `/workflows/triggers` | List all workflow triggers | `—` | — |
| DELETE | `/workflows/{id}` | Delete a workflow | `workflow.delete` | — |
| GET | `/workflows/{id}` | Retrieve a workflow | `workflow.read` | — |
| PUT | `/workflows/{id}` | Update a workflow | `workflow.update` | — |
| GET | `/workflows/{id}/logs` | Retrieve workflow logs | `workflow.logs` | — |
| GET | `/workflows/{id}/share` | Retrieve a workflow | `workflow.read` | — |


## 4. Cross-cutting behaviour

### 4.1 Pagination — there is no single model; three coexist

1. **Cursor/page search (`POST /search/metadata`, `POST /search/smart`,
   `POST /search/random`, `POST /search/large-assets`)** — the modern
   model. Request: `page` (int) and/or `cursor` (string), `size` (int).
   Response `SearchAssetResponseDto`: `items[]`, `count` (page size),
   `total` (**deprecated** — `x-immich-state: Deprecated`, do not rely on
   it), `nextPage` (nullable string token), `nextCursor`. Use `nextPage`
   / `nextCursor` to page; do not assume numeric pages keep working.
   `MetadataSearchDto` also has `order` (`AssetOrder`: `asc`/`desc`) and
   `orderBy` (`SearchOrder`: field + direction).
2. **Time buckets (`GET /timeline/buckets`, `GET /timeline/bucket`)** —
   the timeline model (see §5.4). No page numbers; buckets are months.
3. **Unpaginated lists** — `GET /albums` (filter params only, no paging),
   `GET /people`, `GET /tags`, `GET /memories`, `GET /notifications`,
   `GET /libraries`. Fine for normal libraries; a pathological library
   (10k albums) returns everything in one response — guard with a cap in
   the client.

### 4.2 Errors (UNKNOWN in spec — runtime behaviour)

The spec documents **no error schemas at all**. What is known from the
server's history and third-party clients (immich-go v3 support PR,
Immich-Android-TV notes):

- **v3.0 changed error shapes**: class-validator → Zod. Old
  `{error, statusCode}` fields were removed; errors are now structured
  Zod issues and the correlation id moved to the **`X-Correlation-ID`
  response header**. NOVA must parse errors tolerantly: read the HTTP
  status, then try `message` (string or string[]), then fall back to the
  raw body. Never pattern-match on an exact error JSON shape.
- Expected statuses: `400` validation, `401` bad/expired token,
  `403` missing API-key permission (common during development — check
  the key's scopes first), `404` unknown id, `413` file too large
  (UNKNOWN — not documented), `500` server fault.
- **No `429` in the spec** — no documented rate limiting.

### 4.3 Shared links (`key`/`slug`)

Many read endpoints accept optional `key` + `slug` query params for
shared-link access. Dedicated shared-link API (`Shared links`, 9 ops):
`GET /shared-links`, `POST /shared-links` (`sharedLink.create`),
`GET /shared-links/me` (resolve a link by key/slug),
`POST /shared-links/login` (password-protected link),
`GET/PUT/DELETE /shared-links/{id}`,
`GET /shared-links/{id}/assets`. NOVA v1: out of scope unless we add
"share album as link".

### 4.4 `x-immich-history` — per-field versioning

Every operation and many schema fields carry `x-immich-history`
(`version` + `state`: Added/Beta/Stable/Deprecated/Updated/Internal).
There are **125 deprecated schema fields**. Notable deprecations for
NOVA: `SearchAssetResponseDto.total` (v3.0.0),
`AssetResponseDto.resized` (v1.113.0), `AssetResponseDto.libraryId`
(v1), `ApiKeyCreateResponseDto.apiKey` (v3.2.0), and thumbnail
`size=original` (v3 — use `GET /assets/{id}/original` instead).
**Do not code against deprecated fields.**

## 5. Functional deep dives

### 5.1 Assets — listing

**There is no `GET /assets` list endpoint in v3.4.2.** Asset listing is
done through search (below) or the timeline. This is the single biggest
"gotcha" for a new client.

| Method & path | Purpose |
|---|---|
| `GET /assets/{id}` | One asset → `AssetResponseDto` (see §5.1.1). `asset.read`. |
| `GET /assets/statistics` | `{images, videos, total}`; filters `isFavorite`, `isTrashed`, `visibility`. `asset.statistics`. |
| `POST /search/metadata` | **The list endpoint.** `MetadataSearchDto` (40+ filters: `albumIds`, `personIds`, `tagIds`, `takenAfter/Before`, `createdAfter/Before`, `type` (`IMAGE`/`VIDEO`/`AUDIO`/`OTHER`), `isFavorite`, `isMotion`, `isNotInAlbum`, `visibility`, `rating` 1–5, `checksum`, `originalFileName`, `ocr`, `withExif`, `withPeople`, `withStacked`, `withDeleted`, `libraryId`, `order`, `orderBy`, `page`, `size`, `cursor`). Response `SearchAssetResponseDto` (`items`, `count`, `nextPage`, `nextCursor`, `facets`). `asset.read`. **Album contents are listed this way too** (pass `albumIds`) — albums no longer embed assets. |
| `POST /search/random` | Random assets (same filter family). |
| `POST /search/large-assets` | Largest files first (storage UI). |
| `GET /assets/{id}` with `exifInfo`, or `POST /search/metadata` with `withExif: true` | EXIF block. (There is no standalone `/assets/{id}/exif` endpoint in v3.4.2.) |

#### 5.1.1 `AssetResponseDto` (key fields)

`id` (uuid), `type` (`IMAGE|VIDEO|AUDIO|OTHER`), `originalFileName`,
`originalMimeType`, `originalPath`, `checksum` (SHA-1), `fileCreatedAt`,
`fileModifiedAt`, `createdAt`, `updatedAt`, `localDateTime`,
`duration` (video, `HH:MM:SS.mmm` string in v3 — **was a number in
v2**), `width`, `height`, `isFavorite`, `isArchived`, `isTrashed`,
`visibility` (`timeline|archive|hidden|locked`), `ownerId`, `owner`,
`people[]`, `tags[]`, `exifInfo` (full EXIF incl. lat/lon, make/model),
`thumbhash` (blurhash-style placeholder — render while thumbnails
load), `stack` (stack info or null), `livePhotoVideoId`,
`duplicateId`, `isOffline`, `isEdited`, `hasMetadata`,
`libraryId` (**deprecated**), `resized` (**deprecated**).

### 5.2 Assets — upload (multipart, duplicates, bulk check)

| Method & path | Purpose |
|---|---|
| `POST /assets` | **Upload one asset.** `multipart/form-data`, body `AssetMediaCreateDto`. **Required parts:** `assetData` (file bytes), `fileCreatedAt`, `fileModifiedAt`. Optional: `filename`, `duration` (ms, videos), `isFavorite`, `livePhotoVideoId`, `sidecarData` (XMP sidecar), `visibility`, `metadata[]`. Optional header `x-immich-checksum` (SHA-1) for pre-upload duplicate detection. Responses: **201** created → `AssetMediaResponseDto` `{id, status:"created"}`; **200** → same DTO with `status:"duplicate"` (server already has this checksum — do **not** treat 200 as an error). Permission `asset.upload`. |
| `POST /assets/bulk-upload-check` | Pre-flight for many files: body `AssetBulkUploadCheckDto` `{assets: [{id, checksum}]}` → `AssetBulkUploadCheckResponseDto` `{results: [{id, checksum, action: "accept"|"reject"}]}`. **Use this before uploading a camera roll** — one round-trip instead of one per file. |
| `PUT /assets/copy` | Copy an asset to another library (body `AssetCopyDto`). |
| `POST /assets/jobs` | Trigger a per-asset job (e.g. regenerate thumbnail). |

**There is no chunked/resumable upload endpoint in the public spec.**
Large files are a single multipart POST. (The official mobile app
uploads the same way; for very large videos on flaky mobile data, split
client-side is NOT supported server-side — retry the whole file.
UNKNOWN whether the server enforces a max body size; the default
reverse-proxy/Nest limit is the practical cap — verify against the
target server during QA.)
**`deviceId` / `deviceAssetId` were removed from the upload DTO in
v3** — do not send them (ignored on v3, and may be rejected if strict
validation lands later).

### 5.3 Assets — download, thumbnails, video

| Method & path | Purpose |
|---|---|
| `GET /assets/{id}/original` | Original file bytes (`application/octet-stream`). Query `edited=true` returns the edited version if one exists. Permission `asset.download` (note: **different** from `asset.view`). |
| `GET /assets/{id}/thumbnail` | Thumbnail bytes (`application/octet-stream`). Query `size` = `AssetMediaSize`: `thumbnail` (~250px WebP), `preview` (1440px JPEG), `fullsize`, `original` (**`original` is deprecated in v3 — use `/original`**). Query `edited=true`. Permission `asset.view`. **Note the spec text:** "Viewing the fullsize thumbnail might redirect to downloadAsset, which requires a different permission" — requesting `fullsize` can 403 on a key with only `asset.view`. |
| `GET /assets/{id}/video/stream/{sessionId}/{variantIndex}/playlist.m3u8` + `GET .../{filename}` + `DELETE ...` | HLS video streaming (transcoded variants). Sessions are created by the video-playback flow; NOVA should use the platform video player pointed at the playlist URL with auth headers/cookies. |
| `POST /download/info` | Body `DownloadInfoDto` (asset ids and/or album id) → groups of downloadable assets (the server splits archives by size). |
| `POST /download/archive` | Returns a zip archive of the requested assets. |
| `GET /asset-files/{id}/download` | Download one asset file record (`Asset files`, Alpha). |

**Thumbnail URL patterns (for the client):**

```text
{base}/api/assets/{id}/thumbnail?size=thumbnail   # grid (~250 px WebP)
{base}/api/assets/{id}/thumbnail?size=preview     # detail (1440 px JPEG)
{base}/api/assets/{id}/original                   # full file
```

All three need auth (`Authorization: Bearer …` or `x-api-key` header —
note: `<img>`-style plain URL loads cannot set headers; in Flutter use
an authenticated HTTP client / cached network image with headers, or
the cookie scheme).

### 5.4 Timeline (time buckets)

| Method & path | Purpose |
|---|---|
| `GET /timeline/buckets` | Array of `TimeBucketsResponseDto` — one entry per **month** that has assets: `{timeBucket: "2024-01-01T00:00:00.000Z", count}`. Filters: `albumId`, `personId`, `tagId`, `userId`, `isFavorite`, `isTrashed`, `visibility`, `bbox` (map), `order`, `orderBy` (`takenAt`/`createdAt`), `withPartners`, `withStacked`, `withCoordinates`. Permission `asset.read`. **State: `Internal`** (built for the official clients, but stable in practice since v1). |
| `GET /timeline/bucket` | `timeBucket` (required, `YYYY-MM-DDT00:00:00.000Z`) → `TimeBucketAssetResponseDto` — the asset ids (and minimal data) in that month. Same filters. This is the **primary timeline data source**: buckets first, then per-month fetch, then `GET /assets/{id}` / search for full data. |

### 5.5 Favorites / archive / visibility

There is **no dedicated favorite endpoint** — favorites are a flag on
the asset:

- Single: `PUT /assets/{id}` body `UpdateAssetDto`
  (`isFavorite`, `description`, `dateTimeOriginal`, `latitude`,
  `longitude`, `rating` 1–5 / `-1` rejected / `null` unrated,
  `visibility`, `livePhotoVideoId`).
- Bulk: `PUT /assets` body `AssetBulkUpdateDto` (`ids[]` **required**,
  plus the same fields, `dateTimeRelative`, `timeZone`,
  `duplicateId`).
- **Archive / hide / lock** are the same flag family: `visibility` =
  `timeline` (default) | `archive` | `hidden` | `locked`. Locked assets
  additionally need the session unlocked (`POST /auth/session/unlock`
  + PIN). `AssetResponseDto.isArchived` is a convenience mirror of
  `visibility=archive`.
- Delete: `DELETE /assets` (bulk, body `AssetBulkDeleteDto`) and
  per-asset delete is via the same bulk endpoint — **there is no
  `DELETE /assets/{id}`** in v3.4.2. Delete = move to trash by default;
  permanent delete is a trash operation (see §5.11).

### 5.6 Search & smart search (CLIP)

| Method & path | Purpose |
|---|---|
| `POST /search/smart` | **CLIP semantic search.** Body `SmartSearchDto`: `query` (natural language, e.g. "sunset over the ocean"), `language`, `queryAssetId` (find visually similar to an asset), plus the same filter family as metadata search (`albumIds`, `personIds`, `tagIds`, city/state/country, dates, `type`, `isFavorite`, `rating`, `visibility`, `page`, `size`). Requires the server's smart-search (CLIP) feature — check `GET /server/features` → `smartSearch`. Returns `SearchAssetResponseDto`. |
| `POST /search/metadata` | Structured search — see §5.1. |
| `GET /search/explore` | Explore lanes (objects/faces/places groupings). |
| `GET /search/person` | Search people by name. |
| `GET /search/cities`, `GET /search/places` | Location autocomplete/grouping. |
| `GET /search/suggestions` | Search-box suggestions. |
| `POST /search/statistics` | Facet counts for a query. |
| `GET /assets/{id}/ocr` | OCR text extracted from an asset (searchable via `ocr` filter). |

### 5.7 Albums & shared albums

`GET /albums` (filters: `assetId`, `id`, `isOwned`, `isShared`,
`name` — **no pagination**), `POST /albums` (`CreateAlbumDto`:
`albumName`, `description`, `albumUsers[]`, `assetIds[]`),
`GET /albums/{id}` (accepts `key`/`slug` for shared links),
`PATCH /albums/{id}` (`UpdateAlbumDto`), `DELETE /albums/{id}` →
204, `GET /albums/statistics`, `PUT /albums/{id}/assets` /
`DELETE /albums/{id}/assets` (body `BulkIdsDto`), `PUT /albums/assets`
(add assets to many albums), `PUT /albums/{id}/users` (share),
`PUT /albums/{id}/user/{userId}` (role), `DELETE /albums/{id}/user/{userId}`,
`GET /albums/{id}/map-markers`.
**v3 breaking change:** `GET /albums/{id}` **no longer embeds
`assets`** — only `assetCount`. Album contents come from
`POST /search/metadata` with `albumIds=[id]`. The old `shared` query
param is gone (replaced by `isShared`/`isOwned`). `AlbumResponseDto`
has no `owner`/`ownerId` fields — ownership lives in `albumUsers[]`
(first entry is always the owner; second is the auth user if
different; rest alphabetical), each `{user, role}`.
Album **activities** (comments/likes): `Activities` tag, 4 ops
(`GET/POST /activities`, `GET /activities/statistics`,
`DELETE /activities/{id}`).

### 5.8 Memories

`GET /memories` (list; `Memories`, 8 ops), `POST /memories`,
`GET /memories/{id}`, `PATCH /memories/{id}` (save/hide),
`DELETE /memories/{id}`, `GET /memories/{id}/assets`,
`GET /memories/statistics`. `MemoryResponseDto`: `type` (e.g.
"on-this-day"), `memoryAt`, `data`, `assets[]`, `isSaved`, `seenAt`,
`hideAt`/`showAt`. NOVA v1: a "On this day" lane is cheap to add once
the timeline works.

### 5.9 People & faces

- `People` (15 ops): `GET /people` (list, filters incl. `withHidden`),
  `POST /people`, `GET /people/{id}`, `PUT /people/{id}` (name,
  birthDate, favorite, hidden, feature face), `DELETE /people/{id}`,
  `POST /people/merge` (`person.merge`), `GET /people/{id}/assets`,
  `GET /people/{id}/statistics`, `GET /people/{id}/thumbnail`,
  `POST /people/{id}/reassign` (`person.reassign`), plus
  `GET /people/{id}/...` variants. `PersonResponseDto`: `id`, `name`,
  `birthDate`, `isFavorite`, `isHidden`, `thumbnailPath`, `color`,
  `otherPeople`, `sharedBy`/`sharedWith`.
- `Faces` (4 ops): `GET /faces`, `GET /faces/{id}`, `PUT /faces/{id}`,
  `DELETE /faces/{id}` — individual face bounding boxes / assignments.
- `Cluster groups` (8 ops): face-cluster management
  (`clusterGroup.*`), including `POST /cluster-groups/{id}/regenerate-people`.
  Mostly admin/ML-maintenance surface; NOVA v1 can ignore cluster
  groups.
- Faces depend on the server's facial-recognition feature
  (`GET /server/features` → `facialRecognition`).

### 5.10 Tags, locations/map, statistics

- **Tags** (9 ops): `GET /tags`, `POST /tags` (`tag.create`),
  `GET/PATCH/DELETE /tags/{id}`, `GET /tags/{id}/assets`,
  `PUT /tags/assets` (bulk tag/untag, `tag.asset`),
  `DELETE /tags/assets`. `TagResponseDto`: `value` (hierarchical
  `Parent/Child` path), `name`, `color`, `parentId`.
- **Map** (2 ops): `GET /map/markers` (markers in a bounding box;
  `map.read`), `GET /map/reverse-geocode` (`map.search`). Album
  markers: `GET /albums/{id}/map-markers`. Reverse geocoding needs the
  server feature (`reverseGeocoding`).
- **Statistics**: `GET /assets/statistics` (own library),
  `GET /server/statistics` (**admin-only** — whole instance),
  `GET /albums/statistics`, `GET /memories/statistics`,
  `POST /search/statistics`, `GET /libraries/{id}/statistics`,
  `GET /people/{id}/statistics`, `GET /activities/statistics`.

### 5.11 Trash

`POST /trash/restore` (restore all), `POST /trash/restore/assets`
(body `BulkIdsDto`), `POST /trash/empty` (permanent delete of
everything — irreversible). Trashed assets are listed via
`POST /search/metadata` with `isTrashed` / `trashedAfter` /
`trashedBefore`, or `GET /timeline/buckets?isTrashed=true`.
There is no `GET /trash` list endpoint.

### 5.12 Notifications

`GET /notifications` (list own), `GET /notifications/{id}`,
`PUT /notifications/{id}` (mark read), `DELETE /notifications/{id}`,
`POST /notifications` (create — admin/partner use),
`GET /notifications/statistics`. Admin: `GET /admin/notifications`,
`GET /admin/notifications/templates/{name}`,
`POST /admin/notifications/test-email`.
`NotificationDto`: `type`, `level`, `title`, `description`, `data`,
`readAt`. In-app notifications also arrive over the WebSocket
(`on_notification`).

### 5.13 System config / admin (for reference; NOVA v1 does NOT need these)

- `System config` (4 ops): `GET /system-config`,
  `PUT /system-config`, `GET /system-config/defaults` — **all three
  Deprecated** — and `GET /system-config/storage-template-options`
  (Stable). Admin-only. (The current config surface is `Config
  (admin)`; see generated table.)
- `Config (admin)` (3 ops), `Config (public)` (2 ops),
  `Config (user)` (2 ops), `Maintenance (admin)` (9 ops),
  `Database Backups (admin)` (5 ops), `Queues` (5 ops),
  `Jobs` (3 ops), `Integrity (admin)`, `System metadata` (4 ops),
  `Workflows` (8 ops) + `Plugins` (4 ops) — the v3 automation system
  (event-triggered workflows; Alpha).
- `Libraries` (8 ops): external libraries
  (`GET /libraries`, `POST /libraries`, `POST /libraries/{id}/scan`,
  `POST /libraries/{id}/validate`, `GET /libraries/{id}/statistics`).
  Read-only library browsing is possible; scanning is admin.
- `Views` (2 ops): `GET /view/folder`, `GET /view/folder/unique-paths`
  (`folder.read`) — browse the server's on-disk library folders.
- `Partners` (5 ops): `GET /partners`, `POST /partners`,
  `PUT/DELETE /partners/{id}` — partner sharing (see partner assets
  via timeline `withPartners`).
- `GET /server/apk-links` — download links for the official Android
  APKs matching this server version (`server.apkLinks`).
- `GET /server/license`, `PUT/DELETE /server/license` — instance
  license (admin).

### 5.14 Server info / version / features

| Method & path | Auth | Purpose |
|---|---|---|
| `GET /server/ping` | **none** | `{"res":"pong"}`. Connectivity check. |
| `GET /server/version` | auth | `ServerVersionResponseDto`: `major`, `minor`, `patch`, `prerelease`, **`featureLevel`** (increments independently of releases — the real compatibility signal). Demo server: 3.4.2 / featureLevel 2. |
| `GET /server/features` | auth | `ServerFeaturesDto`: `smartSearch`, `facialRecognition`, `map`, `trash`, `oauth`, `passwordLogin`, `email`, `search`, `sidecar`, `ocr`, `duplicateDetection`, `reverseGeocoding`, `backups`, `configFile`, `importFaces`, `oauthAutoLaunch`, `realtimeTranscoding`. **Call this once at login and gate features on it.** |
| `GET /server/about` | auth | `ServerAboutResponseDto`: `version`, `repository`, `sourceRef`, `build`, `ffmpeg`, `exiftool`, `imagemagick`, `libvips`, `nodejs`, `licensed`, `versionUrl`. `server.about`. |
| `GET /server/config` | auth | Public server config (login page, OAuth, theme). |
| `GET /server/media-types` | auth | Supported media types. |
| `GET /server/storage` | auth | Storage usage (`server.storage`). |
| `GET /server/version-check` | auth | Last upstream version-check result (`server.versionCheck`). |
| `GET /server/version-history` | auth | Version history. |

### 5.15 Duplicates, stacks, asset files, asset edits

- **Duplicates** (4 ops): `GET /duplicates` (groups),
  `GET /duplicates/{id}`, `POST /duplicates/resolve`,
  `DELETE /duplicates/{id}` (`duplicate.delete`). Needs
  `duplicateDetection` feature.
- **Stacks** (7 ops): `GET /stacks`, `POST /stacks`,
  `GET/PUT/DELETE /stacks/{id}`, `GET /stacks/{id}/assets/{assetId}`,
  `DELETE /stacks/{id}/assets/{assetId}` — motion-photo / burst /
  RAW+JPEG groups. `AssetResponseDto.stack` links an asset to its stack.
- **Asset files** (4 ops, Alpha): `GET /asset-files`,
  `GET /asset-files/{id}`, `DELETE /asset-files/{id}`,
  `GET /asset-files/{id}/download` — the individual files behind an
  asset (original, preview, thumbnail, encoded video, sidecar).
- **Asset edits** (Beta): `GET/PUT/DELETE /assets/{id}/edits` —
  non-destructive edit stack (crop/rotate); `edited=true` on
  thumbnail/original returns the edited render.
- **Asset metadata** (key/value store): `GET/PUT /assets/{id}/metadata`,
  `GET/DELETE /assets/{id}/metadata/{key}`, bulk `PUT/DELETE /assets/metadata`.
  This is the extension point for app-specific per-asset data — but
  note it is visible to other clients; do not store secrets here.

### 5.16 Sync (delta sync — the official mobile app's mechanism)

| Method & path | Purpose |
|---|---|
| `POST /sync/stream` | **JSON-lines stream of changes.** Body `SyncStreamDto` (types to sync + checkpoint). Response is a `text/event-stream`-like NDJSON stream of `SyncEntity` changes (assets, albums, people, …). "Used by the mobile app to efficiently stay up to date." Permission `sync.stream`. **This is the right primitive for NOVA's background sync**, not polling search. |
| `GET /sync/ack` · `POST /sync/ack` · `DELETE /sync/ack` | Checkpoints: confirm received changes so the next stream resumes where the last left off (`syncCheckpoint.read/update/delete`). |

Full `SyncStreamDto` / `SyncAckDto` shapes are in the spec
(`key-schemas2.txt` in the research folder only summarises them —
**verify the exact checkpoint fields from the spec file before
implementing**; they are `Alpha`-adjacent in stability even though the
endpoint is marked `Stable`).

### 5.17 WebSocket events (NOT in the OpenAPI spec — from the official web client source)

The server runs **Socket.IO** (v4.8.1) at **`/api/socket.io/`**
(`wss://<host>/api/socket.io/`), authenticated with the same JWT
(session cookie / bearer token — the server's WebSocket adapter uses
the same auth service as HTTP; exact handshake: pass the access token
as the Socket.IO `auth` payload / `Authorization` header — **verify
against the running server in Stage 4**, as this is not documented in
the spec). The web client (`web/src/lib/stores/websocket.ts`, `main`
branch, fetched 2026-11-22) subscribes to:

| Server event | Payload | Meaning |
|---|---|---|
| `on_upload_success` | `AssetResponseDto` | A new asset finished uploading |
| `on_asset_update` | `AssetResponseDto` | Asset metadata changed |
| `on_asset_delete` | asset id (string) | Asset permanently deleted |
| `on_asset_trash` | asset ids (string[]) | Assets moved to trash |
| `on_asset_restore` | asset ids (string[]) | Assets restored from trash |
| `on_asset_hidden` | asset id (string) | Asset hidden |
| `on_asset_stack_update` | asset ids (string[]) | Stack membership changed |
| `on_person_thumbnail` | person id (string) | Face thumbnail (re)generated |
| `on_server_version` | `ServerVersionResponseDto` | Server version changed |
| `on_config_update` | — | Server config changed (reload config/features) |
| `on_new_release` | `ReleaseEventV1` | New Immich release available |
| `on_session_delete` | session id | Current session was revoked → re-login |
| `on_notification` | `NotificationDto` | New in-app notification |
| `on_user_delete` | user id | User deleted (admin) |
| `ResourceEventV1` | resource event | Generic resource change (handled by the web resource manager) |
| `AppRestartV1` | mode | Server restarting |
| `MaintenanceStatusV1` | status | Maintenance mode on/off |

For NOVA: subscribe to `on_upload_success`, `on_asset_update`,
`on_asset_delete`, `on_asset_trash`, `on_asset_restore` and
`on_server_version` for live timeline updates. Socket.IO is a
**separate protocol from the REST spec** — the Flutter client needs a
Socket.IO client (e.g. `socket_io_client` package), not a raw
WebSocket. Reconnect with backoff; on reconnect, re-run a
`/sync/stream` catch-up rather than trusting the socket alone.

## 6. Client integration notes (NOVA PHOTOS)

### 6.1 Recommended auth approach for a mobile client

**Use email/password login + bearer JWT, stored securely — NOT a
long-lived API key as the primary login.**

- Login: `POST /auth/login` → `accessToken` (JWT). Store it in
  platform secure storage (Android Keystore via `flutter_secure_storage`).
  Send as `Authorization: Bearer <token>` on every call.
- **There is no refresh-token endpoint in the spec.** The JWT is a
  session token; the official mobile app re-validates with
  `POST /auth/validateToken` and re-logs-in when it expires. NOVA
  must do the same: on `401`, try `validateToken`; if it fails,
  prompt for credentials again (or keep the password only if the user
  opts into "stay signed in" — prefer biometric-gated re-login).
- **API keys** (`x-api-key`) are the right tool for *secondary*
  access: a user-generated key with a minimal permission set
  (`asset.read`, `asset.view`, `asset.download`, `timeline.read`…)
  for e.g. a companion integration or a "read-only viewer" mode.
  Do **not** bake a single shared API key into the app — keys are
  per-user secrets, shown once at creation, and a leaked key with
  `asset.delete` is a data-loss vector. If NOVA ever offers "connect
  with API key" as a login alternative, request the *least*
  permissions needed and surface the missing-permission `403` with a
  clear message ("this key lacks `asset.upload` — recreate it with
  upload permission").
- OAuth: supported if the server has it (`GET /server/config` /
  `features.oauth`); use the system browser + `oauth/mobile-redirect`
  flow, never an embedded WebView that could harvest credentials.
- **Session lock / PIN:** locked (`visibility=locked`) assets need
  `POST /auth/session/unlock` + PIN before their thumbnails load.
  Handle `403` on a locked asset by prompting for the PIN, not by
  failing the whole timeline.

### 6.2 Thumbnail URL patterns

```text
{base}/api/assets/{id}/thumbnail?size=thumbnail   # grid cells (~250 px, WebP)
{base}/api/assets/{id}/thumbnail?size=preview     # full-screen viewer (1440 px JPEG)
{base}/api/assets/{id}/thumbnail?size=fullsize    # may 403 without asset.download — avoid
{base}/api/assets/{id}/original                   # original bytes; permission asset.download
```

- Always send auth headers (Bearer or `x-api-key`). Plain
  `Image.network` cannot set headers — use an authenticated image
  provider (e.g. `cached_network_image` with `httpHeaders`, or a
  custom `ImageProvider` backed by Dio).
- Use `thumbhash` from `AssetResponseDto` as a blur placeholder.
- `size=original` on the thumbnail endpoint is **deprecated in v3**;
  use `/original`.
- Thumbnails are `application/octet-stream` — sniff content type from
  the response, don't assume JPEG.

### 6.3 Upload best practice

1. `POST /assets/bulk-upload-check` with SHA-1 checksums first —
   skip anything the server says `reject` (already present).
2. Otherwise `POST /assets` multipart with `assetData`,
   `fileCreatedAt`, `fileModifiedAt` (required), `filename`, and
   `x-immich-checksum` header.
3. Treat **HTTP 200 as "duplicate"** and **201 as "created"** — both
   return `AssetMediaResponseDto {id, status}`.
4. Preserve EXIF: send original bytes untouched; the server extracts
   EXIF/GPS itself. Send `fileCreatedAt` from EXIF
   `DateTimeOriginal` when present, else file mtime.
5. Live Photos: upload the photo, then the video with
   `livePhotoVideoId` set to the photo's id (linking is via that
   field on `AssetMediaCreateDto` / `UpdateAssetDto`).
6. Upload one file per request, in the background (WorkManager), with
   retry + backoff; there is **no resumable/chunked upload** in the
   public API.
7. After upload, the server processes thumbnails/ML asynchronously —
   expect `on_upload_success` over the socket, or poll
   `GET /assets/{id}` until thumbnails exist.

### 6.4 WebSocket endpoint + auth

- URL: `wss://<host>/api/socket.io/` (Socket.IO v4, path `/api/socket.io/`).
- Auth: same JWT as REST (Socket.IO `auth` payload / `Authorization`
  header — **verify the exact handshake against a live server in
  Stage 4**; it is not in the OpenAPI spec).
- Subscribe to at least: `on_upload_success`, `on_asset_update`,
  `on_asset_delete`, `on_asset_trash`, `on_asset_restore`,
  `on_server_version`, `on_config_update`, `on_session_delete`.
- Treat the socket as a *hint*, not the source of truth: on
  reconnect, catch up with `POST /sync/stream` + ack.

### 6.5 Top gotchas (checklist for the build)

1. **No `GET /assets` list** — list via `POST /search/metadata` or the timeline buckets.
2. **Albums don't embed assets** (v3) — fetch contents via search with `albumIds`.
3. **`total` is deprecated** in search responses — page with `nextPage`/`nextCursor`.
4. **Duration is a string in v3** (`"HH:MM:SS.mmm"`), was a number in v2.
5. **`deviceId`/`deviceAssetId` removed** from upload in v3.
6. **No `DELETE /assets/{id}`** — bulk delete only.
7. **No `GET /trash`** — trash is queried through search filters.
8. **No "devices" API** — device/session info is `GET /sessions`.
9. **Error shapes are undocumented** — parse defensively; correlation id is in `X-Correlation-ID`.
10. **`PUT` → `PATCH` migration announced**: several endpoints note
    "PATCH will become the default in v4, and PUT will be dropped in
    v5" — prefer `PATCH` where both exist (albums, people, tags).
11. **Timeline endpoints are marked `Internal`** — stable in practice,
    but pin behaviour with a test against the target server version.
12. **Feature-gate on `GET /server/features`** (smart search, faces,
    map, trash, OCR) — never assume a feature exists.
13. **Permissions are granular** — a `403` usually means the API key
    lacks that one scope, not that the user is unauthorised.
14. **No rate limits documented** — but use bulk endpoints and the
    sync stream instead of polling.
15. **Version-check on every launch**: `GET /server/version` +
    `featureLevel`; refuse/ warn when the server is v2.x (see
    `API_VERSION_COMPATIBILITY.md`).

## 7. Research method & provenance

- Fetched `https://raw.githubusercontent.com/immich-app/immich/v3.4.2/open-api/immich-openapi-specs.json`
  (HTTP 200, 974,791 bytes) and `main` (990,700 bytes, v3.4.0-rc.0).
- `https://api.immich.app/` returns the interactive docs SPA (HTTP
  200); `https://api.immich.app/openapi.json` returns the same SPA
  HTML, **not** a spec — the spec lives in the GitHub repo.
- Live unauthenticated check: `GET https://demo.immich.app/api/server/version`
  → 3.4.2 / featureLevel 2. No login was performed anywhere.
- WebSocket event list: `web/src/lib/stores/websocket.ts` from
  `immich-app/immich` `main`, fetched 2026-11-22.
- Latest release: GitHub API `repos/immich-app/immich/releases/latest`
  → `v3.4.2`, published 2026-11-18T20:14:51Z.
- Research date: **2026-11-22**. Immich ships roughly monthly; re-fetch
  the spec per release.
