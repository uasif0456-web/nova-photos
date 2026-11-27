/// Memories API — `GET /memories`, `GET/PUT/DELETE /memories/{id}`,
/// add/remove assets. Hand-written from spec v3.4.2.
///
/// A memory is a server-generated "on this day" (or birthday) lane.
/// `GET /memories` returns the current lanes with their assets.
library;

import '../models/memory.dart';
import 'api_client.dart';

class MemoriesApi {
  const MemoriesApi(this.client);

  final ImmichApiClient client;

  /// `GET /memories` — current memory lanes.
  Future<List<Memory>> listMemories() async {
    final response = await client.get('/memories');
    final list = client.decodeJsonList(response);
    return list
        .whereType<Map<String, Object?>>()
        .map(Memory.fromJson)
        .toList(growable: false);
  }

  /// `GET /memories/{id}`.
  Future<Memory> getMemory(String id) async {
    final response = await client.get('/memories/$id');
    return Memory.fromJson(client.decodeJson(response));
  }

  /// `PUT /memories/{id}` — save/hide a memory. The spec marks this
  /// as the update endpoint; `isSaved` pins it, `hideAt`/`showAt`
  /// control visibility.
  Future<Memory> updateMemory(
    String id, {
    bool? isSaved,
    DateTime? hideAt,
    DateTime? showAt,
    DateTime? seenAt,
  }) async {
    final response = await client.put('/memories/$id', body: {
      'isSaved': ? isSaved,
      'hideAt': ? hideAt?.toIso8601String(),
      'showAt': ? showAt?.toIso8601String(),
      'seenAt': ? seenAt?.toIso8601String(),
    });
    return Memory.fromJson(client.decodeJson(response));
  }

  /// `DELETE /memories/{id}`.
  Future<void> deleteMemory(String id) async {
    final response = await client.delete('/memories/$id');
    client.decodeJson(response);
  }

  /// `PUT /memories/{id}/assets` — add assets to a memory.
  Future<void> addAssets(String memoryId, List<String> assetIds) async {
    final response = await client.put('/memories/$memoryId/assets', body: {
      'ids': assetIds,
    });
    client.decodeJson(response);
  }

  /// `DELETE /memories/{id}/assets` — remove assets from a memory.
  Future<void> removeAssets(
    String memoryId,
    List<String> assetIds,
  ) async {
    final response = await client.delete(
      '/memories/$memoryId/assets',
      body: {'ids': assetIds},
    );
    client.decodeJson(response);
  }

  /// `GET /memories/statistics`.
  Future<Map<String, Object?>> getStatistics() async {
    final response = await client.get('/memories/statistics');
    return client.decodeJson(response);
  }
}
