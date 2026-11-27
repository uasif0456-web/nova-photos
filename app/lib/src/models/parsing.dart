/// Shared parsing helpers for hand-written models.
///
/// Every model parses defensively: unknown JSON keys are ignored, missing
/// optional fields fall back to sane defaults, and a wrong-typed value
/// never crashes the whole response — it yields the default instead.
/// The Immich server adds fields in minors constantly, so leniency is a
/// compatibility requirement, not laziness.
library;

/// Parse an ISO-8601 date-time, or null when absent/unparseable.
DateTime? parseDateTime(Object? value) {
  if (value is String && value.isNotEmpty) {
    return DateTime.tryParse(value);
  }
  return null;
}

/// Parse a duration that may arrive in any of the shapes Immich has used:
/// - integer milliseconds (v3.4.2 spec: `duration` is an integer),
/// - a number of seconds (v2-era),
/// - a `"HH:MM:SS.mmm"` string (documented in the v3 migration notes).
Duration? parseDuration(Object? value) {
  if (value == null) return null;
  if (value is int) return Duration(milliseconds: value);
  if (value is double) return Duration(milliseconds: (value * 1000).round());
  if (value is String) {
    final parts = value.split(':');
    if (parts.length == 3) {
      final hours = int.tryParse(parts[0]) ?? 0;
      final minutes = int.tryParse(parts[1]) ?? 0;
      final seconds = double.tryParse(parts[2]) ?? 0;
      return Duration(
        hours: hours,
        minutes: minutes,
        milliseconds: (seconds * 1000).round(),
      );
    }
    final asDouble = double.tryParse(value);
    if (asDouble != null) {
      return Duration(milliseconds: (asDouble * 1000).round());
    }
  }
  return null;
}

/// Read a string field, coercing numbers to strings; null when absent.
String? parseString(Object? value) => switch (value) {
      null => null,
      String s => s,
      num n => n.toString(),
      _ => null,
    };

/// Read a bool field; null when absent or wrong-typed.
bool? parseBool(Object? value) => value is bool ? value : null;

/// Read an int field, coercing doubles; null when absent.
int? parseInt(Object? value) => switch (value) {
      null => null,
      int i => i,
      double d => d.round(),
      _ => null,
    };

/// Read a double field, coercing ints; null when absent.
double? parseDouble(Object? value) => switch (value) {
      null => null,
      double d => d,
      int i => i.toDouble(),
      _ => null,
    };

/// Read a list of maps, skipping non-map entries.
List<Map<String, Object?>> parseMapList(Object? value) {
  if (value is! List) return const [];
  return value.whereType<Map<String, Object?>>().toList(growable: false);
}

/// Read a list of strings, coercing numbers; skips the rest.
List<String> parseStringList(Object? value) {
  if (value is! List) return const [];
  return value
      .map(parseString)
      .whereType<String>()
      .toList(growable: false);
}
