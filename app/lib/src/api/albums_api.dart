/// Albums API — `GET/POST /albums`, `GET/PATCH/DELETE /albums/{id}`,
/// add/remove assets, share with users. Hand-written from spec v3.4.2.
///
/// v3 facts: `GET /albums/{id}` returns no embedded assets (only
/// `assetCount`); album contents come from `POST /search/metadata`
/// with `albumIds`. Update prefers `PATCH` (the spec announces PUT
/// will be dropped in v5 for these endpoints).
library;

import '../models/album.dart';
import 'api_client.dart';

class AlbumsApi {
  const AlbumsApi(this.client);

  final ImmichApiClient client;

  /// `GET /albums` — unpaginated list (filter params only).
  Future<List<Album>> listAlbums({
    String? assetId,
    String? id,
    bool? isOwned,
    bool? isShared,
    String? name,
  }) async {
    final response = await client.get('/albums', query: {
      'assetId': ? assetId,
      'id': ? id,
      'isOwned': ? isOwned,
      'isShared': ? isShared,
      'name': ? name,
    });
    final list = client.decodeJsonList(response);
    return list
        .whereType<Map<String, Object?>>()
        .map(Album.fromJson)
        .toList(growable: false);
  }

  /// `GET /albums/{id}`.
  Future<Album> getAlbum(String id) async {
    final response = await client.get('/albums/$id');
    return Album.fromJson(client.decodeJson(response));
  }

  /// `POST /albums` — create an album, optionally with initial assets.
  Future<Album> createAlbum({
    required String albumName,
    String? description,
    List<String> assetIds = const [],
  }) async {
    final response = await client.post('/albums', body: {
      'albumName': albumName,
      'description': ? description,
      'assetIds': assetIds,
    });
    return Album.fromJson(client.decodeJson(response));
  }

  /// `PATCH /albums/{id}` — update name, description, thumbnail asset,
  /// activity flag. PATCH is preferred over PUT (v4 migration note).
  Future<Album> updateAlbum(
    String id, {
    String? albumName,
    String? description,
    String? albumThumbnailAssetId,
    bool? isActivityEnabled,
  }) async {
    final response = await client.patch('/albums/$id', body: {
      'albumName': ? albumName,
      'description': ? description,
      'albumThumbnailAssetId': ? albumThumbnailAssetId,
      'isActivityEnabled': ? isActivityEnabled,
    });
    return Album.fromJson(client.decodeJson(response));
  }

  /// `DELETE /albums/{id}`.
  Future<void> deleteAlbum(String id) async {
    final response = await client.delete('/albums/$id');
    client.decodeJson(response);
  }

  /// `PUT /albums/{id}/assets` — add assets to an album.
  Future<void> addAssets(String albumId, List<String> assetIds) async {
    final response = await client.put('/albums/$albumId/assets', body: {
      'ids': assetIds,
    });
    client.decodeJson(response);
  }

  /// `DELETE /albums/{id}/assets` — remove assets from an album.
  Future<void> removeAssets(String albumId, List<String> assetIds) async {
    final response = await client.delete('/albums/$albumId/assets', body: {
      'ids': assetIds,
    });
    client.decodeJson(response);
  }

  /// `PUT /albums/assets` — add assets to several albums at once.
  Future<void> addAssetsToAlbums(
    List<String> albumIds,
    List<String> assetIds,
  ) async {
    final response = await client.put('/albums/assets', body: {
      'albumIds': albumIds,
      'ids': assetIds,
    });
    client.decodeJson(response);
  }

  /// `PUT /albums/{id}/users` — share an album with users.
  /// Each entry: `{'userId': …, 'role': 'editor'|'viewer'}`.
  Future<void> shareAlbum(
    String albumId,
    List<Map<String, String>> albumUsers,
  ) async {
    final response = await client.put('/albums/$albumId/users', body: {
      'albumUsers': albumUsers,
    });
    client.decodeJson(response);
  }

  /// `PUT /albums/{id}/user/{userId}` — change one user's role.
  Future<void> updateUserRole(
    String albumId,
    String userId,
    String role,
  ) async {
    final response = await client.put(
      '/albums/$albumId/user/$userId',
      body: {'role': role},
    );
    client.decodeJson(response);
  }

  /// `DELETE /albums/{id}/user/{userId}` — remove a user from an album.
  Future<void> removeUser(String albumId, String userId) async {
    final response = await client.delete('/albums/$albumId/user/$userId');
    client.decodeJson(response);
  }

  /// `GET /albums/statistics` — `{owned, shared}`.
  Future<AlbumStatistics> getStatistics() async {
    final response = await client.get('/albums/statistics');
    return AlbumStatistics.fromJson(client.decodeJson(response));
  }
}
