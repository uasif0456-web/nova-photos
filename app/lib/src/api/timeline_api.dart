/// Timeline API — `GET /timeline/buckets`, `GET /timeline/bucket`.
/// Hand-written from spec v3.4.2.
///
/// These endpoints are marked `Internal` in the spec (built for the
/// official clients) but stable in practice since v1. The timeline is
/// the primary data source for the Photos tab: buckets first (one
/// entry per month with a count), then per-month asset summaries.
/// The full local-first sync mirror (Drift + `/sync/stream`) lands in
/// Track B; these endpoints are the server-side fallback and the v1
/// timeline source.
library;

import '../models/search.dart';
import 'api_client.dart';

class TimelineApi {
  const TimelineApi(this.client);

  final ImmichApiClient client;

  /// `GET /timeline/buckets` — one entry per month that has assets.
  Future<List<TimeBucket>> getBuckets({
    String? albumId,
    String? personId,
    String? tagId,
    String? userId,
    bool? isFavorite,
    bool? isTrashed,
    String? visibility,
    bool? withPartners,
    bool? withStacked,
    String order = 'desc',
  }) async {
    final response = await client.get('/timeline/buckets', query: {
      'albumId': ? albumId,
      'personId': ? personId,
      'tagId': ? tagId,
      'userId': ? userId,
      'isFavorite': ? isFavorite,
      'isTrashed': ? isTrashed,
      'visibility': ? visibility,
      'withPartners': ? withPartners,
      'withStacked': ? withStacked,
      'order': order,
    });
    final list = client.decodeJsonList(response);
    return list
        .whereType<Map<String, Object?>>()
        .map(TimeBucket.fromJson)
        .toList(growable: false);
  }

  /// `GET /timeline/bucket?timeBucket=YYYY-MM-01T00:00:00.000Z` —
  /// asset summaries for one month (columnar arrays).
  Future<List<TimeBucketAsset>> getBucket(
    DateTime timeBucket, {
    String? albumId,
    String? personId,
    String? tagId,
    String? userId,
    bool? isFavorite,
    bool? isTrashed,
    String? visibility,
    bool? withPartners,
    bool? withStacked,
  }) async {
    final bucket = DateTime.utc(timeBucket.year, timeBucket.month, 1);
    final response = await client.get('/timeline/bucket', query: {
      'timeBucket': bucket.toIso8601String(),
      'albumId': ? albumId,
      'personId': ? personId,
      'tagId': ? tagId,
      'userId': ? userId,
      'isFavorite': ? isFavorite,
      'isTrashed': ? isTrashed,
      'visibility': ? visibility,
      'withPartners': ? withPartners,
      'withStacked': ? withStacked,
    });
    return TimeBucketAsset.listFromJson(client.decodeJson(response));
  }
}
