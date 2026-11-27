/// Local Drift (SQLite) database — schema version 1.
///
/// NOVA uses Drift **without codegen** on purpose (see DEPENDENCIES.md:
/// no `drift_dev` / `build_runner`): tables are plain `CREATE TABLE`
/// statements executed in the migration's `onCreate`, and the DAOs in
/// `daos.dart` query them with Drift's `customSelect` /
/// `customStatement`. The typed surface is the DAO layer, not generated
/// table classes — the SQL is the schema of record, documented in
/// `~/workspace/nova-photos/DATABASE_SCHEMA.md`.
///
/// Layer rule: `store` never imports `api`. It stores plain rows and
/// model objects only.
library;

import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';

/// Current schema version. Bump on any table change and add the
/// matching step in [NovaDatabase.migration] (see DATABASE_SCHEMA.md
/// "Upgrade path").
const int novaSchemaVersion = 1;

/// File name of the on-device database.
const String novaDatabaseFileName = 'nova_photos.db';

/// `CREATE TABLE` statements for schema v1, in dependency order.
/// Kept as data (not code) so DATABASE_SCHEMA.md and the DB cannot
/// silently drift apart — the doc quotes these statements.
const List<String> novaSchemaV1Statements = [
  '''
  CREATE TABLE IF NOT EXISTS assets_mirror (
    id TEXT PRIMARY KEY,
    owner_id TEXT NOT NULL DEFAULT '',
    type TEXT NOT NULL DEFAULT 'IMAGE',
    original_file_name TEXT NOT NULL DEFAULT '',
    original_path TEXT NOT NULL DEFAULT '',
    checksum TEXT NOT NULL DEFAULT '',
    file_created_at INTEGER NOT NULL DEFAULT 0,
    file_modified_at INTEGER NOT NULL DEFAULT 0,
    local_date_time INTEGER NOT NULL DEFAULT 0,
    created_at INTEGER NOT NULL DEFAULT 0,
    updated_at INTEGER NOT NULL DEFAULT 0,
    width INTEGER NOT NULL DEFAULT 0,
    height INTEGER NOT NULL DEFAULT 0,
    is_favorite INTEGER NOT NULL DEFAULT 0,
    is_archived INTEGER NOT NULL DEFAULT 0,
    is_trashed INTEGER NOT NULL DEFAULT 0,
    visibility TEXT NOT NULL DEFAULT 'timeline',
    thumbhash TEXT NOT NULL DEFAULT '',
    duration_ms INTEGER,
    mime_type TEXT,
    local_path TEXT,
    sync_state TEXT NOT NULL DEFAULT 'synced',
    updated_locally_at INTEGER
  )
  ''',
  'CREATE INDEX IF NOT EXISTS idx_assets_local_date '
      'ON assets_mirror (local_date_time DESC)',
  'CREATE INDEX IF NOT EXISTS idx_assets_checksum '
      'ON assets_mirror (checksum)',
  '''
  CREATE TABLE IF NOT EXISTS albums_mirror (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL DEFAULT '',
    description TEXT NOT NULL DEFAULT '',
    owner_id TEXT NOT NULL DEFAULT '',
    asset_count INTEGER NOT NULL DEFAULT 0,
    shared INTEGER NOT NULL DEFAULT 0,
    has_shared_link INTEGER NOT NULL DEFAULT 0,
    thumbnail_asset_id TEXT,
    created_at INTEGER NOT NULL DEFAULT 0,
    updated_at INTEGER NOT NULL DEFAULT 0
  )
  ''',
  '''
  CREATE TABLE IF NOT EXISTS album_assets (
    album_id TEXT NOT NULL,
    asset_id TEXT NOT NULL,
    PRIMARY KEY (album_id, asset_id)
  )
  ''',
  'CREATE INDEX IF NOT EXISTS idx_album_assets_asset '
      'ON album_assets (asset_id)',
  '''
  CREATE TABLE IF NOT EXISTS people_cache (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL DEFAULT '',
    is_hidden INTEGER NOT NULL DEFAULT 0,
    birth_date TEXT,
    color TEXT,
    is_favorite INTEGER NOT NULL DEFAULT 0,
    thumbnail_path TEXT NOT NULL DEFAULT ''
  )
  ''',
  '''
  CREATE TABLE IF NOT EXISTS tags_cache (
    id TEXT PRIMARY KEY,
    value TEXT NOT NULL DEFAULT '',
    name TEXT NOT NULL DEFAULT '',
    color TEXT,
    parent_id TEXT
  )
  ''',
  '''
  CREATE TABLE IF NOT EXISTS asset_tags (
    asset_id TEXT NOT NULL,
    tag_id TEXT NOT NULL,
    PRIMARY KEY (asset_id, tag_id)
  )
  ''',
  '''
  CREATE TABLE IF NOT EXISTS upload_queue (
    id TEXT PRIMARY KEY,
    local_path TEXT NOT NULL,
    filename TEXT NOT NULL DEFAULT '',
    sha1 TEXT NOT NULL DEFAULT '',
    size_bytes INTEGER NOT NULL DEFAULT 0,
    state TEXT NOT NULL DEFAULT 'pending',
    retry_count INTEGER NOT NULL DEFAULT 0,
    last_error TEXT,
    server_asset_id TEXT,
    file_created_at INTEGER NOT NULL DEFAULT 0,
    file_modified_at INTEGER NOT NULL DEFAULT 0,
    created_at INTEGER NOT NULL DEFAULT 0
  )
  ''',
  'CREATE INDEX IF NOT EXISTS idx_upload_queue_state '
      'ON upload_queue (state, created_at)',
  'CREATE INDEX IF NOT EXISTS idx_upload_queue_sha1 '
      'ON upload_queue (sha1)',
  '''
  CREATE TABLE IF NOT EXISTS pending_ops (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    kind TEXT NOT NULL,
    asset_id TEXT,
    album_id TEXT,
    payload TEXT NOT NULL DEFAULT '{}',
    created_at INTEGER NOT NULL DEFAULT 0,
    attempts INTEGER NOT NULL DEFAULT 0,
    last_error TEXT
  )
  ''',
  'CREATE INDEX IF NOT EXISTS idx_pending_ops_created '
      'ON pending_ops (created_at)',
  '''
  CREATE TABLE IF NOT EXISTS sync_checkpoints (
    entity_type TEXT PRIMARY KEY,
    ack TEXT NOT NULL DEFAULT '',
    updated_at INTEGER NOT NULL DEFAULT 0
  )
  ''',
  '''
  CREATE TABLE IF NOT EXISTS settings (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL DEFAULT ''
  )
  ''',
];

class NovaDatabase extends GeneratedDatabase {
  NovaDatabase(super.executor);

  /// In-memory database for unit tests.
  factory NovaDatabase.memory() => NovaDatabase(NativeDatabase.memory());

  @override
  int get schemaVersion => novaSchemaVersion;

  // No generated tables: the schema is the raw SQL in
  // [novaSchemaV1Statements], executed by the migration below.
  @override
  List<TableInfo<Table, Object?>> get allTables => const [];

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          for (final statement in novaSchemaV1Statements) {
            await customStatement(statement);
          }
        },
        onUpgrade: (m, from, to) async {
          // v1 is the first shipped schema. Future upgrades add steps
          // here guarded by `if (from < N)`, and must be additive
          // (new tables / columns, never a destructive rewrite) so an
          // interrupted upgrade cannot lose the mirror or the queue.
          // Defensive: re-run the v1 creates (all are IF NOT EXISTS).
          if (from < 1) {
            for (final statement in novaSchemaV1Statements) {
              await customStatement(statement);
            }
          }
        },
        beforeOpen: (details) async {
          // Foreign keys are not used (the mirror is denormalised and
          // server-driven), but WAL keeps reads from blocking writes
          // during a sync burst.
          await customStatement('PRAGMA journal_mode = WAL');
        },
      );

  /// Run [action] inside a transaction.
  Future<T> inTransaction<T>(Future<T> Function() action) =>
      transaction(action);
}

/// Open (creating if needed) the on-device database file.
Future<NovaDatabase> openNovaDatabase() async {
  final dir = await getApplicationSupportDirectory();
  final file = File('${dir.path}/$novaDatabaseFileName');
  return NovaDatabase(
    NativeDatabase.createInBackground(file),
  );
}
