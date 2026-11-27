/// Tags API — `GET/POST /tags`, `GET/PATCH/DELETE /tags/{id}`,
/// tag/untag assets. Hand-written from spec v3.4.2.
///
/// Tags are hierarchical (`Parent/Child` in `value`). Update prefers
/// `PATCH` (v4 migration note).
library;

import '../models/tag.dart';
import 'api_client.dart';

class TagsApi {
  const TagsApi(this.client);

  final ImmichApiClient client;

  /// `GET /tags` — all tags.
  Future<List<Tag>> listTags() async {
    final response = await client.get('/tags');
    final list = client.decodeJsonList(response);
    return list
        .whereType<Map<String, Object?>>()
        .map(Tag.fromJson)
        .toList(growable: false);
  }

  /// `GET /tags/{id}`.
  Future<Tag> getTag(String id) async {
    final response = await client.get('/tags/$id');
    return Tag.fromJson(client.decodeJson(response));
  }

  /// `POST /tags` — create a tag. `value` is the full path
  /// (`Parent/Child`); `color` is an optional hex color.
  Future<Tag> createTag({required String value, String? color}) async {
    final response = await client.post('/tags', body: {
      'value': value,
      'color': ? color,
    });
    return Tag.fromJson(client.decodeJson(response));
  }

  /// `PATCH /tags/{id}` — rename / recolor a tag.
  Future<Tag> updateTag(String id, {String? value, String? color}) async {
    final response = await client.patch('/tags/$id', body: {
      'value': ? value,
      'color': ? color,
    });
    return Tag.fromJson(client.decodeJson(response));
  }

  /// `DELETE /tags/{id}`.
  Future<void> deleteTag(String id) async {
    final response = await client.delete('/tags/$id');
    client.decodeJson(response);
  }

  /// `PUT /tags/{id}/assets` — tag assets.
  Future<void> tagAssets(String tagId, List<String> assetIds) async {
    final response = await client.put('/tags/$tagId/assets', body: {
      'ids': assetIds,
    });
    client.decodeJson(response);
  }

  /// `DELETE /tags/{id}/assets` — untag assets.
  Future<void> untagAssets(String tagId, List<String> assetIds) async {
    final response = await client.delete('/tags/$tagId/assets', body: {
      'ids': assetIds,
    });
    client.decodeJson(response);
  }

  /// `PUT /tags/assets` — tag assets with several tags at once.
  Future<void> tagAssetsBulk(
    List<String> tagIds,
    List<String> assetIds,
  ) async {
    final response = await client.put('/tags/assets', body: {
      'tagIds': tagIds,
      'ids': assetIds,
    });
    client.decodeJson(response);
  }
}
