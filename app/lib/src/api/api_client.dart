/// Core HTTP transport for the NOVA PHOTOS Immich client.
///
/// Hand-written from the Immich OpenAPI spec v3.4.2 — this is NOT the
/// generated Immich Dart SDK and contains no Immich code. It speaks the
/// public REST API over plain HTTP with `package:http`.
///
/// Auth: session JWT sent as `Authorization: Bearer <token>` on every
/// authenticated call. The server also sets an `immich_access_token`
/// cookie on login; when present it is stored and sent back as a
/// `Cookie` header (the web UI's scheme — accepted on every endpoint).
/// TLS verification is never disabled.
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'exceptions.dart';

/// Normalises a user-typed server URL:
/// - trims whitespace, adds `https://` when no scheme is present,
/// - strips a trailing slash and any trailing `/api` segment
///   (the client appends `/api` itself).
String normalizeServerUrl(String raw) {
  var url = raw.trim();
  if (url.isEmpty) return url;
  if (!url.contains('://')) url = 'https://$url';
  while (url.endsWith('/')) {
    url = url.substring(0, url.length - 1);
  }
  if (url.toLowerCase().endsWith('/api')) {
    url = url.substring(0, url.length - 4);
  }
  return url;
}

/// Low-level client: one per server URL. Domain APIs (assets, albums,
/// …) are thin wrappers over this class — see the sibling files.
class ImmichApiClient {
  ImmichApiClient({
    required String serverUrl,
    http.Client? httpClient,
    this._timeout = const Duration(seconds: 30),
  })  : _httpClient = httpClient ?? http.Client(),
        _serverUrl = normalizeServerUrl(serverUrl);

  final http.Client _httpClient;
  final Duration _timeout;
  String _serverUrl;

  String? _accessToken;
  String? _cookie;

  /// The normalised server URL (no trailing slash, no `/api` suffix).
  String get serverUrl => _serverUrl;

  /// The API base, e.g. `https://demo.immich.app/api`.
  String get apiBase => '$_serverUrl/api';

  bool get isAuthenticated => _accessToken != null && _accessToken!.isNotEmpty;

  /// The stored `immich_access_token` cookie value, if any.
  String? get cookie => _cookie;

  void setServerUrl(String serverUrl) {
    _serverUrl = normalizeServerUrl(serverUrl);
  }

  void setAccessToken(String? token) {
    _accessToken = token;
  }

  /// The `immich_access_token` cookie value captured from login.
  void setCookie(String? cookie) {
    _cookie = cookie;
  }

  void clearAuth() {
    _accessToken = null;
    _cookie = null;
  }

  /// Headers for an authenticated request. The token is never logged.
  Map<String, String> get authHeaders {
    final headers = <String, String>{
      'Accept': 'application/json',
    };
    if (_accessToken != null && _accessToken!.isNotEmpty) {
      headers['Authorization'] = 'Bearer $_accessToken';
    }
    if (_cookie != null && _cookie!.isNotEmpty) {
      headers['Cookie'] = 'immich_access_token=$_cookie';
    }
    return headers;
  }

  /// Headers for an unauthenticated request.
  Map<String, String> get publicHeaders => const {
        'Accept': 'application/json',
      };

  Uri _uri(String path, [Map<String, Object?>? query]) {
    final uri = Uri.parse('$apiBase$path');
    if (query == null || query.isEmpty) return uri;
    final params = <String, String>{};
    query.forEach((key, value) {
      if (value == null) return;
      params[key] = value.toString();
    });
    return uri.replace(queryParameters: params);
  }

  /// Exposed for URL builders (thumbnails, downloads) that need the
  /// full URI plus auth headers supplied by the caller.
  Uri uriFor(String path, [Map<String, Object?>? query]) => _uri(path, query);

  Future<http.Response> get(
    String path, {
    Map<String, Object?>? query,
    bool authenticated = true,
  }) =>
      _send(() => _httpClient.get(
            _uri(path, query),
            headers: authenticated ? authHeaders : publicHeaders,
          ));

  Future<http.Response> post(
    String path, {
    Object? body,
    Map<String, Object?>? query,
    bool authenticated = true,
  }) =>
      _send(() => _httpClient.post(
            _uri(path, query),
            headers: {
              ...(authenticated ? authHeaders : publicHeaders),
              'Content-Type': 'application/json',
            },
            body: body == null ? null : jsonEncode(body),
          ));

  Future<http.Response> put(
    String path, {
    Object? body,
    Map<String, Object?>? query,
    bool authenticated = true,
  }) =>
      _send(() => _httpClient.put(
            _uri(path, query),
            headers: {
              ...(authenticated ? authHeaders : publicHeaders),
              'Content-Type': 'application/json',
            },
            body: body == null ? null : jsonEncode(body),
          ));

  Future<http.Response> patch(
    String path, {
    Object? body,
    Map<String, Object?>? query,
    bool authenticated = true,
  }) =>
      _send(() => _httpClient.patch(
            _uri(path, query),
            headers: {
              ...(authenticated ? authHeaders : publicHeaders),
              'Content-Type': 'application/json',
            },
            body: body == null ? null : jsonEncode(body),
          ));

  Future<http.Response> delete(
    String path, {
    Object? body,
    Map<String, Object?>? query,
    bool authenticated = true,
  }) =>
      _send(() => _httpClient.delete(
            _uri(path, query),
            headers: {
              ...(authenticated ? authHeaders : publicHeaders),
              'Content-Type': 'application/json',
            },
            body: body == null ? null : jsonEncode(body),
          ));

  /// Raw bytes (thumbnails, originals). Callers check the status
  /// themselves via [requireSuccess] or use [getBytesOrThrow].
  Future<http.Response> getBytes(
    String path, {
    Map<String, Object?>? query,
    bool authenticated = true,
  }) =>
      _send(() => _httpClient.get(
            _uri(path, query),
            headers: authenticated ? authHeaders : publicHeaders,
          ));

  /// Multipart upload (assets). `fields` are text parts, `fileField`
  /// the file part name (`assetData`), `fileBytes` the file content.
  /// Optional `checksum` is sent as the `x-immich-checksum` header
  /// (SHA-1, for server-side duplicate detection).
  Future<http.Response> postMultipart(
    String path, {
    required String fileField,
    required List<int> fileBytes,
    required String filename,
    Map<String, String> fields = const {},
    Map<String, String> extraFileParts = const {},
    String? checksum,
    bool authenticated = true,
  }) async {
    final request = http.MultipartRequest('POST', _uri(path));
    request.headers.addAll(authenticated ? authHeaders : publicHeaders);
    if (checksum != null && checksum.isNotEmpty) {
      request.headers['x-immich-checksum'] = checksum;
    }
    request.fields.addAll(fields);
    request.files.add(http.MultipartFile.fromBytes(
      fileField,
      fileBytes,
      filename: filename,
    ));
    for (final entry in extraFileParts.entries) {
      // Reserved for future sidecar parts; currently unused.
      request.files.add(http.MultipartFile.fromBytes(
        entry.key,
        const [],
        filename: entry.value,
      ));
    }
    final streamed = await _sendStreamed(request);
    return http.Response.fromStream(streamed);
  }

  /// Streaming POST (sync stream): yields decoded JSON lines as they
  /// arrive. The caller closes the subscription; the stream ends when
  /// the server sends `SyncCompleteV1` or closes the connection.
  Stream<Map<String, Object?>> postJsonLines(
    String path, {
    required Object body,
    bool authenticated = true,
  }) async* {
    final request = http.Request('POST', _uri(path));
    request.headers.addAll({
      ...(authenticated ? authHeaders : publicHeaders),
      'Content-Type': 'application/json',
    });
    request.body = jsonEncode(body);
    final streamed = await _sendStreamed(request);
    _requireSuccess(streamed.statusCode, streamed.headers, streamed);
    final lines = streamed.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter());
    await for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      final decoded = jsonDecode(trimmed);
      if (decoded is Map<String, Object?>) yield decoded;
    }
  }

  Future<http.StreamedResponse> _sendStreamed(http.BaseRequest request) async {
    try {
      return await _httpClient.send(request).timeout(_timeout);
    } on TimeoutException {
      throw const ImmichNetworkException(
        'The server did not answer in time. Check the connection and try again.',
      );
    } on http.ClientException catch (e) {
      throw ImmichNetworkException(
        'Could not reach the server (${e.message}).',
      );
    }
  }

  Future<http.Response> _send(
    Future<http.Response> Function() call,
  ) async {
    try {
      final response = await call().timeout(_timeout);
      // Every call throws a typed error on a non-2xx status, so
      // callers never have to check `statusCode` themselves. The
      // decode helpers re-check defensively (a no-op on success).
      _requireSuccess(response.statusCode, response.headers, response);
      return response;
    } on TimeoutException {
      throw const ImmichNetworkException(
        'The server did not answer in time. Check the connection and try again.',
      );
    } on http.ClientException catch (e) {
      throw ImmichNetworkException(
        'Could not reach the server (${e.message}).',
      );
    }
  }

  /// Decode a successful JSON response body into a Map, or throw the
  /// typed error for a non-2xx status. Empty 204 bodies yield `{}`.
  Map<String, Object?> decodeJson(http.Response response) {
    _requireSuccess(response.statusCode, response.headers, response);
    if (response.bodyBytes.isEmpty) return const {};
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is Map<String, Object?>) return decoded;
    throw const ImmichApiException('Unexpected response from the server.');
  }

  /// Decode a successful JSON response body into a List, or throw.
  List<Object?> decodeJsonList(http.Response response) {
    _requireSuccess(response.statusCode, response.headers, response);
    if (response.bodyBytes.isEmpty) return const [];
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is List<Object?>) return decoded;
    throw const ImmichApiException('Unexpected response from the server.');
  }

  /// Decode a successful response body into raw bytes, or throw.
  List<int> decodeBytes(http.Response response) {
    _requireSuccess(response.statusCode, response.headers, response);
    return response.bodyBytes;
  }

  void _requireSuccess(
    int statusCode,
    Map<String, String> headers,
    http.BaseResponse response,
  ) {
    if (statusCode >= 200 && statusCode < 300) return;
    String body = '';
    if (response is http.Response) body = response.body;
    throw exceptionFromResponse(
      statusCode,
      body,
      correlationId: headers['x-correlation-id'],
    );
  }

  /// Extract the `immich_access_token` cookie from a login response's
  /// `set-cookie` header, if the server sent one.
  static String? extractAccessTokenCookie(http.Response response) {
    final setCookie = response.headers['set-cookie'];
    if (setCookie == null) return null;
    for (final part in setCookie.split(',')) {
      final trimmed = part.trim();
      if (trimmed.startsWith('immich_access_token=')) {
        final value = trimmed
            .substring('immich_access_token='.length)
            .split(';')
            .first
            .trim();
        if (value.isNotEmpty) return value;
      }
    }
    return null;
  }

  void close() => _httpClient.close();
}

/// URL builders for media endpoints. These return plain URIs — the
/// caller must attach auth headers (see [ImmichApiClient.authHeaders])
/// because `<img>`-style unauthenticated loads cannot set them.
/// Thumbnail sizes: `thumbnail` (~250 px WebP, grid), `preview`
/// (1440 px JPEG, viewer). `size=original` is deprecated in v3 — use
/// [original] instead.
class MediaUrls {
  const MediaUrls(this.client);

  final ImmichApiClient client;

  Uri thumbnail(String assetId, {String size = 'thumbnail'}) =>
      client.uriFor('/assets/$assetId/thumbnail', {'size': size});

  Uri preview(String assetId) => thumbnail(assetId, size: 'preview');

  Uri original(String assetId, {bool edited = false}) =>
      client.uriFor('/assets/$assetId/original', {'edited': edited});

  /// Video playback URL (byte-range stream, `asset.view` permission).
  Uri videoPlayback(String assetId) =>
      client.uriFor('/assets/$assetId/video/playback');

  /// HLS main playlist for transcoded playback.
  Uri hlsPlaylist(String assetId) =>
      client.uriFor('/assets/$assetId/video/stream/main.m3u8');

  Uri personThumbnail(String personId) =>
      client.uriFor('/people/$personId/thumbnail');

  Uri userProfileImage(String userId) =>
      client.uriFor('/users/$userId/profile-image');

  /// Socket.IO endpoint path (the socket connects to the server origin
  /// with path `/api/socket.io`).
  String get socketIoPath => '/api/socket.io';
}
