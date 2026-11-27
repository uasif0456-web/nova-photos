/// Track B tests — timeline grouping, selection, recent searches,
/// album/search API calls against a mocked HTTP layer, the photos
/// notifier's local updates, and viewer navigation.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nova_photos/src/api/api_client.dart';
import 'package:nova_photos/src/api/nova_api.dart';
import 'package:nova_photos/src/models/asset.dart';
import 'package:nova_photos/src/models/search.dart';
import 'package:nova_photos/src/providers/providers.dart';
import 'package:nova_photos/src/providers/track_b_providers.dart';
import 'package:nova_photos/src/ui/screens/viewer_screen.dart';
import 'package:nova_photos/src/ui/widgets/asset_tile.dart';
import 'package:nova_photos/src/utils/recent_searches.dart';
import 'package:nova_photos/src/utils/timeline_utils.dart';

import 'models_test.dart' show assetJson;

NovaAsset asset({
  String id = 'a1',
  String file = 'IMG_0001.jpg',
  DateTime? taken,
  bool favorite = false,
  String type = 'IMAGE',
  Object? duration = 0,
}) {
  final json = assetJson(id: id, type: type, duration: duration);
  json['originalFileName'] = file;
  json['isFavorite'] = favorite;
  final t = taken ?? DateTime(2026, 11, 1, 10, 0);
  json['localDateTime'] = t.toIso8601String();
  json['fileCreatedAt'] = t.toIso8601String();
  return NovaAsset.fromJson(json);
}

Map<String, Object?> albumJson({
  String id = 'al1',
  String name = 'Lahore trip',
  int count = 3,
}) {
  return {
    'id': id,
    'albumName': name,
    'description': '',
    'albumUsers': [],
    'assetCount': count,
    'shared': false,
    'hasSharedLink': false,
    'isActivityEnabled': false,
    'createdAt': '2026-11-01T00:00:00.000Z',
    'updatedAt': '2026-11-01T00:00:00.000Z',
  };
}

void main() {
  group('timeline utils', () {
    test('groupAssetsByDay groups by local date, newest first', () {
      final assets = [
        asset(id: 'a1', taken: DateTime(2026, 11, 2, 9, 0)),
        asset(id: 'a2', taken: DateTime(2026, 11, 1, 10, 0)),
        asset(id: 'a3', taken: DateTime(2026, 11, 2, 18, 0)),
        asset(id: 'a4', taken: DateTime(2025, 4, 1, 8, 0)),
      ];
      final sections = groupAssetsByDay(assets);
      expect(sections.length, 3);
      expect(sections[0].day, DateTime(2026, 11, 2));
      expect(sections[0].assets.map((a) => a.id), ['a3', 'a1']);
      expect(sections[1].assets.map((a) => a.id), ['a2']);
      expect(sections[2].day, DateTime(2025, 4, 1));
    });

    test('dayLabel says Today / Yesterday / full date', () {
      final now = DateTime(2026, 11, 22, 12, 0);
      expect(dayLabel(DateTime(2026, 11, 22), now: now), 'Today');
      expect(dayLabel(DateTime(2026, 11, 21), now: now), 'Yesterday');
      expect(
        dayLabel(DateTime(2026, 11, 1), now: now),
        'Sunday, 1 November 2026',
      );
    });

    test('formatDuration renders tile badges', () {
      expect(formatDuration(null), '');
      expect(formatDuration(const Duration(seconds: 12)), '0:12');
      expect(formatDuration(const Duration(minutes: 1, seconds: 5)), '1:05');
      expect(
        formatDuration(const Duration(hours: 1, minutes: 2, seconds: 3)),
        '1:02:03',
      );
    });

    test('sectionIndexForOffset finds the section at an offset', () {
      final sections = [
        DaySection(day: DateTime(2026, 11, 2), assets: [asset(id: 'a1')]),
        DaySection(
          day: DateTime(2026, 11, 1),
          assets: [asset(id: 'a2'), asset(id: 'a3'), asset(id: 'a4')],
        ),
      ];
      // Section 0: header 48 + 1 row * 100 = 148. Section 1 follows.
      expect(
        sectionIndexForOffset(
          sections: sections,
          offset: 0,
          tileHeight: 100,
          headerHeight: 48,
        ),
        0,
      );
      expect(
        sectionIndexForOffset(
          sections: sections,
          offset: 200,
          tileHeight: 100,
          headerHeight: 48,
        ),
        1,
      );
      expect(
        sectionIndexForOffset(
          sections: sections,
          offset: 99999,
          tileHeight: 100,
          headerHeight: 48,
        ),
        1,
      );
    });

    test('onThisDayByYear picks same month/day in earlier years', () {
      final assets = [
        asset(id: 'a1', taken: DateTime(2025, 11, 22, 10, 0)),
        asset(id: 'a2', taken: DateTime(2024, 11, 22, 10, 0)),
        asset(id: 'a3', taken: DateTime(2025, 11, 21, 10, 0)),
        asset(id: 'a4', taken: DateTime(2026, 11, 22, 10, 0)),
      ];
      final byYear = onThisDayByYear(
        assets,
        today: DateTime(2026, 11, 22),
      );
      expect(byYear.keys.toSet(), {2025, 2024});
      expect(byYear[2025]!.map((a) => a.id), ['a1']);
    });

    test('bucketLabel formats a date-only bucket month', () {
      final bucket = TimeBucket.fromJson({
        'timeBucket': '2025-04-01',
        'count': 5,
      });
      expect(bucket.timeBucket.month, 4);
      expect(bucketLabel(bucket), 'April 2025');
    });
  });

  group('SelectionNotifier', () {
    test('toggle / selectAll / clear', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(selectionProvider.notifier);
      expect(container.read(selectionProvider), isEmpty);
      notifier.toggle('a');
      expect(container.read(selectionProvider), {'a'});
      notifier.toggle('a');
      expect(container.read(selectionProvider), isEmpty);
      notifier.selectAll(['a', 'b']);
      expect(container.read(selectionProvider), {'a', 'b'});
      expect(notifier.isSelecting, isTrue);
      notifier.clear();
      expect(container.read(selectionProvider), isEmpty);
      expect(notifier.isSelecting, isFalse);
    });
  });

  group('RecentSearchesStore', () {
    test('adds most-recent-first, dedups, caps, removes, clears', () async {
      final dir = await Directory.systemTemp.createTemp('nova-recent-');
      addTearDown(() => dir.delete(recursive: true));
      final store = RecentSearchesStore(
        directory: () async => dir,
        maxEntries: 3,
      );
      expect(await store.load(), isEmpty);
      await store.add('sunset');
      await store.add('beach');
      await store.add('Sunset'); // dedup, case-insensitive, moves to front
      expect(await store.load(), ['Sunset', 'beach']);
      await store.add('mountains');
      await store.add('desert'); // capped at 3
      expect(await store.load(), ['desert', 'mountains', 'Sunset']);
      await store.remove('mountains');
      expect(await store.load(), ['desert', 'Sunset']);
      await store.clear();
      expect(await store.load(), isEmpty);
    });

    test('corrupt file loads as empty, never throws', () async {
      final dir = await Directory.systemTemp.createTemp('nova-recent-');
      addTearDown(() => dir.delete(recursive: true));
      await File('${dir.path}/recent_searches.json')
          .writeAsString('not json at all');
      final store = RecentSearchesStore(directory: () async => dir);
      expect(await store.load(), isEmpty);
    });
  });

  group('search models (Track B additions)', () {
    test('MetadataSearchRequest carries city/country', () {
      const request = MetadataSearchRequest(city: 'Lahore', country: 'PK');
      final json = request.toJson();
      expect(json['city'], 'Lahore');
      expect(json['country'], 'PK');
      expect(request.copyWith().city, 'Lahore');
    });

    test('SearchPlace parses name/admin/lat/lng and labels', () {
      final place = SearchPlace.fromJson({
        'name': 'Lahore',
        'admin1name': 'Punjab',
        'latitude': 31.5204,
        'longitude': 74.3587,
      });
      expect(place.label, 'Lahore, Punjab');
      expect(place.latitude, closeTo(31.5204, 0.0001));
    });
  });

  group('album + search API (mock HTTP)', () {
    late List<http.BaseRequest> seen;
    late NovaApi api;

    setUp(() {
      seen = [];
      final mock = MockClient((request) async {
        seen.add(request);
        final path = request.url.path;
        if (request.method == 'POST' && path == '/api/albums') {
          return http.Response(jsonEncode(albumJson()), 201);
        }
        if (request.method == 'PATCH' && path == '/api/albums/al1') {
          return http.Response(
            jsonEncode(albumJson(name: 'Renamed')),
            200,
          );
        }
        if (request.method == 'DELETE' && path == '/api/albums/al1') {
          return http.Response('', 204);
        }
        if (request.method == 'PUT' &&
            path == '/api/albums/al1/assets') {
          return http.Response('', 204);
        }
        if (request.method == 'DELETE' &&
            path == '/api/albums/al1/assets') {
          return http.Response('', 204);
        }
        if (request.method == 'POST' && path == '/api/search/metadata') {
          final body = jsonDecode(request.body) as Map<String, Object?>;
          expect(body['albumIds'], ['al1']);
          return http.Response(
            jsonEncode({
              'assets': {
                'items': [assetJson(), assetJson(id: 'b2')],
                'count': 2,
                'nextPage': null,
                'nextCursor': null,
              },
              'albums': {'items': [], 'count': 0},
            }),
            200,
          );
        }
        if (request.method == 'GET' && path == '/api/search/places') {
          return http.Response(
            jsonEncode([
              {
                'name': 'Lahore',
                'admin1name': 'Punjab',
                'latitude': 31.5204,
                'longitude': 74.3587,
              },
            ]),
            200,
          );
        }
        if (request.method == 'GET' && path == '/api/search/cities') {
          return http.Response(jsonEncode([assetJson()]), 200);
        }
        return http.Response('{"message":"not found"}', 404);
      });
      api = NovaApi(
        ImmichApiClient(serverUrl: 'https://demo.test', httpClient: mock),
      );
    });

    test('create / rename / delete album', () async {
      final created = await api.albums.createAlbum(albumName: 'Lahore trip');
      expect(created.albumName, 'Lahore trip');
      final renamed = await api.albums.updateAlbum('al1', albumName: 'Renamed');
      expect(renamed.albumName, 'Renamed');
      await api.albums.deleteAlbum('al1');
      expect(
        seen.map((r) => '${r.method} ${r.url.path}'),
        contains('DELETE /api/albums/al1'),
      );
    });

    test('add / remove assets from an album', () async {
      await api.albums.addAssets('al1', ['a1', 'a2']);
      await api.albums.removeAssets('al1', ['a1']);
      expect(
        seen.map((r) => '${r.method} ${r.url.path}'),
        containsAll([
          'PUT /api/albums/al1/assets',
          'DELETE /api/albums/al1/assets',
        ]),
      );
    });

    test('album assets load via search/metadata with albumIds', () async {
      final assets = await api.search.searchMetadataAllAssets(
        const MetadataSearchRequest(albumIds: ['al1'], size: 100),
      );
      expect(assets.length, 2);
      expect(assets.first.originalFileName, 'IMG_0001.jpg');
    });

    test('listPlaces and cityAssets parse typed results', () async {
      final places = await api.search.listPlaces();
      expect(places.length, 1);
      expect(places.first.label, 'Lahore, Punjab');
      final cities = await api.search.cityAssets();
      expect(cities.length, 1);
      expect(cities.first.exifInfo?.city, 'Lahore');
    });
  });

  group('PhotosNotifier local updates', () {
    test('updateAsset replaces in place; removeAssets drops', () async {
      final mock = MockClient((request) async {
        if (request.url.path == '/api/search/metadata') {
          return http.Response(
            jsonEncode({
              'assets': {
                'items': [assetJson(), assetJson(id: 'b2')],
                'count': 2,
                'nextPage': null,
                'nextCursor': null,
              },
              'albums': {'items': [], 'count': 0},
            }),
            200,
          );
        }
        return http.Response('{"message":"not found"}', 404);
      });
      final api = NovaApi(
        ImmichApiClient(serverUrl: 'https://demo.test', httpClient: mock),
      );
      final container = ProviderContainer(
        overrides: [novaApiProvider.overrideWithValue(api)],
      );
      addTearDown(container.dispose);
      final loaded = await container.read(photosProvider.future);
      expect(loaded.length, 2);
      final notifier = container.read(photosProvider.notifier);
      notifier.updateAsset(loaded.first.copyWith(isFavorite: false));
      expect(
        container.read(photosProvider).value!.first.isFavorite,
        isFalse,
      );
      notifier.removeAssets(['b2']);
      expect(container.read(photosProvider).value!.length, 1);
    });
  });

  group('widgets', () {
    testWidgets('AssetTile shows video duration and favorite mark',
        (tester) async {
      final video = asset(
        type: 'VIDEO',
        duration: 12500,
        favorite: true,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 120,
              height: 120,
              child: AssetTile(
                asset: video,
                thumbnailUrl: null,
                headers: const {},
              ),
            ),
          ),
        ),
      );
      expect(find.text('0:12'), findsOneWidget);
      expect(find.byIcon(Icons.favorite), findsOneWidget);
    });

    testWidgets('ViewerScreen pages across the result set', (tester) async {
      final mock = MockClient(
        (_) async => http.Response('{"message":"not found"}', 404),
      );
      final api = NovaApi(
        ImmichApiClient(serverUrl: 'https://demo.test', httpClient: mock),
      );
      final assets = [
        asset(id: 'a1', file: 'FIRST.jpg'),
        asset(id: 'a2', file: 'SECOND.jpg'),
      ];
      await tester.pumpWidget(
        ProviderScope(
          overrides: [novaApiProvider.overrideWithValue(api)],
          child: MaterialApp(
            home: ViewerScreen(assets: assets, initialIndex: 0),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('1 of 2'), findsOneWidget);
      expect(find.textContaining('FIRST.jpg'), findsOneWidget);
      await tester.fling(
        find.byType(PageView),
        const Offset(-400, 0),
        1000,
      );
      // No pumpAndSettle: the image placeholder spinner animates
      // forever in tests. Manual pumps run the page animation out.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('2 of 2'), findsOneWidget);
      expect(find.textContaining('SECOND.jpg'), findsOneWidget);
    });
  });
}
