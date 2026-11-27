/// Library tab — Favorites, Archive, Trash, device folders and
/// backup.
///
/// Favorites / Archive / Trash are metadata searches
/// (`isFavorite`, `visibility: archive`, `isTrashed` — there is no
/// `GET /trash` endpoint). Trash restores and empties through the
/// Trash API. Device folders are a read-only `photo_manager` scan
/// with counts. Backup opens the backup dashboard placeholder —
/// the real engine is Track C's job.
library;

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/asset.dart';
import '../../models/search.dart';
import '../../providers/track_b_providers.dart';
import 'asset_list_screen.dart';
import 'backup_dashboard_screen.dart';

class LibraryPage extends ConsumerWidget {
  const LibraryPage({super.key});

  void _openList(
    BuildContext context,
    String title,
    MetadataSearchRequest request, {
    bool trashMode = false,
  }) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AssetListScreen(
          title: title,
          request: request,
          trashMode: trashMode,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(libraryStatisticsProvider);
    final folders = ref.watch(deviceFoldersProvider);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        stats.when(
          data: (s) => Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _Stat('Photos', s.images),
                  _Stat('Videos', s.videos),
                  _Stat('Total', s.total),
                ],
              ),
            ),
          ),
          loading: () => const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            ),
          ),
          error: (error, _) => Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Could not load library stats.\n$error'),
            ),
          ),
        ),
        const SizedBox(height: 8),
        ListTile(
          leading: const Icon(Icons.favorite_outlined),
          title: const Text('Favorites'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _openList(
            context,
            'Favorites',
            const MetadataSearchRequest(
              isFavorite: true,
              size: 100,
              withExif: true,
            ),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.archive_outlined),
          title: const Text('Archive'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _openList(
            context,
            'Archive',
            const MetadataSearchRequest(
              visibility: AssetVisibility.archive,
              size: 100,
              withExif: true,
            ),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.delete_outlined),
          title: const Text('Trash'),
          subtitle: const Text('Restore or permanently empty.'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _openList(
            context,
            'Trash',
            const MetadataSearchRequest(
              isTrashed: true,
              size: 100,
              withExif: true,
            ),
            trashMode: true,
          ),
        ),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.cloud_upload_outlined),
          title: const Text('Backup'),
          subtitle: const Text('Backup settings and status.'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => const BackupDashboardScreen(),
            ),
          ),
        ),
        const Divider(),
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 4),
          child: Text(
            'On this device',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        const Text(
          'Read-only list of device folders with photo counts. '
          'Uploading from them is the backup engine’s job (Track C).',
        ),
        const SizedBox(height: 8),
        folders.when(
          data: (list) {
            if (list.isEmpty) {
              return const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'No device folders found. The app may not have '
                    'permission to read your photos, or there are no '
                    'local albums.',
                  ),
                ),
              );
            }
            return Column(
              children: [
                for (final folder in list)
                  ListTile(
                    leading: const Icon(Icons.folder_outlined),
                    title: Text(folder.name),
                    trailing: Text('${folder.count}'),
                  ),
              ],
            );
          },
          loading: () => const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (error, _) => Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Could not scan device folders.\n$error'),
            ),
          ),
        ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value);

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          '$value',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}
