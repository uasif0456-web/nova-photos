/// Riverpod providers — the wiring between services and UI.
///
/// Layers:
/// - [tokenStoreProvider]: secure storage (overridable in tests).
/// - [authServiceProvider]: the auth service.
/// - [authStateProvider]: the current session (async — restores the
///   stored session on launch).
/// - [novaApiProvider]: the API facade for the current server.
/// - [photosProvider]: the Photos tab's asset list (real data from
///   `POST /search/metadata`, paged).
/// - [backupStatusProvider]: the app-bar backup indicator.
///
/// No business logic lives in widgets; widgets only watch these.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../api/nova_api.dart';
import '../models/asset.dart';
import '../models/search.dart';
import '../services/auth_service.dart';
import '../services/backup_engine.dart';
import '../services/backup_service.dart';
import '../services/backup_settings.dart';
import '../services/pending_ops_service.dart';
import '../services/sync_service.dart';
import '../services/thumbnail_cache_service.dart';
import '../services/token_store.dart';
import '../store/nova_database.dart';

/// Secure storage. Override with [InMemoryTokenStore] in tests.
final tokenStoreProvider = Provider<TokenStore>((ref) {
  return SecureTokenStore();
});

/// Auth service (login / logout / session restore / version gating).
final authServiceProvider = Provider<AuthService>((ref) {
  final store = ref.watch(tokenStoreProvider);
  final service = AuthService(tokenStore: store);
  ref.onDispose(() => service.client?.close());
  return service;
});

/// Current session. On first build this restores the stored session
/// (validateToken + /users/me + version + features); null means
/// "not signed in" and the login screen is shown.
final authStateProvider =
    AsyncNotifierProvider<AuthStateNotifier, NovaSession?>(() {
  return AuthStateNotifier();
});

class AuthStateNotifier extends AsyncNotifier<NovaSession?> {
  @override
  Future<NovaSession?> build() async {
    final auth = ref.read(authServiceProvider);
    return auth.restoreSession();
  }

  Future<NovaSession> login({
    required String email,
    required String password,
  }) async {
    state = const AsyncLoading();
    final auth = ref.read(authServiceProvider);
    final session = await auth.login(email: email, password: password);
    state = AsyncData(session);
    return session;
  }

  Future<void> logout() async {
    final auth = ref.read(authServiceProvider);
    ref.read(novaApiProvider)?.socket.disconnect();
    await auth.logout();
    state = const AsyncData(null);
    ref.invalidate(novaApiProvider);
    ref.invalidate(photosProvider);
    ref.invalidate(syncServiceProvider);
    ref.invalidate(pendingOpsServiceProvider);
    ref.invalidate(backupEngineProvider);
    ref.invalidate(backupSettingsProvider);
  }
}

/// API facade for the current server. Null until a server URL is known
/// (after a probe or a session restore).
final novaApiProvider = Provider<NovaApi?>((ref) {
  final auth = ref.watch(authServiceProvider);
  final client = auth.client;
  if (client == null) return null;
  return NovaApi(client);
});

/// Backup status for the app-bar indicator (Track C: real engine
/// state). [BackupService] owns the status; this provider re-emits
/// every update, so the chip shows live progress.
final backupServiceProvider = Provider<BackupService>((ref) {
  final service = BackupService();
  ref.onDispose(service.dispose);
  return service;
});

final backupStatusProvider = StreamProvider<BackupStatus>((ref) {
  return ref.watch(backupServiceProvider).stream;
});

/// Local Drift database. Opened once in `main()` (async — the file
/// path comes from `path_provider`) and injected here via a
/// `ProviderScope` override. Tests override it with
/// `NovaDatabase.memory()`. Never construct a second instance.
final databaseProvider = Provider<NovaDatabase>((ref) {
  throw StateError(
    'NovaDatabase not initialized — main() must override '
    'databaseProvider with the opened database.',
  );
});

/// Sync engine (null until signed in — it needs a live [NovaApi]).
final syncServiceProvider = Provider<SyncService?>((ref) {
  final api = ref.watch(novaApiProvider);
  if (api == null) return null;
  final db = ref.watch(databaseProvider);
  final service = SyncService(api: api, db: db);
  ref.onDispose(service.dispose);
  return service;
});

/// Offline pending-operations queue (null until signed in).
final pendingOpsServiceProvider = Provider<PendingOpsService?>((ref) {
  final api = ref.watch(novaApiProvider);
  if (api == null) return null;
  final db = ref.watch(databaseProvider);
  final service = PendingOpsService(api: api, db: db);
  ref.onDispose(service.dispose);
  return service;
});

/// Backup engine (null until signed in). The scanner is the real
/// `photo_manager` one; tests inject a fake via overrides.
final backupEngineProvider = Provider<BackupEngine?>((ref) {
  final api = ref.watch(novaApiProvider);
  if (api == null) return null;
  final db = ref.watch(databaseProvider);
  final backupService = ref.watch(backupServiceProvider);
  return BackupEngine(
    api: api,
    db: db,
    backupService: backupService,
    scanner: PhotoManagerScanner(),
  );
});

/// Thumbnail disk-cache service (size display + clear action).
final thumbnailCacheServiceProvider =
    Provider<ThumbnailCacheService>((ref) {
  return ThumbnailCacheService();
});

/// Backup preferences, loaded from the Drift `settings` table.
final backupSettingsProvider =
    FutureProvider<BackupSettings>((ref) async {
  final engine = ref.watch(backupEngineProvider);
  if (engine == null) return const BackupSettings();
  return engine.loadSettings();
});

/// Photos tab state: the first page of the user's library, newest
/// first, loaded from `POST /search/metadata`.
final photosProvider =
    AsyncNotifierProvider<PhotosNotifier, List<NovaAsset>>(() {
  return PhotosNotifier();
});

class PhotosNotifier extends AsyncNotifier<List<NovaAsset>> {
  SearchResult? _lastPage;
  final MetadataSearchRequest _request =
      const MetadataSearchRequest(size: 100);

  @override
  Future<List<NovaAsset>> build() async {
    return _loadFirstPage();
  }

  Future<List<NovaAsset>> _loadFirstPage() async {
    final api = ref.read(novaApiProvider);
    if (api == null) return const [];
    final page = await api.search.searchMetadata(_request);
    _lastPage = page;
    return page.items;
  }

  /// Load the next page (if any) and append it to the grid.
  Future<void> loadMore() async {
    final api = ref.read(novaApiProvider);
    final last = _lastPage;
    if (api == null || last == null || !last.hasNextPage) return;
    final current = state.value ?? const [];
    final nextRequest = last.nextCursor != null
        ? _request.copyWith(page: null, cursor: last.nextCursor)
        : _request.copyWith(
            page: int.tryParse(last.nextPage ?? ''),
            cursor: null,
          );
    final page = await api.search.searchMetadata(nextRequest);
    _lastPage = page;
    state = AsyncData([...current, ...page.items]);
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(_loadFirstPage);
  }

  /// Replace one asset in the loaded list (e.g. after a favorite or
  /// archive toggle in the viewer) without a full reload.
  void updateAsset(NovaAsset updated) {
    final current = state.value;
    if (current == null) return;
    state = AsyncData([
      for (final asset in current)
        if (asset.id == updated.id) updated else asset,
    ]);
  }

  /// Drop assets from the loaded list (e.g. after a delete).
  void removeAssets(Iterable<String> ids) {
    final current = state.value;
    if (current == null) return;
    final doomed = ids.toSet();
    state = AsyncData(
      current.where((a) => !doomed.contains(a.id)).toList(),
    );
  }
}

/// Authenticated image headers for `cached_network_image` — thumbnails
/// and previews need the Bearer token (plain `Image.network` cannot
/// set headers).
final authImageHeadersProvider = Provider<Map<String, String>>((ref) {
  final auth = ref.watch(authServiceProvider);
  return auth.client?.authHeaders ?? const {};
});

/// Media URL builder for the current server (null until signed in).
final mediaUrlsProvider = Provider<MediaUrls?>((ref) {
  final api = ref.watch(novaApiProvider);
  return api?.media;
});
