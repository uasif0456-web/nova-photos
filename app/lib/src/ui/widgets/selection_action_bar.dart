/// Selection action bar — the bottom bar shown while assets are
/// selected in the timeline / album / search grids.
///
/// Actions: favorite, archive, add to album, share, download,
/// delete (with confirmation). The bar only renders the actions;
/// the owning screen supplies the callbacks, which call
/// [AssetActionsService] and refresh their providers.
library;

import 'package:material_ui/material_ui.dart';

class SelectionActionBar extends StatelessWidget {
  const SelectionActionBar({
    super.key,
    required this.count,
    required this.onFavorite,
    required this.onArchive,
    required this.onAddToAlbum,
    required this.onShare,
    required this.onDownload,
    required this.onDelete,
    required this.onClear,
  });

  final int count;
  final VoidCallback onFavorite;
  final VoidCallback onArchive;
  final VoidCallback onAddToAlbum;
  final VoidCallback onShare;
  final VoidCallback onDownload;
  final VoidCallback onDelete;
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
            IconButton(
              icon: const Icon(Icons.favorite_outlined),
              tooltip: 'Favorite',
              onPressed: onFavorite,
            ),
            IconButton(
              icon: const Icon(Icons.archive_outlined),
              tooltip: 'Archive',
              onPressed: onArchive,
            ),
            IconButton(
              icon: const Icon(Icons.add_to_photos_outlined),
              tooltip: 'Add to album',
              onPressed: onAddToAlbum,
            ),
            IconButton(
              icon: const Icon(Icons.share_outlined),
              tooltip: 'Share',
              onPressed: onShare,
            ),
            IconButton(
              icon: const Icon(Icons.download_outlined),
              tooltip: 'Download',
              onPressed: onDownload,
            ),
            IconButton(
              icon: const Icon(Icons.delete_outlined),
              tooltip: 'Delete',
              onPressed: onDelete,
            ),
          ],
        ),
      ),
    );
  }
}

/// Confirm-delete dialog used by the selection bar and the viewer.
/// Returns true when the user confirms.
Future<bool> confirmDelete(
  BuildContext context, {
  required int count,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(count == 1 ? 'Delete photo?' : 'Delete $count photos?'),
      content: const Text(
        'Photos move to trash. You can restore them from the Library '
        'tab until the trash is emptied.',
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
  return confirmed ?? false;
}

/// Album picker dialog for "add to album". Returns the chosen
/// album id, or the sentinel `'__new__'` when the user wants to
/// create a new album (the caller then asks for a name).
Future<String?> pickAlbum(
  BuildContext context, {
    required List<({String id, String name, int count})> albums,
  }) async {
  return showDialog<String>(
    context: context,
    builder: (context) => SimpleDialog(
      title: const Text('Add to album'),
      children: [
        for (final album in albums)
          SimpleDialogOption(
            onPressed: () => Navigator.of(context).pop(album.id),
            child: Row(
              children: [
                const Icon(Icons.photo_album_outlined),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '${album.name} (${album.count})',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        SimpleDialogOption(
          onPressed: () => Navigator.of(context).pop('__new__'),
          child: const Row(
            children: [
              Icon(Icons.add),
              SizedBox(width: 12),
              Text('New album'),
            ],
          ),
        ),
      ],
    ),
  );
}

/// Ask for a new album name. Returns null when cancelled.
Future<String?> askAlbumName(BuildContext context, {String? initial}) async {
  final controller = TextEditingController(text: initial ?? '');
  final name = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(initial == null ? 'New album' : 'Rename album'),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: const InputDecoration(hintText: 'Album name'),
        textCapitalization: TextCapitalization.sentences,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(controller.text.trim()),
          child: const Text('Save'),
        ),
      ],
    ),
  );
  controller.dispose();
  return (name == null || name.isEmpty) ? null : name;
}
