/// Asset picker — pick photos from the library to add to an album.
///
/// Shows the Photos timeline grid ([photosProvider]) with local
/// multi-select; confirming adds the chosen assets to the album and
/// pops. Nothing is uploaded or moved — the assets stay in the
/// library and are only linked to the album.
library;

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/album.dart';
import '../../providers/providers.dart';
import '../../providers/track_b_providers.dart';
import '../widgets/asset_grid.dart';

class AssetPickerScreen extends ConsumerStatefulWidget {
  const AssetPickerScreen({super.key, required this.album});

  final Album album;

  @override
  ConsumerState<AssetPickerScreen> createState() => _AssetPickerScreenState();
}

class _AssetPickerScreenState extends ConsumerState<AssetPickerScreen> {
  final _picked = <String>{};
  bool _busy = false;

  Future<void> _confirm() async {
    if (_picked.isEmpty || _busy) return;
    final api = ref.read(novaApiProvider);
    if (api == null) return;
    setState(() => _busy = true);
    try {
      await api.albums.addAssets(widget.album.id, _picked.toList());
      ref.invalidate(albumAssetsProvider(widget.album.id));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Added ${_picked.length} to ${widget.album.albumName}'),
          ),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('That did not work: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final photos = ref.watch(photosProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text('Add to ${widget.album.albumName}'),
        actions: [
          TextButton(
            onPressed: _picked.isEmpty || _busy ? null : _confirm,
            child: Text('Add (${_picked.length})'),
          ),
        ],
      ),
      body: photos.when(
        data: (assets) {
          if (assets.isEmpty) {
            return const Center(child: Text('No photos in your library yet.'));
          }
          return AssetGrid(
            assets: assets,
            selectedIds: _picked,
            onOpen: (i) {
              final id = assets[i].id;
              setState(() {
                if (_picked.contains(id)) {
                  _picked.remove(id);
                } else {
                  _picked.add(id);
                }
              });
            },
            onLongPress: (asset) {
              setState(() {
                if (_picked.contains(asset.id)) {
                  _picked.remove(asset.id);
                } else {
                  _picked.add(asset.id);
                }
              });
            },
            onLoadMore: () =>
                ref.read(photosProvider.notifier).loadMore(),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Could not load photos.\n$error')),
      ),
    );
  }
}
