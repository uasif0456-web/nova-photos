/// Offline pending operations — actions taken while offline, replayed
/// in order when connectivity returns.
///
/// Kinds (stored in `pending_ops.kind`):
/// - `favorite` — payload `{isFavorite: bool}`
/// - `archive` — payload `{archived: bool}`
/// - `delete` — payload `{force: bool}` (trash by default)
/// - `add_to_album` — payload `{assetIds: [...]}`, album in `album_id`
/// - `remove_from_album` — payload `{assetIds: [...]}`
///
/// Replay is strictly FIFO (oldest `id` first) so a favorite-then-
/// delete on the same asset replays in the order the user did it.
/// Conflicts resolve **server-wins**: if replay fails because the
/// server no longer has the asset (404 / gone), the op is dropped and
/// logged, and the next sync re-asserts the server's state into the
/// mirror. A transient failure (network / 5xx) keeps the op queued
/// with an incremented attempt counter.
library;

import 'dart:async';

import '../api/exceptions.dart';
import '../api/nova_api.dart';
import '../store/daos.dart';
import '../store/nova_database.dart';

/// One replay outcome, for the log the Dashboard shows.
class PendingOpResult {
  const PendingOpResult({
    required this.opId,
    required this.kind,
    required this.outcome,
    this.detail,
  });

  final int opId;
  final String kind;

  /// `replayed`, `dropped_conflict`, `failed_retryable`.
  final String outcome;
  final String? detail;
}

class PendingOpsService {
  PendingOpsService({required this.api, required this.db})
      : _dao = PendingOpsDao(db),
        _assets = AssetDao(db);

  final NovaApi api;
  final NovaDatabase db;
  final PendingOpsDao _dao;
  final AssetDao _assets;

  final _logController = StreamController<PendingOpResult>.broadcast();

  /// Replay outcomes, newest first in arrival order.
  Stream<PendingOpResult> get replayLog => _logController.stream;

  /// Queue an offline action. Also applies the optimistic local
  /// mirror change for favorite/archive so the UI reflects it offline.
  Future<int> enqueue({
    required String kind,
    String? assetId,
    String? albumId,
    Map<String, Object?> payload = const {},
  }) async {
    final id = await _dao.enqueue(
      kind: kind,
      assetId: assetId,
      albumId: albumId,
      payload: payload,
    );
    if (assetId != null) {
      switch (kind) {
        case 'favorite':
          final fav = payload['isFavorite'];
          if (fav is bool) {
            await _assets.setLocalFlags(assetId, isFavorite: fav);
          }
        case 'archive':
          final archived = payload['archived'];
          if (archived is bool) {
            await _assets.setLocalFlags(assetId, isArchived: archived);
          }
      }
    }
    return id;
  }

  Future<int> get pendingCount => _dao.count();

  Future<List<PendingOperationRow>> listPending() =>
      _dao.listOldestFirst();

  /// Replay every queued op in FIFO order. Returns the per-op
  /// outcomes. A retryable failure stops the replay (later ops may
  /// depend on the failed one — e.g. add-to-album after a create);
  /// conflicts are dropped and replay continues.
  Future<List<PendingOpResult>> replayAll() async {
    final results = <PendingOpResult>[];
    final ops = await _dao.listOldestFirst();
    for (final op in ops) {
      final result = await _replayOne(op);
      results.add(result);
      if (!_logController.isClosed) _logController.add(result);
      if (result.outcome == 'failed_retryable') break;
    }
    return results;
  }

  Future<PendingOpResult> _replayOne(PendingOperationRow op) async {
    try {
      switch (op.kind) {
        case 'favorite':
          final assetId = op.assetId;
          final fav = op.payload['isFavorite'];
          if (assetId == null || fav is! bool) {
            return await _drop(op, 'dropped_conflict', 'malformed favorite op');
          }
          await api.assets.setFavorite(assetId, fav);
        case 'archive':
          final assetId = op.assetId;
          final archived = op.payload['archived'];
          if (assetId == null || archived is! bool) {
            return await _drop(op, 'dropped_conflict', 'malformed archive op');
          }
          await api.assets.setArchived(assetId, archived);
        case 'delete':
          final assetId = op.assetId;
          if (assetId == null) {
            return await _drop(op, 'dropped_conflict', 'malformed delete op');
          }
          final force = op.payload['force'] is bool
              ? op.payload['force'] as bool
              : false;
          await api.assets.bulkDelete([assetId], force: force);
        case 'add_to_album':
          final albumId = op.albumId;
          final assetIds = _assetIds(op);
          if (albumId == null || assetIds.isEmpty) {
            return await _drop(op, 'dropped_conflict', 'malformed album op');
          }
          await api.albums.addAssets(albumId, assetIds);
        case 'remove_from_album':
          final albumId = op.albumId;
          final assetIds = _assetIds(op);
          if (albumId == null || assetIds.isEmpty) {
            return await _drop(op, 'dropped_conflict', 'malformed album op');
          }
          await api.albums.removeAssets(albumId, assetIds);
        default:
          return await _drop(op, 'dropped_conflict', 'unknown kind ${op.kind}');
      }
      await _dao.deleteById(op.id);
      return PendingOpResult(
        opId: op.id,
        kind: op.kind,
        outcome: 'replayed',
      );
    } on ImmichApiException catch (e) {
      // Server-wins conflict: the asset/album is gone on the server,
      // or the request is invalid for the server's current state.
      // Drop the op; the next sync re-asserts server state locally.
      if (e is ImmichNotFoundException || e is ImmichForbiddenException) {
        return await _drop(
          op,
          'dropped_conflict',
          'server state won (${e.message})',
        );
      }
      await _dao.markFailed(op.id, e.message);
      return PendingOpResult(
        opId: op.id,
        kind: op.kind,
        outcome: 'failed_retryable',
        detail: e.message,
      );
    } catch (e) {
      await _dao.markFailed(op.id, e.toString());
      return PendingOpResult(
        opId: op.id,
        kind: op.kind,
        outcome: 'failed_retryable',
        detail: e.toString(),
      );
    }
  }

  Future<PendingOpResult> _drop(
    PendingOperationRow op,
    String outcome,
    String detail,
  ) async {
    await _dao.deleteById(op.id);
    return PendingOpResult(
      opId: op.id,
      kind: op.kind,
      outcome: outcome,
      detail: detail,
    );
  }

  List<String> _assetIds(PendingOperationRow op) {
    final raw = op.payload['assetIds'];
    if (raw is List) {
      return raw.map((e) => e.toString()).toList(growable: false);
    }
    final single = op.assetId;
    return single == null ? const [] : [single];
  }

  void dispose() {
    _logController.close();
  }
}

/// Pure replay-order helper (unit-tested): pending ops must replay in
/// ascending `id` order — the order the user performed them.
List<PendingOperationRow> sortPendingOpsForReplay(
  List<PendingOperationRow> ops,
) {
  final sorted = [...ops];
  sorted.sort((a, b) => a.id.compareTo(b.id));
  return sorted;
}
