/// DAOs for the NOVA local store.
///
/// Each DAO is a thin typed wrapper over the raw-SQL schema in
/// `nova_database.dart` (Drift `customSelect` / `customStatement` —
/// no codegen). Rows cross the boundary as plain Dart values or the
/// hand-written models in `lib/src/models/`; no API types are imported
/// here.
library;

import 'dart:convert';

import 'package:drift/drift.dart';

import '../models/album.dart';
import '../models/asset.dart';
import '../models/person.dart';
import '../models/tag.dart';
import '../models/user.dart';
import 'nova_database.dart';
import 'upload_queue.dart';

int _boolInt(bool value) => value ? 1 : 0;
bool _readBool(QueryRow row, String name) => row.read<int>(name) == 1;
DateTime _readDate(QueryRow row, String name) =>
    DateTime.fromMillisecondsSinceEpoch(row.read<int>(name), isUtc: true);

/// One row of `upload_queue`.
class UploadQueueItem {
  const UploadQueueItem({
    required this.id,
    required this.localPath,
    required this.filename,
    required this.sha1,
    required this.sizeBytes,
    required this.state,
    required this.retryCount,
    this.lastError,
    this.serverAssetId,
    required this.fileCreatedAt,
    required this.fileModifiedAt,
    required this.createdAt,
  });

  final String id;
  final String localPath;
  final String filename;
  final String sha1;
  final int sizeBytes;
  final UploadQueueState state;
  final int retryCount;
  final String? lastError;
  final String? serverAssetId;
  final DateTime fileCreatedAt;
  final DateTime fileModifiedAt;
  final DateTime createdAt;

  bool get canAutoRetry =>
      state == UploadQueueState.failed && shouldRetry(retryCount);
}

/// One row of `pending_ops`.
class PendingOperationRow {
  const PendingOperationRow({
    required this.id,
    required this.kind,
    this.assetId,
    this.albumId,
    required this.payload,
    required this.createdAt,
    required this.attempts,
    this.lastError,
  });

  final int id;
  final String kind;
  final String? assetId;
  final String? albumId;
  final Map<String, Object?> payload;
  final DateTime createdAt;
  final int attempts;
  final String? lastError;
}

/// Mirror of one server asset (subset of [NovaAsset] needed offline).
class AssetDao {
  AssetDao(this.db);

  final NovaDatabase db;

  static const _columns = 'id, owner_id, type, original_file_name, '
      'original_path, checksum, file_created_at, file_modified_at, '
      'local_date_time, created_at, updated_at, width, height, '
      'is_favorite, is_archived, is_trashed, visibility, thumbhash, '
      'duration_ms, mime_type, local_path, sync_state';

  NovaAsset _fromRow(QueryRow row) => NovaAsset(
        id: row.read<String>('id'),
        type: assetTypeFromJson(row.read<String>('type')),
        checksum: row.read<String>('checksum'),
        originalFileName: row.read<String>('original_file_name'),
        originalPath: row.read<String>('original_path'),
        fileCreatedAt: _readDate(row, 'file_created_at'),
        fileModifiedAt: _readDate(row, 'file_modified_at'),
        localDateTime: _readDate(row, 'local_date_time'),
        createdAt: _readDate(row, 'created_at'),
        updatedAt: _readDate(row, 'updated_at'),
        width: row.read<int>('width'),
        height: row.read<int>('height'),
        isFavorite: _readBool(row, 'is_favorite'),
        isArchived: _readBool(row, 'is_archived'),
        isTrashed: _readBool(row, 'is_trashed'),
        isOffline: false,
        isEdited: false,
        hasMetadata: false,
        visibility:
            assetVisibilityFromJson(row.read<String>('visibility')),
        ownerId: row.read<String>('owner_id'),
        thumbhash: row.read<String>('thumbhash'),
        duration: row.readNullable<int>('duration_ms') == null
            ? null
            : Duration(
                milliseconds: row.readNullable<int>('duration_ms')!),
        originalMimeType: row.readNullable<String>('mime_type'),
      );

  /// Upsert one asset from a sync record (server-wins: the row is
  /// replaced wholesale, except a locally-set `local_path` is kept
  /// when the incoming record has none).
  Future<void> upsert(NovaAsset asset, {String? localPath}) async {
    await db.customStatement(
      'INSERT INTO assets_mirror ($_columns) VALUES '
      '(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?) '
      'ON CONFLICT(id) DO UPDATE SET '
      'owner_id=excluded.owner_id, type=excluded.type, '
      'original_file_name=excluded.original_file_name, '
      'original_path=excluded.original_path, '
      'checksum=excluded.checksum, '
      'file_created_at=excluded.file_created_at, '
      'file_modified_at=excluded.file_modified_at, '
      'local_date_time=excluded.local_date_time, '
      'created_at=excluded.created_at, updated_at=excluded.updated_at, '
      'width=excluded.width, height=excluded.height, '
      'is_favorite=excluded.is_favorite, '
      'is_archived=excluded.is_archived, '
      'is_trashed=excluded.is_trashed, visibility=excluded.visibility, '
      'thumbhash=excluded.thumbhash, duration_ms=excluded.duration_ms, '
      'mime_type=excluded.mime_type, sync_state=\'synced\'',
      [
        asset.id,
        asset.ownerId,
        assetTypeToJson(asset.type),
        asset.originalFileName,
        asset.originalPath,
        asset.checksum,
        asset.fileCreatedAt.millisecondsSinceEpoch,
        asset.fileModifiedAt.millisecondsSinceEpoch,
        asset.localDateTime.millisecondsSinceEpoch,
        asset.createdAt.millisecondsSinceEpoch,
        asset.updatedAt.millisecondsSinceEpoch,
        asset.width,
        asset.height,
        _boolInt(asset.isFavorite),
        _boolInt(asset.isArchived),
        _boolInt(asset.isTrashed),
        assetVisibilityToJson(asset.visibility),
        asset.thumbhash,
        asset.duration?.inMilliseconds,
        asset.originalMimeType,
        localPath,
        'synced',
      ],
    );
  }

  Future<void> deleteById(String id) async {
    await db.customStatement(
      'DELETE FROM assets_mirror WHERE id = ?',
      [id],
    );
    await db.customStatement(
      'DELETE FROM album_assets WHERE asset_id = ?',
      [id],
    );
    await db.customStatement(
      'DELETE FROM asset_tags WHERE asset_id = ?',
      [id],
    );
  }

  Future<NovaAsset?> getById(String id) async {
    final rows = await db
        .customSelect(
          'SELECT $_columns FROM assets_mirror WHERE id = ?',
          variables: [Variable.withString(id)],
        )
        .get();
    return rows.isEmpty ? null : _fromRow(rows.first);
  }

  /// Timeline read: newest first, paged. This is the offline source
  /// of truth the Photos tab will read (Track B wires it up).
  Future<List<NovaAsset>> listNewest({
    int limit = 100,
    int offset = 0,
  }) async {
    final rows = await db
        .customSelect(
          'SELECT $_columns FROM assets_mirror '
          'WHERE is_trashed = 0 '
          'ORDER BY local_date_time DESC LIMIT ? OFFSET ?',
          variables: [Variable.withInt(limit), Variable.withInt(offset)],
        )
        .get();
    return rows.map(_fromRow).toList(growable: false);
  }

  Future<int> count() async {
    final rows = await db
        .customSelect('SELECT COUNT(*) AS n FROM assets_mirror')
        .get();
    return rows.first.read<int>('n');
  }

  /// Apply a local optimistic change (favorite/archive) while the
  /// matching pending op waits for replay; the next sync overwrites
  /// it server-wins.
  Future<void> setLocalFlags(
    String id, {
    bool? isFavorite,
    bool? isArchived,
  }) async {
    final sets = <String>[];
    final args = <Object?>[];
    if (isFavorite != null) {
      sets.add('is_favorite = ?');
      args.add(_boolInt(isFavorite));
    }
    if (isArchived != null) {
      sets.add('is_archived = ?');
      args.add(_boolInt(isArchived));
      sets.add('visibility = ?');
      args.add(isArchived ? 'archive' : 'timeline');
    }
    if (sets.isEmpty) return;
    sets.add('sync_state = ?');
    args.add('pending');
    args.add(id);
    await db.customStatement(
      'UPDATE assets_mirror SET ${sets.join(', ')} WHERE id = ?',
      args,
    );
  }

  Future<void> clearAll() async {
    await db.customStatement('DELETE FROM assets_mirror');
  }
}

/// Album mirror + membership.
class AlbumDao {
  AlbumDao(this.db);

  final NovaDatabase db;

  Future<void> upsert(Album album) async {
    await db.customStatement(
      'INSERT INTO albums_mirror (id, name, description, owner_id, '
      'asset_count, shared, has_shared_link, thumbnail_asset_id, '
      'created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?) '
      'ON CONFLICT(id) DO UPDATE SET name=excluded.name, '
      'description=excluded.description, owner_id=excluded.owner_id, '
      'asset_count=excluded.asset_count, shared=excluded.shared, '
      'has_shared_link=excluded.has_shared_link, '
      'thumbnail_asset_id=excluded.thumbnail_asset_id, '
      'created_at=excluded.created_at, updated_at=excluded.updated_at',
      [
        album.id,
        album.albumName,
        album.description,
        album.owner?.id ?? '',
        album.assetCount,
        _boolInt(album.shared),
        _boolInt(album.hasSharedLink),
        album.albumThumbnailAssetId,
        album.createdAt.millisecondsSinceEpoch,
        album.updatedAt.millisecondsSinceEpoch,
      ],
    );
  }

  Future<void> deleteById(String id) async {
    await db.customStatement('DELETE FROM albums_mirror WHERE id = ?', [id]);
    await db.customStatement(
      'DELETE FROM album_assets WHERE album_id = ?',
      [id],
    );
  }

  Future<List<Album>> listAll() async {
    final rows = await db
        .customSelect(
          'SELECT id, name, description, owner_id, asset_count, shared, '
          'has_shared_link, thumbnail_asset_id, created_at, updated_at '
          'FROM albums_mirror ORDER BY updated_at DESC',
        )
        .get();
    return rows.map((row) {
      final ownerId = row.read<String>('owner_id');
      return Album(
        id: row.read<String>('id'),
        albumName: row.read<String>('name'),
        description: row.read<String>('description'),
        albumUsers: ownerId.isEmpty
            ? const []
            : [
                AlbumUser(
                  user: NovaUserShim(id: ownerId),
                  role: 'owner',
                ),
              ],
        assetCount: row.read<int>('asset_count'),
        shared: _readBool(row, 'shared'),
        hasSharedLink: _readBool(row, 'has_shared_link'),
        isActivityEnabled: false,
        createdAt: _readDate(row, 'created_at'),
        updatedAt: _readDate(row, 'updated_at'),
        albumThumbnailAssetId:
            row.readNullable<String>('thumbnail_asset_id'),
      );
    }).toList(growable: false);
  }

  Future<void> setMembers(String albumId, List<String> assetIds) async {
    await db.customStatement(
      'DELETE FROM album_assets WHERE album_id = ?',
      [albumId],
    );
    for (final assetId in assetIds) {
      await db.customStatement(
        'INSERT OR IGNORE INTO album_assets (album_id, asset_id) '
        'VALUES (?, ?)',
        [albumId, assetId],
      );
    }
  }

  Future<void> addMember(String albumId, String assetId) async {
    await db.customStatement(
      'INSERT OR IGNORE INTO album_assets (album_id, asset_id) '
      'VALUES (?, ?)',
      [albumId, assetId],
    );
  }

  Future<void> removeMember(String albumId, String assetId) async {
    await db.customStatement(
      'DELETE FROM album_assets WHERE album_id = ? AND asset_id = ?',
      [albumId, assetId],
    );
  }
}

/// People + tags cache (read from the server, never edited locally).
class PeopleTagsDao {
  PeopleTagsDao(this.db);

  final NovaDatabase db;

  Future<void> upsertPeople(List<Person> people) async {
    for (final person in people) {
      await db.customStatement(
        'INSERT INTO people_cache (id, name, is_hidden, birth_date, '
        'color, is_favorite, thumbnail_path) VALUES (?, ?, ?, ?, ?, ?, ?) '
        'ON CONFLICT(id) DO UPDATE SET name=excluded.name, '
        'is_hidden=excluded.is_hidden, birth_date=excluded.birth_date, '
        'color=excluded.color, is_favorite=excluded.is_favorite, '
        'thumbnail_path=excluded.thumbnail_path',
        [
          person.id,
          person.name,
          _boolInt(person.isHidden),
          person.birthDate,
          person.color,
          _boolInt(person.isFavorite),
          person.thumbnailPath,
        ],
      );
    }
  }

  Future<void> deletePerson(String id) async {
    await db.customStatement('DELETE FROM people_cache WHERE id = ?', [id]);
  }

  Future<List<Person>> listPeople() async {
    final rows = await db
        .customSelect(
          'SELECT id, name, is_hidden, birth_date, color, is_favorite, '
          'thumbnail_path FROM people_cache ORDER BY name',
        )
        .get();
    return rows
        .map(
          (row) => Person(
            id: row.read<String>('id'),
            name: row.read<String>('name'),
            isHidden: _readBool(row, 'is_hidden'),
            thumbnailPath: row.read<String>('thumbnail_path'),
            birthDate: row.readNullable<String>('birth_date'),
            color: row.readNullable<String>('color'),
            isFavorite: _readBool(row, 'is_favorite'),
          ),
        )
        .toList(growable: false);
  }

  Future<void> upsertTags(List<Tag> tags) async {
    for (final tag in tags) {
      await db.customStatement(
        'INSERT INTO tags_cache (id, value, name, color, parent_id) '
        'VALUES (?, ?, ?, ?, ?) '
        'ON CONFLICT(id) DO UPDATE SET value=excluded.value, '
        'name=excluded.name, color=excluded.color, '
        'parent_id=excluded.parent_id',
        [tag.id, tag.value, tag.name, tag.color, tag.parentId],
      );
    }
  }

  Future<List<Tag>> listTags() async {
    final rows = await db
        .customSelect(
          'SELECT id, value, name, color, parent_id FROM tags_cache '
          'ORDER BY value',
        )
        .get();
    return rows
        .map(
          (row) => Tag(
            id: row.read<String>('id'),
            value: row.read<String>('value'),
            name: row.read<String>('name'),
            color: row.readNullable<String>('color'),
            parentId: row.readNullable<String>('parent_id'),
          ),
        )
        .toList(growable: false);
  }
}

/// Durable upload queue.
class UploadQueueDao {
  UploadQueueDao(this.db);

  final NovaDatabase db;

  static const _columns = 'id, local_path, filename, sha1, size_bytes, '
      'state, retry_count, last_error, server_asset_id, '
      'file_created_at, file_modified_at, created_at';

  UploadQueueItem _fromRow(QueryRow row) => UploadQueueItem(
        id: row.read<String>('id'),
        localPath: row.read<String>('local_path'),
        filename: row.read<String>('filename'),
        sha1: row.read<String>('sha1'),
        sizeBytes: row.read<int>('size_bytes'),
        state: uploadQueueStateFromString(row.read<String>('state')),
        retryCount: row.read<int>('retry_count'),
        lastError: row.readNullable<String>('last_error'),
        serverAssetId: row.readNullable<String>('server_asset_id'),
        fileCreatedAt: _readDate(row, 'file_created_at'),
        fileModifiedAt: _readDate(row, 'file_modified_at'),
        createdAt: _readDate(row, 'created_at'),
      );

  /// Enqueue a candidate; dedupes on SHA-1 (same file scanned twice
  /// is one queue row) and on local id.
  Future<void> enqueue(UploadQueueItem item) async {
    await db.customStatement(
      'INSERT INTO upload_queue ($_columns) VALUES '
      '(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?) '
      'ON CONFLICT(id) DO NOTHING',
      [
        item.id,
        item.localPath,
        item.filename,
        item.sha1,
        item.sizeBytes,
        uploadQueueStateToString(item.state),
        item.retryCount,
        item.lastError,
        item.serverAssetId,
        item.fileCreatedAt.millisecondsSinceEpoch,
        item.fileModifiedAt.millisecondsSinceEpoch,
        item.createdAt.millisecondsSinceEpoch,
      ],
    );
  }

  Future<UploadQueueItem?> getBySha1(String sha1) async {
    final rows = await db
        .customSelect(
          'SELECT $_columns FROM upload_queue WHERE sha1 = ? LIMIT 1',
          variables: [Variable.withString(sha1)],
        )
        .get();
    return rows.isEmpty ? null : _fromRow(rows.first);
  }

  Future<List<UploadQueueItem>> listByState(
    UploadQueueState state,
  ) async {
    final rows = await db
        .customSelect(
          'SELECT $_columns FROM upload_queue WHERE state = ? '
          'ORDER BY created_at',
          variables: [Variable.withString(state.name)],
        )
        .get();
    return rows.map(_fromRow).toList(growable: false);
  }

  Future<List<UploadQueueItem>> listAll() async {
    final rows = await db
        .customSelect(
          'SELECT $_columns FROM upload_queue ORDER BY created_at',
        )
        .get();
    return rows.map(_fromRow).toList(growable: false);
  }

  Future<int> countByState(UploadQueueState state) async {
    final rows = await db
        .customSelect(
          'SELECT COUNT(*) AS n FROM upload_queue WHERE state = ?',
          variables: [Variable.withString(state.name)],
        )
        .get();
    return rows.first.read<int>('n');
  }

  /// Change state only along a legal transition; returns false (and
  /// writes nothing) on an illegal one.
  Future<bool> setState(
    String id,
    UploadQueueState to, {
    String? lastError,
    String? serverAssetId,
    bool bumpRetry = false,
  }) async {
    final current = await db
        .customSelect(
          'SELECT state, retry_count FROM upload_queue WHERE id = ?',
          variables: [Variable.withString(id)],
        )
        .get();
    if (current.isEmpty) return false;
    final from = uploadQueueStateFromString(
      current.first.read<String>('state'),
    );
    if (from == to) return true;
    if (!canTransition(from, to)) return false;
    final retryCount = current.first.read<int>('retry_count') +
        (bumpRetry ? 1 : 0);
    await db.customStatement(
      'UPDATE upload_queue SET state = ?, retry_count = ?, '
      'last_error = ?, server_asset_id = COALESCE(?, server_asset_id) '
      'WHERE id = ?',
      [to.name, retryCount, lastError, serverAssetId, id],
    );
    return true;
  }

  /// Crash recovery: anything left `uploading` when the process died
  /// goes back to `pending` (its retry counter is unchanged — the
  /// attempt never completed).
  Future<int> resetStuckUploading() async {
    final rows = await db
        .customSelect(
          'SELECT COUNT(*) AS n FROM upload_queue WHERE state = ?',
          variables: [Variable.withString('uploading')],
        )
        .get();
    await db.customStatement(
      'UPDATE upload_queue SET state = ? WHERE state = ?',
      ['pending', 'uploading'],
    );
    return rows.first.read<int>('n');
  }

  Future<void> deleteById(String id) async {
    await db.customStatement(
      'DELETE FROM upload_queue WHERE id = ?',
      [id],
    );
  }
}

/// Offline pending-operations queue (FIFO by `id` / `created_at`).
class PendingOpsDao {
  PendingOpsDao(this.db);

  final NovaDatabase db;

  Future<int> enqueue({
    required String kind,
    String? assetId,
    String? albumId,
    Map<String, Object?> payload = const {},
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.customStatement(
      'INSERT INTO pending_ops (kind, asset_id, album_id, payload, '
      'created_at) VALUES (?, ?, ?, ?, ?)',
      [kind, assetId, albumId, jsonEncode(payload), now],
    );
    final rows = await db
        .customSelect('SELECT last_insert_rowid() AS id')
        .get();
    return rows.first.read<int>('id');
  }

  Future<List<PendingOperationRow>> listOldestFirst() async {
    final rows = await db
        .customSelect(
          'SELECT id, kind, asset_id, album_id, payload, created_at, '
          'attempts, last_error FROM pending_ops ORDER BY id ASC',
        )
        .get();
    return rows.map((row) {
      final payloadRaw = row.read<String>('payload');
      Map<String, Object?> payload;
      try {
        final decoded = jsonDecode(payloadRaw);
        payload = decoded is Map<String, Object?> ? decoded : const {};
      } catch (_) {
        payload = const {};
      }
      return PendingOperationRow(
        id: row.read<int>('id'),
        kind: row.read<String>('kind'),
        assetId: row.readNullable<String>('asset_id'),
        albumId: row.readNullable<String>('album_id'),
        payload: payload,
        createdAt: _readDate(row, 'created_at'),
        attempts: row.read<int>('attempts'),
        lastError: row.readNullable<String>('last_error'),
      );
    }).toList(growable: false);
  }

  Future<int> count() async {
    final rows = await db
        .customSelect('SELECT COUNT(*) AS n FROM pending_ops')
        .get();
    return rows.first.read<int>('n');
  }

  Future<void> markFailed(int id, String error) async {
    await db.customStatement(
      'UPDATE pending_ops SET attempts = attempts + 1, '
      'last_error = ? WHERE id = ?',
      [error, id],
    );
  }

  Future<void> deleteById(int id) async {
    await db.customStatement('DELETE FROM pending_ops WHERE id = ?', [id]);
  }

  Future<void> clearAll() async {
    await db.customStatement('DELETE FROM pending_ops');
  }
}

/// Sync checkpoints: entity type → last acked token.
class SyncCheckpointDao {
  SyncCheckpointDao(this.db);

  final NovaDatabase db;

  Future<void> save(String entityType, String ack) async {
    await db.customStatement(
      'INSERT INTO sync_checkpoints (entity_type, ack, updated_at) '
      'VALUES (?, ?, ?) ON CONFLICT(entity_type) DO UPDATE SET '
      'ack=excluded.ack, updated_at=excluded.updated_at',
      [entityType, ack, DateTime.now().millisecondsSinceEpoch],
    );
  }

  Future<String?> get(String entityType) async {
    final rows = await db
        .customSelect(
          'SELECT ack FROM sync_checkpoints WHERE entity_type = ?',
          variables: [Variable.withString(entityType)],
        )
        .get();
    return rows.isEmpty ? null : rows.first.read<String>('ack');
  }

  Future<Map<String, String>> getAll() async {
    final rows = await db
        .customSelect('SELECT entity_type, ack FROM sync_checkpoints')
        .get();
    return {
      for (final row in rows)
        row.read<String>('entity_type'): row.read<String>('ack'),
    };
  }

  Future<void> clearAll() async {
    await db.customStatement('DELETE FROM sync_checkpoints');
  }
}

/// Key/value settings (backup prefs only — server URL + session stay
/// in secure storage, see ARCHITECTURE.md).
class SettingsDao {
  SettingsDao(this.db);

  final NovaDatabase db;

  Future<void> set(String key, String value) async {
    await db.customStatement(
      'INSERT INTO settings (key, value) VALUES (?, ?) '
      'ON CONFLICT(key) DO UPDATE SET value=excluded.value',
      [key, value],
    );
  }

  Future<String?> get(String key) async {
    final rows = await db
        .customSelect(
          'SELECT value FROM settings WHERE key = ?',
          variables: [Variable.withString(key)],
        )
        .get();
    return rows.isEmpty ? null : rows.first.read<String>('value');
  }

  Future<Map<String, String>> getAll() async {
    final rows = await db
        .customSelect('SELECT key, value FROM settings')
        .get();
    return {
      for (final row in rows)
        row.read<String>('key'): row.read<String>('value'),
    };
  }
}

// Minimal stand-in so AlbumDao can build an Album from a cached
// owner id without importing the user model graph twice. AlbumUser
// only needs a NovaUser; this shim is replaced by the real user row
// when the album is re-fetched from the server.
class NovaUserShim extends NovaUser {
  NovaUserShim({required super.id}) : super(email: '', name: '');
}
