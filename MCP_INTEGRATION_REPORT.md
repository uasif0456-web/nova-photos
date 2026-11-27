# MCP Integration Report — Immich MCP Servers (NOVA PHOTOS, Stage 3)

> Research date: **2026-11-22**. All servers below are **third-party** —
> **Immich ships no official MCP server.** There is no MCP support in the
> `immich-app/immich` repo, no MCP section on https://docs.immich.app/,
> and no mention of MCP in the official OpenAPI spec. Every project here
> is a community wrapper around the same public REST API catalogued in
> `IMMICH_API_CATALOGUE.md`.
>
> Method: web search + GitHub repository search
> (`api.github.com/search/repositories?q=immich+mcp`, 31 matches) +
> README fetched from each repo's `main`/`master` branch (HTTP 200) and
> existence confirmed via the GitHub API. Star counts are from
> 2026-11-22 and will move; treat them as a rough popularity signal, not
> a quality verdict. No MCP server was installed or run — this is
> documentation-level research only.

## 0. Verdict up front

- **Real Immich MCP servers exist — at least 10.** They fall into two
  families: (a) **generated full-API servers** that expose one MCP tool
  per OpenAPI operation (~276 tools), and (b) **curated servers** with
  20–100 hand-picked tools for library browsing/curation.
- **None is official, none is needed for NOVA PHOTOS.** NOVA is a
  Flutter app that should talk to the Immich REST API directly
  (Dio + generated Dart models). An MCP server is a bridge for
  *AI assistants* (Claude Desktop/Code, ChatGPT connectors) to drive a
  photo library — a different product surface. MCP is relevant to NOVA
  only as a **reference/competitor surface** and as a **testing aid**:
  the curated servers document the exact REST calls for common flows,
  and the generated ones prove the OpenAPI spec is machine-usable.
- **If the mission later wants "ask an AI about my photos"**, the best
  candidates are `drolosoft/immich-photo-manager` (best tested, 94
  tools) or `JoeRu/mcp4immich` (full API, strongest safety model).
  Do **not** adopt any of them without a fresh security review: every
  one of them holds a privileged API key and several expose destructive
  tools by default.
- **Do not confuse MCP servers with the official Immich CLI** (`immich
  upload` etc.) or the official SDKs (`@immich/sdk` TypeScript,
  generated Dart SDK in `mobile/openapi`). Those are official; the MCP
  servers are not.

## 1. Comparison table

| # | Server | Repo | Lang / runtime | Tools | Transport | Auth to Immich | Stars* | Updated* |
|---|---|---|---|---|---|---|---|---|
| 1 | **mcp4immich** (ex-`claw2immich`) | https://github.com/JoeRu/mcp4immich | Python 3.12+, MCP Python SDK 2.x | **282** (276 generated + 6 hand-written) | stdio, HTTP, OAuth 2.1 resource server | API key (`x-api-key`); bearer token also supported | 4 | 2026-11-20 |
| 2 | **immich-mcp** (okopok) | https://github.com/okopok/immich-mcp | TypeScript, `@immich/sdk` | **276** (every OpenAPI op) | stdio / HTTP / both | API key or access token | — | — |
| 3 | **immich-photo-manager** (drolosoft) | https://github.com/drolosoft/immich-photo-manager | Python, MCP SDK | **94** curated | stdio, Streamable HTTP (port 8626 Docker) | API key (`x-api-key`) | 65 | 2026-11-18 |
| 4 | **immichctrl / immich-mcp** (lidless-labs) | https://github.com/lidless-labs/immichctrl | TypeScript/Node, `@immich/sdk` | **74** across 16 domains | stdio (`immichctrl mcp`), HTTP | API key | — | — |
| 5 | **ImmichMCP** (barryw) | https://github.com/barryw/ImmichMCP | TypeScript | **49** | stdio / HTTP; `gateway` mode (tools on demand) | API key | 59 | 2026-11-21 |
| 6 | **immich-mcp** (whitehara) | https://github.com/whitehara/immich-mcp | Python 3.11+ (`httpx`) | **40+** | stdio / Streamable HTTP (Docker :8000) | API key | — | — |
| 7 | **immich-library-mcp** (snickery) | https://github.com/snickery/immich-library-mcp | Python (`uvx` / PyPI) | ~30 (read + optional curation) | stdio | **Two keys**: read-only key + optional write key | — | — |
| 8 | **immich-mcp** (mattmaas) | https://github.com/mattmaas/immich-mcp | TypeScript/Node 20+ | **22** | stdio | API key | — | 2026-09-06 created |
| 9 | **immich-mcp-server** (pimpmypixel) | https://github.com/pimpmypixel/immich-mcp-server | TypeScript/Node | ~17 (albums/assets/search) | stdio / Docker | API key | 3 | 2026-08-02 |
| 10 | **Immich-MCP-server** (wanjau2) | https://github.com/wanjau2/Immich-MCP-server | Python (PyPI `immich-mcp` 0.5.7, 2025-09-03) | UNKNOWN (not fully verified — see §2.10) | stdio / HTTP, ChatGPT connector focus | API key + own bearer token for the MCP endpoint | — | — |

\* Stars/updated from the GitHub search API on 2026-11-22; "—" = not
returned in the top results (low stars). Star counts are a weak signal
here: the most-starred projects are the curated ones, while the
full-API generators are newer.

Note on naming collisions: **four different projects call themselves
`immich-mcp`** (okopok, whitehara, mattmaas, and the PyPI package from
the wanjau2/OpenHands lineage). Always cite the **owner/repo**, never
just the name. The PyPI name `immich-mcp` belongs to the wanjau2
lineage, **not** to snickery's `immich-library-mcp` (different package).

## 2. Server-by-server findings

### 2.1 JoeRu/mcp4immich — the full-API generator with the strongest safety model

- **Repo:** https://github.com/JoeRu/mcp4immich
  (renamed from `claw2immich` on 2026-09-20; old GHCR image
  `ghcr.io/joeru/claw2immich` still works, new images at
  `ghcr.io/joeru/mcp4immich`). Version **1.0.0**.
- **Approach:** generates **one MCP tool per OpenAPI operation** from
  the running server's spec — **282 tools against Immich 3.2.1**
  (276 operations + 6 hand-written), filtered at runtime by the API
  key's actual permissions. Works against Immich **2.x and 3.x**.
  Runs on the official MCP Python SDK 2.x, protocol revision
  `2026-07-28`, still serving 2025-era clients.
- **Hand-written tools (6):** `ping_server`, `get_server_version`,
  `tool_access_report` (what this client may call + why anything is
  blocked), `write_capability_report`, `get_current_user`,
  `downloadAsset`.
- **Tool naming:** `immich_<operation>` or `immich_<method>_<path>`;
  parameters are explicitly prefixed (`path_<name>`, `query_<name>`,
  `header_<name>`, `cookie_<name>`, `body`). Responses for assets,
  albums, people, places include a `web_url` link into the Immich web
  UI when `IMMICH_EXTERNAL_DOMAIN` is set.
- **Safety (best in class):** every tool is risk-classified
  `read` / `write` / `destructive` / `destructive_admin`, with MCP
  annotations. `destructive_admin` tools (bulk delete, `POST
  /trash/empty`, `POST /duplicates/resolve`, `POST /people/merge`,
  `DELETE /admin/*`, …) are **not registered at all** unless
  `IMMICH_ENABLE_DESTRUCTIVE=true`. Destructive tools require
  `confirm=true` in the call arguments. `downloadAsset` defaults to
  creating a **shared link** (a write!) to deliver the file — only
  `inline_base64` mode is a pure read; the tool is classified `write`
  unless `IMMICH_DOWNLOAD_ASSET_DELIVERY=inline_base64`. Can act as
  an **OAuth 2.1 resource server** (what claude.ai custom connectors
  need). Profiles: `read_only` etc. via `IMMICH_PROFILE`.
- **Auth:** Immich API key; env `IMMICH_URL`, `IMMICH_API_KEY`
  (+ `IMMICH_ENABLE_DESTRUCTIVE`, `IMMICH_DOWNLOAD_ASSET_DELIVERY`,
  `MCP_EXCLUDE_TOOLS`, …). Python 3.12+, developed with `uv`; Docker
  images published to GHCR per push/release.
- **Limitations:** 282 tools ≈ large context consumption in the LLM
  client; tool set is generated from the *running* server's spec, so
  it needs network access to the spec at startup (falls back to a
  cached copy). No Flutter/Dart relevance — reference only.
- **Relevance to NOVA:** the safety model (permission-filtered tools
  + destructive gating + `tool_access_report`) is worth copying as a
  *design pattern* for any future NOVA "AI assistant" feature; the
  code itself is not reusable in Flutter.

### 2.2 okopok/immich-mcp — full-API generator on the official TypeScript SDK

- **Repo:** https://github.com/okopok/immich-mcp
- **Approach:** exposes **every operation of the official Immich API
  (276 tools across 41 API groups)**, generated from the OpenAPI spec,
  runtime built on the official **`@immich/sdk`** — the same generated
  client the Immich web UI uses, so requests are typed.
- **Tools:** all 276, with **flattened request bodies** (DTO fields as
  first-class tool arguments, easier for an LLM than nested JSON).
  Filtering via `IMMICH_MCP_TAGS` / `IMMICH_MCP_EXCLUDE_TAGS` /
  `IMMICH_MCP_TOOLS` / `IMMICH_MCP_EXCLUDE_TOOLS`, and
  `IMMICH_MCP_READONLY=1` (GET operations only).
- **Transport/config:** `stdio`, `http` or `both` (`IMMICH_MCP_TRANSPORT`);
  HTTP on `:3000/mcp` (health `/health`), optional
  `IMMICH_MCP_HTTP_AUTH_TOKEN` bearer gate. Auth to Immich via
  `IMMICH_API_KEY` **or** `IMMICH_ACCESS_TOKEN`. Docker build
  regenerates the tool manifest from the spec at build time
  (`IMMICH_SDK_VERSION` build arg pins the API version, e.g. 3.3.0).
- **Limitations:** the author notes 276 tools ≈ **~300 KiB of schemas**,
  which "consumes model context" — recommends scoping tags or
  read-only mode. Self-described as "honestly *vibecoded*… built with
  heavy AI assistance for personal use. It is not affiliated with the
  Immich team… it can modify and delete data."
- **Relevance to NOVA:** proves the `@immich/sdk` + OpenAPI route is
  the canonical way to get full coverage; also a warning that
  full-API exposure is a context and safety cost. Not a dependency.

### 2.3 drolosoft/immich-photo-manager — best-tested curated server (94 tools)

- **Repo:** https://github.com/drolosoft/immich-photo-manager
  (65 stars, updated 2026-11-18). Also ships a Claude Code plugin.
- **Approach:** curated **94 tools** for library management rather than
  1:1 API coverage, plus distinctive extras: **perceptual-hash
  duplicate detection**, geographic albums, video-frames/PDF
  photobook export, asset notes (persistent per-asset verdicts),
  calendar heatmap, OCR search.
- **Tool groups (from README):** Search (10: `search_smart`,
  `search_metadata`, `search_explore`, `search_cities`,
  `search_places`, `search_suggestions`, `search_random`,
  `search_statistics`, `search_large_assets`, `list_assets`); Albums
  (7); Assets/metadata (9 incl. `rotate_assets`,
  `revert_asset_edits`, `reverse_geocode`, `upload_asset`); Images &
  thumbnails (6 incl. batch getters); Video & PDF (4 incl.
  `get_video_frames`, `export_pdf`); People & faces (8 incl.
  `reassign_face`); Duplicates & stacks (7); Tags (7); Dates (7 incl.
  `get_calendar_heatmap`); Sharing (12: shared links, users,
  partners, activities); Download (2); Trash (4); Asset notes (5);
  Server & connection (6 incl. `update_credentials`).
  Full parameter/return documentation in `doc/MCP-TOOLS.md`.
- **Transport/config:** stdio; multi-arch Docker image serving MCP
  over Streamable HTTP on **port 8626** (`/mcp`, liveness `/health`),
  both MCP protocol eras (legacy handshake + stateless 2026-07-28),
  DNS-rebinding protection (`MCP_ALLOWED_HOSTS`). Env
  `IMMICH_BASE_URL`, `IMMICH_API_KEY`; credentials can also be set
  in-session via `update_credentials` (persisted under `/data`).
- **Testing (strongest claim of any server found):** 364 unit tests on
  CI per push; every release is run **live against real Immich 2.7.5
  and 3.1.0** in Docker, all 94 tools over MCP, state re-read after
  each write (last full run 2026-09-03, 132/132 checks on both).
- **Limitations:** Python; the Claude Code plugin stores the API key
  in the OS secure storage (good) but the Docker `update_credentials`
  path persists a key in a volume. Write tools exist (upload, delete,
  resolve duplicates) — safety is by review-prompt convention, not by
  a hard gate like mcp4immich's.
- **Relevance to NOVA:** the best-documented mapping of
  *user-facing jobs* → *Immich API calls* (e.g. dedupe, geographic
  albums, heatmap). Useful as a **functional reference** when scoping
  NOVA v2 features. Its live-test rig (real Immich in Docker, all
  tools exercised) is a model for NOVA's own integration testing.

### 2.4 lidless-labs/immichctrl — operator CLI + MCP adapter (74 tools)

- **Repo:** https://github.com/lidless-labs/immichctrl
  (README fetched from `master` branch; `main` 404s).
- **Approach:** a **ctl-first CLI** (`immichctrl server stats`,
  `immichctrl search smart "…"`, `immichctrl duplicates`, …) with an
  MCP adapter (`immichctrl mcp`, back-compat `immich-mcp` binary,
  `npx -y immich-mcp`). **74 tools across 16 domains**, built on
  `@immich/sdk`.
- **Tool list (from README):** System (5: `immich_ping`,
  `immich_get_server_info`, `immich_get_server_statistics`,
  `immich_get_capabilities`, `immich_get_storage`); Assets (11 incl.
  `immich_upload_asset_from_path` confined to
  `IMMICH_UPLOAD_BASE_DIR`); Search (3); Albums (8); Album flows (1:
  `immich_search_then_album`); People (7); Tags (7); Shared links
  (5); Activities (4); Memories (2) + Memory flows (2:
  `immich_memories_today`, `immich_daily_digest`); Duplicates (2) +
  Duplicate flows (8: categorise, byte-dupes, CLIP-dupes, keep
  strategies, audits); Stacks (4); Trash (3 incl.
  `immich_empty_trash`); Jobs (2).
- **Safety:** reads always work; **writes are off by default**
  (`IMMICH_ALLOW_WRITES=true` to expose them) and destructive calls
  additionally demand per-call `confirm: true`. The CLI itself
  exposes only read tools.
- **Limitations:** HTTP mode sessions idle-reap after 30 min; no
  per-client authorisation on the HTTP adapter (single shared API
  key). README positions it against the Immich CLI (not an MCP
  adapter) and other MCP servers (narrower coverage).
- **Relevance to NOVA:** the duplicate-flow tools (dry-run first,
  checksum-safe resolution, trash auditing) are the most careful
  dedupe design found; worth reading before NOVA implements any
  dedupe UI.

### 2.5 barryw/ImmichMCP — 49 tools, gateway mode (59 stars)

- **Repo:** https://github.com/barryw/ImmichMCP (updated 2026-11-21).
- **Approach:** TypeScript, **49 tools**, with a `gateway` mode:
  `IMMICH_TOOL_MODE=gateway` exposes only `immich_tools_list` +
  `immich_tools_enable` first, and clients enable categories on
  demand (emits `notifications/tools/list_changed`) — a direct answer
  to the "276 tools eat all context" problem.
- **Tools (from README):** `immich_ping`, `immich_capabilities`;
  Assets (13: list/get/exif/download original+thumbnail/upload
  **base64**/upload-from-path/**upload-authorize** (mint a short-lived
  upload-only URL so a client can upload without seeing the API key)
  /**upload-init**/**upload-status** (out-of-band upload sessions),
  update/bulk-update/delete/statistics); Search (metadata, smart,
  OCR, explore); Albums (8); People (5); Tags (7); plus shared
  links, activities, duplicates, memories (full list in README).
- **Testing:** `IMMICH_INTEGRATION_TESTS=true` runs a 49-tool smoke
  against a real server; mutation tests exercise every tool with
  teardown (except `immich_people_update`/`merge`, exercised with
  bogus ids).
- **Limitations:** base64 upload path is inefficient for large
  videos; the upload-authorize/init/status trio is this project's own
  invention (out-of-band upload sessions) — **not an Immich API
  feature**; verify before relying on it.
- **Relevance to NOVA:** the `gateway` (lazy tool loading) idea and
  the upload-authorize pattern are interesting for a future
  "share-to-NOVA" flow; otherwise reference only.

### 2.6 whitehara/immich-mcp — 40+ tools, Python, safety annotations

- **Repo:** https://github.com/whitehara/immich-mcp
- **Approach:** Python 3.11+, `httpx` with automatic retries
  (`IMMICH_MAX_RETRIES`, default 3). **40+ tools** across assets,
  albums, search, people, tags, shared links, activities, duplicates;
  **3 MCP prompts** (duplicate review, album organisation, untagged
  photo discovery); tool annotations (`readOnlyHint`,
  `destructiveHint`, `idempotentHint`).
- **Auth/permissions:** the README documents the exact granular
  API-key scopes per tool (e.g. `asset.read` → search/list,
  `asset.upload` → upload, `duplicate.delete` → dismiss) and a
  read-only scope set — the clearest permission mapping of any
  curated server. Immich ≥ 1.138.0 required for granular scopes;
  older servers need "All" permissions.
- **Config:** `IMMICH_BASE_URL`, `IMMICH_API_KEY`,
  `IMMICH_EXTERNAL_URL` (public URL for `web_url` links),
  `IMMICH_TIMEOUT` (default 30 s; notes `/api/duplicates` on 70k+
  libraries can exceed it — set 120 s+).
- **Limitations:** no HTTP transport documented in the excerpt
  reviewed (stdio + Docker streamable-http on :8000 per the Glama
  summary); duplicate tools can be slow on huge libraries.
- **Relevance to NOVA:** best **permission-to-feature mapping**
  reference for NOVA's own API-key scope requests (see catalogue
  §6.1).

### 2.7 snickery/immich-library-mcp — two-key trust model, image-returning tools

- **Repo:** https://github.com/snickery/immich-library-mcp
  (PyPI distribution `immich-library-mcp`; import package
  `immich_mcp`; installable via `uvx immich-library-mcp --stdio`).
  Built against **Immich v3.3.3**.
- **Approach:** read-first, with curation behind a **second key**:
  `IMMICH_API_KEY` is always **read-only** (the integration suite
  asserts a `403` on album create with it); `IMMICH_WRITE_API_KEY`
  (optional) is scoped to exactly the 13 write permissions the
  curation tools use and **no read permissions**, so every lookup
  still goes through the read key. Curation tools are not even
  registered without the write key.
- **Tools (~30):** Reading: `immich_search` (CLIP query, or metadata
  browse; filters: people/album/tags/city/state/country/camera/
  media type/favorite/year/date range/OCR/filename/description/
  visibility/order, `limit` ≤ 100), `immich_count` (incl.
  `group_by` year/month), `immich_get_asset` (EXIF, GPS+place,
  people, tags, albums, live-photo link, OCR), `immich_view`
  (returns the images as MCP image content, preview 1440 px ≤ 6 or
  thumbnail ~250 px WebP ≤ 20), `immich_contact_sheet` (grid JPEG
  of ≤ 50 thumbnails with index legend), `immich_people`,
  `immich_albums`, `immich_places`, `immich_memories`,
  `immich_overview`, `immich_download`, `immich_export` (≤ 200
  assets as browser-ready files + `manifest.json`),
  `immich_export_cleanup`; Analysis: `immich_duplicates`,
  `immich_large_assets`, `immich_random`, `immich_stacks`,
  `immich_activity`, `immich_processing_status`, `immich_folders`,
  `immich_album`, `immich_person`; Organising (write key only):
  `immich_update_assets` (≤ 200, returns previous values so the
  change can be undone), `immich_tag_assets` (≤ 1000),
  `immich_delete_tag`, `immich_create_album`, `immich_update_album`,
  `immich_album_assets`, `immich_delete_album`,
  `immich_merge_people`, …
- **Limitations:** one tool (`immich_large_assets`) documents an
  Immich 3.3 endpoint quirk (mis-parsed list/boolean filters) —
  evidence these tools are tested against real servers. Export
  writes local files (needs a shared mount in container setups).
- **Relevance to NOVA:** the **two-key model** is the cleanest
  privilege-separation pattern found, and `immich_view` /
  `immich_contact_sheet` show how an AI client consumes images —
  directly relevant if NOVA ever adds an AI-assistant surface.

### 2.8 mattmaas/immich-mcp — small bidirectional server (22 tools)

- **Repo:** https://github.com/mattmaas/immich-mcp (created 2026-09-06).
- **Tools (22, from README):** `immich_search_smart`,
  `immich_search_metadata`, `immich_search_people`,
  `immich_get_asset`, `immich_get_asset_info`,
  `immich_upload_asset`, `immich_update_asset`,
  `immich_delete_assets`, `immich_list_albums`,
  `immich_create_album`, `immich_add_to_album`,
  `immich_get_album`, `immich_list_people`, `immich_rename_person`,
  `immich_merge_people`, `immich_get_statistics`,
  `immich_run_job`, `immich_describe_photo` (generate a description
  for a photo), `immich_bulk_update`, `immich_server_info`,
  `immich_random_assets`, `immich_get_asset_by_date`.
- **Auth/config:** `IMMICH_URL`, `IMMICH_API_KEY`; Node.js 20+;
  stdio only (per README). MIT licence.
- **Limitations:** smallest curated set; **no input/output schemas
  documented** in the README (tool names + one-line descriptions
  only); `immich_describe_photo` implies an LLM call of its own,
  which is **not** an Immich API capability — its backing model is
  UNKNOWN from the README. No safety gating documented.
- **Relevance to NOVA:** minimal; the tool list is a reasonable
  "v1 feature checklist" for a photo app, nothing more.

### 2.9 pimpmypixel/immich-mcp-server — Immich 2.0-era, OpenAPI-based

- **Repo:** https://github.com/pimpmypixel/immich-mcp-server
  (created 2025-10-05, 3 stars, last README activity 2026-08-02).
- **Tools (~17, from README):** Albums (`albums_list`,
  `albums_create`, `albums_get`, `albums_update`, `albums_delete`,
  `albums_add_assets`, `albums_remove_assets`); Assets
  (`assets_list`, `assets_get`, `assets_update`, `assets_delete`,
  `assets_bulk_update`, `assets_get_statistics`,
  `assets_get_random`); Search (`search_general`, `search_smart`,
  `search_metadata`, `search_explore`). Targets **Immich 2.0 API**.
- **Limitations:** built for Immich 2.x; several endpoints it wraps
  changed or were removed in v3 (e.g. album asset embedding,
  `GET /assets` semantics) — **assume stale for v3.4.2 until
  re-verified**. Smallest documented surface; Docker + Claude
  Desktop setup documented.
- **Relevance to NOVA:** none beyond historical interest. Do not use
  as a v3 reference.

### 2.10 wanjau2/Immich-MCP-server (+ the PyPI `immich-mcp` lineage) — ChatGPT-connector focused

- **Repo:** https://github.com/wanjau2/Immich-MCP-server (existence
  confirmed via GitHub API, 2026-11-22; README **not** fetched in
  full — the summary below is from the Glama.ai mirror and PyPI, so
  tool details are **partially verified**).
- **Approach:** Streamable-HTTP MCP server designed for **ChatGPT
  custom connectors** (remote HTTPS endpoint, Cloudflare Tunnel),
  with its own bearer-token gate for the MCP endpoint (three accepted
  forms: `Authorization: Bearer`, path-embedded token, `?key=`).
- **Tools (per Glama summary):** `search` (CLIP), `fetch` (full EXIF
  for one asset — named deliberately, because ChatGPT Deep Research
  ignores all other tools), `search_by_metadata`, `list_albums`,
  `get_album`, `list_people`, `library_stats`, `server_info`,
  `get_image` (inline bytes), `get_image_link` (signed, expiring
  HMAC URL `…/img/<asset-id>/<size>/<expiry>/<signature>.jpg`),
  `create_share_link` (**off by default**). Album-restricted mode:
  the server builds the allowed asset-id set itself and refuses
  `fetch` outside it.
- **Related:** the PyPI package `immich-mcp` (latest 0.5.7,
  2025-09-03; author jerome.zeghoudi@gmail.com; originally from
  OpenHands) is a separate, older Python MCP server in the same
  lineage — env `IMMICH_BASE_URL`, `IMMICH_API_KEY`, `uv run mcp
  dev src/immich_mcp/server.py`. It is **not** the same code as
  wanjau2's repo; do not conflate them.
- **Limitations:** the signed-image-link mechanism is this project's
  own construction (Immich has no such public endpoint); the
  ChatGPT-connector focus means its tool names are optimised for
  Deep Research, not for general use. **Verify the repo README
  before citing tool schemas.**
- **Relevance to NOVA:** the `get_image_link` signed-URL idea is a
  useful pattern if NOVA ever needs to hand an image URL to an
  external viewer without sharing the API key.

### 2.11 Others found but not detailed

GitHub search returned **31 repositories** matching `immich mcp`
(name/description). The ten above are the ones with a fetchable README
and a real tool surface. The remainder are mostly forks, stubs, or
mentions (e.g. `immich-mcp` forks, dotfile repos that merely *configure*
an MCP client). Two further names appeared only in Glama.ai listings
and were **not** independently verified against GitHub in this pass —
treat as leads, not findings: any additional `immich-mcp` forks on
PyPI/npm. No other MCP server with a distinct tool surface was found.

## 3. What the MCP servers agree on (useful for NOVA)

1. **Auth is always an Immich API key** (`x-api-key` header). No MCP
   server uses the login/session flow — that is a deliberate choice:
   keys are scoped, revocable, and don't expire. (NOVA's choice of
   login+JWT for the *mobile app* is still correct — see catalogue
   §6.1 — but the MCP world standardises on keys.)
2. **Granular permissions are the safety boundary.** Every serious
   server documents the exact scopes its key needs (whitehara's table
   is the best; snickery enforces it with two keys; mcp4immich
   enforces it by *filtering the tool list* from the key's
   permissions).
3. **Smart search (`POST /search/smart`) and metadata search
   (`POST /search/metadata`) are the two workhorse tools** — every
   server exposes both.
4. **Destructive operations are the risk.** The good servers gate
   them three ways: not registering them (mcp4immich), a writes
   master-switch (immichctrl), or a separate write key (snickery).
   The weak ones (mattmaas, pimpmypixel) document no gating.
5. **Tool-count tension is real:** 276 tools = full coverage but
   ~300 KiB of schemas in the model context (okopok); curated
   servers (22–94 tools) trade coverage for usability. NOVA's
   *app* doesn't face this (native code, not tool schemas), but any
   future NOVA AI feature will.

## 4. Recommendation for NOVA PHOTOS

- **Do not integrate an MCP server into NOVA v1.** The app talks
  REST directly. MCP adds a server process, a second trust boundary,
  and no capability the REST API lacks.
- **Use this report as a reference** when scoping features: the
  curated tool lists (§2.3, §2.4, §2.7) are effectively user-validated
  feature checklists (dedupe, geographic albums, heatmap, contact
  sheets, memories-today digest).
- **If a future milestone adds an AI assistant** ("ask about my
  photos"), evaluate in this order: (1) `drolosoft/immich-photo-manager`
  — best tested, broadest curated surface; (2) `JoeRu/mcp4immich` —
  full API + strongest safety model; (3) `snickery/immich-library-mcp`
  — cleanest privilege separation. Re-verify versions, licences, and
  security posture at that time; all three are third-party code that
  would hold a privileged key to the user's library.
- **Security note for any adoption:** an MCP server with a fully
  permissioned key can delete the whole library (`POST /trash/empty`,
  bulk delete). Any adoption must use a least-privilege key, keep
  destructive tools off by default, and never expose the MCP endpoint
  to the internet without its own authentication (several servers
  ship HTTP transports with token gates — verify the gate is actually
  enabled).

## 5. Sources

- GitHub repo search, 2026-11-22:
  `https://api.github.com/search/repositories?q=immich+mcp+in:name,description&per_page=20&sort=stars`
  (31 matches; top: drolosoft/immich-photo-manager 65★,
  barryw/ImmichMCP 59★, JoeRu/mcp4immich 4★,
  pimpmypixel/immich-mcp-server 3★).
- READMEs fetched raw from GitHub (`main`/`master`, HTTP 200) for:
  JoeRu/mcp4immich, lidless-labs/immichctrl, mattmaas/immich-mcp,
  pimpmypixel/immich-mcp-server, drolosoft/immich-photo-manager,
  barryw/ImmichMCP, whitehara/immich-mcp,
  snickery/immich-library-mcp, okopok/immich-mcp. Local copies in
  this folder (`mcp-*.md`, `mcp2-*.md`).
- Glama.ai MCP directory listings for snickery/immich-library-mcp,
  okopok/immich-mcp, whitehara/immich-mcp, wanjau2/Immich-MCP-server
  (used only to corroborate tool lists; repo READMEs are primary).
- PyPI: `immich-mcp` 0.5.7 (2025-09-03), `immich-library-mcp`.
- Official Immich: no MCP server, docs page, or spec mention found
  in `immich-app/immich`, https://docs.immich.app/, or
  https://api.immich.app/ (checked 2026-11-22).
