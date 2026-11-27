/// Memories tab — "on this day" lanes from the server plus locally
/// derived highlights.
///
/// Server lanes come from `GET /memories` and are labelled as
/// server-provided. The "This day in previous years" section is
/// generated on this device from the loaded timeline
/// ([onThisDayByYear]) and is labelled as such — it is not a server
/// lane. Tapping any card opens the viewer on those assets.
library;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/asset.dart';
import '../../models/memory.dart';
import '../../providers/providers.dart';
import '../../providers/track_b_providers.dart';
import '../../utils/timeline_utils.dart';
import '../selection_actions.dart';

class MemoriesPage extends ConsumerWidget {
  const MemoriesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final memories = ref.watch(memoriesProvider);
    final photos = ref.watch(photosProvider);
    final headers = ref.watch(authImageHeadersProvider);
    final media = ref.watch(mediaUrlsProvider);
    final highlights = onThisDayByYear(photos.value ?? const []);
    final highlightYears = highlights.keys.toList()
      ..sort((a, b) => b.compareTo(a));
    final recentMonths = _recentMonths(photos.value ?? const []);

    return RefreshIndicator(
      onRefresh: () async {
        await ref.read(memoriesProvider.notifier).refresh();
        await ref.read(photosProvider.notifier).refresh();
      },
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Memories', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          const Text('From your server — “on this day” lanes.'),
          const SizedBox(height: 12),
          memories.when(
            data: (lanes) {
              if (lanes.isEmpty) {
                return const Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'No memories from the server yet.\n'
                      'They appear here once you have photos from this '
                      'date in earlier years.',
                    ),
                  ),
                );
              }
              return Column(
                children: [
                  for (final memory in lanes)
                    _MemoryCard(
                      memory: memory,
                      headers: headers,
                      previewUrl: memory.assets.isEmpty
                          ? null
                          : media
                              ?.preview(memory.assets.first.id)
                              .toString(),
                    ),
                ],
              );
            },
            loading: () => const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (error, _) => Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text('Could not load memories.\n$error'),
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'This day in previous years',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 4),
          const Text(
            'Generated on this device from your timeline — '
            'not a server memory.',
          ),
          const SizedBox(height: 12),
          if (highlightYears.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Nothing from this date in earlier years in the '
                  'photos loaded so far.',
                ),
              ),
            )
          else
            for (final year in highlightYears)
              _HighlightRow(
                year: year,
                assets: highlights[year]!,
                headers: headers,
                previewUrl: media
                    ?.preview(highlights[year]!.first.id)
                    .toString(),
              ),
          const SizedBox(height: 24),
          Text(
            'Recent highlights',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 4),
          const Text(
            'Your busiest recent months, from the loaded timeline — '
            'generated on this device, not a server memory.',
          ),
          const SizedBox(height: 12),
          if (recentMonths.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text('Load more photos to see recent highlights.'),
              ),
            )
          else
            for (final entry in recentMonths)
              _MonthRow(
                month: entry.key,
                assets: entry.value,
                headers: headers,
                previewUrl: media
                    ?.preview(entry.value.first.id)
                    .toString(),
              ),
        ],
      ),
    );
  }
}

/// Busiest recent months in the loaded timeline (newest first,
/// up to 3): the "recent highlights" lane, derived locally.
List<MapEntry<DateTime, List<NovaAsset>>> _recentMonths(
  List<NovaAsset> assets,
) {
  final byMonth = <DateTime, List<NovaAsset>>{};
  for (final asset in assets) {
    final d = asset.localDateTime;
    final month = DateTime(d.year, d.month, 1);
    (byMonth[month] ??= []).add(asset);
  }
  final entries = byMonth.entries.toList()
    ..sort((a, b) => b.key.compareTo(a.key));
  return entries.take(3).toList(growable: false);
}

class _MemoryCard extends ConsumerWidget {
  const _MemoryCard({
    required this.memory,
    required this.headers,
    required this.previewUrl,
  });

  final Memory memory;
  final Map<String, String> headers;
  final String? previewUrl;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = DateTime.now();
    final firstYear = memory.assets.isEmpty
        ? null
        : memory.assets.first.localDateTime.year;
    final years = firstYear == null ? null : now.year - firstYear;
    final title = switch (memory.type) {
      MemoryType.birthday =>
        'Birthday — ${memory.data['personName'] ?? 'someone'}',
      MemoryType.onThisDay =>
        years == null ? 'On this day' : yearsAgoLabel(years),
      MemoryType.unknown => 'Memory',
    };
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: memory.assets.isEmpty
            ? null
            : () => openViewer(context, memory.assets, 0),
        child: Row(
          children: [
            SizedBox(
              width: 96,
              height: 96,
              child: previewUrl == null
                  ? Container(
                      color: Theme.of(context)
                          .colorScheme
                          .surfaceContainerHighest,
                      child: const Icon(Icons.history_outlined),
                    )
                  : CachedNetworkImage(
                      imageUrl: previewUrl!,
                      httpHeaders: headers,
                      fit: BoxFit.cover,
                      errorWidget: (context, _, _) =>
                          const Icon(Icons.broken_image_outlined),
                    ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(
                      '${memory.assets.length} photos · Server memory',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
            IconButton(
              icon: Icon(
                memory.isSaved
                    ? Icons.bookmark
                    : Icons.bookmark_border_outlined,
              ),
              tooltip: memory.isSaved ? 'Unsave' : 'Save',
              onPressed: () => ref
                  .read(memoriesProvider.notifier)
                  .save(memory.id, !memory.isSaved),
            ),
            IconButton(
              icon: const Icon(Icons.visibility_off_outlined),
              tooltip: 'Hide',
              onPressed: () =>
                  ref.read(memoriesProvider.notifier).hide(memory.id),
            ),
          ],
        ),
      ),
    );
  }
}

class _MonthRow extends StatelessWidget {
  const _MonthRow({
    required this.month,
    required this.assets,
    required this.headers,
    required this.previewUrl,
  });

  final DateTime month;
  final List<NovaAsset> assets;
  final Map<String, String> headers;
  final String? previewUrl;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => openViewer(context, assets, 0),
        child: Row(
          children: [
            SizedBox(
              width: 96,
              height: 96,
              child: previewUrl == null
                  ? Container(
                      color: Theme.of(context)
                          .colorScheme
                          .surfaceContainerHighest,
                      child: const Icon(Icons.history_outlined),
                    )
                  : CachedNetworkImage(
                      imageUrl: previewUrl!,
                      httpHeaders: headers,
                      fit: BoxFit.cover,
                      errorWidget: (context, _, _) =>
                          const Icon(Icons.broken_image_outlined),
                    ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      monthLabel(month),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${assets.length} photos · Generated on this device',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.only(right: 12),
              child: Icon(Icons.chevron_right),
            ),
          ],
        ),
      ),
    );
  }
}

class _HighlightRow extends StatelessWidget {
  const _HighlightRow({
    required this.year,
    required this.assets,
    required this.headers,
    required this.previewUrl,
  });

  final int year;
  final List<NovaAsset> assets;
  final Map<String, String> headers;
  final String? previewUrl;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => openViewer(context, assets, 0),
        child: Row(
          children: [
            SizedBox(
              width: 96,
              height: 96,
              child: previewUrl == null
                  ? Container(
                      color: Theme.of(context)
                          .colorScheme
                          .surfaceContainerHighest,
                      child: const Icon(Icons.history_outlined),
                    )
                  : CachedNetworkImage(
                      imageUrl: previewUrl!,
                      httpHeaders: headers,
                      fit: BoxFit.cover,
                      errorWidget: (context, _, _) =>
                          const Icon(Icons.broken_image_outlined),
                    ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      yearsAgoLabel(now.year - year),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${assets.length} photos from $year · '
                      'Generated on this device',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.only(right: 12),
              child: Icon(Icons.chevron_right),
            ),
          ],
        ),
      ),
    );
  }
}
