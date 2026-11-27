/// Asset grid — a 3-column grid of [AssetTile]s, reused by the
/// Search results, album detail and library lists.
///
/// Tap opens the viewer (the caller supplies [onOpen] with the
/// tapped index so the viewer can page across the same list);
/// long-press enters selection mode via [onLongPress].
library;

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/asset.dart';
import '../../providers/providers.dart';
import 'asset_tile.dart';

class AssetGrid extends ConsumerWidget {
  const AssetGrid({
    super.key,
    required this.assets,
    this.selectedIds = const {},
    this.onOpen,
    this.onLongPress,
    this.onLoadMore,
    this.padding = const EdgeInsets.all(2),
  });

  final List<NovaAsset> assets;
  final Set<String> selectedIds;
  final void Function(int index)? onOpen;
  final void Function(NovaAsset asset)? onLongPress;
  final VoidCallback? onLoadMore;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final headers = ref.watch(authImageHeadersProvider);
    final media = ref.watch(mediaUrlsProvider);
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (onLoadMore != null &&
            notification.metrics.maxScrollExtent -
                    notification.metrics.pixels <
                600) {
          onLoadMore!();
        }
        return false;
      },
      child: GridView.builder(
        padding: padding,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: 2,
          mainAxisSpacing: 2,
        ),
        itemCount: assets.length,
        itemBuilder: (context, index) {
          final asset = assets[index];
          return AssetTile(
            asset: asset,
            thumbnailUrl:
                media?.thumbnail(asset.id, size: 'thumbnail').toString(),
            headers: headers,
            selected: selectedIds.contains(asset.id),
            onTap: () => onOpen?.call(index),
            onLongPress: () => onLongPress?.call(asset),
          );
        },
      ),
    );
  }
}
