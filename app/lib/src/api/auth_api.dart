/// Auth API — `POST /auth/login`, `/auth/logout`,
/// `/auth/validateToken`, `/auth/status`, `/auth/change-password`.
/// Hand-written from spec v3.4.2.
///
/// Login returns a session JWT (`accessToken`); there is **no refresh
/// token** in the spec. A stored token is re-validated with
/// `validateToken` on launch; on 401 the user must log in again.
/// The server may also set an `immich_access_token` cookie on login —
/// it is captured and sent back alongside the Bearer token.
library;

import '../models/user.dart';
import 'api_client.dart';
import 'exceptions.dart';

class AuthApi {
  const AuthApi(this.client);

  final ImmichApiClient client;

  /// `POST /auth/login`. Returns the login payload; also installs the
  /// token (and any cookie the server set) on the client so subsequent
  /// calls are authenticated. Throws typed errors on 400/401.
  Future<LoginResponse> login({
    required String email,
    required String password,
  }) async {
    final response = await client.post(
      '/auth/login',
      authenticated: false,
      body: {'email': email, 'password': password},
    );
    final login = LoginResponse.fromJson(client.decodeJson(response));
    client.setAccessToken(login.accessToken);
    final cookie = ImmichApiClient.extractAccessTokenCookie(response);
    if (cookie != null) client.setCookie(cookie);
    return login;
  }

  /// `POST /auth/logout`. Server failures are swallowed — logout is
  /// local-first: the client clears its token regardless.
  Future<void> logout() async {
    try {
      await client.post('/auth/logout');
    } on ImmichApiException {
      // Logout is best-effort; the local session is cleared anyway.
    }
    client.clearAuth();
  }

  /// `POST /auth/validateToken` — is the stored token still valid?
  Future<bool> validateToken() async {
    try {
      final response = await client.post('/auth/validateToken');
      return ValidateTokenResponse.fromJson(client.decodeJson(response))
          .authStatus;
    } on ImmichUnauthorizedException {
      return false;
    }
  }

  /// `GET /auth/status` — session info (has password, can access
  /// locked assets).
  Future<Map<String, Object?>> getStatus() async {
    final response = await client.get('/auth/status');
    return client.decodeJson(response);
  }

  /// `POST /auth/change-password`.
  Future<void> changePassword({
    required String password,
    required String newPassword,
  }) async {
    final response = await client.post(
      '/auth/change-password',
      body: {'password': password, 'newPassword': newPassword},
    );
    client.decodeJson(response);
  }

  /// `GET /users/me` — the first call after login; the profile of the
  /// signed-in user.
  Future<NovaUser> getCurrentUser() async {
    final response = await client.get('/users/me');
    return NovaUser.fromJson(client.decodeJson(response));
  }
}
