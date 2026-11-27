/// Asset actions — the operations the viewer and the selection bar
/// perform on assets: favorite, archive, delete, add to album,
/// download the original, share via the Android share sheet.
///
/// One service, no widgets: the UI calls these and then refreshes
/// its providers. Download writes into the app documents directory
/// (`NOVA PHOTOS/<file name>`) — writing to the public Downloads
/// folder needs a MediaStore/SAF flow that is not in v1; the returned
/// path is shown to the user so the file is findable.
library;

import 'dart:io';
import 'dart:ui';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../api/nova_api.dart';
import '../models/asset.dart';

class AssetActionsService {
  const AssetActionsService();

  /// Favorite / unfavorite. Single asset uses the single-asset
  /// endpoint; several use the bulk endpoint.
  Future<void> setFavorite(
    NovaApi api,
    List<String> ids,
    bool isFavorite,
  ) async {
    if (ids.isEmpty) return;
    if (ids.length == 1) {
      await api.assets.setFavorite(ids.first, isFavorite);
    } else {
      await api.assets.bulkUpdate(ids, isFavorite: isFavorite);
    }
  }

  /// Archive / unarchive (`visibility: archive` / `timeline`).
  Future<void> setArchived(
    NovaApi api,
    List<String> ids,
    bool archived,
  ) async {
    if (ids.isEmpty) return;
    if (ids.length == 1) {
      await api.assets.setArchived(ids.first, archived);
    } else {
      await api.assets
          .bulkUpdate(ids, visibility: archived ? 'archive' : 'timeline');
    }
  }

  /// Move to trash (server default) or permanently delete with
  /// [force]. Callers must confirm with the user first.
  Future<void> delete(NovaApi api, List<String> ids, {bool force = false}) async {
    if (ids.isEmpty) return;
    await api.assets.bulkDelete(ids, force: force);
  }

  /// Add assets to an album.
  Future<void> addToAlbum(
    NovaApi api,
    String albumId,
    List<String> assetIds,
  ) async {
    if (assetIds.isEmpty) return;
    await api.albums.addAssets(albumId, assetIds);
  }

  /// Download one asset's original bytes to the app documents
  /// directory and return the saved file.
  Future<File> downloadOriginal(NovaApi api, NovaAsset asset) async {
    final response = await api.client.getBytes(
      '/assets/${asset.id}/original',
    );
    final bytes = api.client.decodeBytes(response);
    final dir = await getApplicationDocumentsDirectory();
    final folder = Directory('${dir.path}/NOVA PHOTOS');
    await folder.create(recursive: true);
    final file = File('${folder.path}/${asset.originalFileName}');
    return file.writeAsBytes(bytes, flush: true);
  }

  /// Download the original, then open the Android share sheet with
  /// it attached. [sharePositionOrigin] anchors the sheet on large
  /// screens; pass the source widget's global rect when available.
  Future<void> shareOriginal(
    NovaApi api,
    NovaAsset asset, {
    Rect? sharePositionOrigin,
  }) async {
    final file = await downloadOriginal(api, asset);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path)],
        fileNameOverrides: [asset.originalFileName],
        sharePositionOrigin: sharePositionOrigin,
      ),
    );
  }

  /// Share several originals (downloads each first).
  Future<void> shareOriginals(
    NovaApi api,
    List<NovaAsset> assets, {
    Rect? sharePositionOrigin,
  }) async {
    final files = <XFile>[];
    final names = <String>[];
    for (final asset in assets) {
      final file = await downloadOriginal(api, asset);
      files.add(XFile(file.path));
      names.add(asset.originalFileName);
    }
    await SharePlus.instance.share(
      ShareParams(
        files: files,
        fileNameOverrides: names,
        sharePositionOrigin: sharePositionOrigin,
      ),
    );
  }
}
