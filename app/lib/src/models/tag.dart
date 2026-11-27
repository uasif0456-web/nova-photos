/// Tag model — `TagResponseDto`. Hand-written from spec v3.4.2.
library;

import 'parsing.dart';

/// `TagResponseDto`. Tags are hierarchical: `value` is the full
/// `Parent/Child` path, `name` the leaf name.
class Tag {
  const Tag({
    required this.id,
    required this.value,
    required this.name,
    this.color,
    this.parentId,
    this.createdAt,
    this.updatedAt,
  });

  factory Tag.fromJson(Map<String, Object?> json) {
    return Tag(
      id: parseString(json['id']) ?? '',
      value: parseString(json['value']) ?? '',
      name: parseString(json['name']) ?? '',
      color: parseString(json['color']),
      parentId: parseString(json['parentId']),
      createdAt: parseDateTime(json['createdAt']),
      updatedAt: parseDateTime(json['updatedAt']),
    );
  }

  final String id;
  final String value;
  final String name;
  final String? color;
  final String? parentId;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  Map<String, Object?> toJson() => {
        'id': id,
        'value': value,
        'name': name,
        if (color != null) 'color': color,
        if (parentId != null) 'parentId': parentId,
        if (createdAt != null) 'createdAt': createdAt!.toIso8601String(),
        if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
      };
}
