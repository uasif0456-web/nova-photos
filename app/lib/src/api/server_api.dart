/// Server info API — `GET /server/ping`, `/server/version`,
/// `/server/features`, `/server/about`, `/server/statistics`,
/// `/server/media-types`. Hand-written from spec v3.4.2.
///
/// `ping` is the only operation in the whole spec that needs no auth;
/// `version` is also reachable without auth on the servers NOVA targets
/// (the demo server answers it unauthenticated), so both are probed
/// before login. `features` and `about` require a session.
library;

import '../models/server.dart';
import 'api_client.dart';
import 'exceptions.dart';

class ServerApi {
  const ServerApi(this.client);

  final ImmichApiClient client;

  /// `GET /server/ping` → `{"res":"pong"}`. The connectivity check.
  /// Throws [ImmichUnreachableException] when the server cannot be
  /// reached at all (wrong URL, server down, TLS failure).
  Future<void> ping() async {
    try {
      final response =
          await client.get('/server/ping', authenticated: false);
      final json = client.decodeJson(response);
      if (json['res'] != 'pong') {
        throw const ImmichApiException(
          'The server did not answer the ping as expected.',
        );
      }
    } on ImmichNetworkException {
      throw ImmichUnreachableException(
        'Could not reach a server at ${client.serverUrl}. '
        'Check the URL and that the server is running.',
      );
    }
  }

  /// `GET /server/version`. Tried without auth first (most servers
  /// answer it publicly); retried with the session token on 401.
  Future<ServerVersion> getVersion() async {
    try {
      final response =
          await client.get('/server/version', authenticated: false);
      return ServerVersion.fromJson(client.decodeJson(response));
    } on ImmichUnauthorizedException {
      if (!client.isAuthenticated) rethrow;
      final response = await client.get('/server/version');
      return ServerVersion.fromJson(client.decodeJson(response));
    }
  }

  /// `GET /server/features` — the feature flags the client gates on.
  Future<ServerFeatures> getFeatures() async {
    final response = await client.get('/server/features');
    return ServerFeatures.fromJson(client.decodeJson(response));
  }

  /// `GET /server/about` — build info.
  Future<ServerAbout> getAbout() async {
    final response = await client.get('/server/about');
    return ServerAbout.fromJson(client.decodeJson(response));
  }

  /// `GET /server/statistics` (admin-only on most servers).
  Future<Map<String, Object?>> getStatistics() async {
    final response = await client.get('/server/statistics');
    return client.decodeJson(response);
  }

  /// `GET /server/media-types` — supported media types.
  Future<Map<String, Object?>> getMediaTypes() async {
    final response = await client.get('/server/media-types');
    return client.decodeJson(response);
  }
}
