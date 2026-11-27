# NOVA PHOTOS — Testing Report

All results below are from real runs in this VM on 2026-11-22. Nothing is claimed without a run behind it.

## Summary

| Suite | Result |
|---|---|
| `flutter analyze --no-pub` | **No issues found!** (verified by coordinator after Tracks B + C merged) |
| `flutter test` (full suite) | **82 passed, 0 failed, 1 skipped** |
| Live smoke test vs demo server | **Passed** (1 test, run with `DEMO_USER`/`DEMO_PASS` env vars) |
| `flutter build apk --release` (local) | **Failed** — Gradle daemon handshake (see BUILD_INSTRUCTIONS.md) |

## Unit / widget tests (82 passed, 0 failed)

Run: `flutter test` in `~/workspace/nova-photos/app/` (no env vars; live smoke skipped).

- **Track A (39 tests):** model parsing (assets, albums, search responses), auth service with mock HTTP, error mapping (incl. Zod message arrays + `X-Correlation-ID`), media URL builders, cookie extraction, pagination (nextPage + nextCursor preference), SHA-1 test vectors, bulk-upload-check split logic.
- **Track B (+18 tests, `test/track_b_test.dart`):** timeline grouping/labels/duration/offset/on-this-day helpers, selection mode, recent-searches store (including corrupt-file case), album + search API against `MockClient`, photos-notifier local updates, `AssetTile` badges, viewer paging across a result set.
- **Track C (+25 tests, `test/track_c_test.dart`):** upload queue state machine, retry/backoff delays (exact 2s/4s), SHA-1 dedup split + streaming file SHA-1, sync-stream JSONL parsing (blank/malformed lines skipped, acks kept), settings, Drift DAO round-trips including crash recovery, sync `applyRecord`, pending-ops replay order + 404 server-wins, engine end-to-end (duplicate skipped, retry-then-success, exhausted-retries failure state).

Two Track B tests failed transiently during Track C's run (dayLabel weekday, ViewerScreen widget) because Track B was still editing them; both pass in the final suite.

## Live smoke test (passed)

Run: `DEMO_USER='demo@immich.app' DEMO_PASS='demo' flutter test --tags live` (public demo credentials from Immich's own README; env vars only, never committed).

- Server version: **Immich 3.4.2, featureLevel 2** (`GET /api/server/version`)
- Login OK as demo@immich.app (user "Jane Doe")
- Features: smartSearch=true, facialRecognition=true, trash=true
- Library statistics: **32,892 images, 52 videos, 32,944 total**
- `POST /search/metadata` page 1: 10 assets, `hasNextPage=true`; first asset `6418c37d-…`, IMAGE, taken 2025-04-30
- Thumbnail fetch: **6,656 bytes**
- Timeline: **205 buckets**; first bucket 2025-04-01, count 5; bucket fetch returned 5 assets

Full record: `app/SMOKE_TEST.md`.

## What was NOT tested

- **No on-device test.** There is no Android device or emulator in this VM, and no APK was produced locally (Gradle daemon failure). The app has never been installed or tapped-through on a real phone. First-run UI testing (login screen, timeline scroll, viewer gestures, backup dashboard) is the first job once the cloud-built APK exists.
- **No live sync/backup run.** The sync engine and backup engine are unit-tested with mocks, but no live `/sync/stream` or real upload was run against the demo server (no demo credentials were present in the Track C session; the Track A smoke test covers the underlying endpoints only). A live pass is documented as remaining work.
- **No background WorkManager run on-device.** Registration + headless dispatcher are wired; the 6-hour periodic task has never executed.
- **No performance measurement.** Startup time, scroll frame rate, memory under a 30k-asset library, and upload throughput are unmeasured — no device to measure on. Do not quote performance figures for this build.
- **No security penetration test.** The security model (Keystore storage, HTTPS-only, no token logging) is implemented and reviewed in `SECURITY.md`, but no independent audit was performed.

## Bugs found by testing (all fixed)

1. `POST /search/metadata` returns a `{albums, assets}` wrapper — the first client parsed the wrapper as the page and got 0 items. Fixed: `SearchResult` parses the wrapper (bare page still accepted defensively).
2. Timeline buckets are date-only strings (`"2025-04-01"`); parser handles both formats.
3. `MetadataSearchRequest.copyWith` could not clear `page`/`cursor` (`??` kept old values) — fixed with a sentinel.
4. Sync-stream `types` takes `SyncRequestType` values (`AssetsV2`, `AlbumsV2`, …), not the `SyncEntityType` values Track A first used — translation added (`syncRequestTypesFor()`), verified against the spec.
