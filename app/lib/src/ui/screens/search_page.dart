/// Search tab — smart (CLIP) search plus filtered metadata search.
///
/// - Query field runs `POST /search/smart` (gated on the server's
///   smart-search feature in the login flow; an error here surfaces
///   plainly).
/// - Recent searches persist locally ([recentSearchesProvider]).
/// - Suggestions come from `GET /search/suggestions`.
/// - People results come from `GET /people` (filtered locally by
///   name); places from `GET /search/places`; cities from
///   `GET /search/cities` (representative assets' EXIF cities).
/// - Filters (media type, favorites, date range) run through
///   `POST /search/metadata`.
/// Results reuse the shared [AssetGrid] and open the viewer.
library;

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/asset.dart';
import '../../models/search.dart';
import '../../providers/track_b_providers.dart';
import '../selection_actions.dart';
import '../widgets/asset_grid.dart';

class SearchPage extends ConsumerStatefulWidget {
  const SearchPage({super.key});

  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage> {
  final _controller = TextEditingController();
  SearchFilters _filters = const SearchFilters();
  bool _showFilters = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _runSmart() async {
    final query = _controller.text.trim();
    if (query.isEmpty) return;
    FocusScope.of(context).unfocus();
    await ref.read(searchProvider.notifier).runSmart(query, filters: _filters);
  }

  Future<void> _runFilters() async {
    FocusScope.of(context).unfocus();
    await ref.read(searchProvider.notifier).runMetadata(_filters);
  }

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(1990),
      lastDate: now,
      initialDateRange: _filters.takenAfter != null && _filters.takenBefore != null
          ? DateTimeRange(start: _filters.takenAfter!, end: _filters.takenBefore!)
          : null,
    );
    if (range == null) return;
    setState(() {
      _filters = _filters.copyWith(
        takenAfter: range.start,
        takenBefore: range.end,
      );
    });
  }

  void _clearDateRange() {
    setState(() {
      _filters = SearchFilters(
        type: _filters.type,
        isFavorite: _filters.isFavorite,
        city: _filters.city,
        personId: _filters.personId,
        tagId: _filters.tagId,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final search = ref.watch(searchProvider);
    final recent = ref.watch(recentSearchesProvider);
    final suggestions = ref.watch(searchSuggestionsProvider);
    final people = ref.watch(peopleProvider);
    final places = ref.watch(searchPlacesProvider);
    final cityAssets = ref.watch(searchCityAssetsProvider);
    final query = _controller.text.trim().toLowerCase();
    final matchingPeople = people.value
            ?.where((p) => query.isEmpty || p.name.toLowerCase().contains(query))
            .map((p) => (id: p.id, name: p.name))
            .toList() ??
        const [];
    final matchingPlaces = places.value
            ?.where((p) => query.isEmpty || p.name.toLowerCase().contains(query))
            .toList() ??
        const [];
    final cities = <String>{
      for (final asset in cityAssets.value ?? const [])
        if (asset.exifInfo?.city != null) asset.exifInfo!.city!,
    }.toList()
      ..sort();
    final matchingCities = cities
        .where((c) => query.isEmpty || c.toLowerCase().contains(query))
        .toList();
    final matchingSuggestions = suggestions.value
            ?.where((s) => query.isNotEmpty && s.toLowerCase().contains(query))
            .take(5)
            .toList() ??
        const [];

    final outcome = search.value;
    final hasResults = outcome != null;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: TextField(
            controller: _controller,
            decoration: InputDecoration(
              hintText: 'Search photos… (e.g. “sunset at the beach”)',
              prefixIcon: const Icon(Icons.search_outlined),
              suffixIcon: _controller.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        setState(() => _controller.clear());
                        ref.read(searchProvider.notifier).clear();
                      },
                    ),
            ),
            textInputAction: TextInputAction.search,
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _runSmart(),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              FilterChip(
                label: const Text('Filters'),
                selected: _showFilters,
                onSelected: (v) => setState(() => _showFilters = v),
              ),
              const SizedBox(width: 8),
              if (_filters.type != null)
                Chip(
                  label: Text(_filters.type!.name),
                  onDeleted: () => setState(() {
                    _filters = SearchFilters(
                      isFavorite: _filters.isFavorite,
                      takenAfter: _filters.takenAfter,
                      takenBefore: _filters.takenBefore,
                      city: _filters.city,
                    );
                  }),
                ),
              if (_filters.isFavorite == true)
                const SizedBox(width: 8),
              if (_filters.isFavorite == true)
                Chip(
                  label: const Text('Favorites'),
                  onDeleted: () => setState(() {
                    _filters = SearchFilters(
                      type: _filters.type,
                      takenAfter: _filters.takenAfter,
                      takenBefore: _filters.takenBefore,
                      city: _filters.city,
                    );
                  }),
                ),
            ],
          ),
        ),
        if (_showFilters)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('All'),
                  selected: _filters.type == null,
                  onSelected: (_) => setState(() {
                    _filters = SearchFilters(
                      isFavorite: _filters.isFavorite,
                      takenAfter: _filters.takenAfter,
                      takenBefore: _filters.takenBefore,
                      city: _filters.city,
                    );
                  }),
                ),
                ChoiceChip(
                  label: const Text('Photos'),
                  selected: _filters.type == AssetType.image,
                  onSelected: (_) => setState(() {
                    _filters = _filters.copyWith(type: AssetType.image);
                  }),
                ),
                ChoiceChip(
                  label: const Text('Videos'),
                  selected: _filters.type == AssetType.video,
                  onSelected: (_) => setState(() {
                    _filters = _filters.copyWith(type: AssetType.video);
                  }),
                ),
                FilterChip(
                  label: const Text('Favorites only'),
                  selected: _filters.isFavorite == true,
                  onSelected: (v) => setState(() {
                    _filters = SearchFilters(
                      type: _filters.type,
                      isFavorite: v ? true : null,
                      takenAfter: _filters.takenAfter,
                      takenBefore: _filters.takenBefore,
                      city: _filters.city,
                    );
                  }),
                ),
                ActionChip(
                  label: Text(
                    _filters.takenAfter == null
                        ? 'Date range'
                        : '${_filters.takenAfter!.day}/${_filters.takenAfter!.month}/${_filters.takenAfter!.year} – ${_filters.takenBefore!.day}/${_filters.takenBefore!.month}/${_filters.takenBefore!.year}',
                  ),
                  onPressed: _pickDateRange,
                ),
                if (_filters.takenAfter != null)
                  ActionChip(
                    label: const Text('Clear dates'),
                    onPressed: _clearDateRange,
                  ),
                FilledButton(
                  onPressed: _runFilters,
                  child: const Text('Apply filters'),
                ),
              ],
            ),
          ),
        const SizedBox(height: 8),
        Expanded(
          child: search.when(
            data: (_) {
              if (!hasResults) {
                return _BrowseView(
                recent: recent.value ?? const [],
                matchingPeople: matchingPeople,
                matchingPlaces: matchingPlaces,
                matchingCities: matchingCities,
                matchingSuggestions: matchingSuggestions,
                onRecentTap: (q) {
                  _controller.text = q;
                  _runSmart();
                },
                onRecentDelete: (q) => ref
                    .read(recentSearchesProvider.notifier)
                    .remove(q),
                onClearRecent: () =>
                    ref.read(recentSearchesProvider.notifier).clear(),
                onPersonTap: (person) async {
                  await ref.read(searchProvider.notifier).runForPerson(
                        person.id,
                        person.name,
                      );
                },
                onPlaceTap: (place) async {
                  await ref
                      .read(searchProvider.notifier)
                      .runMetadata(SearchFilters(city: place.name));
                },
                onCityTap: (city) async {
                  await ref
                      .read(searchProvider.notifier)
                      .runForCity(city);
                },
                onSuggestionTap: (s) {
                  _controller.text = s;
                  _runSmart();
                },
              );
              }
              final assets = outcome.assets;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Results for “${outcome.query}”'
                            '${outcome.isSmart ? '' : ' (filtered)'}'
                            ' — ${assets.length} photos',
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                        ),
                        TextButton(
                          onPressed: () {
                            _controller.clear();
                            ref.read(searchProvider.notifier).clear();
                          },
                          child: const Text('Clear'),
                        ),
                      ],
                    ),
                  ),
                  if (outcome.albums.isNotEmpty)
                    SizedBox(
                      height: 48,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: outcome.albums.length,
                        itemBuilder: (context, i) {
                          final album = outcome.albums[i];
                          return Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ActionChip(
                              avatar: const Icon(
                                Icons.photo_album_outlined,
                                size: 18,
                              ),
                              label: Text(album.albumName),
                              onPressed: () {},
                            ),
                          );
                        },
                      ),
                    ),
                  Expanded(
                    child: assets.isEmpty
                        ? const Center(
                            child: Padding(
                              padding: EdgeInsets.all(32),
                              child: Text(
                                'No matches.\nTry a different word, or '
                                'clear the filters.',
                                textAlign: TextAlign.center,
                              ),
                            ),
                          )
                        : AssetGrid(
                            assets: assets,
                            onOpen: (i) => openViewer(context, assets, i),
                          ),
                  ),
                ],
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.search_off_outlined, size: 48),
                    const SizedBox(height: 12),
                    Text(
                      'Search did not work.\n$error',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: _runSmart,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _BrowseView extends ConsumerWidget {
  const _BrowseView({
    required this.recent,
    required this.matchingPeople,
    required this.matchingPlaces,
    required this.matchingCities,
    required this.matchingSuggestions,
    required this.onRecentTap,
    required this.onRecentDelete,
    required this.onClearRecent,
    required this.onPersonTap,
    required this.onPlaceTap,
    required this.onCityTap,
    required this.onSuggestionTap,
  });

  final List<String> recent;
  final List<({String id, String name})> matchingPeople;
  final List<SearchPlace> matchingPlaces;
  final List<String> matchingCities;
  final List<String> matchingSuggestions;
  final void Function(String query) onRecentTap;
  final void Function(String query) onRecentDelete;
  final VoidCallback onClearRecent;
  final void Function(({String id, String name}) person) onPersonTap;
  final void Function(SearchPlace place) onPlaceTap;
  final void Function(String city) onCityTap;
  final void Function(String suggestion) onSuggestionTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      children: [
        if (matchingSuggestions.isNotEmpty) ...[
          _SectionTitle('Suggestions'),
          for (final s in matchingSuggestions)
            ListTile(
              leading: const Icon(Icons.search_outlined),
              title: Text(s),
              onTap: () => onSuggestionTap(s),
            ),
        ],
        if (matchingPeople.isNotEmpty) ...[
          _SectionTitle('People'),
          for (final person in matchingPeople)
            ListTile(
              leading: const Icon(Icons.person_outlined),
              title: Text(person.name),
              onTap: () => onPersonTap(person),
            ),
        ],
        if (matchingPlaces.isNotEmpty) ...[
          _SectionTitle('Places'),
          for (final place in matchingPlaces)
            ListTile(
              leading: const Icon(Icons.place_outlined),
              title: Text(place.label),
              onTap: () => onPlaceTap(place),
            ),
        ],
        if (matchingCities.isNotEmpty) ...[
          _SectionTitle('Cities'),
          Wrap(
            spacing: 8,
            children: [
              for (final city in matchingCities)
                ActionChip(
                  label: Text(city),
                  onPressed: () => onCityTap(city),
                ),
            ],
          ),
        ],
        if (recent.isNotEmpty) ...[
          Row(
            children: [
              const _SectionTitle('Recent searches'),
              const Spacer(),
              TextButton(
                onPressed: onClearRecent,
                child: const Text('Clear all'),
              ),
            ],
          ),
          Wrap(
            spacing: 8,
            children: [
              for (final q in recent)
                Chip(
                  label: Text(q),
                  deleteIcon: const Icon(Icons.close, size: 16),
                  onDeleted: () => onRecentDelete(q),
                ),
            ],
          ),
        ],
        if (recent.isEmpty &&
            matchingPeople.isEmpty &&
            matchingPlaces.isEmpty &&
            matchingCities.isEmpty &&
            matchingSuggestions.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 64),
            child: Column(
              children: [
                Icon(Icons.search_outlined, size: 64),
                SizedBox(height: 16),
                Text(
                  'Search your photos by what is in them.\n'
                  'Try “sunset”, “birthday” or a place name.',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 4),
      child: Text(text, style: Theme.of(context).textTheme.titleMedium),
    );
  }
}
