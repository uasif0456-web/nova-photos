/// Album detail — the assets of one album (loaded via
/// `POST /search/metadata` with `albumIds`; albums never embed
/// assets in v3), with rename / delete in the app bar, an "add
/// photos" action, and selection mode for removing assets or the
/// usual selection actions.
library;

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/album.dart';
import '../../providers/providers.dart';
import '../../providers/track_b_providers.dart';
import '../selection_actions.dart';
import '../widgets/asset_grid.dart';
import '../widgets/selection_action_bar.dart';
import 'asset_picker_screen.dart';

class AlbumDetailScreen extends ConsumerStatefulWidget {
  const AlbumDetailScreen({super.key, required this.album});

  final Album album;

  @override
  ConsumerState<AlbumDetailScreen> createState() => _AlbumDetailScreenState();
}

class _AlbumDetailScreenState extends ConsumerState<AlbumDetailScreen> {
  late Album _album;

  @override
  void initState() {
    super.initState();
    _album = widget.album;
    ref.read(selectionProvider.notifier).clear();
  }

  @override
  void dispose() {
    ref.read(selectionProvider.notifier).clear();
    super.dispose();
  }

  Future<void> _rename() async {
    final name = await askAlbumName(context, initial: _album.albumName);
    if (name == null) return;
    await ref.read(albumsProvider.notifier).rename(_album.id, name);
    final updated = ref
        .read(albumsProvider)
        .value
        ?.where((a) => a.id == _album.id)
        .firstOrNull;
    if (updated != null && mounted) setState(() => _album = updated);
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete album?'),
        content: Text(
          '“${_album.albumName}” will be deleted. The photos stay in '
          'your library.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(albumsProvider.notifier).delete(_album.id);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _removeSelected(Set<String> ids) async {
    final api = ref.read(novaApiProvider);
    if (api == null) return;
    try {
      await api.albums.removeAssets(_album.id, ids.toList());
      ref.read(selectionProvider.notifier).clear();
      ref.invalidate(albumAssetsProvider(_album.id));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Removed ${ids.length} from album')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('That did not work: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final assetsAsync = ref.watch(albumAssetsProvider(_album.id));
    final selected = ref.watch(selectionProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(_album.albumName),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'Album options',
            onSelected: (value) {
              if (value == 'rename') _rename();
              if (value == 'delete') _delete();
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'rename', child: Text('Rename')),
              PopupMenuItem(value: 'delete', child: Text('Delete album')),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => AssetPickerScreen(album: _album),
            ),
          );
          ref.invalidate(albumAssetsProvider(_album.id));
        },
        icon: const Icon(Icons.add_photo_alternate_outlined),
        label: const Text('Add photos'),
      ),
      body: assetsAsync.when(
        data: (assets) {
          if (assets.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'This album is empty.\nTap “Add photos” to add some.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return Column(
            children: [
              Expanded(
                child: AssetGrid(
                  assets: assets,
                  selectedIds: selected,
                  onOpen: (i) => openViewer(context, assets, i),
                  onLongPress: (asset) => ref
                      .read(selectionProvider.notifier)
                      .toggle(asset.id),
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
                    onChanged: () =>
                        ref.invalidate(albumAssetsProvider(_album.id)),
                  ),
                  onArchive: () => performSelectionAction(
                    context: context,
                    ref: ref,
                    assets: assets,
                    selectedIds: selected,
                    action: SelectionAction.archive,
                    onChanged: () =>
                        ref.invalidate(albumAssetsProvider(_album.id)),
                  ),
                  onAddToAlbum: () => performSelectionAction(
                    context: context,
                    ref: ref,
                    assets: assets,
                    selectedIds: selected,
                    action: SelectionAction.addToAlbum,
                    onChanged: () =>
                        ref.invalidate(albumAssetsProvider(_album.id)),
                  ),
                  onShare: () => performSelectionAction(
                    context: context,
                    ref: ref,
                    assets: assets,
                    selectedIds: selected,
                    action: SelectionAction.share,
                    onChanged: () =>
                        ref.invalidate(albumAssetsProvider(_album.id)),
                  ),
                  onDownload: () => performSelectionAction(
                    context: context,
                    ref: ref,
                    assets: assets,
                    selectedIds: selected,
                    action: SelectionAction.download,
                    onChanged: () =>
                        ref.invalidate(albumAssetsProvider(_album.id)),
                  ),
                  onDelete: () => performSelectionAction(
                    context: context,
                    ref: ref,
                    assets: assets,
                    selectedIds: selected,
                    action: SelectionAction.delete,
                    onChanged: () =>
                        ref.invalidate(albumAssetsProvider(_album.id)),
                  ),
                  onClear: () =>
                      ref.read(selectionProvider.notifier).clear(),
                ),
              if (selected.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: TextButton.icon(
                    onPressed: () => _removeSelected(selected),
                    icon: const Icon(Icons.remove_circle_outlined),
                    label: const Text('Remove from album'),
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
                Text('Could not load this album.\n$error',
                    textAlign: TextAlign.center),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () =>
                      ref.invalidate(albumAssetsProvider(_album.id)),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
