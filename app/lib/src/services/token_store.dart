/// Secure token storage abstraction.
///
/// The production implementation uses `flutter_secure_storage`
/// (Android Keystore). Tests use [InMemoryTokenStore]. The app never
/// stores tokens in plain files, logs, or SharedPreferences.
library;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Keys used in secure storage. Server URL is not a secret, but it is
/// kept here alongside the session so there is exactly one store to
/// reason about (and so a logout wipes everything in one place).
abstract class TokenStoreKeys {
  static const String serverUrl = 'nova.server_url';
  static const String accessToken = 'nova.access_token';
  static const String accessTokenCookie = 'nova.access_token_cookie';
  static const String userId = 'nova.user_id';
  static const String userEmail = 'nova.user_email';
  static const String userName = 'nova.user_name';
  static const String userJson = 'nova.user_json';
}

abstract class TokenStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
  Future<void> deleteAll();
}

/// Production store backed by the platform keystore.
class SecureTokenStore implements TokenStore {
  SecureTokenStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage(
              // Default AndroidOptions already use AES-GCM with an
              // RSA-wrapped Keystore key (API 23+); no extra flag needed.
              aOptions: AndroidOptions(),
            );

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);

  @override
  Future<void> deleteAll() => _storage.deleteAll();
}

/// In-memory store for unit tests (and for the live smoke test's
/// throwaway session, where nothing must persist).
class InMemoryTokenStore implements TokenStore {
  final _map = <String, String>{};

  @override
  Future<String?> read(String key) async => _map[key];

  @override
  Future<void> write(String key, String value) async {
    _map[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    _map.remove(key);
  }

  @override
  Future<void> deleteAll() async => _map.clear();

  Map<String, String> get snapshot => Map.unmodifiable(_map);
}
