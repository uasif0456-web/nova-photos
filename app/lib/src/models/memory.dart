/// Memory model — `MemoryResponseDto`. Hand-written from spec v3.4.2.
library;

import 'asset.dart';
import 'parsing.dart';

/// Memory type (`MemoryType`).
enum MemoryType { onThisDay, birthday, unknown }

MemoryType memoryTypeFromJson(Object? value) => switch (value) {
      'on_this_day' => MemoryType.onThisDay,
      'birthday' => MemoryType.birthday,
      _ => MemoryType.unknown,
    };

String memoryTypeToJson(MemoryType type) => switch (type) {
      MemoryType.onThisDay => 'on_this_day',
      MemoryType.birthday => 'birthday',
      MemoryType.unknown => 'unknown',
    };

/// `MemoryResponseDto`. `data` carries the memory payload
/// (`{year}` for on-this-day, `{personId, personName}` for birthdays).
class Memory {
  const Memory({
    required this.id,
    required this.type,
    required this.memoryAt,
    required this.ownerId,
    required this.isSaved,
    required this.createdAt,
    required this.updatedAt,
    required this.assets,
    this.data = const {},
    this.seenAt,
    this.hideAt,
    this.showAt,
    this.deletedAt,
  });

  factory Memory.fromJson(Map<String, Object?> json) {
    return Memory(
      id: parseString(json['id']) ?? '',
      type: memoryTypeFromJson(json['type']),
      memoryAt:
          parseDateTime(json['memoryAt']) ?? DateTime.fromMillisecondsSinceEpoch(0),
      ownerId: parseString(json['ownerId']) ?? '',
      isSaved: parseBool(json['isSaved']) ?? false,
      createdAt:
          parseDateTime(json['createdAt']) ?? DateTime.fromMillisecondsSinceEpoch(0),
      updatedAt:
          parseDateTime(json['updatedAt']) ?? DateTime.fromMillisecondsSinceEpoch(0),
      assets:
          parseMapList(json['assets']).map(NovaAsset.fromJson).toList(),
      data: json['data'] is Map<String, Object?>
          ? json['data'] as Map<String, Object?>
          : const {},
      seenAt: parseDateTime(json['seenAt']),
      hideAt: parseDateTime(json['hideAt']),
      showAt: parseDateTime(json['showAt']),
      deletedAt: parseDateTime(json['deletedAt']),
    );
  }

  final String id;
  final MemoryType type;
  final DateTime memoryAt;
  final String ownerId;
  final bool isSaved;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<NovaAsset> assets;
  final Map<String, Object?> data;
  final DateTime? seenAt;
  final DateTime? hideAt;
  final DateTime? showAt;
  final DateTime? deletedAt;

  /// Years since the remembered moment (on-this-day memories).
  int? get yearsAgo => parseInt(data['year']) == null
      ? null
      : memoryAt.year - (parseInt(data['year']) ?? memoryAt.year);

  Map<String, Object?> toJson() => {
        'id': id,
        'type': memoryTypeToJson(type),
        'memoryAt': memoryAt.toIso8601String(),
        'ownerId': ownerId,
        'isSaved': isSaved,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'assets': assets.map((a) => a.toJson()).toList(),
        'data': data,
        if (seenAt != null) 'seenAt': seenAt!.toIso8601String(),
        if (hideAt != null) 'hideAt': hideAt!.toIso8601String(),
        if (showAt != null) 'showAt': showAt!.toIso8601String(),
        if (deletedAt != null) 'deletedAt': deletedAt!.toIso8601String(),
      };
}
