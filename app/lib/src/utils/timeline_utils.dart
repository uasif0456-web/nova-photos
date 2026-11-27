/// Timeline helpers — pure functions over [NovaAsset] lists.
///
/// No UI, no API, no Riverpod: the Photos timeline, the Memories
/// highlights and the tests all share these. Dates use the asset's
/// `localDateTime` (the date the photo was taken, in local time).
library;

import 'package:intl/intl.dart';

import '../models/asset.dart';
import '../models/search.dart';

/// One day's worth of assets in the timeline, newest day first.
class DaySection {
  const DaySection({required this.day, required this.assets});

  /// Midnight on the day (local time).
  final DateTime day;
  final List<NovaAsset> assets;
}

/// Group [assets] (any order) by calendar day of `localDateTime`,
/// newest day first, assets within a day newest first.
List<DaySection> groupAssetsByDay(List<NovaAsset> assets) {
  final byDay = <DateTime, List<NovaAsset>>{};
  for (final asset in assets) {
    final d = asset.localDateTime;
    final day = DateTime(d.year, d.month, d.day);
    (byDay[day] ??= []).add(asset);
  }
  final days = byDay.keys.toList()..sort((a, b) => b.compareTo(a));
  return [
    for (final day in days)
      DaySection(
        day: day,
        assets: [...byDay[day]!]..sort(
            (a, b) => b.localDateTime.compareTo(a.localDateTime),
          ),
      ),
  ];
}

/// Header label for a day: "Today", "Yesterday", or e.g.
/// "Monday, 3 November 2026".
String dayLabel(DateTime day, {DateTime? now}) {
  final today = now ?? DateTime.now();
  final todayMidnight = DateTime(today.year, today.month, today.day);
  final dayMidnight = DateTime(day.year, day.month, day.day);
  final diff = todayMidnight.difference(dayMidnight).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Yesterday';
  return DateFormat('EEEE, d MMMM yyyy').format(day);
}

/// Month label for a bucket or a day, e.g. "November 2026".
String monthLabel(DateTime date) => DateFormat('MMMM yyyy').format(date);

/// Short month label for the fast-scroll indicator, e.g. "Nov 2026".
String shortMonthLabel(DateTime date) => DateFormat('MMM yyyy').format(date);

/// Format a video duration for a tile badge: "0:12", "1:02:03".
/// Null (images, unknown) formats as an empty string.
String formatDuration(Duration? duration) {
  if (duration == null) return '';
  final totalSeconds = duration.inSeconds;
  final hours = totalSeconds ~/ 3600;
  final minutes = (totalSeconds % 3600) ~/ 60;
  final seconds = totalSeconds % 60;
  final mm = minutes.toString().padLeft(2, '0');
  final ss = seconds.toString().padLeft(2, '0');
  if (hours > 0) return '$hours:$mm:$ss';
  return '$minutes:$ss';
}

/// Which day section is at [offset] in a timeline rendered as
/// header + 3-column grid rows, given the tile height and header
/// height. Used for the fast-scroll date indicator. Returns the
/// section index, clamped to the list.
int sectionIndexForOffset({
  required List<DaySection> sections,
  required double offset,
  required double tileHeight,
  required double headerHeight,
  int crossAxisCount = 3,
}) {
  if (sections.isEmpty) return 0;
  var cursor = 0.0;
  for (var i = 0; i < sections.length; i++) {
    final rows = (sections[i].assets.length / crossAxisCount).ceil();
    final height = headerHeight + rows * tileHeight;
    if (offset < cursor + height) return i;
    cursor += height;
  }
  return sections.length - 1;
}

/// "On this day" assets: taken on the same month/day as [today] in
/// an earlier year, grouped by year (newest year first). This is the
/// locally-derived Memories highlight — it is labelled as generated
/// on this device, unlike the server-provided `GET /memories` lanes.
Map<int, List<NovaAsset>> onThisDayByYear(
  List<NovaAsset> assets, {
  DateTime? today,
}) {
  final now = today ?? DateTime.now();
  final byYear = <int, List<NovaAsset>>{};
  for (final asset in assets) {
    final d = asset.localDateTime;
    if (d.month == now.month && d.day == now.day && d.year < now.year) {
      (byYear[d.year] ??= []).add(asset);
    }
  }
  return byYear;
}

/// Years-ago label for a memory lane, e.g. "3 years ago".
String yearsAgoLabel(int years) => years <= 1 ? '1 year ago' : '$years years ago';

/// Human-readable label for a timeline bucket (date-only strings
/// such as "2025-04-01" parse to the first of the month).
String bucketLabel(TimeBucket bucket) => monthLabel(bucket.timeBucket);
