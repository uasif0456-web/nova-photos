/// Backup engine — scans local media, dedups by SHA-1, uploads the
/// rest, and reports real progress to [BackupService] (which the
/// app-bar chip reads).
///
/// Flow per candidate file (ARCHITECTURE.md §3):
/// 1. SHA-1 of the whole file (streamed, see `sha1HexOfFile`).
/// 2. `POST /assets/bulk-upload-check` for the whole batch — a 200
///    `reject` (duplicate) is a **success**, the file is marked done
///    without uploading.
/// 3. Multipart `POST /assets` for the accepted files; 201 `created`
///    and 200 `duplicate` are both successes.
/// 4. A failed upload retries with exponential backoff, up to
///    [maxUploadAttempts] total attempts, then stays `failed` for a
///    manual retry from the Backup Dashboard.
///
/// Resumable uploads, honestly: the server has **no chunked upload**
/// in v3.4.2, so an interrupted upload restarts from byte 0. The
/// queue records that (the item goes back to `pending` with its retry
/// counter bumped); nothing here pretends otherwise.
///
/// Policy enforcement: Wi-Fi-only / charging-only are enforced for
/// **background** work by the WorkManager `Constraints` in
/// [BackupScheduler] (OS-level, reliable). The foreground engine has
/// no connectivity/battery plugin installed (deliberately — no new
/// dependency for a check the OS already does for scheduled work),
/// so a manual "Back up now" run assumes the user checked the
/// conditions; the predicates below are injectable for tests and for
/// a future plugin. Background work is the default path.
library;

import 'dart:async';
import 'dart:io';

import 'package:photo_manager/photo_manager.dart';
import 'package:workmanager/workmanager.dart';

import '../api/api_client.dart';
import '../api/nova_api.dart';
import '../store/daos.dart';
import '../store/nova_database.dart';
import '../store/upload_queue.dart';
import 'backup_service.dart';
import 'backup_settings.dart';
import 'token_store.dart';
import 'upload_service.dart';

/// One local media file found by the scanner.
class LocalMediaFile {
  const LocalMediaFile({
    required this.id,
    required this.path,
    required this.filename,
    required this.sizeBytes,
    required this.createdAt,
    required this.modifiedAt,
    required this.isVideo,
    this.durationMs,
    required this.folderName,
  });

  final String id;
  final String path;
  final String filename;
  final int sizeBytes;
  final DateTime createdAt;
  final DateTime modifiedAt;
  final bool isVideo;
  final int? durationMs;
  final String folderName;
}

/// Scans the device media library. Separated from the engine so unit
/// tests can substitute a fake scanner (no device, no permissions).
abstract class LocalMediaScanner {
  Future<List<LocalMediaFile>> scan(BackupSettings settings);
}

/// `photo_manager` implementation of [LocalMediaScanner].
class PhotoManagerScanner implements LocalMediaScanner {
  @override
  Future<List<LocalMediaFile>> scan(BackupSettings settings) async {
    final permission = await PhotoManager.requestPermissionExtend();
    if (!permission.hasAccess) return const [];
    // One `common` (image + video) listing per album; folder
    // filtering happens below via settings.folderInScope, so
    // camera-only vs all-folders is a filter, not a second query.
    const type = RequestType.common;
    final paths = await PhotoManager.getAssetPathList(type: type);
    final out = <LocalMediaFile>[];
    for (final path in paths) {
      final folderName = path.name;
      if (!settings.folderInScope(folderName)) continue;
      final count = await path.assetCountAsync;
      const pageSize = 200;
      for (var page = 0; page * pageSize < count; page++) {
        final entities = await path.getAssetListPaged(
          page: page,
          size: pageSize,
        );
        for (final entity in entities) {
          final file = await entity.loadFile();
          if (file == null) continue;
          final size = await file.length().catchError((_) => 0);
          out.add(
            LocalMediaFile(
              id: entity.id,
              path: file.path,
              filename:
                  entity.title ?? file.path.split('/').last,
              sizeBytes: size,
              createdAt: entity.createDateTime,
              modifiedAt: entity.modifiedDateTime,
              isVideo: entity.type == AssetType.video,
              durationMs: entity.type == AssetType.video
                  ? entity.duration * 1000
                  : null,
              folderName: folderName,
            ),
          );
        }
      }
    }
    return out;
  }
}

class BackupEngine {
  BackupEngine({
    required this.api,
    required this.db,
    required this.backupService,
    required this.scanner,
    this.isOnWifi,
    this.isCharging,
    this.sleeper = Future.delayed,
  })  : _queue = UploadQueueDao(db),
        _settingsDao = SettingsDao(db);

  final NovaApi api;
  final NovaDatabase db;
  final BackupService backupService;
  final LocalMediaScanner scanner;

  /// Injectable policy predicates (default: assume allowed — see the
  /// library doc: OS constraints enforce these for background work).
  final Future<bool> Function()? isOnWifi;
  final Future<bool> Function()? isCharging;

  /// Injectable sleep (tests pass a no-op so backoff costs no time).
  final Future<void> Function(Duration duration) sleeper;

  final UploadQueueDao _queue;
  final SettingsDao _settingsDao;

  bool _paused = false;
  bool _running = false;

  Future<BackupSettings> loadSettings() async =>
      BackupSettings.fromMap(await _settingsDao.getAll());

  Future<void> saveSettings(BackupSettings settings) async {
    for (final entry in settings.toMap().entries) {
      await _settingsDao.set(entry.key, entry.value);
    }
  }

  void pause() {
    _paused = true;
    backupService.update(
      backupService.status.copyWith(state: BackupState.paused),
    );
  }

  void resume() {
    _paused = false;
  }

  bool get isPaused => _paused;

  /// One backup run: scan → enqueue → bulk-check → upload.
  /// [manual] runs even when backup is disabled in settings (the
  /// Dashboard's "Back up now" button); scheduled runs require it on.
  Future<void> runOnce({bool manual = false}) async {
    if (_running) return;
    _running = true;
    try {
      final settings = await loadSettings();
      if (!settings.enabled && !manual) {
        backupService.update(const BackupStatus.idle());
        return;
      }
      // Crash recovery first: items left `uploading` by a killed run.
      await _queue.resetStuckUploading();

      backupService.update(
        BackupStatus(state: BackupState.running, lastRunAt: DateTime.now()),
      );
      final media = await scanner.scan(settings);
      final now = DateTime.now();
      for (final file in media) {
        if (_paused) break;
        final sha1 = await sha1HexOfFile(File(file.path));
        final existing = await _queue.getBySha1(sha1);
        if (existing != null) continue;
        await _queue.enqueue(
          UploadQueueItem(
            id: 'local-${file.id}',
            localPath: file.path,
            filename: file.filename,
            sha1: sha1,
            sizeBytes: file.sizeBytes,
            state: UploadQueueState.pending,
            retryCount: 0,
            fileCreatedAt: file.createdAt,
            fileModifiedAt: file.modifiedAt,
            createdAt: now,
          ),
        );
      }
      // Bulk-check the whole pending batch in one round-trip.
      await _bulkCheckPending();
      // Upload what is left, in queue order.
      await _uploadPending(settings);
      await _publishFinalStatus();
    } finally {
      _running = false;
    }
  }

  /// Re-queue failed items and run again (Dashboard "Retry failed").
  Future<void> retryFailed() async {
    final failed = await _queue.listByState(UploadQueueState.failed);
    for (final item in failed) {
      await _queue.setState(item.id, UploadQueueState.pending);
    }
    await runOnce(manual: true);
  }

  Future<void> _bulkCheckPending() async {
    final pending = await _queue.listByState(UploadQueueState.pending);
    if (pending.isEmpty) return;
    final candidates = pending
        .map(
          (item) => UploadCandidate(
            id: item.id,
            filename: item.filename,
            checksum: item.sha1,
            fileCreatedAt: item.fileCreatedAt,
            fileModifiedAt: item.fileModifiedAt,
          ),
        )
        .toList(growable: false);
    final results = await api.assets.bulkUploadCheck({
      for (final c in candidates) c.id: c.checksum,
    });
    final actions = {
      for (final r in results) r.id: r.action,
    };
    final split = splitBulkCheckResults(candidates, actions);
    for (final already in split.alreadyPresent) {
      // 200 `reject` = duplicate on the server: a success, not an
      // error. Mark done without uploading.
      await _queue.setState(already.id, UploadQueueState.uploading);
      await _queue.setState(already.id, UploadQueueState.done);
    }
  }

  Future<void> _uploadPending(BackupSettings settings) async {
    var pending = await _queue.listByState(UploadQueueState.pending);
    var total = await _queue.countByState(UploadQueueState.done) +
        pending.length +
        await _queue.countByState(UploadQueueState.failed);
    var uploaded = await _queue.countByState(UploadQueueState.done);
    for (final item in pending) {
      if (_paused) break;
      // Policy gate, checked per item so a run stops promptly when
      // the user leaves Wi-Fi / unplugs (background runs are already
      // gated by WorkManager constraints; this is the foreground path).
      if (settings.wifiOnly && isOnWifi != null) {
        if (!await isOnWifi!()) {
          backupService.update(
            backupService.status.copyWith(state: BackupState.paused),
          );
          return;
        }
      }
      if (settings.chargingOnly && isCharging != null) {
        if (!await isCharging!()) {
          backupService.update(
            backupService.status.copyWith(state: BackupState.paused),
          );
          return;
        }
      }
      await _uploadOne(item);
      uploaded = await _queue.countByState(UploadQueueState.done);
      pending = await _queue.listByState(UploadQueueState.pending);
      backupService.update(
        BackupStatus(
          state: BackupState.running,
          total: total,
          uploaded: uploaded,
          remaining: pending.length,
          lastRunAt: DateTime.now(),
        ),
      );
      total = uploaded + pending.length;
    }
  }

  /// Upload one queue item, retrying with backoff up to
  /// [maxUploadAttempts] total attempts. Returns true on success.
  Future<bool> _uploadOne(UploadQueueItem item) async {
    var attempt = 0;
    while (true) {
      attempt++;
      await _queue.setState(item.id, UploadQueueState.uploading);
      try {
        final file = File(item.localPath);
        if (!await file.exists()) {
          throw StateError('Local file no longer exists: ${item.filename}');
        }
        final bytes = await file.readAsBytes();
        final result = await api.assets.uploadAsset(
          bytes: bytes,
          filename: item.filename,
          fileCreatedAt: item.fileCreatedAt,
          fileModifiedAt: item.fileModifiedAt,
          checksum: item.sha1,
        );
        // 201 created and 200 duplicate are both successes.
        await _queue.setState(
          item.id,
          UploadQueueState.done,
          serverAssetId: result.id.isEmpty ? null : result.id,
        );
        return true;
      } catch (e) {
        final exhausted = !shouldRetry(attempt);
        await _queue.setState(
          item.id,
          UploadQueueState.failed,
          lastError: e.toString(),
          bumpRetry: true,
        );
        if (exhausted) return false;
        await sleeper(retryDelay(attempt));
        // Back to pending for the next attempt (legal transition).
        await _queue.setState(item.id, UploadQueueState.pending);
      }
    }
  }

  Future<void> _publishFinalStatus() async {
    final done = await _queue.countByState(UploadQueueState.done);
    final pending = await _queue.countByState(UploadQueueState.pending);
    final failed = await _queue.countByState(UploadQueueState.failed);
    final now = DateTime.now();
    if (_paused) {
      backupService.update(
        BackupStatus(
          state: BackupState.paused,
          total: done + pending + failed,
          uploaded: done,
          remaining: pending,
          failed: failed,
          lastRunAt: now,
        ),
      );
      return;
    }
    if (failed > 0 && pending == 0) {
      backupService.update(
        BackupStatus(
          state: BackupState.error,
          total: done + failed,
          uploaded: done,
          remaining: 0,
          failed: failed,
          lastError: 'Some photos could not be uploaded.',
          lastRunAt: now,
          lastSuccessfulAt: done > 0 ? now : null,
        ),
      );
      return;
    }
    backupService.update(
      BackupStatus(
        state: BackupState.upToDate,
        total: done + pending + failed,
        uploaded: done,
        remaining: pending,
        failed: failed,
        lastRunAt: now,
        lastSuccessfulAt: now,
      ),
    );
  }

  /// Queue snapshot for the Dashboard.
  Future<List<UploadQueueItem>> queueSnapshot() => _queue.listAll();
}

/// Background scheduling for the backup engine (WorkManager).
///
/// The periodic worker runs as an Android **foreground service**
/// (`foregroundServiceType: dataSync`, Android 14+) for the whole
/// task, showing a persistent "Backing up photos" notification —
/// declared in `AndroidManifest.xml` (FOREGROUND_SERVICE +
/// FOREGROUND_SERVICE_DATA_SYNC permissions) and requested here via
/// [ForegroundServiceConfig]. Wi-Fi-only / charging-only are OS
/// constraints on the work request itself, so the OS will not even
/// start the worker off-policy.
class BackupScheduler {
  static const String periodicUniqueName = 'nova_backup_periodic';
  static const String taskName = 'novaBackup';
  static const String oneOffUniqueName = 'nova_backup_one_off';

  /// Register (or replace) the periodic backup job. Minimum useful
  /// interval is 15 minutes on Android; NOVA uses 6 hours.
  Future<void> registerPeriodic(BackupSettings settings) async {
    await Workmanager().registerPeriodicTask(
      periodicUniqueName,
      taskName,
      frequency: const Duration(hours: 6),
      constraints: Constraints(
        networkType: settings.wifiOnly
            ? NetworkType.unmetered
            : NetworkType.connected,
        requiresCharging: settings.chargingOnly,
      ),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.replace,
      backoffPolicy: BackoffPolicy.exponential,
      foregroundServiceConfig: ForegroundServiceConfig(
        notificationTitle: 'NOVA PHOTOS backup',
        notificationText: 'Backing up your photos…',
        notificationChannelId: 'nova_backup',
        notificationChannelName: 'Photo backup',
        foregroundServiceType: ForegroundServiceType.dataSync,
      ),
    );
  }

  Future<void> cancel() async {
    await Workmanager().cancelByUniqueName(periodicUniqueName);
  }

  Future<bool> isScheduled() =>
      Workmanager().isScheduledByUniqueName(periodicUniqueName);
}

/// WorkManager entry point, registered from `main.dart`.
///
/// Runs headless: opens the Drift DB, restores the stored session
/// (server URL + JWT from secure storage), and runs one backup pass.
/// Returns false when the run failed so WorkManager applies its own
/// exponential backoff. Untested on a real device in this VM (no APK
/// build here — Stage 14); the foreground path is covered by the
/// Dashboard's "Back up now".
@pragma('vm:entry-point')
void backupCallbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      final store = SecureTokenStore();
      final serverUrl =
          await store.read(TokenStoreKeys.serverUrl);
      final token = await store.read(TokenStoreKeys.accessToken);
      if (serverUrl == null || token == null) return true;
      final client = ImmichApiClient(serverUrl: serverUrl);
      client.setAccessToken(token);
      final cookie =
          await store.read(TokenStoreKeys.accessTokenCookie);
      if (cookie != null && cookie.isNotEmpty) {
        client.setCookie(cookie);
      }
      final api = NovaApi(client);
      final db = await openNovaDatabase();
      final backupService = BackupService();
      final engine = BackupEngine(
        api: api,
        db: db,
        backupService: backupService,
        scanner: PhotoManagerScanner(),
      );
      await engine.runOnce();
      await db.close();
      api.dispose();
      return backupService.status.state != BackupState.error;
    } catch (_) {
      return false;
    }
  });
}
