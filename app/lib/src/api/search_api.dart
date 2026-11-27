/// Search API — `POST /search/metadata`, `/search/smart`,
/// `/search/random`, plus explore / suggestions / places.
/// Hand-written from spec v3.4.2.
///
/// `POST /search/metadata` **is** the asset list endpoint (there is no
/// `GET /assets`). Album contents are listed the same way with
/// `albumIds`. Paging is cursor/page based via `nextPage`/`nextCursor`;
/// `total` is deprecated and never used to drive paging.
library;

import '../models/asset.dart';
import '../models/search.dart';
import 'api_client.dart';

class SearchApi {
  const SearchApi(this.client);

  final ImmichApiClient client;

  /// `POST /search/metadata` — structured asset search / listing.
  Future<SearchResult> searchMetadata(MetadataSearchRequest request) async {
    final response =
        await client.post('/search/metadata', body: request.toJson());
    return SearchResult.fromJson(client.decodeJson(response));
  }

  /// Fetch **all** pages of a metadata search, following `nextPage` /
  /// `nextCursor` until the server stops returning one. Guarded by
  /// [maxPages] so a misbehaving server cannot loop forever.
  Future<List<SearchResult>> searchMetadataAll(
    MetadataSearchRequest request, {
    int maxPages = 50,
  }) async {
    final pages = <SearchResult>[];
    var current = request;
    for (var i = 0; i < maxPages; i++) {
      final page = await searchMetadata(current);
      pages.add(page);
      if (!page.hasNextPage) break;
      // The server returns either an opaque cursor or a page token;
      // prefer the cursor when present, otherwise the page token.
      if (page.nextCursor != null) {
        current = current.copyWith(page: null, cursor: page.nextCursor);
      } else {
        current = current.copyWith(
          page: _parsePageToken(page.nextPage!),
          cursor: null,
        );
      }
    }
    return pages;
  }

  /// Convenience: every asset matching [request], flattened.
  Future<List<NovaAsset>> searchMetadataAllAssets(
    MetadataSearchRequest request, {
    int maxPages = 50,
  }) async {
    final pages = await searchMetadataAll(request, maxPages: maxPages);
    return pages.expand((p) => p.items).toList(growable: false);
  }

  int? _parsePageToken(String token) => int.tryParse(token);

  /// `POST /search/smart` — CLIP semantic search. Gate on
  /// `ServerFeatures.smartSearch` before calling.
  Future<SearchResult> smartSearch(SmartSearchRequest request) async {
    final response =
        await client.post('/search/smart', body: request.toJson());
    return SearchResult.fromJson(client.decodeJson(response));
  }

  /// `POST /search/random` — random assets (same filter family).
  Future<SearchResult> randomAssets({
    int size = 20,
    String? type,
  }) async {
    final response = await client.post('/search/random', body: {
      'size': size,
      'type': ? type,
    });
    return SearchResult.fromJson(client.decodeJson(response));
  }

  /// `GET /search/explore` — explore lanes (objects/faces/places).
  Future<List<Object?>> explore() async {
    final response = await client.get('/search/explore');
    return client.decodeJsonList(response);
  }

  /// `GET /search/suggestions` — search-box suggestions.
  Future<List<String>> suggestions() async {
    final response = await client.get('/search/suggestions');
    final list = client.decodeJsonList(response);
    return list.map((e) => e.toString()).toList(growable: false);
  }

  /// `GET /search/cities` — assets grouped by city.
  Future<List<Object?>> cities() async {
    final response = await client.get('/search/cities');
    return client.decodeJsonList(response);
  }

  /// `GET /search/cities` as typed assets (the spec returns an array
  /// of `AssetResponseDto` — one representative asset per city, in
  /// practice). Track B addition (2026-11-22): the untyped [cities]
  /// above is untouched; this is the typed convenience the Search
  /// screen uses to derive the distinct city names.
  Future<List<NovaAsset>> cityAssets() async {
    final response = await client.get('/search/cities');
    final list = client.decodeJsonList(response);
    return list
        .whereType<Map<String, Object?>>()
        .map(NovaAsset.fromJson)
        .toList(growable: false);
  }

  /// `GET /search/places` — location autocomplete/grouping.
  Future<List<Object?>> places() async {
    final response = await client.get('/search/places');
    return client.decodeJsonList(response);
  }

  /// `GET /search/places` as typed [SearchPlace] entries.
  /// Track B addition (2026-11-22): the untyped [places] above is
  /// untouched; this is the typed convenience the Search screen uses.
  Future<List<SearchPlace>> listPlaces() async {
    final response = await client.get('/search/places');
    final list = client.decodeJsonList(response);
    return list
        .whereType<Map<String, Object?>>()
        .map(SearchPlace.fromJson)
        .toList(growable: false);
  }

  /// `GET /search/person?name=…` — search people by name.
  Future<List<Object?>> searchPerson(String name) async {
    final response =
        await client.get('/search/person', query: {'name': name});
    return client.decodeJsonList(response);
  }

  /// `POST /search/statistics` — facet counts for a query.
  Future<Map<String, Object?>> statistics(
    MetadataSearchRequest request,
  ) async {
    final response =
        await client.post('/search/statistics', body: request.toJson());
    return client.decodeJson(response);
  }
}
