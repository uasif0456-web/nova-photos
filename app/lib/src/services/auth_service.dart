/// Auth service — login, logout, session restore, version gating.
///
/// Flow:
/// 1. `probeServer(url)` — normalise the URL, `GET /server/ping`,
///    then `GET /server/version`; blocks on major < 3, warns on major > 3.
/// 2. `login(email, password)` — `POST /auth/login`, stores the JWT +
///    cookie + user in secure storage, fetches `/server/features` for
///    feature gating.
/// 3. `restoreSession()` — on launch: read the stored URL + token,
///    re-validate with `POST /auth/validateToken`, fetch `/users/me`.
///    Returns false when there is nothing to restore or the token died.
/// 4. `logout()` — server logout (best-effort) + local wipe.
///
/// There is no refresh-token endpoint in the Immich API: a 401 means
/// the user must log in again. The service never stores the password.
library;

import 'dart:convert';

import '../api/api_client.dart';
import '../api/auth_api.dart';
import '../api/server_api.dart';
import '../models/server.dart';
import '../models/user.dart';
import 'token_store.dart';

/// Result of a server probe (before any login).
class ServerProbe {
  const ServerProbe({
    required this.serverUrl,
    required this.version,
    this.features,
  });

  final String serverUrl;
  final ServerVersion version;
  final ServerFeatures? features;

  /// Blocking: the server is too old for NOVA (major < 3).
  bool get isTooOld => version.isTooOld;

  /// Non-blocking: a future major — keep working, show a banner.
  bool get isNewerMajor => version.isNewerMajor;
}

/// The signed-in session as the app sees it.
class NovaSession {
  const NovaSession({
    required this.serverUrl,
    required this.user,
    required this.version,
    required this.features,
  });

  final String serverUrl;
  final NovaUser user;
  final ServerVersion version;
  final ServerFeatures features;

  Map<String, Object?> toJson() => {
        'serverUrl': serverUrl,
        'user': user.toJson(),
        'version': version.toJson(),
        'features': features.toJson(),
      };
}

class AuthService {
  AuthService({
    required this._tokenStore,
    ImmichApiClient Function(String serverUrl)? clientFactory,
  })  : _clientFactory =
            clientFactory ?? ((url) => ImmichApiClient(serverUrl: url));

  final TokenStore _tokenStore;
  final ImmichApiClient Function(String serverUrl) _clientFactory;

  ImmichApiClient? _client;
  NovaSession? _session;

  /// The live API client for the current server (null until a server
  /// URL is known). Created lazily by [probeServer]/[restoreSession].
  ImmichApiClient? get client => _client;

  NovaSession? get session => _session;

  bool get isSignedIn => _session != null;

  /// Probe a server URL without logging in: ping + version. Throws
  /// [ImmichUnreachableException] when nothing answers, and returns a
  /// probe with `isTooOld == true` for a v2 (or older) server.
  Future<ServerProbe> probeServer(String rawUrl) async {
    final url = normalizeServerUrl(rawUrl);
    final client = _clientFactory(url);
    final server = ServerApi(client);
    await server.ping();
    final version = await server.getVersion();
    _client = client;
    await _tokenStore.write(TokenStoreKeys.serverUrl, url);
    return ServerProbe(serverUrl: url, version: version);
  }

  /// Log in with email + password. Requires [probeServer] (or a
  /// restored server URL) first so the client knows where to call.
  /// On success the session is persisted and [session] is set.
  Future<NovaSession> login({
    required String email,
    required String password,
  }) async {
    final client = _client ??
        await _clientForStoredUrl() ??
        (throw StateError(
          'No server URL configured — call probeServer first.',
        ));
    final auth = AuthApi(client);
    final login = await auth.login(email: email, password: password);
    await _tokenStore.write(TokenStoreKeys.accessToken, login.accessToken);
    await _tokenStore.write(TokenStoreKeys.userId, login.userId);
    await _tokenStore.write(TokenStoreKeys.userEmail, login.userEmail);
    await _tokenStore.write(TokenStoreKeys.userName, login.name);
    final cookie = client.cookie;
    if (cookie != null && cookie.isNotEmpty) {
      await _tokenStore.write(TokenStoreKeys.accessTokenCookie, cookie);
    }
    final user = await auth.getCurrentUser();
    await _tokenStore.write(
      TokenStoreKeys.userJson,
      jsonEncode(user.toJson()),
    );
    final server = ServerApi(client);
    final version = await server.getVersion();
    final features = await server.getFeatures();
    _session = NovaSession(
      serverUrl: client.serverUrl,
      user: user,
      version: version,
      features: features,
    );
    _client = client;
    return _session!;
  }

  /// Restore a previous session on launch. Returns the session, or
  /// null when there is no stored session or the token is dead.
  Future<NovaSession?> restoreSession() async {
    final url = await _tokenStore.read(TokenStoreKeys.serverUrl);
    final token = await _tokenStore.read(TokenStoreKeys.accessToken);
    if (url == null || url.isEmpty || token == null || token.isEmpty) {
      return null;
    }
    final client = _clientFactory(url);
    client.setAccessToken(token);
    final cookie = await _tokenStore.read(TokenStoreKeys.accessTokenCookie);
    if (cookie != null && cookie.isNotEmpty) {
      client.setCookie(cookie);
    }
    final auth = AuthApi(client);
    final valid = await auth.validateToken();
    if (!valid) {
      await _clearStoredSession();
      return null;
    }
    final user = await auth.getCurrentUser();
    final server = ServerApi(client);
    final version = await server.getVersion();
    final features = await server.getFeatures();
    _client = client;
    _session = NovaSession(
      serverUrl: client.serverUrl,
      user: user,
      version: version,
      features: features,
    );
    return _session;
  }

  /// Log out: server logout (best-effort) + wipe the stored session.
  Future<void> logout() async {
    final client = _client;
    if (client != null) {
      try {
        await AuthApi(client).logout();
      } catch (_) {
        // Best-effort; local wipe happens regardless.
      }
    }
    await _clearStoredSession();
    _client = null;
    _session = null;
  }

  Future<ImmichApiClient?> _clientForStoredUrl() async {
    final url = await _tokenStore.read(TokenStoreKeys.serverUrl);
    if (url == null || url.isEmpty) return null;
    final client = _clientFactory(url);
    _client = client;
    return client;
  }

  Future<void> _clearStoredSession() async {
    await _tokenStore.delete(TokenStoreKeys.accessToken);
    await _tokenStore.delete(TokenStoreKeys.accessTokenCookie);
    await _tokenStore.delete(TokenStoreKeys.userId);
    await _tokenStore.delete(TokenStoreKeys.userEmail);
    await _tokenStore.delete(TokenStoreKeys.userName);
    await _tokenStore.delete(TokenStoreKeys.userJson);
  }
}
