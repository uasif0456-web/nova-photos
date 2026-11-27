/// Full-screen viewer — swipeable across the current result set
/// (timeline, album, search, memory or library list).
///
/// Images load the 1440px preview (never the original); videos play
/// from `/video/playback` with the auth headers. Pinch zoom via
/// [InteractiveViewer], double-tap toggles 1x / 2.5x. The info sheet
/// shows date, location, camera, file name and dimensions. Favorite,
/// archive, share, download, add-to-album and delete all act through
/// [AssetActionsService] / the API and refresh [photosProvider].
library;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';

import '../../models/asset.dart';
import '../../providers/providers.dart';
import '../../providers/track_b_providers.dart';
import '../widgets/selection_action_bar.dart';

class ViewerScreen extends ConsumerStatefulWidget {
  const ViewerScreen({
    super.key,
    required this.assets,
    required this.initialIndex,
  });

  final List<NovaAsset> assets;
  final int initialIndex;

  @override
  ConsumerState<ViewerScreen> createState() => _ViewerScreenState();
}

class _ViewerScreenState extends ConsumerState<ViewerScreen> {
  late final PageController _pageController;
  late List<NovaAsset> _assets;
  late int _index;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _assets = List.of(widget.assets);
    _index = widget.initialIndex.clamp(0, _assets.length - 1);
    _pageController = PageController(initialPage: _index);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  NovaAsset get _current => _assets[_index];

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _run(Future<void> Function() action, String done) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      if (done.isNotEmpty) _snack(done);
    } catch (e) {
      _snack('That did not work: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toggleFavorite() async {
    final api = ref.read(novaApiProvider);
    if (api == null) return _snack('Not signed in.');
    final asset = _current;
    final next = !asset.isFavorite;
    await _run(() async {
      final updated =
          await api.assets.setFavorite(asset.id, next);
      _replaceCurrent(updated);
      ref.read(photosProvider.notifier).updateAsset(updated);
    }, next ? 'Added to favorites' : 'Removed from favorites');
  }

  Future<void> _toggleArchive() async {
    final api = ref.read(novaApiProvider);
    if (api == null) return _snack('Not signed in.');
    final asset = _current;
    final next = !asset.isArchived;
    await _run(() async {
      final updated = await api.assets.setArchived(asset.id, next);
      _replaceCurrent(updated);
      ref.read(photosProvider.notifier).updateAsset(updated);
    }, next ? 'Archived' : 'Unarchived');
  }

  void _replaceCurrent(NovaAsset updated) {
    setState(() => _assets[_index] = updated);
  }

  Future<void> _share() async {
    final api = ref.read(novaApiProvider);
    if (api == null) return _snack('Not signed in.');
    final origin = _shareOrigin();
    await _run(
      () => ref
          .read(assetActionsProvider)
          .shareOriginal(api, _current, sharePositionOrigin: origin),
      'Shared',
    );
  }

  Rect? _shareOrigin() {
    final box = context.findRenderObject();
    if (box is RenderBox && box.hasSize) {
      return box.localToGlobal(Offset.zero) & box.size;
    }
    return null;
  }

  Future<void> _download() async {
    final api = ref.read(novaApiProvider);
    if (api == null) return _snack('Not signed in.');
    await _run(() async {
      final file = await ref
          .read(assetActionsProvider)
          .downloadOriginal(api, _current);
      _snack('Saved to ${file.path}');
    }, '');
  }

  Future<void> _delete() async {
    final api = ref.read(novaApiProvider);
    if (api == null) return _snack('Not signed in.');
    if (!await confirmDelete(context, count: 1)) return;
    await _run(() async {
      await ref.read(assetActionsProvider).delete(api, [_current.id]);
      ref.read(photosProvider.notifier).removeAssets([_current.id]);
      final removed = _current;
      setState(() => _assets.remove(removed));
      if (_assets.isEmpty) {
        if (mounted) Navigator.of(context).pop();
      } else if (_index >= _assets.length) {
        setState(() => _index = _assets.length - 1);
      }
    }, 'Moved to trash');
  }

  Future<void> _addToAlbum() async {
    final api = ref.read(novaApiProvider);
    if (api == null) return _snack('Not signed in.');
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
      if (!mounted) return;
      final name = await askAlbumName(context);
      if (name == null) return;
      final album = await ref.read(albumsProvider.notifier).create(name);
      if (album == null) return _snack('Could not create the album.');
      albumId = album.id;
    }
    await _run(() async {
      await ref
          .read(assetActionsProvider)
          .addToAlbum(api, albumId, [_current.id]);
      ref.invalidate(albumAssetsProvider(albumId));
    }, 'Added to album');
  }

  void _showMetadata() {
    final asset = _current;
    final exif = asset.exifInfo;
    final date = DateFormat('EEEE, d MMMM yyyy · HH:mm')
        .format(asset.localDateTime);
    final location = [
      if (exif?.city != null) exif!.city,
      if (exif?.country != null) exif!.country,
    ].join(', ');
    final camera = [
      if (exif?.make != null) exif!.make,
      if (exif?.model != null) exif!.model,
    ].join(' ');
    String fileSize() {
      final bytes = exif?.fileSizeInByte;
      if (bytes == null) return '—';
      if (bytes >= 1024 * 1024) {
        return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
      }
      return '${(bytes / 1024).toStringAsFixed(0)} KB';
    }

    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Details', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            _MetaRow('Date', date),
            _MetaRow('File name', asset.originalFileName),
            _MetaRow('Dimensions', '${asset.width} × ${asset.height}'),
            if (asset.isVideo && asset.duration != null)
              _MetaRow('Duration', asset.duration.toString()),
            _MetaRow('Camera', camera.isEmpty ? '—' : camera),
            _MetaRow('Location', location.isEmpty ? '—' : location),
            if (exif?.latitude != null && exif?.longitude != null)
              _MetaRow(
                'Coordinates',
                '${exif!.latitude}, ${exif.longitude}',
              ),
            _MetaRow('File size', fileSize()),
            _MetaRow('Type', asset.originalMimeType ?? asset.type.name),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_assets.isEmpty) {
      return const Scaffold(
        body: Center(child: Text('Nothing to show.')),
      );
    }
    final asset = _current;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text('${_index + 1} of ${_assets.length}'),
        actions: [
          IconButton(
            icon: Icon(
              asset.isFavorite ? Icons.favorite : Icons.favorite_outlined,
              color: asset.isFavorite ? Colors.red : Colors.white,
            ),
            tooltip: asset.isFavorite ? 'Remove from favorites' : 'Favorite',
            onPressed: _busy ? null : _toggleFavorite,
          ),
          IconButton(
            icon: Icon(
              asset.isArchived
                  ? Icons.unarchive_outlined
                  : Icons.archive_outlined,
            ),
            tooltip: asset.isArchived ? 'Unarchive' : 'Archive',
            onPressed: _busy ? null : _toggleArchive,
          ),
          IconButton(
            icon: const Icon(Icons.info_outlined),
            tooltip: 'Details',
            onPressed: _showMetadata,
          ),
          PopupMenuButton<String>(
            tooltip: 'More',
            onSelected: (value) {
              switch (value) {
                case 'share':
                  _share();
                case 'download':
                  _download();
                case 'album':
                  _addToAlbum();
                case 'delete':
                  _delete();
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'share',
                child: Text('Share'),
              ),
              PopupMenuItem(
                value: 'download',
                child: Text('Download original'),
              ),
              PopupMenuItem(
                value: 'album',
                child: Text('Add to album'),
              ),
              PopupMenuItem(
                value: 'delete',
                child: Text('Delete'),
              ),
            ],
          ),
        ],
      ),
      body: PageView.builder(
        controller: _pageController,
        itemCount: _assets.length,
        onPageChanged: (i) => setState(() => _index = i),
        itemBuilder: (context, index) => _ViewerPage(asset: _assets[index]),
      ),
      bottomNavigationBar: Container(
        color: Colors.black,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: SafeArea(
          top: false,
          child: Text(
            '${asset.originalFileName}\n'
            '${DateFormat('d MMMM yyyy · HH:mm').format(asset.localDateTime)}',
            style: const TextStyle(color: Colors.white70),
          ),
        ),
      ),
    );
  }
}

class _MetaRow extends StatelessWidget {
  const _MetaRow(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}

/// One page of the viewer: image with pinch + double-tap zoom, or
/// video with playback controls.
class _ViewerPage extends ConsumerWidget {
  const _ViewerPage({required this.asset});

  final NovaAsset asset;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (asset.isVideo) return _VideoPage(asset: asset);
    return _ImagePage(asset: asset);
  }
}

class _ImagePage extends ConsumerStatefulWidget {
  const _ImagePage({required this.asset});

  final NovaAsset asset;

  @override
  ConsumerState<_ImagePage> createState() => _ImagePageState();
}

class _ImagePageState extends ConsumerState<_ImagePage> {
  final _transformationController = TransformationController();

  @override
  void dispose() {
    _transformationController.dispose();
    super.dispose();
  }

  void _onDoubleTap() {
    final controller = _transformationController;
    if (controller.value != Matrix4.identity()) {
      controller.value = Matrix4.identity();
    } else {
      controller.value = Matrix4.diagonal3Values(2.5, 2.5, 1);
    }
  }

  @override
  Widget build(BuildContext context) {
    final headers = ref.watch(authImageHeadersProvider);
    final media = ref.watch(mediaUrlsProvider);
    final url = media?.preview(widget.asset.id).toString();
    if (url == null) {
      return const Center(
        child: Icon(Icons.broken_image_outlined, color: Colors.white54),
      );
    }
    return GestureDetector(
      onDoubleTap: _onDoubleTap,
      child: InteractiveViewer(
        transformationController: _transformationController,
        minScale: 1,
        maxScale: 4,
        child: Center(
          child: CachedNetworkImage(
            imageUrl: url,
            httpHeaders: headers,
            fit: BoxFit.contain,
            placeholder: (context, _) => const CircularProgressIndicator(
              color: Colors.white70,
            ),
            errorWidget: (context, _, _) => const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.broken_image_outlined, color: Colors.white54),
                SizedBox(height: 8),
                Text(
                  'Could not load this photo.',
                  style: TextStyle(color: Colors.white70),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _VideoPage extends ConsumerStatefulWidget {
  const _VideoPage({required this.asset});

  final NovaAsset asset;

  @override
  ConsumerState<_VideoPage> createState() => _VideoPageState();
}

class _VideoPageState extends ConsumerState<_VideoPage> {
  VideoPlayerController? _controller;
  String? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final media = ref.read(mediaUrlsProvider);
    final headers = ref.read(authImageHeadersProvider);
    if (media == null) {
      setState(() => _error = 'Not signed in.');
      return;
    }
    final controller = VideoPlayerController.networkUrl(
      media.videoPlayback(widget.asset.id),
      httpHeaders: headers,
    );
    try {
      await controller.initialize();
      controller.setLooping(true);
      await controller.play();
    } catch (e) {
      setState(() => _error = 'Could not play this video: $e');
      return;
    }
    if (mounted) setState(() => _controller = controller);
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _error!,
            style: const TextStyle(color: Colors.white70),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white70),
      );
    }
    return GestureDetector(
      onTap: () {
        if (controller.value.isPlaying) {
          controller.pause();
        } else {
          controller.play();
        }
        setState(() {});
      },
      child: Stack(
        fit: StackFit.expand,
        alignment: Alignment.center,
        children: [
          Center(
            child: AspectRatio(
              aspectRatio: controller.value.aspectRatio,
              child: VideoPlayer(controller),
            ),
          ),
          if (!controller.value.isPlaying)
            const Icon(
              Icons.play_circle_filled,
              color: Colors.white70,
              size: 64,
            ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: VideoProgressIndicator(
              controller,
              allowScrubbing: true,
              colors: const VideoProgressColors(
                playedColor: Colors.white,
                backgroundColor: Colors.white24,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
