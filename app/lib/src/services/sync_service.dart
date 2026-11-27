/// Sync engine — consumes `POST /sync/stream` (JSONL), applies
/// deltas to the Drift mirror, checkpoints with `POST /sync/ack`.
///
/// The Socket.IO client is an **invalidation trigger only**: any
/// asset/album event re-runs the sync stream; on disconnect the
/// engine retries with exponential backoff and then does a full
/// re-sync. The socket is never trusted as the source of truth.
///
/// Wire-format note (spec v3.4.2, verified in `spec-v3.4.2.json`):
/// `SyncStreamDto.types` takes **SyncRequestType** values
/// (`AssetsV2`, `AlbumsV2`, `AlbumToAssetsV1`, `PeopleV1`,
/// `MemoriesV2`, …) while the records that come back carry
/// **SyncEntityType** values (`AssetV2`, `AssetDeleteV1`, …).
/// Track A's `SyncEntityTypes.defaultTypes` lists entity types, so
/// this service translates them with [syncRequestTypesFor] before
/// sending the request. The ack still uses the record's entity type.
/// This translation has NOT yet been verified live against the demo
/// server (needs `DEMO_USER`/`DEMO_PASS`); see DEVELOPMENT_LOG.
library;

import 'dart:async';
import 'dart:convert';

import '../api/nova_api.dart';
import '../api/sync_socket.dart';
import '../models/album.dart';
import '../models/asset.dart';
import '../models/parsing.dart';
import '../models/person.dart';
import '../models/sync.dart';
import '../store/daos.dart';
import '../store/nova_database.dart';
import '../store/upload_queue.dart';

/// Translate requested entity types into the SyncRequestType values
/// the `POST /sync/stream` body actually accepts (spec v3.4.2).
/// Delete / membership records ride along inside their parent's
/// request type, so several entity types collapse to one request type.
List<String> syncRequestTypesFor(List<String> entityTypes) {
  const mapping = {
    SyncEntityTypes.authUserV2: 'AuthUsersV2',
    SyncEntityTypes.assetV2: 'AssetsV2',
    SyncEntityTypes.assetDeleteV1: 'AssetsV2',
    SyncEntityTypes.assetExifV1: 'AssetExifsV1',
    SyncEntityTypes.albumV2: 'AlbumsV2',
    SyncEntityTypes.albumDeleteV1: 'AlbumsV2',
    SyncEntityTypes.albumToAssetV1: 'AlbumToAssetsV1',
    SyncEntityTypes.albumToAssetDeleteV1: 'AlbumToAssetsV1',
    SyncEntityTypes.memoryV2: 'MemoriesV2',
    SyncEntityTypes.memoryDeleteV1: 'MemoriesV2',
    SyncEntityTypes.personV1: 'PeopleV1',
    SyncEntityTypes.personDeleteV1: 'PeopleV1',
    SyncEntityTypes.stackV1: 'StacksV1',
    SyncEntityTypes.stackDeleteV1: 'StacksV1',
  };
  final out = <String>[];
  for (final type in entityTypes) {
    final mapped = mapping[type];
    if (mapped != null && !out.contains(mapped)) out.add(mapped);
  }
  return out;
}

/// Parse a raw JSONL sync-stream body into records. Blank lines are
/// skipped; a malformed line is skipped (never aborts the whole
/// stream — one bad record must not lose the rest of the sync).
/// Pure function, unit-tested.
List<SyncRecord> parseSyncJsonLines(String body) {
  final records = <SyncRecord>[];
  for (final line in const LineSplitter().convert(body)) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) continue;
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is Map<String, Object?>) {
        records.add(SyncRecord.fromJson(decoded));
      }
    } catch (_) {
      // Skip the bad line; the next sync re-fetches anything missed
      // because its ack was never sent.
    }
  }
  return records;
}

/// Extract an entity id from a sync record's `data`: delete records
/// carry `{assetId: …}` / `{albumId: …}` / `{personId: …}` maps (spec
/// `Sync*DeleteV1`), never a bare string in v3.4.2 — but a bare
/// string is accepted defensively.
String? syncRecordId(SyncRecord record, [String? key]) {
  final data = record.data;
  if (data is String) return data;
  if (data is Map<String, Object?>) {
    for (final candidate in [key, 'id', 'assetId', 'albumId', 'personId',
        'memoryId', 'stackId']) {
      if (candidate == null) continue;
      final value = parseString(data[candidate]);
      if (value != null && value.isNotEmpty) return value;
    }
  }
  return null;
}

/// Observable sync state (last sync time, pending-op count, errors).
class SyncState {
  const SyncState({
    this.isSyncing = false,
    this.lastSyncAt,
    this.lastError,
    this.recordsApplied = 0,
    this.pendingOps = 0,
  });

  final bool isSyncing;
  final DateTime? lastSyncAt;
  final String? lastError;
  final int recordsApplied;
  final int pendingOps;

  SyncState copyWith({
    bool? isSyncing,
    DateTime? lastSyncAt,
    String? lastError,
    int? recordsApplied,
    int? pendingOps,
  }) =>
      SyncState(
        isSyncing: isSyncing ?? this.isSyncing,
        lastSyncAt: lastSyncAt ?? this.lastSyncAt,
        lastError: lastError,
        recordsApplied: recordsApplied ?? this.recordsApplied,
        pendingOps: pendingOps ?? this.pendingOps,
      );
}

class SyncService {
  SyncService({
    required this.api,
    required this.db,
    this.onSyncError,
  })  : _assets = AssetDao(db),
        _albums = AlbumDao(db),
        _peopleTags = PeopleTagsDao(db),
        _checkpoints = SyncCheckpointDao(db),
        _pendingOps = PendingOpsDao(db);

  final NovaApi api;
  final NovaDatabase db;

  /// Called with non-fatal sync failures (network, bad record) so the
  /// UI can show them; the engine keeps going.
  final void Function(Object error)? onSyncError;

  final AssetDao _assets;
  final AlbumDao _albums;
  final PeopleTagsDao _peopleTags;
  final SyncCheckpointDao _checkpoints;
  final PendingOpsDao _pendingOps;

  SyncState _state = const SyncState();
  final _stateController = StreamController<SyncState>.broadcast();
  StreamSubscription<NovaSocketEvent>? _eventSub;
  StreamSubscription<bool>? _connectionSub;
  Timer? _debounceTimer;
  Timer? _retryTimer;
  int _retryAttempt = 0;
  bool _syncing = false;
  bool _disposed = false;

  SyncState get state => _state;
  Stream<SyncState> get stateStream async* {
    yield _state;
    yield* _stateController.stream;
  }

  void _emit(SyncState next) {
    _state = next;
    if (!_stateController.isClosed) _stateController.add(next);
  }

  /// One full catch-up run: stream all default types, apply each
  /// record, ack it, checkpoint it. Safe to call concurrently — a
  /// second call while one is running is a no-op.
  Future<void> syncNow({bool reset = false}) async {
    if (_syncing) return;
    _syncing = true;
    _emit(_state.copyWith(isSyncing: true, lastError: null));
    var applied = 0;
    try {
      if (reset) {
        await _resetMirror();
      }
      final request = SyncStreamRequest(
        types: syncRequestTypesFor(SyncEntityTypes.defaultTypes),
        reset: reset,
      );
      await for (final record in api.sync.streamChanges(request)) {
        if (_disposed) break;
        if (record.isReset) {
          await _resetMirror();
          continue;
        }
        await applyRecord(record);
        applied++;
        if (record.ack != null && record.ack!.isNotEmpty) {
          await api.sync.ack(
            SyncAckRequest(ack: record.ack!, type: record.type),
          );
          await _checkpoints.save(record.type, record.ack!);
        }
        if (record.isComplete) break;
      }
      _retryAttempt = 0;
      final pending = await _pendingOps.count();
      _emit(
        _state.copyWith(
          isSyncing: false,
          lastSyncAt: DateTime.now(),
          recordsApplied: _state.recordsApplied + applied,
          pendingOps: pending,
        ),
      );
    } catch (e) {
      final pending = await _pendingOps
          .count()
          .catchError((_) => _state.pendingOps);
      _emit(
        _state.copyWith(
          isSyncing: false,
          lastError: e.toString(),
          pendingOps: pending,
        ),
      );
      onSyncError?.call(e);
      _scheduleRetry(reset: reset);
    } finally {
      _syncing = false;
    }
  }

  /// Apply one sync record to the Drift mirror. Server-wins: the
  /// incoming payload replaces the local row wholesale. Unknown
  /// record types are ignored (forward-compatible with new server
  /// minors) — their ack is still sent by the caller.
  Future<void> applyRecord(SyncRecord record) async {
    final data = record.data;
    switch (record.type) {
      case SyncEntityTypes.assetV2:
        if (data is Map<String, Object?>) {
          final asset = NovaAsset.fromJson(data);
          if (asset.id.isEmpty) return;
          await _assets.upsert(asset);
          if (asset.tags.isNotEmpty) {
            await _peopleTags.upsertTags(asset.tags);
          }
          if (asset.people.isNotEmpty) {
            await _peopleTags.upsertPeople(asset.people);
          }
        }
      case SyncEntityTypes.assetDeleteV1:
        final id = syncRecordId(record, 'assetId');
        if (id != null) await _assets.deleteById(id);
      case SyncEntityTypes.assetExifV1:
        // No EXIF columns in the v1 mirror (see DATABASE_SCHEMA.md):
        // the AssetV2 record already carries the fields the timeline
        // needs. Skipped deliberately, ack still sent.
        break;
      case SyncEntityTypes.albumV2:
        if (data is Map<String, Object?>) {
          final album = Album.fromJson(data);
          if (album.id.isEmpty) return;
          await _albums.upsert(album);
        }
      case SyncEntityTypes.albumDeleteV1:
        final id = syncRecordId(record, 'albumId');
        if (id != null) await _albums.deleteById(id);
      case SyncEntityTypes.albumToAssetV1:
        if (data is Map<String, Object?>) {
          final albumId = parseString(data['albumId']);
          final assetId = parseString(data['assetId']);
          if (albumId != null && assetId != null) {
            await _albums.addMember(albumId, assetId);
          }
        }
      case SyncEntityTypes.albumToAssetDeleteV1:
        if (data is Map<String, Object?>) {
          final albumId = parseString(data['albumId']);
          final assetId = parseString(data['assetId']);
          if (albumId != null && assetId != null) {
            await _albums.removeMember(albumId, assetId);
          }
        }
      case SyncEntityTypes.personV1:
        if (data is Map<String, Object?>) {
          final person = Person.fromJson(data);
          if (person.id.isEmpty) return;
          await _peopleTags.upsertPeople([person]);
        }
      case SyncEntityTypes.personDeleteV1:
        final id = syncRecordId(record, 'personId');
        if (id != null) await _peopleTags.deletePerson(id);
      case SyncEntityTypes.memoryV2:
      case SyncEntityTypes.memoryDeleteV1:
      case SyncEntityTypes.stackV1:
      case SyncEntityTypes.stackDeleteV1:
      case SyncEntityTypes.authUserV2:
      case SyncEntityTypes.syncCompleteV1:
        // No v1 mirror table for memories / stacks / auth user
        // (DATABASE_SCHEMA.md). Ack still sent by the caller.
        break;
      default:
        // Unknown future entity type: ignore, ack anyway.
        break;
    }
  }

  /// Start watching the socket as an invalidation trigger. Any
  /// asset/album event schedules a debounced re-sync; a reconnect
  /// (connection change to `true`) triggers a full re-sync, because
  /// events fired while disconnected were missed.
  void watchSocket() {
    _eventSub?.cancel();
    _connectionSub?.cancel();
    _eventSub = api.socket.events.listen((event) {
      if (event.name.startsWith('on_asset') ||
          event.name.startsWith('on_upload') ||
          event.name == 'ResourceEventV1') {
        _scheduleDebouncedSync();
      }
    });
    _connectionSub = api.socket.connectionChanges.listen((connected) {
      if (connected) {
        _retryAttempt = 0;
        _retryTimer?.cancel();
        unawaited(syncNow());
      }
    });
  }

  void _scheduleDebouncedSync() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(seconds: 2), () {
      if (!_disposed) unawaited(syncNow());
    });
  }

  void _scheduleRetry({bool reset = false}) {
    if (_disposed) return;
    _retryAttempt++;
    final delay = socketReconnectDelay(_retryAttempt);
    _retryTimer?.cancel();
    _retryTimer = Timer(delay, () {
      if (!_disposed) unawaited(syncNow(reset: reset));
    });
  }

  Future<void> _resetMirror() async {
    await _assets.clearAll();
    await db.customStatement('DELETE FROM album_assets');
    await db.customStatement('DELETE FROM albums_mirror');
    await db.customStatement('DELETE FROM people_cache');
    await db.customStatement('DELETE FROM tags_cache');
    await db.customStatement('DELETE FROM asset_tags');
    await _checkpoints.clearAll();
  }

  /// Refresh the pending-ops count shown in [SyncState].
  Future<void> refreshPendingCount() async {
    final pending = await _pendingOps.count();
    _emit(_state.copyWith(pendingOps: pending));
  }

  void dispose() {
    _disposed = true;
    _debounceTimer?.cancel();
    _retryTimer?.cancel();
    _eventSub?.cancel();
    _connectionSub?.cancel();
    _stateController.close();
  }
}
