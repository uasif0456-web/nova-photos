/// Photos tab — the real timeline.
///
/// Assets page in newest-first through `POST /search/metadata`
/// ([photosProvider]) and are grouped by day ([groupAssetsByDay])
/// under date headers. Month buckets from `GET /timeline/buckets`
/// ([bucketsProvider]) drive the month-jump sheet; the grid itself
/// never loads originals — thumbnails only.
///
/// Features: date headers, fast-scroll date indicator, month jump,
/// pull-to-refresh, infinite scroll, scroll-position preservation
/// (PageStorageKey + the shell's IndexedStack), long-press selection
/// mode with the selection action bar, video duration badges and
/// favorite marks on the tiles.
library;

import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/asset.dart';
import '../../models/search.dart';
import '../../providers/providers.dart';
import '../../providers/track_b_providers.dart';
import '../../utils/timeline_utils.dart';
import '../selection_actions.dart';
import '../widgets/asset_tile.dart';
import '../widgets/selection_action_bar.dart';

class PhotosPage extends ConsumerStatefulWidget {
  const PhotosPage({super.key});

  @override
  ConsumerState<PhotosPage> createState() => _PhotosPageState();
}

class _PhotosPageState extends ConsumerState<PhotosPage> {
  final _scrollController = ScrollController();
  final _sectionKeys = <String, GlobalKey>{};
  Timer? _indicatorTimer;
  bool _showIndicator = false;
  int _currentSection = 0;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _indicatorTimer?.cancel();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.maxScrollExtent - position.pixels < 600) {
      ref.read(photosProvider.notifier).loadMore();
    }
    // Fast-scroll date indicator: which day section is at the top.
    final assets = ref.read(photosProvider).value ?? const [];
    if (assets.isEmpty) return;
    final sections = groupAssetsByDay(assets);
    final width = MediaQuery.of(context).size.width;
    final tileHeight = (width - 8) / 3;
    final index = sectionIndexForOffset(
      sections: sections,
      offset: position.pixels,
      tileHeight: tileHeight,
      headerHeight: 48,
    );
    if (index != _currentSection) {
      setState(() => _currentSection = index);
    }
    if (!_showIndicator) setState(() => _showIndicator = true);
    _indicatorTimer?.cancel();
    _indicatorTimer = Timer(const Duration(milliseconds: 900), () {
      if (mounted) setState(() => _showIndicator = false);
    });
  }

  GlobalKey _keyFor(DateTime day) {
    final key = day.toIso8601String();
    return _sectionKeys.putIfAbsent(key, () => GlobalKey());
  }

  Future<void> _jumpToMonth(TimeBucket bucket) async {
    Navigator.of(context).pop();
    final assets = ref.read(photosProvider).value ?? const [];
    final sections = groupAssetsByDay(assets);
    final target = sections.indexWhere(
      (s) =>
          s.day.year == bucket.timeBucket.year &&
          s.day.month == bucket.timeBucket.month,
    );
    if (target < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'No ${monthLabel(bucket.timeBucket)} photos loaded yet — '
            'scroll down to load more.',
          ),
        ),
      );
      return;
    }
    final key = _keyFor(sections[target].day);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    if (!mounted) return;
    final sectionContext = key.currentContext;
    if (sectionContext != null && sectionContext.mounted) {
      await Scrollable.ensureVisible(
        sectionContext,
        duration: const Duration(milliseconds: 300),
        alignment: 0,
      );
    }
  }

  void _showMonthSheet() {
    final buckets = ref.read(bucketsProvider).value ?? const [];
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: buckets.isEmpty
            ? const Padding(
                padding: EdgeInsets.all(24),
                child: Text('No months loaded yet.'),
              )
            : ListView.builder(
                shrinkWrap: true,
                itemCount: buckets.length,
                itemBuilder: (context, index) {
                  final bucket = buckets[index];
                  return ListTile(
                    leading: const Icon(Icons.calendar_month_outlined),
                    title: Text(monthLabel(bucket.timeBucket)),
                    trailing: Text('${bucket.count}'),
                    onTap: () => _jumpToMonth(bucket),
                  );
                },
              ),
      ),
    );
  }

  void _onTileTap(List<NovaAsset> assets, int index) {
    final selection = ref.read(selectionProvider);
    if (selection.isNotEmpty) {
      ref.read(selectionProvider.notifier).toggle(assets[index].id);
      return;
    }
    openViewer(context, assets, index);
  }

  @override
  Widget build(BuildContext context) {
    final photos = ref.watch(photosProvider);
    final headers = ref.watch(authImageHeadersProvider);
    final media = ref.watch(mediaUrlsProvider);
    final selected = ref.watch(selectionProvider);
    return photos.when(
      data: (assets) {
        if (assets.isEmpty) {
          return RefreshIndicator(
            onRefresh: () => ref.read(photosProvider.notifier).refresh(),
            child: ListView(
              children: const [
                SizedBox(height: 120),
                Icon(Icons.photo_library_outlined, size: 64),
                SizedBox(height: 16),
                Text(
                  'No photos yet.\nUploads from this device land here.',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          );
        }
        final sections = groupAssetsByDay(assets);
        final currentLabel = sections.isEmpty
            ? ''
            : monthLabel(sections[_currentSection.clamp(0, sections.length - 1)].day);
        return Stack(
          children: [
            Column(
              children: [
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: () =>
                        ref.read(photosProvider.notifier).refresh(),
                    child: CustomScrollView(
                      key: const PageStorageKey<String>('photos-timeline'),
                      controller: _scrollController,
                      slivers: [
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                            child: Row(
                              children: [
                                Text(
                                  '${assets.length} photos loaded',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall,
                                ),
                                const Spacer(),
                                TextButton.icon(
                                  onPressed: _showMonthSheet,
                                  icon: const Icon(
                                    Icons.calendar_month_outlined,
                                    size: 18,
                                  ),
                                  label: const Text('Jump to month'),
                                ),
                              ],
                            ),
                          ),
                        ),
                        for (final section in sections) ...[
                          SliverToBoxAdapter(
                            key: _keyFor(section.day),
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                              child: Text(
                                '${dayLabel(section.day)} · ${section.assets.length}',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ),
                          ),
                          SliverGrid.builder(
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 3,
                              crossAxisSpacing: 2,
                              mainAxisSpacing: 2,
                            ),
                            itemCount: section.assets.length,
                            itemBuilder: (context, index) {
                              final asset = section.assets[index];
                              final flatIndex = assets.indexOf(asset);
                              return AssetTile(
                                asset: asset,
                                thumbnailUrl: media
                                    ?.thumbnail(asset.id, size: 'thumbnail')
                                    .toString(),
                                headers: headers,
                                selected: selected.contains(asset.id),
                                onTap: () =>
                                    _onTileTap(assets, flatIndex),
                                onLongPress: () => ref
                                    .read(selectionProvider.notifier)
                                    .toggle(asset.id),
                              );
                            },
                          ),
                        ],
                        const SliverToBoxAdapter(
                          child: SizedBox(height: 16),
                        ),
                      ],
                    ),
                  ),
                ),
                if (selected.isNotEmpty)
                  SelectionActionBar(
                    count: selected.length,
                    onFavorite: () => performSelectionAction(
                      context: context,
                      ref: ref,
                      assets: assets,
                      selectedIds: selected,
                      action: SelectionAction.favorite,
                      onChanged: () {},
                    ),
                    onArchive: () => performSelectionAction(
                      context: context,
                      ref: ref,
                      assets: assets,
                      selectedIds: selected,
                      action: SelectionAction.archive,
                      onChanged: () {},
                    ),
                    onAddToAlbum: () => performSelectionAction(
                      context: context,
                      ref: ref,
                      assets: assets,
                      selectedIds: selected,
                      action: SelectionAction.addToAlbum,
                      onChanged: () {},
                    ),
                    onShare: () => performSelectionAction(
                      context: context,
                      ref: ref,
                      assets: assets,
                      selectedIds: selected,
                      action: SelectionAction.share,
                      onChanged: () {},
                    ),
                    onDownload: () => performSelectionAction(
                      context: context,
                      ref: ref,
                      assets: assets,
                      selectedIds: selected,
                      action: SelectionAction.download,
                      onChanged: () {},
                    ),
                    onDelete: () => performSelectionAction(
                      context: context,
                      ref: ref,
                      assets: assets,
                      selectedIds: selected,
                      action: SelectionAction.delete,
                      onChanged: () {},
                    ),
                    onClear: () =>
                        ref.read(selectionProvider.notifier).clear(),
                  ),
              ],
            ),
            if (_showIndicator && sections.isNotEmpty)
              Positioned(
                top: 12,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.15),
                          blurRadius: 8,
                        ),
                      ],
                    ),
                    child: Text(
                      currentLabel,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_outlined, size: 48),
              const SizedBox(height: 12),
              Text(
                'Could not load photos.\n$error',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () =>
                    ref.read(photosProvider.notifier).refresh(),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
