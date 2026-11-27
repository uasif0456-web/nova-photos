/// Album models — `AlbumResponseDto`, `AlbumUserResponseDto`.
/// Hand-written from spec v3.4.2.
///
/// v3 facts: `GET /albums/{id}` does **not** embed assets (only
/// `assetCount`); album contents come from `POST /search/metadata`
/// with `albumIds`. Ownership lives in `albumUsers[]` — the first entry
/// is always the owner.
library;

import 'parsing.dart';
import 'user.dart';

/// One entry of `AlbumResponseDto.albumUsers`.
class AlbumUser {
  const AlbumUser({required this.user, required this.role});

  factory AlbumUser.fromJson(Map<String, Object?> json) {
    return AlbumUser(
      user: json['user'] is Map<String, Object?>
          ? NovaUser.fromJson(json['user'] as Map<String, Object?>)
          : NovaUser(
              id: parseString(json['userId']) ?? '',
              email: '',
              name: '',
            ),
      role: parseString(json['role']) ?? 'viewer',
    );
  }

  final NovaUser user;

  /// `owner` | `editor` | `viewer`.
  final String role;

  bool get isOwner => role == 'owner';

  Map<String, Object?> toJson() => {'user': user.toJson(), 'role': role};
}

/// `AlbumResponseDto`.
class Album {
  const Album({
    required this.id,
    required this.albumName,
    required this.description,
    required this.albumUsers,
    required this.assetCount,
    required this.shared,
    required this.hasSharedLink,
    required this.isActivityEnabled,
    required this.createdAt,
    required this.updatedAt,
    this.albumThumbnailAssetId,
    this.startDate,
    this.endDate,
    this.lastModifiedAssetTimestamp,
  });

  factory Album.fromJson(Map<String, Object?> json) {
    return Album(
      id: parseString(json['id']) ?? '',
      albumName: parseString(json['albumName']) ?? '',
      description: parseString(json['description']) ?? '',
      albumUsers:
          parseMapList(json['albumUsers']).map(AlbumUser.fromJson).toList(),
      assetCount: parseInt(json['assetCount']) ?? 0,
      shared: parseBool(json['shared']) ?? false,
      hasSharedLink: parseBool(json['hasSharedLink']) ?? false,
      isActivityEnabled: parseBool(json['isActivityEnabled']) ?? false,
      createdAt:
          parseDateTime(json['createdAt']) ?? DateTime.fromMillisecondsSinceEpoch(0),
      updatedAt:
          parseDateTime(json['updatedAt']) ?? DateTime.fromMillisecondsSinceEpoch(0),
      albumThumbnailAssetId: parseString(json['albumThumbnailAssetId']),
      startDate: parseDateTime(json['startDate']),
      endDate: parseDateTime(json['endDate']),
      lastModifiedAssetTimestamp:
          parseDateTime(json['lastModifiedAssetTimestamp']),
    );
  }

  final String id;
  final String albumName;
  final String description;
  final List<AlbumUser> albumUsers;
  final int assetCount;
  final bool shared;
  final bool hasSharedLink;
  final bool isActivityEnabled;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? albumThumbnailAssetId;
  final DateTime? startDate;
  final DateTime? endDate;
  final DateTime? lastModifiedAssetTimestamp;

  /// First album user is always the owner (spec behaviour).
  NovaUser? get owner => albumUsers.isEmpty ? null : albumUsers.first.user;

  Map<String, Object?> toJson() => {
        'id': id,
        'albumName': albumName,
        'description': description,
        'albumUsers': albumUsers.map((u) => u.toJson()).toList(),
        'assetCount': assetCount,
        'shared': shared,
        'hasSharedLink': hasSharedLink,
        'isActivityEnabled': isActivityEnabled,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        if (albumThumbnailAssetId != null)
          'albumThumbnailAssetId': albumThumbnailAssetId,
        if (startDate != null) 'startDate': startDate!.toIso8601String(),
        if (endDate != null) 'endDate': endDate!.toIso8601String(),
        if (lastModifiedAssetTimestamp != null)
          'lastModifiedAssetTimestamp':
              lastModifiedAssetTimestamp!.toIso8601String(),
      };
}

/// `GET /albums/statistics` response.
class AlbumStatistics {
  const AlbumStatistics({required this.owned, required this.shared});

  factory AlbumStatistics.fromJson(Map<String, Object?> json) {
    return AlbumStatistics(
      owned: parseInt(json['owned']) ?? 0,
      shared: parseInt(json['shared']) ?? 0,
    );
  }

  final int owned;
  final int shared;

  Map<String, Object?> toJson() => {'owned': owned, 'shared': shared};
}
