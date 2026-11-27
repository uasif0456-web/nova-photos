/// Shared selection actions — the work behind the selection bar in
/// the Photos timeline, album detail and library lists.
///
/// One place for favorite / archive / add-to-album / share /
/// download / delete so the three screens behave identically.
/// Callers pass the currently loaded assets and the selected ids,
/// and a [onChanged] callback that refreshes their own providers
/// after the action lands.
library;

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/asset.dart';
import '../providers/providers.dart';
import '../providers/track_b_providers.dart';
import 'widgets/selection_action_bar.dart';
import 'screens/viewer_screen.dart';

enum SelectionAction { favorite, archive, addToAlbum, share, download, delete }

Future<void> performSelectionAction({
  required BuildContext context,
  required WidgetRef ref,
  required List<NovaAsset> assets,
  required Set<String> selectedIds,
  required SelectionAction action,
  required VoidCallback onChanged,
}) async {
  final api = ref.read(novaApiProvider);
  if (api == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Not signed in.')),
    );
    return;
  }
  if (selectedIds.isEmpty) return;
  final actions = ref.read(assetActionsProvider);
  final selected = assets.where((a) => selectedIds.contains(a.id)).toList();
  final ids = selectedIds.toList();
  try {
    switch (action) {
      case SelectionAction.favorite:
        await actions.setFavorite(api, ids, true);
      case SelectionAction.archive:
        await actions.setArchived(api, ids, true);
      case SelectionAction.addToAlbum:
        final albums = ref.read(albumsProvider).value ?? const [];
        final picked = await pickAlbum(
          context,
          albums: [
            for (final a in albums)
              (id: a.id, name: a.albumName, count: a.assetCount),
          ],
        );
        if (picked == null) return;
        var albumId = picked;
        if (picked == '__new__') {
          if (!context.mounted) return;
          final name = await askAlbumName(context);
          if (name == null) return;
          final album =
              await ref.read(albumsProvider.notifier).create(name);
          if (album == null) return;
          albumId = album.id;
        }
        await actions.addToAlbum(api, albumId, ids);
        ref.invalidate(albumAssetsProvider(albumId));
      case SelectionAction.share:
        await actions.shareOriginals(api, selected);
      case SelectionAction.download:
        for (final asset in selected) {
          await actions.downloadOriginal(api, asset);
        }
      case SelectionAction.delete:
        if (!await confirmDelete(context, count: ids.length)) return;
        await actions.delete(api, ids);
    }
    ref.read(selectionProvider.notifier).clear();
    ref.read(photosProvider.notifier).removeAssets(ids);
    onChanged();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(switch (action) {
            SelectionAction.favorite => 'Added ${ids.length} to favorites',
            SelectionAction.archive => 'Archived ${ids.length}',
            SelectionAction.addToAlbum => 'Added ${ids.length} to album',
            SelectionAction.share => 'Shared ${ids.length}',
            SelectionAction.download =>
              'Downloaded ${ids.length} to NOVA PHOTOS',
            SelectionAction.delete => 'Moved ${ids.length} to trash',
          }),
        ),
      );
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('That did not work: $e')),
      );
    }
  }
}

/// Open the viewer for [assets] starting at [index].
void openViewer(BuildContext context, List<NovaAsset> assets, int index) {
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => ViewerScreen(assets: assets, initialIndex: index),
    ),
  );
}
