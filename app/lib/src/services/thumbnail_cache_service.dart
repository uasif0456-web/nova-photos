/// Thumbnail disk-cache management.
///
/// Thumbnails are cached by `cached_network_image`
/// (`flutter_cache_manager`) under the temp directory's
/// `libCachedImageData` folder. This service only measures that
/// folder and empties it through the cache manager — it never touches
/// the Drift mirror or the server.
library;

import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:path_provider/path_provider.dart';

class ThumbnailCacheService {
  /// Size of the thumbnail disk cache, in bytes.
  Future<int> cacheSizeBytes() async {
    try {
      final temp = await getTemporaryDirectory();
      final dir = Directory('${temp.path}/libCachedImageData');
      if (!await dir.exists()) return 0;
      var total = 0;
      await for (final entity in dir.list(recursive: true)) {
        if (entity is File) {
          total += await entity.length().catchError((_) => 0);
        }
      }
      return total;
    } catch (_) {
      return 0;
    }
  }

  /// Human-readable cache size (`"12.4 MB"`, `"834 KB"`, `"0 B"`).
  static String formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  /// Empty the thumbnail cache. Thumbnails re-download on demand
  /// (authenticated, via the API client headers). Uses the same
  /// default cache manager the grid's `CachedNetworkImageProvider`
  /// writes through, so clearing here really clears the grid's cache.
  Future<void> clearCache() async {
    await CachedNetworkImageProvider.defaultCacheManager.emptyCache();
  }
}
