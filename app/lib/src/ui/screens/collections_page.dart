/// Collections tab — albums, people, tags.
///
/// Albums list `GET /albums` with covers (the album thumbnail asset
/// or a placeholder); album detail loads assets via search with
/// `albumIds` — albums never embed assets in v3. People come from
/// `GET /people` (face thumbnails via the server thumbnail URL);
/// tags from `GET /tags`.
library;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/search.dart';
import '../../providers/providers.dart';
import '../../providers/track_b_providers.dart';
import '../widgets/selection_action_bar.dart';
import 'album_detail_screen.dart';
import 'asset_list_screen.dart';

class CollectionsPage extends ConsumerWidget {
  const CollectionsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 3,
      child: Column(
        children: [
          const TabBar(
            tabs: [
              Tab(text: 'Albums'),
              Tab(text: 'People'),
              Tab(text: 'Tags'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _AlbumsTab(),
                _PeopleTab(),
                _TagsTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AlbumsTab extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final albums = ref.watch(albumsProvider);
    final headers = ref.watch(authImageHeadersProvider);
    final media = ref.watch(mediaUrlsProvider);
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final name = await askAlbumName(context);
          if (name == null) return;
          await ref.read(albumsProvider.notifier).create(name);
        },
        icon: const Icon(Icons.add),
        label: const Text('New album'),
      ),
      body: albums.when(
        data: (list) {
          if (list.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'No albums yet.\nTap “New album” to make one, then add '
                  'photos to it.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: () => ref.read(albumsProvider.notifier).refresh(),
            child: ListView.builder(
              padding: const EdgeInsets.all(8),
              itemCount: list.length,
              itemBuilder: (context, index) {
                final album = list[index];
                final coverId = album.albumThumbnailAssetId;
                return Card(
                  clipBehavior: Clip.antiAlias,
                  child: ListTile(
                    leading: SizedBox(
                      width: 56,
                      height: 56,
                      child: coverId == null || media == null
                          ? Container(
                              color: Theme.of(context)
                                  .colorScheme
                                  .surfaceContainerHighest,
                              child: const Icon(
                                Icons.photo_album_outlined,
                              ),
                            )
                          : CachedNetworkImage(
                              imageUrl: media
                                  .thumbnail(coverId, size: 'thumbnail')
                                  .toString(),
                              httpHeaders: headers,
                              fit: BoxFit.cover,
                              errorWidget: (context, _, _) => const Icon(
                                Icons.photo_album_outlined,
                              ),
                            ),
                    ),
                    title: Text(album.albumName),
                    subtitle: Text(
                      '${album.assetCount} photos'
                      '${album.shared ? ' · Shared' : ''}'
                      '${album.hasSharedLink ? ' · Has a shared link' : ''}',
                    ),
                    trailing: album.shared
                        ? const Icon(Icons.people_outlined)
                        : null,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => AlbumDetailScreen(album: album),
                      ),
                    ),
                  ),
                );
              },
            ),
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
                Text('Could not load albums.\n$error',
                    textAlign: TextAlign.center),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () =>
                      ref.read(albumsProvider.notifier).refresh(),
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

class _PeopleTab extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final people = ref.watch(peopleProvider);
    final headers = ref.watch(authImageHeadersProvider);
    final media = ref.watch(mediaUrlsProvider);
    return people.when(
      data: (list) {
        final visible = list.where((p) => !p.isHidden).toList();
        if (visible.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: Text(
                'No people found.\nFaces appear here once the server has '
                'recognised them.',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }
        return GridView.builder(
          padding: const EdgeInsets.all(16),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
            childAspectRatio: 0.8,
          ),
          itemCount: visible.length,
          itemBuilder: (context, index) {
            final person = visible[index];
            final name =
                person.name.isEmpty ? 'Unnamed' : person.name;
            return InkWell(
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => AssetListScreen(
                    title: name,
                    request: MetadataSearchRequest(
                      personIds: [person.id],
                      size: 100,
                      withExif: true,
                    ),
                  ),
                ),
              ),
              child: Column(
                children: [
                  Expanded(
                    child: ClipOval(
                      child: CachedNetworkImage(
                        imageUrl: media
                                ?.personThumbnail(person.id)
                                .toString() ??
                            '',
                        httpHeaders: headers,
                        fit: BoxFit.cover,
                        width: double.infinity,
                        placeholder: (context, _) => Container(
                          color: Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest,
                          child: const Icon(Icons.person_outlined),
                        ),
                        errorWidget: (context, _, _) => Container(
                          color: Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest,
                          child: const Icon(Icons.person_outlined),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    name,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            );
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(
        child: Text('Could not load people.\n$error',
            textAlign: TextAlign.center),
      ),
    );
  }
}

class _TagsTab extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tags = ref.watch(tagsProvider);
    return tags.when(
      data: (list) {
        if (list.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: Text(
                'No tags yet.\nTags you add to photos appear here.',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(8),
          itemCount: list.length,
          itemBuilder: (context, index) {
            final tag = list[index];
            return ListTile(
              leading: const Icon(Icons.label_outlined),
              title: Text(tag.value),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => AssetListScreen(
                    title: tag.value,
                    request: MetadataSearchRequest(
                      tagIds: [tag.id],
                      size: 100,
                      withExif: true,
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(
        child: Text('Could not load tags.\n$error',
            textAlign: TextAlign.center),
      ),
    );
  }
}
