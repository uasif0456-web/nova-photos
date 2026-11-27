/// Shared links API — `GET/POST /shared-links`,
/// `GET/PATCH/DELETE /shared-links/{id}`, add/remove assets,
/// `POST /shared-links/login`. Hand-written from spec v3.4.2.
library;

import '../models/shared_link.dart';
import 'api_client.dart';

class SharedLinksApi {
  const SharedLinksApi(this.client);

  final ImmichApiClient client;

  /// `GET /shared-links` — all shared links of the signed-in user.
  Future<List<SharedLink>> listSharedLinks() async {
    final response = await client.get('/shared-links');
    final list = client.decodeJsonList(response);
    return list
        .whereType<Map<String, Object?>>()
        .map(SharedLink.fromJson)
        .toList(growable: false);
  }

  /// `GET /shared-links/{id}`.
  Future<SharedLink> getSharedLink(String id) async {
    final response = await client.get('/shared-links/$id');
    return SharedLink.fromJson(client.decodeJson(response));
  }

  /// `POST /shared-links` — create a link for an album or for
  /// individual assets. `type` is `album` or `individual`.
  Future<SharedLink> createSharedLink({
    required String type,
    String? albumId,
    List<String> assetIds = const [],
    String? description,
    DateTime? expiresAt,
    String? password,
    bool allowDownload = true,
    bool allowUpload = false,
    bool showMetadata = true,
  }) async {
    final response = await client.post('/shared-links', body: {
      'type': type,
      'albumId': ? albumId,
      'assetIds': assetIds,
      'description': ? description,
      'expiresAt': ? expiresAt?.toIso8601String(),
      'password': ? password,
      'allowDownload': allowDownload,
      'allowUpload': allowUpload,
      'showMetadata': showMetadata,
    });
    return SharedLink.fromJson(client.decodeJson(response));
  }

  /// `PATCH /shared-links/{id}` — update a link (expiry, password,
  /// download/upload flags, description).
  Future<SharedLink> updateSharedLink(
    String id, {
    String? description,
    DateTime? expiresAt,
    String? password,
    bool? allowDownload,
    bool? allowUpload,
    bool? showMetadata,
  }) async {
    final response = await client.patch('/shared-links/$id', body: {
      'description': ? description,
      'expiresAt': ? expiresAt?.toIso8601String(),
      'password': ? password,
      'allowDownload': ? allowDownload,
      'allowUpload': ? allowUpload,
      'showMetadata': ? showMetadata,
    });
    return SharedLink.fromJson(client.decodeJson(response));
  }

  /// `DELETE /shared-links/{id}`.
  Future<void> deleteSharedLink(String id) async {
    final response = await client.delete('/shared-links/$id');
    client.decodeJson(response);
  }

  /// `PUT /shared-links/{id}/assets` — add assets to a link.
  Future<void> addAssets(String linkId, List<String> assetIds) async {
    final response = await client.put(
      '/shared-links/$linkId/assets',
      body: {'ids': assetIds},
    );
    client.decodeJson(response);
  }

  /// `DELETE /shared-links/{id}/assets` — remove assets from a link.
  Future<void> removeAssets(
    String linkId,
    List<String> assetIds,
  ) async {
    final response = await client.delete(
      '/shared-links/$linkId/assets',
      body: {'ids': assetIds},
    );
    client.decodeJson(response);
  }

  /// `GET /shared-links/me` — resolve the current shared link from a
  /// key/slug (used when opening a public link).
  Future<SharedLink> getCurrentSharedLink({
    required String key,
    required String slug,
  }) async {
    final response = await client.get(
      '/shared-links/me',
      query: {'key': key, 'slug': slug},
    );
    return SharedLink.fromJson(client.decodeJson(response));
  }

  /// `POST /shared-links/login` — unlock a password-protected link.
  Future<void> loginToSharedLink({
    required String key,
    required String slug,
    required String password,
  }) async {
    final response = await client.post('/shared-links/login', body: {
      'key': key,
      'slug': slug,
      'password': password,
    });
    client.decodeJson(response);
  }
}
