/// User + auth models — `LoginResponseDto`, `UserResponseDto`,
/// `ValidateAccessTokenResponseDto`. Hand-written from spec v3.4.2.
library;

import 'parsing.dart';

/// Response of `POST /auth/login`.
class LoginResponse {
  const LoginResponse({
    required this.accessToken,
    required this.userId,
    required this.userEmail,
    required this.name,
    required this.isAdmin,
    required this.isOnboarded,
    required this.shouldChangePassword,
    this.profileImagePath = '',
  });

  factory LoginResponse.fromJson(Map<String, Object?> json) {
    return LoginResponse(
      accessToken: parseString(json['accessToken']) ?? '',
      userId: parseString(json['userId']) ?? '',
      userEmail: parseString(json['userEmail']) ?? '',
      name: parseString(json['name']) ?? '',
      isAdmin: parseBool(json['isAdmin']) ?? false,
      isOnboarded: parseBool(json['isOnboarded']) ?? false,
      shouldChangePassword: parseBool(json['shouldChangePassword']) ?? false,
      profileImagePath: parseString(json['profileImagePath']) ?? '',
    );
  }

  /// Session JWT. Stored only in secure storage, never in logs.
  final String accessToken;
  final String userId;
  final String userEmail;
  final String name;
  final bool isAdmin;
  final bool isOnboarded;
  final bool shouldChangePassword;
  final String profileImagePath;

  Map<String, Object?> toJson() => {
        'accessToken': accessToken,
        'userId': userId,
        'userEmail': userEmail,
        'name': name,
        'isAdmin': isAdmin,
        'isOnboarded': isOnboarded,
        'shouldChangePassword': shouldChangePassword,
        'profileImagePath': profileImagePath,
      };
}

/// `UserResponseDto` — the public shape of a user (also embedded in assets
/// as `owner` and in album user lists).
class NovaUser {
  const NovaUser({
    required this.id,
    required this.email,
    required this.name,
    this.avatarColor,
    this.profileImagePath = '',
    this.profileChangedAt,
  });

  factory NovaUser.fromJson(Map<String, Object?> json) {
    return NovaUser(
      id: parseString(json['id']) ?? '',
      email: parseString(json['email']) ?? '',
      name: parseString(json['name']) ?? '',
      avatarColor: parseString(json['avatarColor']),
      profileImagePath: parseString(json['profileImagePath']) ?? '',
      profileChangedAt: parseDateTime(json['profileChangedAt']),
    );
  }

  final String id;
  final String email;
  final String name;
  final String? avatarColor;
  final String profileImagePath;
  final DateTime? profileChangedAt;

  Map<String, Object?> toJson() => {
        'id': id,
        'email': email,
        'name': name,
        if (avatarColor != null) 'avatarColor': avatarColor,
        'profileImagePath': profileImagePath,
        if (profileChangedAt != null)
          'profileChangedAt': profileChangedAt!.toIso8601String(),
      };
}

/// Response of `POST /auth/validateToken`.
class ValidateTokenResponse {
  const ValidateTokenResponse({required this.authStatus});

  factory ValidateTokenResponse.fromJson(Map<String, Object?> json) {
    return ValidateTokenResponse(
      authStatus: parseBool(json['authStatus']) ?? false,
    );
  }

  final bool authStatus;

  Map<String, Object?> toJson() => {'authStatus': authStatus};
}
