/// Assets API — `GET /assets/{id}`, upload, bulk upload check,
/// bulk update/delete, statistics, OCR, metadata. Hand-written from
/// spec v3.4.2.
///
/// Gotchas encoded here:
/// - There is no `GET /assets` list and no `DELETE /assets/{id}` —
///   listing is search (see search_api.dart), deletion is the bulk
///   endpoint with an id list.
/// - Upload returns **200 + `status: duplicate`** when the checksum
///   already exists — that is a success, not an error.
/// - `deviceId` / `deviceAssetId` were removed from the upload DTO in
///   v3 — they are never sent.
library;

import '../models/asset.dart';
import 'api_client.dart';

class AssetsApi {
  const AssetsApi(this.client);

  final ImmichApiClient client;

  /// `GET /assets/{id}` — one asset with its EXIF, people and tags.
  Future<NovaAsset> getAsset(String id) async {
    final response = await client.get('/assets/$id');
    return NovaAsset.fromJson(client.decodeJson(response));
  }

  /// `GET /assets/statistics` — `{images, videos, total}` for the
  /// signed-in user's library. Optional filters mirror the query params.
  Future<AssetStatistics> getStatistics({
    bool? isFavorite,
    bool? isTrashed,
    String? visibility,
  }) async {
    final response = await client.get('/assets/statistics', query: {
      'isFavorite': ? isFavorite,
      'isTrashed': ? isTrashed,
      'visibility': ? visibility,
    });
    return AssetStatistics.fromJson(client.decodeJson(response));
  }

  /// `GET /assets/{id}/ocr` — OCR text extracted from an asset.
  Future<Map<String, Object?>> getOcr(String id) async {
    final response = await client.get('/assets/$id/ocr');
    return client.decodeJson(response);
  }

  /// `POST /assets/bulk-upload-check` — pre-flight dedup for many
  /// files at once. `items` maps a client-side echo id (e.g. the local
  /// filename) to a hex SHA-1 checksum. The server answers per item
  /// with `action: accept` (upload it) or `reject` (already present).
  Future<List<BulkUploadCheckResult>> bulkUploadCheck(
    Map<String, String> idToChecksum,
  ) async {
    final response = await client.post('/assets/bulk-upload-check', body: {
      'assets': idToChecksum.entries
          .map((e) => {'id': e.key, 'checksum': e.value})
          .toList(),
    });
    final json = client.decodeJson(response);
    final results = json['results'];
    if (results is! List) return const [];
    return results
        .whereType<Map<String, Object?>>()
        .map(BulkUploadCheckResult.fromJson)
        .toList(growable: false);
  }

  /// `POST /assets` — upload one asset as multipart/form-data.
  /// Required parts: `assetData` (bytes), `fileCreatedAt`,
  /// `fileModifiedAt`. Optional: `filename`, `duration` (ms, videos),
  /// `isFavorite`, `visibility`, `livePhotoVideoId`.
  /// `checksum` is the hex SHA-1 of the whole file, sent as the
  /// `x-immich-checksum` header for server-side duplicate detection.
  /// Returns 201 `created` or 200 `duplicate` — both successes.
  Future<AssetUploadResult> uploadAsset({
    required List<int> bytes,
    required String filename,
    required DateTime fileCreatedAt,
    required DateTime fileModifiedAt,
    String? checksum,
    int? durationMs,
    bool isFavorite = false,
    String? visibility,
    String? livePhotoVideoId,
  }) async {
    final response = await client.postMultipart(
      '/assets',
      fileField: 'assetData',
      fileBytes: bytes,
      filename: filename,
      checksum: checksum,
      fields: {
        'filename': filename,
        'fileCreatedAt': fileCreatedAt.toIso8601String(),
        'fileModifiedAt': fileModifiedAt.toIso8601String(),
        'isFavorite': isFavorite.toString(),
        'duration': ? durationMs?.toString(),
        'visibility': ? visibility,
        'livePhotoVideoId': ? livePhotoVideoId,
      },
    );
    return AssetUploadResult.fromJson(client.decodeJson(response));
  }

  /// `PUT /assets/{id}` — update one asset (favorite, description,
  /// visibility, rating, location, date). Prefer `PATCH` where both
  /// exist; this endpoint only offers PUT in v3.4.2.
  Future<NovaAsset> updateAsset(
    String id, {
    bool? isFavorite,
    String? description,
    String? visibility,
    int? rating,
    double? latitude,
    double? longitude,
    DateTime? dateTimeOriginal,
  }) async {
    final response = await client.put('/assets/$id', body: {
      'isFavorite': ? isFavorite,
      'description': ? description,
      'visibility': ? visibility,
      'rating': ? rating,
      'latitude': ? latitude,
      'longitude': ? longitude,
      if (dateTimeOriginal != null)
        'dateTimeOriginal': dateTimeOriginal.toIso8601String(),
    });
    return NovaAsset.fromJson(client.decodeJson(response));
  }

  /// Convenience: toggle the favorite flag on one asset.
  Future<NovaAsset> setFavorite(String id, bool isFavorite) =>
      updateAsset(id, isFavorite: isFavorite);

  /// Convenience: archive / unarchive one asset
  /// (`visibility: archive` / `timeline`).
  Future<NovaAsset> setArchived(String id, bool archived) =>
      updateAsset(id, visibility: archived ? 'archive' : 'timeline');

  /// `PUT /assets` — bulk update (favorites, visibility, rating, …)
  /// for a list of ids.
  Future<void> bulkUpdate(
    List<String> ids, {
    bool? isFavorite,
    String? visibility,
    int? rating,
    String? description,
  }) async {
    final response = await client.put('/assets', body: {
      'ids': ids,
      'isFavorite': ? isFavorite,
      'visibility': ? visibility,
      'rating': ? rating,
      'description': ? description,
    });
    client.decodeJson(response);
  }

  /// `DELETE /assets` — bulk delete. By default this moves assets to
  /// trash; `force: true` deletes permanently (only when the server's
  /// `trash` feature is off, or when the caller really means it).
  Future<void> bulkDelete(List<String> ids, {bool force = false}) async {
    final response = await client.delete('/assets', body: {
      'ids': ids,
      'force': force,
    });
    client.decodeJson(response);
  }

  /// `PUT /assets/copy` — copy an asset to another library.
  Future<void> copyAsset(String id, {String? libraryId}) async {
    final response = await client.put('/assets/copy', body: {
      'id': id,
      'libraryId': ? libraryId,
    });
    client.decodeJson(response);
  }

  /// `GET /assets/{id}/metadata` — app-specific key/value metadata.
  Future<Map<String, Object?>> getMetadata(String id) async {
    final response = await client.get('/assets/$id/metadata');
    return client.decodeJson(response);
  }

  /// `PUT /assets/{id}/metadata` — upsert one metadata key.
  Future<void> setMetadata(String id, String key, Object? value) async {
    final response = await client.put('/assets/$id/metadata', body: {
      'key': key,
      'value': value,
    });
    client.decodeJson(response);
  }

  /// `POST /assets/jobs` — trigger a per-asset job (e.g. regenerate
  /// thumbnails). `name` is a `JobName`, e.g. `generateThumbnails`.
  Future<void> runJob(String name, {List<String>? ids}) async {
    final response = await client.post('/assets/jobs', body: {
      'name': name,
      'ids': ? ids,
    });
    client.decodeJson(response);
  }
}
