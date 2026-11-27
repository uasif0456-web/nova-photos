/// Model parsing tests — asset/album/search/server models against
/// realistic Immich v3.4.2 JSON (shaped from the OpenAPI spec).
/// Parsing must be lenient: unknown fields ignored, missing optionals
/// defaulted, wrong-typed values never crash the response.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:nova_photos/src/models/album.dart';
import 'package:nova_photos/src/models/asset.dart';
import 'package:nova_photos/src/models/parsing.dart';
import 'package:nova_photos/src/models/search.dart';
import 'package:nova_photos/src/models/server.dart';

Map<String, Object?> assetJson({
  String id = '11111111-2222-3333-4444-555555555555',
  String type = 'IMAGE',
  Object? duration = 0,
}) {
  return {
    'id': id,
    'type': type,
    'checksum': 'a9993e364706816aba3e25717850c26c9cd0d89d',
    'originalFileName': 'IMG_0001.jpg',
    'originalMimeType': 'image/jpeg',
    'originalPath': '/usr/src/app/upload/library/user/$id.jpg',
    'fileCreatedAt': '2026-11-01T10:00:00.000Z',
    'fileModifiedAt': '2026-11-01T10:00:00.000Z',
    'localDateTime': '2026-11-01T15:00:00.000Z',
    'createdAt': '2026-11-01T10:00:01.000Z',
    'updatedAt': '2026-11-01T10:00:01.000Z',
    'width': 4032,
    'height': 3024,
    'duration': duration,
    'isFavorite': true,
    'isArchived': false,
    'isTrashed': false,
    'isOffline': false,
    'isEdited': false,
    'hasMetadata': true,
    'visibility': 'timeline',
    'ownerId': '99999999-8888-7777-6666-555555555555',
    'thumbhash': '1QcSHQRnh493V4dIh4eXh1h1h1h1',
    'exifInfo': {
      'make': 'Google',
      'model': 'Pixel 8',
      'latitude': 31.5204,
      'longitude': 74.3587,
      'city': 'Lahore',
      'country': 'Pakistan',
    },
    // Unknown future field — must be ignored, not crash.
    'someFutureField': {'nested': true},
    'libraryId': 'deprecated-but-present',
  };
}

void main() {
  group('NovaAsset.fromJson', () {
    test('parses a full image asset', () {
      final asset = NovaAsset.fromJson(assetJson());
      expect(asset.id, '11111111-2222-3333-4444-555555555555');
      expect(asset.type, AssetType.image);
      expect(asset.isImage, isTrue);
      expect(asset.isVideo, isFalse);
      expect(asset.isFavorite, isTrue);
      expect(asset.originalFileName, 'IMG_0001.jpg');
      expect(asset.width, 4032);
      expect(asset.height, 3024);
      expect(asset.aspectRatio, closeTo(4032 / 3024, 0.001));
      expect(asset.exifInfo?.make, 'Google');
      expect(asset.exifInfo?.hasLocation, isTrue);
      expect(asset.exifInfo?.city, 'Lahore');
      expect(asset.visibility, AssetVisibility.timeline);
    });

    test('parses a video asset with duration', () {
      final asset = NovaAsset.fromJson(assetJson(
        type: 'VIDEO',
        duration: 12500,
      ));
      expect(asset.isVideo, isTrue);
      expect(asset.duration, const Duration(milliseconds: 12500));
    });

    test('accepts the HH:MM:SS.mmm duration string (v3 migration shape)', () {
      final asset = NovaAsset.fromJson(assetJson(duration: '00:00:12.500'));
      expect(asset.duration, const Duration(milliseconds: 12500));
    });

    test('tolerates missing optional fields', () {
      final asset = NovaAsset.fromJson({'id': 'x'});
      expect(asset.id, 'x');
      expect(asset.type, AssetType.other);
      expect(asset.isFavorite, isFalse);
      expect(asset.visibility, AssetVisibility.timeline);
      expect(asset.exifInfo, isNull);
      expect(asset.people, isEmpty);
    });

    test('copyWith toggles favorite/archive without touching the rest', () {
      final asset = NovaAsset.fromJson(assetJson());
      final updated = asset.copyWith(
        isFavorite: false,
        visibility: AssetVisibility.archive,
      );
      expect(updated.isFavorite, isFalse);
      expect(updated.isArchived, isFalse); // copyWith keeps stored flag
      expect(updated.visibility, AssetVisibility.archive);
      expect(updated.id, asset.id);
      expect(updated.checksum, asset.checksum);
    });
  });

  group('Album.fromJson', () {
    test('parses an album; first albumUser is the owner', () {
      final album = Album.fromJson({
        'id': 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee',
        'albumName': 'Lahore trip',
        'description': 'November 2026',
        'albumUsers': [
          {
            'user': {
              'id': 'u1',
              'email': 'owner@example.com',
              'name': 'Owner',
              'profileImagePath': '',
              'avatarColor': 'primary',
              'profileChangedAt': '2026-01-01T00:00:00.000Z',
            },
            'role': 'owner',
          },
          {
            'user': {
              'id': 'u2',
              'email': 'friend@example.com',
              'name': 'Friend',
              'profileImagePath': '',
              'avatarColor': 'secondary',
              'profileChangedAt': '2026-01-01T00:00:00.000Z',
            },
            'role': 'viewer',
          },
        ],
        'assetCount': 42,
        'shared': true,
        'hasSharedLink': false,
        'isActivityEnabled': true,
        'createdAt': '2026-11-01T00:00:00.000Z',
        'updatedAt': '2026-11-02T00:00:00.000Z',
        'albumThumbnailAssetId': '11111111-2222-3333-4444-555555555555',
      });
      expect(album.albumName, 'Lahore trip');
      expect(album.assetCount, 42);
      expect(album.shared, isTrue);
      expect(album.owner?.email, 'owner@example.com');
      expect(album.albumUsers[1].role, 'viewer');
    });
  });

  group('SearchResult', () {
    test('parses items + nextPage/nextCursor; total ignored for paging', () {
      final result = SearchResult.fromJson({
        'items': [assetJson(), assetJson(id: '22222222-3333-4444-5555-666666666666')],
        'count': 2,
        'total': 9999, // deprecated — the model does not even read it
        'nextPage': '2',
        'nextCursor': null,
        'facets': [],
      });
      expect(result.items.length, 2);
      expect(result.count, 2);
      expect(result.nextPage, '2');
      expect(result.nextCursor, isNull);
      expect(result.hasNextPage, isTrue);
    });

    test('hasNextPage is false when both tokens are null', () {
      final result = SearchResult.fromJson({
        'items': [],
        'count': 0,
        'nextPage': null,
        'nextCursor': null,
        'facets': [],
      });
      expect(result.hasNextPage, isFalse);
    });

    test('parses the live wrapper shape {albums, assets}', () {
      // This is what the server actually returns (spec SearchResponseDto):
      // the asset page lives under `assets`, album matches under `albums`.
      final result = SearchResult.fromJson({
        'albums': {
          'total': 1,
          'count': 1,
          'items': [
            {
              'id': 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee',
              'albumName': 'Lahore trip',
              'description': '',
              'albumUsers': [],
              'assetCount': 3,
              'shared': false,
              'hasSharedLink': false,
              'isActivityEnabled': false,
              'createdAt': '2026-11-01T00:00:00.000Z',
              'updatedAt': '2026-11-01T00:00:00.000Z',
            },
          ],
          'facets': [],
        },
        'assets': {
          'total': 1,
          'count': 1,
          'items': [assetJson()],
          'nextPage': null,
          'nextCursor': null,
          'facets': [],
        },
      });
      expect(result.items.length, 1);
      expect(result.items.first.originalFileName, 'IMG_0001.jpg');
      expect(result.albums.length, 1);
      expect(result.albums.first.albumName, 'Lahore trip');
      expect(result.hasNextPage, isFalse);
    });
  });

  group('MetadataSearchRequest.copyWith', () {
    test('explicit null clears the field; omitted keeps it', () {
      const request = MetadataSearchRequest(page: 3, cursor: 'abc', size: 50);
      final cleared = request.copyWith(page: null);
      expect(cleared.page, isNull);
      expect(cleared.cursor, 'abc');
      final kept = request.copyWith();
      expect(kept.page, 3);
      expect(kept.cursor, 'abc');
      expect(kept.size, 50);
    });

    test('toJson omits unset filters and always sends size/order', () {
      const request = MetadataSearchRequest(isFavorite: true, size: 25);
      final json = request.toJson();
      expect(json['isFavorite'], isTrue);
      expect(json['size'], 25);
      expect(json['order'], 'desc');
      expect(json.containsKey('albumIds'), isFalse);
      expect(json.containsKey('page'), isFalse);
    });
  });

  group('ServerVersion gating', () {
    test('v3 is supported; v2 is too old; v4 warns', () {
      final v2 = ServerVersion.fromJson({
        'major': 2, 'minor': 7, 'patch': 5, 'featureLevel': 1,
      });
      expect(v2.isTooOld, isTrue);
      expect(v2.isSupportedMajor, isFalse);

      final v3 = ServerVersion.fromJson({
        'major': 3, 'minor': 4, 'patch': 2, 'featureLevel': 2,
      });
      expect(v3.isTooOld, isFalse);
      expect(v3.isNewerMajor, isFalse);
      expect(v3.isSupportedMajor, isTrue);

      final v4 = ServerVersion.fromJson({
        'major': 4, 'minor': 0, 'patch': 0, 'featureLevel': 3,
      });
      expect(v4.isNewerMajor, isTrue);
      expect(v4.isTooOld, isFalse);
    });

    test('prerelease may be null (live demo returns null)', () {
      final version = ServerVersion.fromJson({
        'major': 3,
        'minor': 4,
        'patch': 2,
        'prerelease': null,
        'featureLevel': 2,
      });
      expect(version.prerelease, isNull);
      expect(version.toString(), contains('3.4.2'));
    });
  });

  group('parseDuration', () {
    test('int is milliseconds, double is seconds, string is HH:MM:SS', () {
      expect(parseDuration(5000), const Duration(milliseconds: 5000));
      expect(parseDuration(2.5), const Duration(milliseconds: 2500));
      expect(parseDuration('01:02:03.456'),
          const Duration(hours: 1, minutes: 2, milliseconds: 3456));
      expect(parseDuration(null), isNull);
      expect(parseDuration('garbage'), isNull);
    });
  });
}
