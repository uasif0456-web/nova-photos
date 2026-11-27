/// API client tests — error mapping, URL normalisation, media URL
/// builders, cookie extraction, and search pagination (nextPage /
/// nextCursor following) against a mocked HTTP layer.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nova_photos/src/api/api_client.dart';
import 'package:nova_photos/src/api/exceptions.dart';
import 'package:nova_photos/src/api/search_api.dart';
import 'package:nova_photos/src/models/search.dart';

import 'models_test.dart' show assetJson;

ImmichApiClient clientWith(MockClient mock, {String url = 'https://demo.test'}) {
  return ImmichApiClient(serverUrl: url, httpClient: mock);
}

void main() {
  group('normalizeServerUrl', () {
    test('adds https, strips trailing slash and /api', () {
      expect(normalizeServerUrl('demo.immich.app'), 'https://demo.immich.app');
      expect(normalizeServerUrl('https://demo.immich.app/'), 'https://demo.immich.app');
      expect(normalizeServerUrl('https://demo.immich.app/api'), 'https://demo.immich.app');
      expect(normalizeServerUrl('http://192.168.1.5:2283/api/'), 'http://192.168.1.5:2283');
      expect(normalizeServerUrl('  https://demo.immich.app  '), 'https://demo.immich.app');
    });
  });

  group('error mapping', () {
    Future<ImmichApiException> errorForStatus(int status) async {
      final client = clientWith(MockClient(
        (_) async => http.Response('{"message":"boom"}', status),
      ));
      try {
        await client.get('/server/version');
        fail('should have thrown');
      } on ImmichApiException catch (e) {
        return e;
      }
    }

    test('401 -> Unauthorized, 403 -> Forbidden, 404 -> NotFound', () async {
      expect(await errorForStatus(401), isA<ImmichUnauthorizedException>());
      expect(await errorForStatus(403), isA<ImmichForbiddenException>());
      expect(await errorForStatus(404), isA<ImmichNotFoundException>());
    });

    test('400 -> Validation, 413 -> FileTooLarge, 500 -> Server', () async {
      expect(await errorForStatus(400), isA<ImmichValidationException>());
      expect(await errorForStatus(413), isA<ImmichFileTooLargeException>());
      expect(await errorForStatus(500), isA<ImmichServerException>());
    });

    test('message is extracted from JSON; falls back to raw body', () async {
      final e401 = await errorForStatus(401);
      expect(e401.message, 'boom');
      final client = clientWith(MockClient(
        (_) async => http.Response('plain failure', 500),
      ));
      try {
        await client.get('/server/version');
        fail('should have thrown');
      } on ImmichApiException catch (e) {
        expect(e.message, 'plain failure');
      }
    });

    test('transport failure -> NetworkException', () async {
      final client = clientWith(MockClient(
        (_) async => throw http.ClientException('Connection refused'),
      ));
      expect(
        () => client.get('/server/version'),
        throwsA(isA<ImmichNetworkException>()),
      );
    });

    test('Zod-style message arrays are joined', () async {
      final client = clientWith(MockClient(
        (_) async => http.Response(
          '{"message":["email is required","password is required"]}',
          400,
        ),
      ));
      try {
        await client.get('/server/version');
        fail('should have thrown');
      } on ImmichApiException catch (e) {
        expect(e.message, contains('email is required'));
        expect(e.message, contains('password is required'));
      }
    });
  });

  group('MediaUrls', () {
    test('builds thumbnail/preview/original/playback URLs', () {
      final client = clientWith(MockClient((_) async => http.Response('', 200)));
      final media = MediaUrls(client);
      const id = '11111111-2222-3333-4444-555555555555';
      expect(
        media.thumbnail(id).toString(),
        'https://demo.test/api/assets/$id/thumbnail?size=thumbnail',
      );
      expect(
        media.preview(id).toString(),
        'https://demo.test/api/assets/$id/thumbnail?size=preview',
      );
      expect(
        media.original(id).toString(),
        'https://demo.test/api/assets/$id/original?edited=false',
      );
      expect(
        media.videoPlayback(id).toString(),
        'https://demo.test/api/assets/$id/video/playback',
      );
      expect(media.socketIoPath, '/api/socket.io');
    });
  });

  group('cookie extraction', () {
    test('finds immich_access_token in set-cookie', () {
      final response = http.Response(
        '{}',
        201,
        headers: {
          'set-cookie':
              'immich_access_token=abc123; Path=/; HttpOnly, other=1',
        },
      );
      expect(
        ImmichApiClient.extractAccessTokenCookie(response),
        'abc123',
      );
    });

    test('returns null when no cookie is set', () {
      expect(
        ImmichApiClient.extractAccessTokenCookie(http.Response('{}', 201)),
        isNull,
      );
    });
  });

  group('SearchApi pagination', () {
    test('searchMetadataAll follows nextPage until it stops', () async {
      var calls = 0;
      final mock = MockClient((http.Request request) async {
        calls++;
        final body = jsonDecode(request.body) as Map<String, Object?>;
        if (body['page'] == null) {
          return http.Response(jsonEncode({
            'items': [assetJson()],
            'count': 1,
            'nextPage': '2',
            'nextCursor': null,
            'facets': [],
          }), 200);
        }
        expect(body['page'], 2);
        return http.Response(jsonEncode({
          'items': [assetJson(id: '22222222-3333-4444-5555-666666666666')],
          'count': 1,
          'nextPage': null,
          'nextCursor': null,
          'facets': [],
        }), 200);
      });
      final api = SearchApi(clientWith(mock));
      final pages = await api.searchMetadataAll(
        const MetadataSearchRequest(size: 1),
      );
      expect(calls, 2);
      expect(pages.length, 2);
      expect(pages[0].items.length, 1);
      expect(pages[1].items.length, 1);
      final all = await api.searchMetadataAllAssets(
        const MetadataSearchRequest(size: 1),
      );
      expect(all.length, 2);
    });

    test('searchMetadataAll prefers nextCursor over nextPage', () async {
      final seenBodies = <Map<String, Object?>>[];
      final mock = MockClient((http.Request request) async {
        seenBodies.add(jsonDecode(request.body) as Map<String, Object?>);
        if (seenBodies.length == 1) {
          return http.Response(jsonEncode({
            'items': [assetJson()],
            'count': 1,
            'nextPage': 'ignored-when-cursor-present',
            'nextCursor': 'cursor-xyz',
            'facets': [],
          }), 200);
        }
        return http.Response(jsonEncode({
          'items': [],
          'count': 0,
          'nextPage': null,
          'nextCursor': null,
          'facets': [],
        }), 200);
      });
      final api = SearchApi(clientWith(mock));
      await api.searchMetadataAll(const MetadataSearchRequest(size: 1));
      expect(seenBodies.length, 2);
      expect(seenBodies[1]['cursor'], 'cursor-xyz');
      expect(seenBodies[1].containsKey('page'), isFalse);
    });
  });
}
