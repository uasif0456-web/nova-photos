/// Asset tile — one thumbnail in a grid.
///
/// Thumbnails only (never originals); authenticated via the headers
/// from [authImageHeadersProvider]. Shows a video duration badge, a
/// favorite mark, and a selection checkmark when [selected].
library;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:material_ui/material_ui.dart';

import '../../models/asset.dart';
import '../../utils/timeline_utils.dart';

class AssetTile extends StatelessWidget {
  const AssetTile({
    super.key,
    required this.asset,
    required this.thumbnailUrl,
    required this.headers,
    this.selected = false,
    this.onTap,
    this.onLongPress,
  });

  final NovaAsset asset;
  final String? thumbnailUrl;
  final Map<String, String> headers;
  final bool selected;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final placeholderColor =
        Theme.of(context).colorScheme.surfaceContainerHighest;
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (thumbnailUrl != null)
            CachedNetworkImage(
              imageUrl: thumbnailUrl!,
              httpHeaders: headers,
              fit: BoxFit.cover,
              placeholder: (context, _) =>
                  Container(color: placeholderColor),
              errorWidget: (context, _, _) => Container(
                color: placeholderColor,
                child: const Icon(Icons.broken_image_outlined),
              ),
            )
          else
            Container(color: placeholderColor),
          if (asset.isVideo)
            Positioned(
              right: 6,
              bottom: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 5,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.play_arrow,
                      color: Colors.white,
                      size: 12,
                    ),
                    const SizedBox(width: 2),
                    Text(
                      formatDuration(asset.duration),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (asset.isFavorite)
            const Positioned(
              left: 6,
              top: 6,
              child: Icon(Icons.favorite, color: Colors.white, size: 16),
            ),
          if (selected)
            Container(
              color: scheme.primary.withValues(alpha: 0.45),
              alignment: Alignment.topLeft,
              padding: const EdgeInsets.all(6),
              child: Icon(
                Icons.check_circle,
                color: scheme.onPrimary,
                size: 22,
              ),
            ),
        ],
      ),
    );
  }
}
