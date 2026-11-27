/// Recent searches — persisted locally as a small JSON file in the
/// app support directory (no new dependency: `shared_preferences`
/// was deliberately not added for one string list).
///
/// The directory is injected so tests can point it at a temp dir;
/// production passes `getApplicationSupportDirectory`.
library;

import 'dart:convert';
import 'dart:io';

/// A store for the Search screen's recent queries. Most recent first,
/// capped at [maxEntries].
class RecentSearchesStore {
  RecentSearchesStore({
    required this.directory,
    this.maxEntries = 20,
  });

  /// Resolves the directory the JSON file lives in.
  final Future<Directory> Function() directory;
  final int maxEntries;

  static const _fileName = 'recent_searches.json';

  Future<File> _file() async {
    final dir = await directory();
    return File('${dir.path}/$_fileName');
  }

  Future<List<String>> load() async {
    try {
      final file = await _file();
      if (!await file.exists()) return const [];
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! List) return const [];
      return decoded
          .whereType<String>()
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .take(maxEntries)
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  Future<List<String>> add(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return load();
    final current = await load();
    final next = [
      trimmed,
      ...current.where((q) => q.toLowerCase() != trimmed.toLowerCase()),
    ].take(maxEntries).toList(growable: false);
    await _save(next);
    return next;
  }

  Future<List<String>> remove(String query) async {
    final current = await load();
    final next = current
        .where((q) => q.toLowerCase() != query.toLowerCase())
        .toList(growable: false);
    await _save(next);
    return next;
  }

  Future<void> clear() async => _save(const []);

  Future<void> _save(List<String> entries) async {
    final file = await _file();
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(entries));
  }
}
