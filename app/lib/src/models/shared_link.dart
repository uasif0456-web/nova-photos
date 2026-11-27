/// Shared-link model — `SharedLinkResponseDto`. Hand-written from spec v3.4.2.
library;

import 'album.dart';
import 'asset.dart';
import 'parsing.dart';

/// Shared link type (`SharedLinkType`).
enum SharedLinkType { album, individual }

SharedLinkType sharedLinkTypeFromJson(Object? value) => switch (value) {
      'album' => SharedLinkType.album,
      _ => SharedLinkType.individual,
    };

/// `SharedLinkResponseDto`.
class SharedLink {
  const SharedLink({
    required this.id,
    required this.userId,
    required this.type,
    required this.key,
    required this.slug,
    required this.allowDownload,
    required this.allowUpload,
    required this.showMetadata,
    this.album,
    this.assets = const [],
    this.description,
    this.password,
    this.expiresAt,
    this.createdAt,
  });

  factory SharedLink.fromJson(Map<String, Object?> json) {
    return SharedLink(
      id: parseString(json['id']) ?? '',
      userId: parseString(json['userId']) ?? '',
      type: sharedLinkTypeFromJson(json['type']),
      key: parseString(json['key']) ?? '',
      slug: parseString(json['slug']) ?? '',
      allowDownload: parseBool(json['allowDownload']) ?? false,
      allowUpload: parseBool(json['allowUpload']) ?? false,
      showMetadata: parseBool(json['showMetadata']) ?? false,
      album: json['album'] is Map<String, Object?>
          ? Album.fromJson(json['album'] as Map<String, Object?>)
          : null,
      assets: parseMapList(json['assets']).map(NovaAsset.fromJson).toList(),
      description: parseString(json['description']),
      password: parseString(json['password']),
      expiresAt: parseDateTime(json['expiresAt']),
      createdAt: parseDateTime(json['createdAt']),
    );
  }

  final String id;
  final String userId;
  final SharedLinkType type;
  final String key;
  final String slug;
  final bool allowDownload;
  final bool allowUpload;
  final bool showMetadata;
  final Album? album;
  final List<NovaAsset> assets;
  final String? description;
  final String? password;
  final DateTime? expiresAt;
  final DateTime? createdAt;

  bool get isExpired =>
      expiresAt != null && expiresAt!.isBefore(DateTime.now());

  Map<String, Object?> toJson() => {
        'id': id,
        'userId': userId,
        'type': type.name,
        'key': key,
        'slug': slug,
        'allowDownload': allowDownload,
        'allowUpload': allowUpload,
        'showMetadata': showMetadata,
        if (album != null) 'album': album!.toJson(),
        'assets': assets.map((a) => a.toJson()).toList(),
        if (description != null) 'description': description,
        if (password != null) 'password': password,
        if (expiresAt != null) 'expiresAt': expiresAt!.toIso8601String(),
        if (createdAt != null) 'createdAt': createdAt!.toIso8601String(),
      };
}
