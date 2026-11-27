# NOVA PHOTOS — Security & Privacy

## Threat model

NOVA PHOTOS connects to a server the user chooses (their own Immich instance or the public demo). The app holds the keys to the user's entire photo library on that server. The security model protects: the access token, the server URL, the user's photos in transit and at rest on the device, and the local backup queue.

## Credential storage

- The Immich access token (JWT from `POST /auth/login`) and the session cookie are stored **only** in `flutter_secure_storage`, which uses the Android Keystore on Android. They are never written to SharedPreferences, SQLite, plain files, or logs.
- The server URL is stored alongside the token in secure storage.
- No password is ever stored: login sends the password once over HTTPS and discards it. A 401 response means re-login; there is no refresh-token flow in the Immich API v3 spec.
- Logout wipes the secure store and the local database mirror.
- The demo server credentials used for testing are read from environment variables at test time only and are never committed to the repository.

## Transport

- HTTPS only. The app refuses plain-HTTP server URLs except `http://localhost` / `http://10.0.2.2` for local development, and warns the user when they enter one.
- TLS verification is **never disabled**. No `badCertificateCallback`, no trust-all-certificates code, no custom `HttpClient` that skips verification.
- All API calls carry `Authorization: Bearer <token>`. Thumbnails use the same header (via `cached_network_image` headers) so the image cache never contains unauthenticated URLs.
- The app never sends the token to any host other than the configured server URL.

## Authorization

- The app only requests what the logged-in user is allowed to see: Immich enforces per-user ownership server-side. The app never attempts to read another user's assets, bypass sharing permissions, or escalate privileges.
- Shared links are created only through the user's explicit action, with the permissions/expiry the user chooses. The app never creates a public link silently.
- Admin endpoints (`/server/*` administration) are not called by the app.

## Local data

- The offline mirror (Drift/SQLite) contains the user's own asset metadata and thumbnails cached from their server. The database file lives in the app-private directory (not world-readable, not on external storage).
- Cached thumbnails are stored in the app-private cache directory and can be cleared from Settings.
- The upload queue records local file paths and SHA-1 checksums — no photo contents are written to logs.
- On logout, the local database and caches are deleted.

## Logging

- Logs never include: access tokens, cookies, passwords, API keys, server credentials, or photo contents.
- Error reports include only the HTTP status, the endpoint path, and the server's error message (which may include a correlation ID). Upload failures log the file name and the error, never the file bytes.

## Permissions (Android)

Requested only as needed, with in-app explanations:

- `READ_MEDIA_IMAGES` / `READ_MEDIA_VIDEO` (Android 13+) or `READ_EXTERNAL_STORAGE` (older) — only for the backup engine to scan local media the user asked to back up.
- `POST_NOTIFICATIONS` — only to show backup progress.
- `ACCESS_NETWORK_STATE` — to honor Wi-Fi-only backup.
- `FOREGROUND_SERVICE` + `FOREGROUND_SERVICE_DATA_SYNC` — only while an upload batch is actively running.
- `INTERNET` — required.
- No location permission is requested for the map view: map markers use GPS metadata already stored on the server's assets, never live device location.

## Privacy

- No analytics, no crash reporting, no advertising SDKs, no third-party trackers in the app.
- No data leaves the device except to the user's configured Immich server (API calls, uploads) and, if the user shares, to the Android share sheet targets they choose.
- The app does not read the user's contacts, calendar, or other apps' data.

## Known limitations

- Token lifetime is governed by the server (no refresh flow in API v3); users on servers with short sessions will be asked to log in again.
- If a user's server uses a self-signed certificate, the app will refuse the connection rather than bypass validation. Users should install a proper certificate (e.g. via a reverse proxy with Let's Encrypt) — the app will not add a trust exception.
- The local database is protected by Android app-private storage, not by SQLCipher-level encryption; a rooted device could read it. This matches the official Immich mobile app's posture and is documented here rather than hidden.
