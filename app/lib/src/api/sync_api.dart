/// Sync API — `POST /sync/stream` (JSON Lines) and the `/sync/ack`
/// checkpoint endpoints. Hand-written from spec v3.4.2.
///
/// This is the official mobile app's delta-sync mechanism and the
/// right primitive for NOVA's background sync (Track B): the server
/// streams typed change records; the client applies them to its local
/// Drift mirror and acks each record's checkpoint token so the next
/// stream resumes where the last left off. The socket (see
/// sync_socket.dart) is only the invalidation trigger — the stream is
/// the source of truth.
library;

import '../models/sync.dart';
import 'api_client.dart';

class SyncApi {
  const SyncApi(this.client);

  final ImmichApiClient client;

  /// `POST /sync/stream` — stream change records as JSON Lines.
  /// The stream ends when the server sends a `SyncCompleteV1` record
  /// or closes the connection. The caller applies each record and
  /// acks its checkpoint (see [ack]) before moving on.
  Stream<SyncRecord> streamChanges(SyncStreamRequest request) {
    return client
        .postJsonLines('/sync/stream', body: request.toJson())
        .map(SyncRecord.fromJson);
  }

  /// `POST /sync/ack` — confirm a record's checkpoint token.
  Future<void> ack(SyncAckRequest request) async {
    final response = await client.post('/sync/ack', body: request.toJson());
    client.decodeJson(response);
  }

  /// `GET /sync/ack` — current checkpoints for every entity type.
  Future<List<Map<String, Object?>>> getAcks() async {
    final response = await client.get('/sync/ack');
    final list = client.decodeJsonList(response);
    return list.whereType<Map<String, Object?>>().toList(growable: false);
  }

  /// `DELETE /sync/ack` — delete checkpoints (forces a full re-sync
  /// on the next stream).
  Future<void> deleteAcks() async {
    final response = await client.delete('/sync/ack');
    client.decodeJson(response);
  }
}
