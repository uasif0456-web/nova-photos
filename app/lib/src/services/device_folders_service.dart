/// Device folders — a read-only scan of the device's local media
/// folders via `photo_manager` (Track C owns backup/upload; this is
/// only the Library screen's "On this device" list with counts).
///
/// Returns an empty list when permission is denied or unavailable —
/// the Library screen shows a "permission needed" state instead of
/// an error, because the server library is the primary content.
library;

import 'package:photo_manager/photo_manager.dart';

/// One local folder (album) on the device.
class DeviceFolder {
  const DeviceFolder({
    required this.id,
    required this.name,
    required this.count,
  });

  final String id;
  final String name;
  final int count;
}

class DeviceFoldersService {
  const DeviceFoldersService();

  Future<List<DeviceFolder>> listFolders() async {
    final permission = await PhotoManager.requestPermissionExtend();
    if (!permission.hasAccess) return const [];
    final paths = await PhotoManager.getAssetPathList(
      type: RequestType.all,
    );
    final folders = <DeviceFolder>[];
    for (final path in paths) {
      final count = await path.assetCountAsync;
      folders.add(DeviceFolder(
        id: path.id,
        name: path.name.isEmpty ? 'All photos' : path.name,
        count: count,
      ));
    }
    folders.sort((a, b) => b.count.compareTo(a.count));
    return folders;
  }
}
