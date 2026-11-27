# immich-library-mcp

[MCP](https://modelcontextprotocol.io) server for an
[Immich](https://immich.app) photo library (built against Immich v3.3.3).
It lets an agent search the library by content (CLIP smart search) or by
metadata, read EXIF/people/album/tag detail, count and map the library,
**look at the photos themselves** (preview/thumbnail images and numbered
contact sheets returned as MCP image content), analyse it (duplicates,
largest files, stacks, activity, processing queues), **export
browser-ready files plus a metadata manifest**, stage originals on a shared
mount for other MCP servers and, with a second key, **organise** it
(favourites, ratings, descriptions, dates, locations, tags, albums, people,
uploads, reprocessing).

Two keys, two trust levels:

- **`IMMICH_API_KEY` (always): read-only.** Scope it to read permissions
  only, so Immich itself refuses writes (the integration suite asserts a
  `403` on album create). With only this key the server is read-only: the
  curation tools are not registered at all, and the only writes are local
  files (the shared mount and the export folder).
- **`IMMICH_WRITE_API_KEY` (optional): curation.** Scoped to exactly the 13
  write permissions the curation tools use and **no read permissions**, so
  every lookup still goes through the read key. It cannot delete or trash
  photos, share anything, or touch admin settings (the integration suite
  asserts `403`s on `/server/about`, `DELETE /assets` and
  `POST /shared-links`). Give it only to clients that should organise the
  library; a shared HTTP deployment (chat front ends, automation) can run without it.

## Install

```bash
uvx immich-library-mcp --stdio        # or: pip install immich-library-mcp
```

The distribution is `immich-library-mcp` (the name `immich-mcp` on PyPI belongs to
another project); the import package is `immich_mcp`, and both `immich-library-mcp`
and `immich-mcp` commands are installed. Claude Desktop / Claude Code (stdio):

```json
{"mcpServers": {"immich": {"command": "uvx", "args": ["immich-library-mcp", "--stdio"],
  "env": {"IMMICH_URL": "http://localhost:2283", "IMMICH_API_KEY": "<read-only key>"}}}}
```

## Tools

All tools take at least one parameter (Claude.ai's remote client rejects
empty schemas). Every read tool carries `readOnlyHint`. The local file
writers (`immich_download`, `immich_export`, `immich_export_cleanup`) and
the curation tools don't; `immich_export_cleanup`, `immich_delete_album`,
`immich_delete_tag` and `immich_merge_people` are marked `destructiveHint`
(and prompt for confirmation through the fleet's MCP guard).

### Reading

| Tool | What it does | Key parameters |
|------|--------------|----------------|
| `immich_search` | Find assets. `query` → CLIP smart search; empty → metadata browse by capture date | `query`, `people` (comma-sep, AND), `album`, `tags`, `city`/`state`/`country`, `camera_make`/`camera_model`, `media_type` `any\|photo\|video`, `favorite_only`, `year` or `taken_after`/`taken_before` (`YYYY`, `YYYY-MM`, `YYYY-MM-DD`), `text_in_image` (OCR), `filename`/`description` (browse only), `visibility` `timeline\|archive\|hidden\|all`, `order` `newest\|oldest`, `limit` ≤100, `page` |
| `immich_count` | How many assets match | same filters (no `query`); `group_by` `total\|year\|month` (grouped = timeline: one person/album/tag, favourite, year, visibility) |
| `immich_get_asset` | Full metadata: EXIF, GPS + place, people, tags, albums, live-photo link, OCR text | `asset_id`, `include_ocr` |
| `immich_view` | Returns the images (with caption lines) so the model can see them | `asset_ids` (list), `size` `preview` (JPEG, 1440 px short side, ≤6) \| `thumbnail` (~250 px WebP, ≤20) |
| `immich_contact_sheet` | One grid JPEG of up to 50 thumbnails, each stamped with its index (`VID` = video), plus a text legend index → id, date, place, people | `asset_ids` (≤50), `columns` (0 = auto, ≤10), `tile_px` 100–400 |
| `immich_people` | Named people (face clusters), optional asset counts | `name` (lookup), `include_unnamed`, `include_hidden`, `with_counts`, `limit` |
| `immich_albums` | Albums with counts and date span | `name_filter`, `sort` `name\|newest\|size` |
| `immich_places` | Geotagged counts per country/state/city | `level`, `country`, `year`/`taken_after`/`taken_before`, `favorite_only`, `limit` |
| `immich_memories` | "On this day" memories | `on_date` (YYYY-MM-DD, default today), `limit_per_memory` |
| `immich_overview` | Library summary (version, totals, span, people, albums, tags, countries) | `include_lists` |
| `immich_download` | Save one original/fullsize/preview: on the shared mount (`shared:<filename>`, for other MCP servers) or in the export folder | `asset_id`, `size`, `destination` `shared\|export`, `subfolder` (export only) |
| `immich_export` | Export up to 200 assets as browser-ready files + `manifest.json` into `EXPORT_DIR/<folder>` (details below) | `asset_ids`, `folder`, `size`, `format`, `max_edge_px`, `quality`, `filename_pattern`, `include_video` |
| `immich_export_cleanup` | Delete export folders/files whose newest file is older than N days | `older_than_days`, `dry_run` |

### Library analysis (read)

| Tool | What it does | Key parameters |
|------|--------------|----------------|
| `immich_duplicates` | Immich's duplicate groups (visually near-identical), with sizes, dimensions, the suggested keeper and reclaimable space | `limit` ≤200, `sort` `wasted\|copies` |
| `immich_large_assets` | Biggest files first | `media_type`, `min_size_mb`, `year`/`taken_after`/`taken_before`, `city`, `country`, `limit` ≤100 (no people/album filter: Immich 3.3's endpoint mis-parses list and boolean filters) |
| `immich_random` | Random assets, narrowed by the search filters | `count` ≤50, `people`, `album`, `tags`, `city`, `country`, `media_type`, `favorite_only`, `year`/`taken_after`/`taken_before` |
| `immich_stacks` | Bursts / RAW+JPEG pairs: list stacks, or every member of one asset's stack | `asset_id`, `limit` |
| `immich_activity` | Photos per day: total, active days, busiest days, per-month totals (every day when ≤62 days) | `start`/`end` (YYYY-MM-DD, default last 365 days), `by` `taken\|upload` |
| `immich_processing_status` | Background queues (faces, OCR, smart search, thumbnails …): waiting/active/failed | `include_idle` |
| `immich_folders` | Folders Immich stores originals under, or the assets in one | `path`, `contains`, `limit` |
| `immich_album` | One album: description, count, span, users, order, cover, top places, first N assets | `album` (name or id), `include_assets` ≤100 |
| `immich_person` | One person: flags, asset count, link, and their face thumbnail as an image | `person` (name or id), `include_face` |

`immich_get_asset` also returns Immich's per-asset key/value metadata, the
stack it belongs to and its duplicate group.

### Organising (only with `IMMICH_WRITE_API_KEY`)

| Tool | What it does | Key parameters |
|------|--------------|----------------|
| `immich_update_assets` | Change up to 200 assets; only the fields passed change. Returns each asset's previous values so the change can be put back | `asset_ids`, `favorite`, `archived`, `rating` (1–5, -1 rejected, 0 clear), `description` (`''` clears), `taken` (`YYYY-MM-DD HH:MM[:SS]` local) + `time_zone` (IANA), or `shift_minutes`, `latitude` + `longitude` |
| `immich_tag_assets` | Tag (creating missing tags; `Parent/Child` nests) or untag up to 1000 assets | `asset_ids`, `tags` (comma-sep), `remove` |
| `immich_delete_tag` | Delete a tag everywhere (assets untouched); reports how many had it. Destructive, asks first | `tag` |
| `immich_create_album` | New private album, optionally with assets; flags a name clash | `name`, `description`, `asset_ids` ≤1000 |
| `immich_update_album` | Rename, describe, set cover or sort order | `album`, `name`, `description`, `cover_asset_id`, `order` `oldest\|newest` |
| `immich_album_assets` | Add/remove assets (removing keeps them in the library) | `album`, `add`, `remove` (≤1000 each) |
| `immich_delete_album` | Delete an album; its photos stay. Destructive, asks first | `album` |
| `immich_update_person` | Name/rename a face cluster, birth date, hide, favourite, face-thumbnail photo; flags an existing person with the same name | `person`, `name`, `birth_date`, `hidden`, `favorite`, `cover_asset_id` |
| `immich_merge_people` | Move every face of `merge` into `into`. Cannot be undone. Destructive, asks first | `into`, `merge` (comma-sep) |
| `immich_upload` | Upload from the shared mount (`shared:<file>`) or export folder (`export:<folder>/<file>`); files Immich already has come back `duplicate` (SHA-1 checksum) | `source`, `album`, `favorite`, `archived`, `description` |
| `immich_reprocess` | Queue `refresh-faces` \| `refresh-metadata` \| `regenerate-thumbnail` \| `transcode-video` for ≤500 assets | `asset_ids`, `job` |

Edits never modify original files: Immich keeps them in its database and
an XMP sidecar. `immich_upload` only reads from the two hand-off folders
(symlinks out of them are refused) and only accepts the extensions Immich
lists in `/server/media-types`.

Names (people, albums, tags) resolve exact → case-insensitive → unique
substring; ambiguous names error with the candidates. UUIDs pass through.

Times are the camera's local wall clock (Immich `localDateTime`); bare dates
in filters are interpreted in `TZ`.

## Gallery exports

`immich_export` writes into `EXPORT_DIR/<folder>` — a persistent, non-hidden
folder (default `~/Pictures/Immich Exports`, created at startup) that you can
connect to another tool once and leave connected. Nothing sweeps it; prune with
`immich_export_cleanup(older_than_days=…)`. Because cleanup deletes inside it,
`EXPORT_DIR` must be a dedicated folder: `~`, `~/Pictures`, `~/Desktop` etc. are
refused.

| Parameter | Default | Notes |
|-----------|---------|-------|
| `asset_ids` | — | Up to 200; duplicates collapsed |
| `folder` | — | One plain folder name, e.g. `china-food-2026-10-16` |
| `size` | `preview` | `thumbnail` (~250 px) \| `preview` (1440 px short side) \| `fullsize` \| `original` |
| `format` | `jpeg` | `jpeg` \| `webp` re-encode; `keep` = bytes exactly as Immich serves them |
| `max_edge_px` | 0 (none) | Downscale only (64–10000); needs `jpeg`/`webp` |
| `quality` | 82 | 1–100 |
| `filename_pattern` | `{taken:%Y-%m-%d_%H%M}_{short_id}.{ext}` | Fields: `{taken}` (datetime, any strftime spec), `{short_id}`, `{id}`, `{stem}` (original name), `{index}` (1-based input order, e.g. `{index:03d}`), `{city}`, `{country}`, `{type}`, `{ext}`. Sanitised to a bare filename; `.{ext}` appended if missing |
| `include_video` | false | Videos always export a poster-frame image; this adds Immich's web-playable video (`/video/playback`, the transcoded MP4) beside it |

**Where pixels come from.** Immich renditions first: `thumbnail`/`preview` are
Immich's own; `fullsize` follows Immich's redirect (the original for web formats,
the preview where Immich has no full-size rendition). Local conversion
(Pillow + pillow-heif) only fills the gaps: HEIC originals at `fullsize`/`original`
are decoded and re-encoded locally. Camera RAW (ARW, NEF …) can't be decoded
here, so it falls back to Immich's preview, flagged in that asset's `note`
(turn on Immich's *Full-size image* generation for true full-res RAW).
Re-encoded files keep the colour profile (iPhone Display P3) and EXIF
orientation, and **drop all other metadata, GPS included** — safe to publish.
`keep` files are untouched, so originals keep their EXIF.

**Dedupe.** If the folder's manifest already has the asset with the same
settings and its file still matches the recorded sha256, it is skipped with
no download (`unchanged`). Otherwise new bytes identical to the file on disk
are not rewritten. A name clash with another asset, or with a file no
manifest owns (your own edits), gets a `-2` suffix rather than being
overwritten. If a re-export renames an asset's file (new pattern or format),
its old file is removed.

**manifest.json** is a JSON array, one entry per exported asset, sorted by
capture time. It accumulates across runs (an asset re-exported replaces its
entry):

```json
{
  "asset_id": "a1b2c3d4-…", "file": "2009-12-02_0135_a1b2c3d4.jpg",
  "width": 1920, "height": 1440, "bytes": 285982, "sha256": "5f1d…",
  "taken": "2009-12-02T01:35:46", "place": "Kyoto, Japan", "city": "Kyoto",
  "country": "Japan", "camera": "Canon IXY DIGITAL 10", "people": ["…"],
  "immich_url": "https://photos.example.com/photos/a1b2c3d4-…",
  "type": "image", "duration_s": null, "variant": "preview/jpeg/0/q82"
}
```

Videos add `video_file`, `video_bytes`, `video_sha256` when exported with
`include_video`. `variant` records the export settings (for dedupe).
`immich_url` is the plain web link; the API key never appears in any URL,
filename or manifest.

The tool returns the absolute `folder` and `manifest` paths, `count`,
`total_bytes`, `by_status` and per-asset `{asset_id, status, file, note?,
error?}` with status `exported` | `updated` | `unchanged` | `failed`.
Failures are per asset; the rest of the batch still exports. Downloads run 5
at a time, with at most 2 large decodes in parallel.

## Configuration

| Env | Default | Notes |
|-----|---------|-------|
| `IMMICH_URL` | `http://immich:2283` | Server base URL, no `/api` |
| `IMMICH_API_KEY` | — | Scope read-only: `asset.read asset.view asset.download asset.statistics album.read album.statistics person.read person.statistics tag.read timeline.read map.read map.search memory.read server.about user.read duplicate.read stack.read queue.read folder.read` |
| `IMMICH_WRITE_API_KEY` | — (curation tools off) | Optional. Scope to exactly `asset.update asset.upload tag.create tag.asset tag.delete album.create album.update album.delete albumAsset.create albumAsset.delete person.update person.merge job.create` |
| `IMMICH_PUBLIC_URL` | `IMMICH_URL` | Browser-facing base for the `url` on every row; set it when the server reaches Immich by an internal address |
| `SHARED_DIR` | `/shared` | Cross-MCP mount for hand-offs to other MCP servers |
| `EXPORT_DIR` | `~/Pictures/Immich Exports` | Persistent export root (`immich_export`, `immich_download(destination='export')`); must be a dedicated folder |
| `MAX_DOWNLOAD_BYTES` | 2 GiB | Cap per streamed file (originals, videos) |
| `IMMICH_TIMEOUT` | 60 | Seconds; cold smart search pays a CLIP model load |
| `TZ` | UTC | For date filters |
| `PORT` | 8336 | HTTP mode |
| `MCP_BEARER_TOKEN` | — | Required for HTTP mode (fails closed) |

## Running

```bash
# stdio (interactive clients; no network surface, no bearer)
uvx --env-file .env immich-library-mcp --stdio

# Streamable HTTP at /mcp (stateless, bearer-authenticated)
MCP_BEARER_TOKEN=... IMMICH_API_KEY=... immich-mcp

# container
podman build -t immich-library-mcp .
```

Sync tool bodies run in a worker thread (one slow upstream call never
stalls the event loop) and each call logs `tool=X outcome=Y duration_ms=N`
to stderr. Argument values are never logged (httpx request logging is
silenced because query strings carry names).

## Testing

```bash
uv run --extra test pytest -q                       # tier 1 + 2 (mocked)
IMMICH_TEST=1 uv run --env-file .env \
    --extra test pytest tests/test_integration.py -v   # tier 3, live
```

The live curation tests run only when `IMMICH_WRITE_API_KEY` is in the env
too. They change one real photo and one named person and restore every
value in a `finally` (favourite, rating, description, a +60/−60 minute time
shift, location), and create and delete their own album and tag. Merging
people is never run live.

- `tests/test_formatting.py` — pure helpers (date bounds, rows, aggregation, name matching)
- `tests/test_client.py` — request shapes, errors, caching, streaming download
- `tests/test_server.py` — every tool through a mocked Immich, schema/annotation and bearer checks
- `tests/test_library.py` — the library-analysis tools (duplicates, large assets, random, stacks, activity, queues, folders, album, person)
- `tests/test_curation.py` — curation tools: request bodies, validation sends nothing, previous-value capture, upload path confinement, which key each request carries, registration only with the write key
- `tests/test_export.py` — HEIC/JPEG/WebP encoding (orientation, ICC kept, EXIF/GPS stripped), filename patterns, name claiming, manifest, cleanup, contact sheet
- `tests/test_gallery.py` — `immich_export` end to end against real image bytes and Immich's fullsize 302s: manifest schema, dedupe, HEIC/RAW paths, video, per-asset failures, collisions, cross-origin redirect refusal
- `tests/test_integration.py` — live: scope probes (403), search → detail → view, counts, places, download, HEIC + video export round trip, contact sheet, library analysis; with the write key, the restore-everything curation round trips
