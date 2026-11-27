/// Search models — `SearchAssetResponseDto`, `MetadataSearchDto`,
/// `SmartSearchDto`, and the timeline bucket models.
/// Hand-written from spec v3.4.2.
///
/// Pagination: the modern model is cursor/page based. The response
/// carries `nextPage` and `nextCursor`; `total` is **deprecated** in v3
/// and must never be used to drive paging.
library;

import 'album.dart';
import 'asset.dart';
import 'parsing.dart';

/// The result page of `POST /search/metadata`, `/search/smart`,
/// `/search/random`.
/// The server wraps the asset page in a `SearchResponseDto`:
/// `{albums: {...}, assets: {items, count, nextPage, nextCursor}}`.
/// The asset page lives under `assets`; the album matches (if any)
/// under `albums`. A bare page (`{items, ...}` with no wrapper) is
/// also accepted, defensively.
class SearchResult {
  const SearchResult({
    required this.items,
    required this.count,
    this.albums = const [],
    this.nextPage,
    this.nextCursor,
  });

  factory SearchResult.fromJson(Map<String, Object?> json) {
    final assetsJson = json['assets'];
    final pageJson = assetsJson is Map<String, Object?> ? assetsJson : json;
    final albumsJson = json['albums'];
    final albumItems = albumsJson is Map<String, Object?>
        ? parseMapList(albumsJson['items']).map(Album.fromJson).toList()
        : const <Album>[];
    return SearchResult(
      items: parseMapList(pageJson['items']).map(NovaAsset.fromJson).toList(),
      count: parseInt(pageJson['count']) ?? 0,
      albums: albumItems,
      nextPage: parseString(pageJson['nextPage']),
      nextCursor: parseString(pageJson['nextCursor']),
    );
  }

  final List<NovaAsset> items;

  /// Number of items in this page.
  final int count;

  /// Album matches for the same query (metadata/smart search only).
  final List<Album> albums;

  /// Opaque token for the next page (null when there is no next page).
  final String? nextPage;

  /// Opaque cursor for the next page (null when there is no next page).
  final String? nextCursor;

  bool get hasNextPage => nextPage != null || nextCursor != null;

  Map<String, Object?> toJson() => {
        'assets': {
          'items': items.map((a) => a.toJson()).toList(),
          'count': count,
          if (nextPage != null) 'nextPage': nextPage,
          if (nextCursor != null) 'nextCursor': nextCursor,
        },
        'albums': {
          'items': albums.map((a) => a.toJson()).toList(),
          'count': albums.length,
        },
      };
}

/// Request body for `POST /search/metadata` (`MetadataSearchDto`).
/// Only the fields NOVA uses are modelled; the spec defines 40+.
/// Unset fields are omitted from the JSON (the server applies defaults).
///
/// Track B addition (2026-11-22): `city` / `country` — the spec's
/// `MetadataSearchDto` has both, the hand-written request did not;
/// place results from `GET /search/places` need them to filter.
class MetadataSearchRequest {
  const MetadataSearchRequest({
    this.albumIds,
    this.personIds,
    this.tagIds,
    this.type,
    this.isFavorite,
    this.isTrashed,
    this.isMotion,
    this.isNotInAlbum,
    this.visibility,
    this.takenAfter,
    this.takenBefore,
    this.createdAfter,
    this.createdBefore,
    this.originalFileName,
    this.checksum,
    this.city,
    this.country,
    this.withExif = false,
    this.withPeople = false,
    this.withStacked = false,
    this.withDeleted = false,
    this.order = 'desc',
    this.page,
    this.cursor,
    this.size = 100,
  });

  final List<String>? albumIds;
  final List<String>? personIds;
  final List<String>? tagIds;
  final AssetType? type;
  final bool? isFavorite;
  final bool? isTrashed;
  final bool? isMotion;
  final bool? isNotInAlbum;
  final AssetVisibility? visibility;
  final DateTime? takenAfter;
  final DateTime? takenBefore;
  final DateTime? createdAfter;
  final DateTime? createdBefore;
  final String? originalFileName;
  final String? checksum;
  final String? city;
  final String? country;
  final bool withExif;
  final bool withPeople;
  final bool withStacked;
  final bool withDeleted;

  /// `asc` | `desc`.
  final String order;
  final int? page;
  final String? cursor;
  final int size;

  static const Object _unset = Object();

  /// Copy with overrides. Passing an explicit `null` for [page] or
  /// [cursor] clears that field (needed when switching between page
  /// and cursor paging); omitting it keeps the current value.
  MetadataSearchRequest copyWith({
    Object? page = _unset,
    Object? cursor = _unset,
  }) {
    return MetadataSearchRequest(
      albumIds: albumIds,
      personIds: personIds,
      tagIds: tagIds,
      type: type,
      isFavorite: isFavorite,
      isTrashed: isTrashed,
      isMotion: isMotion,
      isNotInAlbum: isNotInAlbum,
      visibility: visibility,
      takenAfter: takenAfter,
      takenBefore: takenBefore,
      createdAfter: createdAfter,
      createdBefore: createdBefore,
      originalFileName: originalFileName,
      checksum: checksum,
      city: city,
      country: country,
      withExif: withExif,
      withPeople: withPeople,
      withStacked: withStacked,
      withDeleted: withDeleted,
      order: order,
      page: page == _unset ? this.page : page as int?,
      cursor: cursor == _unset ? this.cursor : cursor as String?,
      size: size,
    );
  }

  Map<String, Object?> toJson() => {
        if (albumIds != null) 'albumIds': albumIds,
        if (personIds != null) 'personIds': personIds,
        if (tagIds != null) 'tagIds': tagIds,
        if (type != null) 'type': assetTypeToJson(type!),
        if (isFavorite != null) 'isFavorite': isFavorite,
        if (isTrashed != null) 'isTrashed': isTrashed,
        if (isMotion != null) 'isMotion': isMotion,
        if (isNotInAlbum != null) 'isNotInAlbum': isNotInAlbum,
        if (visibility != null)
          'visibility': assetVisibilityToJson(visibility!),
        if (takenAfter != null) 'takenAfter': takenAfter!.toIso8601String(),
        if (takenBefore != null)
          'takenBefore': takenBefore!.toIso8601String(),
        if (createdAfter != null)
          'createdAfter': createdAfter!.toIso8601String(),
        if (createdBefore != null)
          'createdBefore': createdBefore!.toIso8601String(),
        if (originalFileName != null) 'originalFileName': originalFileName,
        if (checksum != null) 'checksum': checksum,
        if (city != null) 'city': city,
        if (country != null) 'country': country,
        'withExif': withExif,
        'withPeople': withPeople,
        'withStacked': withStacked,
        'withDeleted': withDeleted,
        'order': order,
        if (page != null) 'page': page,
        if (cursor != null) 'cursor': cursor,
        'size': size,
      };
}

/// Request body for `POST /search/smart` (`SmartSearchDto`) — CLIP
/// semantic search. Requires the server's `smartSearch` feature flag.
class SmartSearchRequest {
  const SmartSearchRequest({
    this.query,
    this.queryAssetId,
    this.language,
    this.albumIds,
    this.personIds,
    this.tagIds,
    this.type,
    this.isFavorite,
    this.takenAfter,
    this.takenBefore,
    this.page,
    this.size = 100,
  });

  /// Natural-language query, e.g. "sunset over the ocean".
  final String? query;

  /// Find assets visually similar to this asset id.
  final String? queryAssetId;
  final String? language;
  final List<String>? albumIds;
  final List<String>? personIds;
  final List<String>? tagIds;
  final AssetType? type;
  final bool? isFavorite;
  final DateTime? takenAfter;
  final DateTime? takenBefore;
  final int? page;
  final int size;

  Map<String, Object?> toJson() => {
        if (query != null) 'query': query,
        if (queryAssetId != null) 'queryAssetId': queryAssetId,
        if (language != null) 'language': language,
        if (albumIds != null) 'albumIds': albumIds,
        if (personIds != null) 'personIds': personIds,
        if (tagIds != null) 'tagIds': tagIds,
        if (type != null) 'type': assetTypeToJson(type!),
        if (isFavorite != null) 'isFavorite': isFavorite,
        if (takenAfter != null) 'takenAfter': takenAfter!.toIso8601String(),
        if (takenBefore != null)
          'takenBefore': takenBefore!.toIso8601String(),
        if (page != null) 'page': page,
        'size': size,
      };
}

/// One month entry of `GET /timeline/buckets`
/// (`TimeBucketsResponseDto`).
class TimeBucket {
  const TimeBucket({required this.timeBucket, required this.count});

  factory TimeBucket.fromJson(Map<String, Object?> json) {
    return TimeBucket(
      timeBucket:
          parseDateTime(json['timeBucket']) ?? DateTime.fromMillisecondsSinceEpoch(0),
      count: parseInt(json['count']) ?? 0,
    );
  }

  /// First day of the month (UTC, `YYYY-MM-01T00:00:00.000Z`).
  final DateTime timeBucket;
  final int count;

  Map<String, Object?> toJson() => {
        'timeBucket': timeBucket.toIso8601String(),
        'count': count,
      };
}

/// One asset summary inside `GET /timeline/bucket`
/// (`TimeBucketAssetResponseDto`). The server returns columnar arrays —
/// one array per field, all the same length — so the model is built
/// from an index into those arrays.
class TimeBucketAsset {
  const TimeBucketAsset({
    required this.id,
    required this.createdAt,
    required this.fileCreatedAt,
    required this.duration,
    required this.isFavorite,
    required this.isImage,
    required this.isTrashed,
    required this.livePhotoVideoId,
    required this.ownerId,
    required this.ratio,
    required this.thumbhash,
    required this.visibility,
    this.city,
    this.country,
    this.latitude,
    this.longitude,
  });

  factory TimeBucketAsset.fromColumns(
    Map<String, Object?> json,
    int index,
  ) {
    T? at<T>(String key) {
      final list = json[key];
      if (list is List && index < list.length) {
        final value = list[index];
        return value is T ? value : null;
      }
      return null;
    }

    return TimeBucketAsset(
      id: at<String>('id') ?? '',
      createdAt: DateTime.tryParse(at<String>('createdAt') ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      fileCreatedAt: DateTime.tryParse(at<String>('fileCreatedAt') ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      duration: parseDuration(at<Object>('duration')),
      isFavorite: at<bool>('isFavorite') ?? false,
      isImage: at<bool>('isImage') ?? true,
      isTrashed: at<bool>('isTrashed') ?? false,
      livePhotoVideoId: at<String>('livePhotoVideoId'),
      ownerId: at<String>('ownerId') ?? '',
      ratio: (at<num>('ratio') ?? 1).toDouble(),
      thumbhash: at<String>('thumbhash') ?? '',
      visibility: assetVisibilityFromJson(at<String>('visibility')),
      city: at<String>('city'),
      country: at<String>('country'),
      latitude: at<num>('latitude')?.toDouble(),
      longitude: at<num>('longitude')?.toDouble(),
    );
  }

  final String id;
  final DateTime createdAt;
  final DateTime fileCreatedAt;
  final Duration? duration;
  final bool isFavorite;
  final bool isImage;
  final bool isTrashed;
  final String? livePhotoVideoId;
  final String ownerId;
  final double ratio;
  final String thumbhash;
  final AssetVisibility visibility;
  final String? city;
  final String? country;
  final double? latitude;
  final double? longitude;

  /// Number of rows in the columnar response.
  static int rowCount(Map<String, Object?> json) {
    final ids = json['id'];
    return ids is List ? ids.length : 0;
  }

  static List<TimeBucketAsset> listFromJson(Map<String, Object?> json) {
    return List<TimeBucketAsset>.generate(
      rowCount(json),
      (i) => TimeBucketAsset.fromColumns(json, i),
      growable: false,
    );
  }
}

/// One entry of `GET /search/places` (`PlacesResponseDto`) — a named
/// place with coordinates. Track B addition (2026-11-22): the client
/// previously returned the raw list; this typed model lets the Search
/// screen show place results and filter by `city` / `country`.
class SearchPlace {
  const SearchPlace({
    required this.name,
    required this.latitude,
    required this.longitude,
    this.admin1name,
    this.admin2name,
  });

  factory SearchPlace.fromJson(Map<String, Object?> json) {
    return SearchPlace(
      name: parseString(json['name']) ?? '',
      latitude: parseDouble(json['latitude']) ?? 0,
      longitude: parseDouble(json['longitude']) ?? 0,
      admin1name: parseString(json['admin1name']),
      admin2name: parseString(json['admin2name']),
    );
  }

  final String name;
  final double latitude;
  final double longitude;

  /// Administrative level 1 name (state/province).
  final String? admin1name;

  /// Administrative level 2 name (county/district).
  final String? admin2name;

  /// Display label, e.g. "Lahore, Punjab".
  String get label =>
      admin1name == null ? name : '$name, $admin1name';

  Map<String, Object?> toJson() => {
        'name': name,
        'latitude': latitude,
        'longitude': longitude,
        if (admin1name != null) 'admin1name': admin1name,
        if (admin2name != null) 'admin2name': admin2name,
      };
}
