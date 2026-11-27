/// Asset models — `AssetResponseDto`, `ExifResponseDto`, upload responses.
/// Hand-written from Immich OpenAPI spec v3.4.2.
///
/// Notable v3 facts encoded here:
/// - `duration` is an integer in the v3.4.2 spec (parsed leniently —
///   see `parseDuration` — because the v3 migration notes describe it
///   as a `"HH:MM:SS.mmm"` string; either shape is accepted).
/// - `libraryId` and `resized` are deprecated — parsed but unused.
/// - There is no `GET /assets` list endpoint; listing goes through
///   `POST /search/metadata` (see search.dart) or the timeline buckets.
library;

import 'parsing.dart';
import 'person.dart';
import 'tag.dart';
import 'user.dart';

/// Asset type (`AssetTypeEnum`).
enum AssetType { image, video, audio, other }

AssetType assetTypeFromJson(Object? value) => switch (value) {
      'IMAGE' => AssetType.image,
      'VIDEO' => AssetType.video,
      'AUDIO' => AssetType.audio,
      _ => AssetType.other,
    };

String assetTypeToJson(AssetType type) => switch (type) {
      AssetType.image => 'IMAGE',
      AssetType.video => 'VIDEO',
      AssetType.audio => 'AUDIO',
      AssetType.other => 'OTHER',
    };

/// Asset visibility (`AssetVisibility`): `timeline` (default), `archive`,
/// `hidden`, `locked`. `isArchived` mirrors `visibility == archive`.
enum AssetVisibility { timeline, archive, hidden, locked }

AssetVisibility assetVisibilityFromJson(Object? value) => switch (value) {
      'archive' => AssetVisibility.archive,
      'hidden' => AssetVisibility.hidden,
      'locked' => AssetVisibility.locked,
      _ => AssetVisibility.timeline,
    };

String assetVisibilityToJson(AssetVisibility v) => switch (v) {
      AssetVisibility.timeline => 'timeline',
      AssetVisibility.archive => 'archive',
      AssetVisibility.hidden => 'hidden',
      AssetVisibility.locked => 'locked',
    };

/// `ExifResponseDto` — the EXIF block embedded in an asset (or fetched
/// with `withExif: true` on search). Every field is optional.
class AssetExif {
  const AssetExif({
    this.city,
    this.country,
    this.dateTimeOriginal,
    this.description,
    this.exifImageWidth,
    this.exifImageHeight,
    this.exposureTime,
    this.fNumber,
    this.fileSizeInByte,
    this.focalLength,
    this.iso,
    this.latitude,
    this.longitude,
    this.make,
    this.model,
    this.orientation,
    this.projectionType,
    this.rating,
    this.timeZone,
  });

  factory AssetExif.fromJson(Map<String, Object?> json) {
    return AssetExif(
      city: parseString(json['city']),
      country: parseString(json['country']),
      dateTimeOriginal: parseString(json['dateTimeOriginal']),
      description: parseString(json['description']),
      exifImageWidth: parseInt(json['exifImageWidth']),
      exifImageHeight: parseInt(json['exifImageHeight']),
      exposureTime: parseString(json['exposureTime']),
      fNumber: parseDouble(json['fNumber']),
      fileSizeInByte: parseInt(json['fileSizeInByte']),
      focalLength: parseDouble(json['focalLength']),
      iso: parseInt(json['iso']),
      latitude: parseDouble(json['latitude']),
      longitude: parseDouble(json['longitude']),
      make: parseString(json['make']),
      model: parseString(json['model']),
      orientation: parseString(json['orientation']),
      projectionType: parseString(json['projectionType']),
      rating: parseInt(json['rating']),
      timeZone: parseString(json['timeZone']),
    );
  }

  final String? city;
  final String? country;
  final String? dateTimeOriginal;
  final String? description;
  final int? exifImageWidth;
  final int? exifImageHeight;
  final String? exposureTime;
  final double? fNumber;
  final int? fileSizeInByte;
  final double? focalLength;
  final int? iso;
  final double? latitude;
  final double? longitude;
  final String? make;
  final String? model;
  final String? orientation;
  final String? projectionType;
  final int? rating;
  final String? timeZone;

  bool get hasLocation => latitude != null && longitude != null;

  Map<String, Object?> toJson() => {
        if (city != null) 'city': city,
        if (country != null) 'country': country,
        if (dateTimeOriginal != null) 'dateTimeOriginal': dateTimeOriginal,
        if (description != null) 'description': description,
        if (exifImageWidth != null) 'exifImageWidth': exifImageWidth,
        if (exifImageHeight != null) 'exifImageHeight': exifImageHeight,
        if (exposureTime != null) 'exposureTime': exposureTime,
        if (fNumber != null) 'fNumber': fNumber,
        if (fileSizeInByte != null) 'fileSizeInByte': fileSizeInByte,
        if (focalLength != null) 'focalLength': focalLength,
        if (iso != null) 'iso': iso,
        if (latitude != null) 'latitude': latitude,
        if (longitude != null) 'longitude': longitude,
        if (make != null) 'make': make,
        if (model != null) 'model': model,
        if (orientation != null) 'orientation': orientation,
        if (projectionType != null) 'projectionType': projectionType,
        if (rating != null) 'rating': rating,
        if (timeZone != null) 'timeZone': timeZone,
      };
}

/// `AssetResponseDto` — the asset JSON.
class NovaAsset {
  const NovaAsset({
    required this.id,
    required this.type,
    required this.checksum,
    required this.originalFileName,
    required this.originalPath,
    required this.fileCreatedAt,
    required this.fileModifiedAt,
    required this.localDateTime,
    required this.createdAt,
    required this.updatedAt,
    required this.width,
    required this.height,
    required this.isFavorite,
    required this.isArchived,
    required this.isTrashed,
    required this.isOffline,
    required this.isEdited,
    required this.hasMetadata,
    required this.visibility,
    required this.ownerId,
    required this.thumbhash,
    this.duplicateId,
    this.duration,
    this.exifInfo,
    this.livePhotoVideoId,
    this.originalMimeType,
    this.owner,
    this.people = const [],
    this.tags = const [],
    this.stackId,
  });

  factory NovaAsset.fromJson(Map<String, Object?> json) {
    final stack = json['stack'];
    String? stackId;
    if (stack is Map<String, Object?>) {
      stackId = parseString(stack['id']);
    }
    return NovaAsset(
      id: parseString(json['id']) ?? '',
      type: assetTypeFromJson(json['type']),
      checksum: parseString(json['checksum']) ?? '',
      originalFileName: parseString(json['originalFileName']) ?? '',
      originalPath: parseString(json['originalPath']) ?? '',
      fileCreatedAt:
          parseDateTime(json['fileCreatedAt']) ?? DateTime.fromMillisecondsSinceEpoch(0),
      fileModifiedAt:
          parseDateTime(json['fileModifiedAt']) ?? DateTime.fromMillisecondsSinceEpoch(0),
      localDateTime:
          parseDateTime(json['localDateTime']) ?? DateTime.fromMillisecondsSinceEpoch(0),
      createdAt:
          parseDateTime(json['createdAt']) ?? DateTime.fromMillisecondsSinceEpoch(0),
      updatedAt:
          parseDateTime(json['updatedAt']) ?? DateTime.fromMillisecondsSinceEpoch(0),
      width: parseInt(json['width']) ?? 0,
      height: parseInt(json['height']) ?? 0,
      isFavorite: parseBool(json['isFavorite']) ?? false,
      isArchived: parseBool(json['isArchived']) ?? false,
      isTrashed: parseBool(json['isTrashed']) ?? false,
      isOffline: parseBool(json['isOffline']) ?? false,
      isEdited: parseBool(json['isEdited']) ?? false,
      hasMetadata: parseBool(json['hasMetadata']) ?? false,
      visibility: assetVisibilityFromJson(json['visibility']),
      ownerId: parseString(json['ownerId']) ?? '',
      thumbhash: parseString(json['thumbhash']) ?? '',
      duplicateId: parseString(json['duplicateId']),
      duration: parseDuration(json['duration']),
      exifInfo: json['exifInfo'] is Map<String, Object?>
          ? AssetExif.fromJson(json['exifInfo'] as Map<String, Object?>)
          : null,
      livePhotoVideoId: parseString(json['livePhotoVideoId']),
      originalMimeType: parseString(json['originalMimeType']),
      owner: json['owner'] is Map<String, Object?>
          ? NovaUser.fromJson(json['owner'] as Map<String, Object?>)
          : null,
      people: parseMapList(json['people']).map(Person.fromJson).toList(),
      tags: parseMapList(json['tags']).map(Tag.fromJson).toList(),
      stackId: stackId,
    );
  }

  final String id;
  final AssetType type;
  final String checksum;
  final String originalFileName;
  final String originalPath;
  final DateTime fileCreatedAt;
  final DateTime fileModifiedAt;
  final DateTime localDateTime;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int width;
  final int height;
  final bool isFavorite;
  final bool isArchived;
  final bool isTrashed;
  final bool isOffline;
  final bool isEdited;
  final bool hasMetadata;
  final AssetVisibility visibility;
  final String ownerId;
  final String thumbhash;
  final String? duplicateId;
  final Duration? duration;
  final AssetExif? exifInfo;
  final String? livePhotoVideoId;
  final String? originalMimeType;
  final NovaUser? owner;
  final List<Person> people;
  final List<Tag> tags;
  final String? stackId;

  bool get isVideo => type == AssetType.video;
  bool get isImage => type == AssetType.image;
  bool get isLivePhoto => livePhotoVideoId != null;
  bool get isInStack => stackId != null;

  /// Display aspect ratio for the grid; falls back to square.
  double get aspectRatio =>
      width > 0 && height > 0 ? width / height : 1.0;

  NovaAsset copyWith({
    bool? isFavorite,
    AssetVisibility? visibility,
    bool? isTrashed,
    bool? isArchived,
  }) {
    return NovaAsset(
      id: id,
      type: type,
      checksum: checksum,
      originalFileName: originalFileName,
      originalPath: originalPath,
      fileCreatedAt: fileCreatedAt,
      fileModifiedAt: fileModifiedAt,
      localDateTime: localDateTime,
      createdAt: createdAt,
      updatedAt: updatedAt,
      width: width,
      height: height,
      isFavorite: isFavorite ?? this.isFavorite,
      isArchived: isArchived ?? this.isArchived,
      isTrashed: isTrashed ?? this.isTrashed,
      isOffline: isOffline,
      isEdited: isEdited,
      hasMetadata: hasMetadata,
      visibility: visibility ?? this.visibility,
      ownerId: ownerId,
      thumbhash: thumbhash,
      duplicateId: duplicateId,
      duration: duration,
      exifInfo: exifInfo,
      livePhotoVideoId: livePhotoVideoId,
      originalMimeType: originalMimeType,
      owner: owner,
      people: people,
      tags: tags,
      stackId: stackId,
    );
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'type': assetTypeToJson(type),
        'checksum': checksum,
        'originalFileName': originalFileName,
        'originalPath': originalPath,
        'fileCreatedAt': fileCreatedAt.toIso8601String(),
        'fileModifiedAt': fileModifiedAt.toIso8601String(),
        'localDateTime': localDateTime.toIso8601String(),
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'width': width,
        'height': height,
        'isFavorite': isFavorite,
        'isArchived': isArchived,
        'isTrashed': isTrashed,
        'isOffline': isOffline,
        'isEdited': isEdited,
        'hasMetadata': hasMetadata,
        'visibility': assetVisibilityToJson(visibility),
        'ownerId': ownerId,
        'thumbhash': thumbhash,
        if (duplicateId != null) 'duplicateId': duplicateId,
        if (duration != null) 'duration': duration!.inMilliseconds,
        if (exifInfo != null) 'exifInfo': exifInfo!.toJson(),
        if (livePhotoVideoId != null) 'livePhotoVideoId': livePhotoVideoId,
        if (originalMimeType != null) 'originalMimeType': originalMimeType,
        if (owner != null) 'owner': owner!.toJson(),
        'people': people.map((p) => p.toJson()).toList(),
        'tags': tags.map((t) => t.toJson()).toList(),
        if (stackId != null) 'stack': {'id': stackId},
      };
}

/// `AssetMediaResponseDto` — the result of `POST /assets`.
/// HTTP 201 + `status: created` means a new asset; HTTP 200 +
/// `status: duplicate` means the server already had this checksum —
/// both are successes, never errors.
class AssetUploadResult {
  const AssetUploadResult({required this.id, required this.status});

  factory AssetUploadResult.fromJson(Map<String, Object?> json) {
    return AssetUploadResult(
      id: parseString(json['id']) ?? '',
      status: parseString(json['status']) ?? 'created',
    );
  }

  final String id;
  final String status;

  bool get isDuplicate => status == 'duplicate';
  bool get isCreated => status == 'created';

  Map<String, Object?> toJson() => {'id': id, 'status': status};
}

/// One entry of `POST /assets/bulk-upload-check`.
class BulkUploadCheckResult {
  const BulkUploadCheckResult({
    required this.id,
    required this.checksum,
    required this.action,
  });

  factory BulkUploadCheckResult.fromJson(Map<String, Object?> json) {
    return BulkUploadCheckResult(
      id: parseString(json['id']) ?? '',
      checksum: parseString(json['checksum']) ?? '',
      action: parseString(json['action']) ?? 'accept',
    );
  }

  /// Client-side echo id (e.g. the local filename) from the request.
  final String id;
  final String checksum;

  /// `accept` — the server does not have this file, upload it.
  /// `reject` — the server already has it, skip the upload.
  final String action;

  bool get shouldUpload => action == 'accept';
  bool get alreadyOnServer => action == 'reject';

  Map<String, Object?> toJson() =>
      {'id': id, 'checksum': checksum, 'action': action};
}

/// `GET /assets/statistics` — `{images, videos, total}`.
class AssetStatistics {
  const AssetStatistics({
    required this.images,
    required this.videos,
    required this.total,
  });

  factory AssetStatistics.fromJson(Map<String, Object?> json) {
    return AssetStatistics(
      images: parseInt(json['images']) ?? 0,
      videos: parseInt(json['videos']) ?? 0,
      total: parseInt(json['total']) ?? 0,
    );
  }

  final int images;
  final int videos;
  final int total;

  Map<String, Object?> toJson() =>
      {'images': images, 'videos': videos, 'total': total};
}
