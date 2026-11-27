/// Generic asset list screen — used by the Library tab (Favorites,
/// Archive, Trash), by People/Tags in Collections, and by any other
/// filtered list.
///
/// Loads one `POST /search/metadata` request, shows the results in
/// the shared [AssetGrid], opens the viewer on tap, and supports
/// selection mode. In trash mode the bar offers Restore and Empty
/// trash instead of the usual actions.
library;

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/asset.dart';
import '../../models/search.dart';
import '../../providers/providers.dart';
import '../../providers/track_b_providers.dart';
import '../selection_actions.dart';
import '../widgets/asset_grid.dart';
import '../widgets/selection_action_bar.dart';

class AssetListScreen extends ConsumerStatefulWidget {
  const AssetListScreen({
    super.key,
    required this.title,
    required this.request,
    this.trashMode = false,
  });

  final String title;
  final MetadataSearchRequest request;
  final bool trashMode;

  @override
  ConsumerState<AssetListScreen> createState() => _AssetListScreenState();
}

class _AssetListScreenState extends ConsumerState<AssetListScreen> {
  List<NovaAsset>? _assets;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    ref.read(selectionProvider.notifier).clear();
    _load();
  }

  @override
  void dispose() {
    ref.read(selectionProvider.notifier).clear();
    super.dispose();
  }

  Future<void> _load() async {
    final api = ref.read(novaApiProvider);
    if (api == null) {
      setState(() {
        _loading = false;
        _error = 'Not signed in.';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final assets =
          await api.search.searchMetadataAllAssets(widget.request);
      if (mounted) {
        setState(() {
          _assets = assets;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _loading = false;
        });
      }
    }
  }

  Future<void> _restoreSelected(Set<String> ids) async {
    final api = ref.read(novaApiProvider);
    if (api == null) return;
    try {
      await api.trash.restoreAssets(ids.toList());
      ref.read(selectionProvider.notifier).clear();
      ref.read(photosProvider.notifier).refresh();
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Restored ${ids.length}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Restore did not work: $e')),
        );
      }
    }
  }

  Future<void> _emptyTrash() async {
    final api = ref.read(novaApiProvider);
    if (api == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Empty trash?'),
        content: const Text(
          'Everything in the trash is permanently deleted. '
          'This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Empty trash'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await api.trash.emptyTrash();
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Trash emptied')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Emptying the trash did not work: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final selected = ref.watch(selectionProvider);
    final assets = _assets ?? const [];
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          if (widget.trashMode)
            IconButton(
              icon: const Icon(Icons.delete_forever_outlined),
              tooltip: 'Empty trash',
              onPressed: _emptyTrash,
            ),
          IconButton(
            icon: const Icon(Icons.refresh_outlined),
            tooltip: 'Refresh',
            onPressed: _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.cloud_off_outlined, size: 48),
                        const SizedBox(height: 12),
                        Text(
                          'Could not load photos.\n$_error',
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: _load,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                )
              : assets.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.photo_library_outlined,
                              size: 64,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Nothing here yet.',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                          ],
                        ),
                      ),
                    )
                  : Column(
                      children: [
                        Expanded(
                          child: AssetGrid(
                            assets: assets,
                            selectedIds: selected,
                            onOpen: (i) =>
                                openViewer(context, assets, i),
                            onLongPress: (asset) => ref
                                .read(selectionProvider.notifier)
                                .toggle(asset.id),
                          ),
                        ),
                        if (selected.isNotEmpty)
                          widget.trashMode
                              ? _TrashBar(
                                  count: selected.length,
                                  onRestore: () =>
                                      _restoreSelected(selected),
                                  onClear: () => ref
                                      .read(selectionProvider.notifier)
                                      .clear(),
                                )
                              : SelectionActionBar(
                                  count: selected.length,
                                  onFavorite: () =>
                                      performSelectionAction(
                                    context: context,
                                    ref: ref,
                                    assets: assets,
                                    selectedIds: selected,
                                    action: SelectionAction.favorite,
                                    onChanged: _load,
                                  ),
                                  onArchive: () =>
                                      performSelectionAction(
                                    context: context,
                                    ref: ref,
                                    assets: assets,
                                    selectedIds: selected,
                                    action: SelectionAction.archive,
                                    onChanged: _load,
                                  ),
                                  onAddToAlbum: () =>
                                      performSelectionAction(
                                    context: context,
                                    ref: ref,
                                    assets: assets,
                                    selectedIds: selected,
                                    action: SelectionAction.addToAlbum,
                                    onChanged: _load,
                                  ),
                                  onShare: () => performSelectionAction(
                                    context: context,
                                    ref: ref,
                                    assets: assets,
                                    selectedIds: selected,
                                    action: SelectionAction.share,
                                    onChanged: _load,
                                  ),
                                  onDownload: () =>
                                      performSelectionAction(
                                    context: context,
                                    ref: ref,
                                    assets: assets,
                                    selectedIds: selected,
                                    action: SelectionAction.download,
                                    onChanged: _load,
                                  ),
                                  onDelete: () => performSelectionAction(
                                    context: context,
                                    ref: ref,
                                    assets: assets,
                                    selectedIds: selected,
                                    action: SelectionAction.delete,
                                    onChanged: _load,
                                  ),
                                  onClear: () => ref
                                      .read(selectionProvider.notifier)
                                      .clear(),
                                ),
                      ],
                    ),
    );
  }
}

class _TrashBar extends StatelessWidget {
  const _TrashBar({
    required this.count,
    required this.onRestore,
    required this.onClear,
  });

  final int count;
  final VoidCallback onRestore;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      color: scheme.surfaceContainerHighest,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.close),
              tooltip: 'Clear selection',
              onPressed: onClear,
            ),
            Text(
              '$count selected',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const Spacer(),
            FilledButton.icon(
              onPressed: onRestore,
              icon: const Icon(Icons.restore_outlined),
              label: const Text('Restore'),
            ),
            const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }
}
