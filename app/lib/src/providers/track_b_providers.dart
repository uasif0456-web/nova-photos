/// Track B providers — selection, timeline buckets, albums, people,
/// tags, memories, search and library lists.
///
/// These sit on top of the Track A wiring in `providers.dart`
/// ([novaApiProvider], [photosProvider]) and follow the same rule:
/// providers own the async work; widgets only watch them.
library;

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../models/album.dart';
import '../models/asset.dart';
import '../models/memory.dart';
import '../models/person.dart';
import '../models/search.dart';
import '../models/tag.dart';
import '../services/asset_actions_service.dart';
import '../services/device_folders_service.dart';
import '../utils/recent_searches.dart';
import 'providers.dart';

/// Shared asset-actions service (favorite/archive/delete/download/
/// share/add-to-album).
final assetActionsProvider = Provider<AssetActionsService>((ref) {
  return const AssetActionsService();
});

/// Multi-select state for the timeline / album / search grids.
/// Empty set means "not selecting". Widgets enter selection mode on
/// long-press and leave it when the set is cleared.
final selectionProvider =
    NotifierProvider<SelectionNotifier, Set<String>>(SelectionNotifier.new);

class SelectionNotifier extends Notifier<Set<String>> {
  @override
  Set<String> build() => const {};

  bool get isSelecting => state.isNotEmpty;

  void toggle(String id) {
    final next = {...state};
    if (next.contains(id)) {
      next.remove(id);
    } else {
      next.add(id);
    }
    state = next;
  }

  void selectAll(Iterable<String> ids) => state = {...state, ...ids};

  void clear() => state = const {};
}

/// Timeline buckets (`GET /timeline/buckets`) — one entry per month
/// with a count. The Photos tab uses these for the month-jump sheet;
/// the grid itself pages through `POST /search/metadata` (see
/// [photosProvider]) because bucket assets are only summaries.
final bucketsProvider =
    AsyncNotifierProvider<BucketsNotifier, List<TimeBucket>>(BucketsNotifier.new);

class BucketsNotifier extends AsyncNotifier<List<TimeBucket>> {
  @override
  Future<List<TimeBucket>> build() async {
    final api = ref.read(novaApiProvider);
    if (api == null) return const [];
    return api.timeline.getBuckets();
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(build);
  }
}

/// Albums list (`GET /albums`) with create / rename / delete.
final albumsProvider =
    AsyncNotifierProvider<AlbumsNotifier, List<Album>>(AlbumsNotifier.new);

class AlbumsNotifier extends AsyncNotifier<List<Album>> {
  @override
  Future<List<Album>> build() async {
    final api = ref.read(novaApiProvider);
    if (api == null) return const [];
    return api.albums.listAlbums();
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(build);
  }

  Future<Album?> create(String name) async {
    final api = ref.read(novaApiProvider);
    if (api == null) return null;
    final album = await api.albums.createAlbum(albumName: name);
    await refresh();
    return album;
  }

  Future<void> rename(String id, String name) async {
    final api = ref.read(novaApiProvider);
    if (api == null) return;
    await api.albums.updateAlbum(id, albumName: name);
    await refresh();
  }

  Future<void> delete(String id) async {
    final api = ref.read(novaApiProvider);
    if (api == null) return;
    await api.albums.deleteAlbum(id);
    await refresh();
  }
}

/// Assets of one album. Albums never embed assets in v3 — this loads
/// them via `POST /search/metadata` with `albumIds`.
final albumAssetsProvider =
    FutureProvider.family<List<NovaAsset>, String>((ref, albumId) async {
  final api = ref.watch(novaApiProvider);
  if (api == null) return const [];
  return api.search.searchMetadataAllAssets(
    MetadataSearchRequest(
      albumIds: [albumId],
      size: 100,
      withExif: true,
    ),
  );
});

/// People (`GET /people`) — faces are server-side; the app never
/// runs face recognition locally.
final peopleProvider = FutureProvider<List<Person>>((ref) async {
  final api = ref.watch(novaApiProvider);
  if (api == null) return const [];
  return api.people.listPeople();
});

/// Tags (`GET /tags`).
final tagsProvider = FutureProvider<List<Tag>>((ref) async {
  final api = ref.watch(novaApiProvider);
  if (api == null) return const [];
  return api.tags.listTags();
});

/// Memory lanes (`GET /memories`) — server-provided "on this day".
final memoriesProvider =
    AsyncNotifierProvider<MemoriesNotifier, List<Memory>>(MemoriesNotifier.new);

class MemoriesNotifier extends AsyncNotifier<List<Memory>> {
  @override
  Future<List<Memory>> build() async {
    final api = ref.read(novaApiProvider);
    if (api == null) return const [];
    return api.memories.listMemories();
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(build);
  }

  /// Hide a memory lane (server `hideAt`); it drops out of the list.
  Future<void> hide(String id) async {
    final api = ref.read(novaApiProvider);
    if (api == null) return;
    await api.memories.updateMemory(id, hideAt: DateTime.now());
    state = AsyncData(
      (state.value ?? const []).where((m) => m.id != id).toList(),
    );
  }

  /// Save (pin) a memory lane.
  Future<void> save(String id, bool isSaved) async {
    final api = ref.read(novaApiProvider);
    if (api == null) return;
    final updated = await api.memories.updateMemory(id, isSaved: isSaved);
    state = AsyncData(
      (state.value ?? const [])
          .map((m) => m.id == id ? updated : m)
          .toList(),
    );
  }
}

/// Search suggestions (`GET /search/suggestions`).
final searchSuggestionsProvider = FutureProvider<List<String>>((ref) async {
  final api = ref.watch(novaApiProvider);
  if (api == null) return const [];
  return api.search.suggestions();
});

/// Places (`GET /search/places`) — named places with coordinates.
final searchPlacesProvider = FutureProvider<List<SearchPlace>>((ref) async {
  final api = ref.watch(novaApiProvider);
  if (api == null) return const [];
  return api.search.listPlaces();
});

/// Cities (`GET /search/cities`) — one representative asset per city;
/// the Search screen derives distinct city names from their EXIF.
final searchCityAssetsProvider =
    FutureProvider<List<NovaAsset>>((ref) async {
  final api = ref.watch(novaApiProvider);
  if (api == null) return const [];
  return api.search.cityAssets();
});

/// Directory the recent-searches file lives in (overridable in tests).
final recentSearchesDirectoryProvider =
    Provider<Future<Directory> Function()>((ref) {
  return getApplicationSupportDirectory;
});

/// Recent smart-search queries, persisted locally (see
/// [RecentSearchesStore]). Most recent first.
final recentSearchesProvider = AsyncNotifierProvider<
    RecentSearchesNotifier, List<String>>(RecentSearchesNotifier.new);

class RecentSearchesNotifier extends AsyncNotifier<List<String>> {
  RecentSearchesStore get _store => RecentSearchesStore(
        directory: ref.read(recentSearchesDirectoryProvider),
      );

  @override
  Future<List<String>> build() => _store.load();

  Future<void> add(String query) async {
    state = AsyncData(await _store.add(query));
  }

  Future<void> remove(String query) async {
    state = AsyncData(await _store.remove(query));
  }

  Future<void> clear() async {
    await _store.clear();
    state = const AsyncData([]);
  }
}

/// Filters for a metadata search from the Search screen.
class SearchFilters {
  const SearchFilters({
    this.type,
    this.isFavorite,
    this.takenAfter,
    this.takenBefore,
    this.city,
    this.personId,
    this.tagId,
  });

  final AssetType? type;
  final bool? isFavorite;
  final DateTime? takenAfter;
  final DateTime? takenBefore;
  final String? city;
  final String? personId;
  final String? tagId;

  bool get isEmpty =>
      type == null &&
      isFavorite == null &&
      takenAfter == null &&
      takenBefore == null &&
      city == null &&
      personId == null &&
      tagId == null;

  SearchFilters copyWith({
    AssetType? type,
    bool? isFavorite,
    DateTime? takenAfter,
    DateTime? takenBefore,
    String? city,
    String? personId,
    String? tagId,
  }) {
    return SearchFilters(
      type: type ?? this.type,
      isFavorite: isFavorite ?? this.isFavorite,
      takenAfter: takenAfter ?? this.takenAfter,
      takenBefore: takenBefore ?? this.takenBefore,
      city: city ?? this.city,
      personId: personId ?? this.personId,
      tagId: tagId ?? this.tagId,
    );
  }
}

/// The outcome of one search run.
class SearchOutcome {
  const SearchOutcome({
    required this.assets,
    required this.albums,
    required this.query,
    required this.isSmart,
  });

  final List<NovaAsset> assets;
  final List<Album> albums;

  /// The query text (smart search) or a description of the filters.
  final String query;
  final bool isSmart;
}

/// Search state: null until the first search runs.
final searchProvider =
    AsyncNotifierProvider<SearchNotifier, SearchOutcome?>(SearchNotifier.new);

class SearchNotifier extends AsyncNotifier<SearchOutcome?> {
  @override
  Future<SearchOutcome?> build() async => null;

  MetadataSearchRequest _metadataRequest(SearchFilters filters) {
    return MetadataSearchRequest(
      type: filters.type,
      isFavorite: filters.isFavorite,
      takenAfter: filters.takenAfter,
      takenBefore: filters.takenBefore,
      city: filters.city,
      personIds:
          filters.personId == null ? null : [filters.personId!],
      tagIds: filters.tagId == null ? null : [filters.tagId!],
      size: 100,
      withExif: true,
    );
  }

  /// Smart (CLIP) search for [query]; records it in recent searches.
  Future<void> runSmart(String query, {SearchFilters? filters}) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;
    final api = ref.read(novaApiProvider);
    if (api == null) return;
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final f = filters ?? const SearchFilters();
      final result = await api.search.smartSearch(
        SmartSearchRequest(
          query: trimmed,
          type: f.type,
          isFavorite: f.isFavorite,
          takenAfter: f.takenAfter,
          takenBefore: f.takenBefore,
        ),
      );
      await ref.read(recentSearchesProvider.notifier).add(trimmed);
      return SearchOutcome(
        assets: result.items,
        albums: result.albums,
        query: trimmed,
        isSmart: true,
      );
    });
  }

  /// Metadata search with [filters] (no query text).
  Future<void> runMetadata(SearchFilters filters) async {
    final api = ref.read(novaApiProvider);
    if (api == null) return;
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final result =
          await api.search.searchMetadata(_metadataRequest(filters));
      return SearchOutcome(
        assets: result.items,
        albums: result.albums,
        query: _describeFilters(filters),
        isSmart: false,
      );
    });
  }

  /// Metadata search for one person / tag / city, used by the
  /// Collections and Search screens.
  Future<void> runForPerson(String personId, String name) =>
      runMetadata(SearchFilters(personId: personId));

  Future<void> runForCity(String city) =>
      runMetadata(SearchFilters(city: city));

  Future<void> runForTag(String tagId) =>
      runMetadata(SearchFilters(tagId: tagId));

  void clear() => state = const AsyncData(null);

  String _describeFilters(SearchFilters f) {
    final parts = <String>[];
    if (f.type != null) parts.add(f.type!.name);
    if (f.isFavorite == true) parts.add('favorites');
    if (f.city != null) parts.add(f.city!);
    if (f.personId != null) parts.add('person');
    if (f.tagId != null) parts.add('tag');
    if (f.takenAfter != null || f.takenBefore != null) {
      parts.add('date range');
    }
    return parts.isEmpty ? 'Filtered search' : parts.join(' · ');
  }
}

/// Library lists (Favorites / Archive / Trash), each a metadata
/// search. Trash assets come from `isTrashed: true` — there is no
/// `GET /trash` endpoint in the API.
enum LibraryList { favorites, archive, trash }

final libraryAssetsProvider =
    FutureProvider.family<List<NovaAsset>, LibraryList>((ref, list) async {
  final api = ref.watch(novaApiProvider);
  if (api == null) return const [];
  final request = switch (list) {
    LibraryList.favorites => const MetadataSearchRequest(
        isFavorite: true,
        size: 100,
        withExif: true,
      ),
    LibraryList.archive => const MetadataSearchRequest(
        visibility: AssetVisibility.archive,
        size: 100,
        withExif: true,
      ),
    LibraryList.trash => const MetadataSearchRequest(
        isTrashed: true,
        size: 100,
        withExif: true,
      ),
  };
  return api.search.searchMetadataAllAssets(request);
});

/// Library statistics (`GET /assets/statistics`).
final libraryStatisticsProvider =
    FutureProvider<AssetStatistics>((ref) async {
  final api = ref.watch(novaApiProvider);
  if (api == null) return const AssetStatistics(images: 0, videos: 0, total: 0);
  return api.assets.getStatistics();
});

/// Device folders (`photo_manager` scan, read-only list with counts).
final deviceFoldersProvider =
    FutureProvider<List<DeviceFolder>>((ref) async {
  return const DeviceFoldersService().listFolders();
});
