/// Person model — `PersonResponseDto`. Hand-written from spec v3.4.2.
library;

import 'parsing.dart';

/// `PersonResponseDto`.
class Person {
  const Person({
    required this.id,
    required this.name,
    required this.isHidden,
    required this.thumbnailPath,
    this.birthDate,
    this.color,
    this.isFavorite = false,
  });

  factory Person.fromJson(Map<String, Object?> json) {
    return Person(
      id: parseString(json['id']) ?? '',
      name: parseString(json['name']) ?? '',
      isHidden: parseBool(json['isHidden']) ?? false,
      thumbnailPath: parseString(json['thumbnailPath']) ?? '',
      birthDate: parseString(json['birthDate']),
      color: parseString(json['color']),
      isFavorite: parseBool(json['isFavorite']) ?? false,
    );
  }

  final String id;
  final String name;
  final bool isHidden;
  final String thumbnailPath;
  final String? birthDate;
  final String? color;
  final bool isFavorite;

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'isHidden': isHidden,
        'thumbnailPath': thumbnailPath,
        if (birthDate != null) 'birthDate': birthDate,
        if (color != null) 'color': color,
        'isFavorite': isFavorite,
      };
}
