# NOVA PHOTOS — Live Smoke Test

## How to run

```bash
cd ~/workspace/nova-photos/app
DEMO_USER=<demo-email> DEMO_PASS=<demo-password> flutter test --tags live
```

The test is `test/live_smoke_test.dart` (`@Tags(['live'])`). Credentials
come **only** from the environment — the public demo credentials
published in Immich's own README — and are never committed, stored, or
logged (the test uses an in-memory token store and a throwaway client).
Without `DEMO_USER`/`DEMO_PASS` the test skips itself, so a plain
`flutter test` never touches the network.

## What it checks

1. `GET /server/ping` + `GET /server/version` (no auth)
2. `POST /auth/login` with the demo credentials
3. `GET /server/features` + `GET /users/me`
4. `GET /assets/statistics`
5. `POST /search/metadata` — first page of real assets
6. `GET /assets/{id}/thumbnail?size=thumbnail` — one real thumbnail
7. `GET /timeline/buckets` + `GET /timeline/bucket` for the first bucket

## Results — 2026-11-22 (run once, live)

Server: `https://demo.immich.app` — **Immich 3.4.2, featureLevel 2**
(all numbers below are real, from that run):

| Check | Result |
|---|---|
| Server ping | `{"res":"pong"}` ✅ |
| Server version | 3.4.2, featureLevel 2 ✅ |
| Login | OK as the public demo user (Jane Doe) ✅ |
| Features | `smartSearch=true`, `facialRecognition=true`, `trash=true` ✅ |
| Current user | Jane Doe ✅ |
| Library statistics | images **32,892**, videos **52**, total **32,944** ✅ |
| `search/metadata` page 1 | **10 assets**, `count=10`, `hasNextPage=true` ✅ |
| First asset | `6418c37d-35b0-4011-882d-36946bc00eb7`, IMAGE, `cc2479e3-2d66-483c-8ad9-187b237d891d.jpg`, taken 2025-04-30T00:13:05Z ✅ |
| Thumbnail fetch | **6,656 bytes** ✅ |
| Timeline buckets | **205 buckets**; first bucket 2025-04-01, count 5, bucket fetch returned **5 assets** ✅ |

`flutter test --tags live`: **1 passed, 0 failed.**

## Bugs found by this run (fixed same day)

1. **`POST /search/metadata` returns a wrapper, not a bare page.**
   The spec's `SearchResponseDto` is `{albums: {...}, assets: {...}}`
   — the asset page lives under `assets`. The first version of
   `SearchResult.fromJson` parsed the wrapper as the page and got 0
   items. Fixed: `SearchResult` now parses the wrapper (and still
   accepts a bare page defensively), and exposes album matches under
   `albums`. Verified live: 10 assets on page 1.
2. **Timeline buckets use date-only strings** (`"2025-04-01"`, not
   `YYYY-MM-01T00:00:00.000Z` as the catalogue assumed). The client's
   `DateTime.tryParse` handles both; `GET /timeline/bucket` accepts
   both formats too (verified with curl). No code change needed.
