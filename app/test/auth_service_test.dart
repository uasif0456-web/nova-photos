/// Auth service tests — login, session restore, logout, version
/// gating. The HTTP layer is mocked with `package:http/testing.dart`;
/// the token store is the in-memory implementation.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nova_photos/src/api/api_client.dart';
import 'package:nova_photos/src/api/exceptions.dart';
import 'package:nova_photos/src/services/auth_service.dart';
import 'package:nova_photos/src/services/token_store.dart';

const _serverUrl = 'https://demo.test';

Map<String, Object?> _loginJson() => {
      'accessToken': 'jwt-token-123',
      'userId': 'user-1',
      'userEmail': 'user@test.local',
      'name': 'Demo',
      'isAdmin': false,
      'isOnboarded': true,
      'shouldChangePassword': false,
      'profileImagePath': '',
    };

Map<String, Object?> _userJson() => {
      'id': 'user-1',
      'email': 'user@test.local',
      'name': 'Demo',
      'avatarColor': 'primary',
      'profileImagePath': '',
      'profileChangedAt': '2026-01-01T00:00:00.000Z',
    };

Map<String, Object?> _versionJson({int major = 3}) => {
      'major': major,
      'minor': 4,
      'patch': 2,
      'prerelease': null,
      'featureLevel': 2,
    };

Map<String, Object?> _featuresJson() => {
      'smartSearch': true,
      'facialRecognition': true,
      'map': true,
      'trash': true,
      'oauth': false,
      'passwordLogin': true,
      'email': true,
      'search': true,
      'sidecar': true,
      'ocr': true,
      'duplicateDetection': true,
      'reverseGeocoding': true,
      'backups': false,
      'configFile': false,
      'importFaces': false,
      'oauthAutoLaunch': false,
      'realtimeTranscoding': false,
    };

/// Mock HTTP client routing by path.
MockClient mockClient({int versionMajor = 3, bool tokenValid = true}) {
  return MockClient((http.Request request) async {
    final path = request.url.path;
    if (path.endsWith('/server/ping')) {
      return http.Response('{"res":"pong"}', 200);
    }
    if (path.endsWith('/server/version')) {
      return http.Response(jsonEncode(_versionJson(major: versionMajor)), 200);
    }
    if (path.endsWith('/server/features')) {
      return http.Response(jsonEncode(_featuresJson()), 200);
    }
    if (path.endsWith('/auth/login')) {
      final body = jsonDecode(request.body) as Map<String, Object?>;
      if (body['email'] == 'user@test.local' &&
          body['password'] == 'correct-password') {
        return http.Response(
          jsonEncode(_loginJson()),
          201,
          headers: {
            'set-cookie':
                'immich_access_token=jwt-token-123; Path=/; HttpOnly',
          },
        );
      }
      return http.Response('{"message":"Incorrect email or password"}', 401);
    }
    if (path.endsWith('/auth/validateToken')) {
      if (!tokenValid) {
        return http.Response('{"message":"Unauthorized"}', 401);
      }
      return http.Response('{"authStatus":true}', 200);
    }
    if (path.endsWith('/users/me')) {
      return http.Response(jsonEncode(_userJson()), 200);
    }
    if (path.endsWith('/auth/logout')) {
      return http.Response('{}', 200);
    }
    return http.Response('{"message":"not found"}', 404);
  });
}

AuthService makeService(MockClient client, {TokenStore? store}) {
  return AuthService(
    tokenStore: store ?? InMemoryTokenStore(),
    clientFactory: (url) => ImmichApiClient(serverUrl: url, httpClient: client),
  );
}

void main() {
  group('AuthService.probeServer', () {
    test('ping + version succeed for a supported server', () async {
      final service = makeService(mockClient());
      final probe = await service.probeServer(_serverUrl);
      expect(probe.serverUrl, _serverUrl);
      expect(probe.version.major, 3);
      expect(probe.isTooOld, isFalse);
      expect(probe.isNewerMajor, isFalse);
    });

    test('v2 server is flagged too old (not an exception)', () async {
      final service = makeService(mockClient(versionMajor: 2));
      final probe = await service.probeServer(_serverUrl);
      expect(probe.isTooOld, isTrue);
    });

    test('unreachable server throws ImmichUnreachableException', () async {
      final failing = MockClient(
        (_) async => throw http.ClientException('Connection refused'),
      );
      final service = makeService(failing);
      expect(
        () => service.probeServer(_serverUrl),
        throwsA(isA<ImmichUnreachableException>()),
      );
    });

    test('normalises a bare host to https and strips /api', () async {
      final service = makeService(mockClient());
      final probe = await service.probeServer('demo.test/api/');
      expect(probe.serverUrl, 'https://demo.test');
    });
  });

  group('AuthService.login', () {
    test('stores token + user and returns a session', () async {
      final store = InMemoryTokenStore();
      final service = makeService(mockClient(), store: store);
      await service.probeServer(_serverUrl);
      final session = await service.login(
        email: 'user@test.local',
        password: 'correct-password',
      );
      expect(session.user.email, 'user@test.local');
      expect(session.version.major, 3);
      expect(session.features.smartSearch, isTrue);
      expect(service.isSignedIn, isTrue);
      expect(await store.read(TokenStoreKeys.accessToken), 'jwt-token-123');
      expect(
        await store.read(TokenStoreKeys.accessTokenCookie),
        'jwt-token-123',
      );
      expect(await store.read(TokenStoreKeys.userEmail), 'user@test.local');
    });

    test('wrong password throws ImmichUnauthorizedException', () async {
      final service = makeService(mockClient());
      await service.probeServer(_serverUrl);
      expect(
        () => service.login(email: 'user@test.local', password: 'wrong'),
        throwsA(isA<ImmichUnauthorizedException>()),
      );
      expect(service.isSignedIn, isFalse);
    });
  });

  group('AuthService.restoreSession', () {
    test('restores a valid stored session', () async {
      final store = InMemoryTokenStore();
      await store.write(TokenStoreKeys.serverUrl, _serverUrl);
      await store.write(TokenStoreKeys.accessToken, 'jwt-token-123');
      final service = makeService(mockClient(), store: store);
      final session = await service.restoreSession();
      expect(session, isNotNull);
      expect(session!.user.email, 'user@test.local');
    });

    test('dead token clears the store and returns null', () async {
      final store = InMemoryTokenStore();
      await store.write(TokenStoreKeys.serverUrl, _serverUrl);
      await store.write(TokenStoreKeys.accessToken, 'stale-token');
      final service =
          makeService(mockClient(tokenValid: false), store: store);
      final session = await service.restoreSession();
      expect(session, isNull);
      expect(await store.read(TokenStoreKeys.accessToken), isNull);
    });

    test('no stored session returns null', () async {
      final service = makeService(mockClient());
      expect(await service.restoreSession(), isNull);
    });
  });

  group('AuthService.logout', () {
    test('wipes the stored session', () async {
      final store = InMemoryTokenStore();
      final service = makeService(mockClient(), store: store);
      await service.probeServer(_serverUrl);
      await service.login(email: 'user@test.local', password: 'correct-password');
      await service.logout();
      expect(service.isSignedIn, isFalse);
      expect(await store.read(TokenStoreKeys.accessToken), isNull);
      expect(await store.read(TokenStoreKeys.userEmail), isNull);
    });
  });
}
