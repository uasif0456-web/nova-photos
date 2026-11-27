/// Backup Dashboard — progress, queue, failures, last successful
/// backup, backup preferences, and thumbnail-cache management.
///
/// The only Track C screen (Track B owns the other tabs). It reads
/// state from the providers, never from the API or the DB directly.
library;

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/providers.dart';
import '../../services/backup_engine.dart';
import '../../services/backup_service.dart';
import '../../services/backup_settings.dart';
import '../../services/thumbnail_cache_service.dart';
import '../../store/upload_queue.dart';

class BackupDashboardScreen extends ConsumerStatefulWidget {
  const BackupDashboardScreen({super.key});

  @override
  ConsumerState<BackupDashboardScreen> createState() =>
      _BackupDashboardScreenState();
}

class _BackupDashboardScreenState
    extends ConsumerState<BackupDashboardScreen> {
  bool _busy = false;
  String? _error;
  int? _cacheBytes;

  @override
  void initState() {
    super.initState();
    _refreshCacheSize();
  }

  Future<void> _refreshCacheSize() async {
    final bytes =
        await ref.read(thumbnailCacheServiceProvider).cacheSizeBytes();
    if (mounted) setState(() => _cacheBytes = bytes);
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        await _refreshCacheSize();
      }
    }
  }

  Future<void> _saveSettings(BackupSettings next) async {
    final engine = ref.read(backupEngineProvider);
    if (engine == null) return;
    await engine.saveSettings(next);
    await BackupScheduler().registerPeriodic(next);
    ref.invalidate(backupSettingsProvider);
  }

  @override
  Widget build(BuildContext context) {
    final statusAsync = ref.watch(backupStatusProvider);
    final status = statusAsync.value ?? const BackupStatus.idle();
    final settingsAsync = ref.watch(backupSettingsProvider);
    final settings = settingsAsync.value ?? const BackupSettings();
    final sync = ref.watch(syncServiceProvider);
    final theme = Theme.of(context);
    final engine = ref.read(backupEngineProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Backup')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(status.label, style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  if (status.state == BackupState.running)
                    LinearProgressIndicator(value: status.progress),
                  const SizedBox(height: 8),
                  Text(
                    'Uploaded ${status.uploaded} of ${status.total}'
                    ' · ${status.remaining} remaining'
                    '${status.failed > 0 ? ' · ${status.failed} failed' : ''}',
                  ),
                  if (status.lastSuccessfulAt != null)
                    Text(
                      'Last successful backup: '
                      '${status.lastSuccessfulAt!.toLocal()}',
                    ),
                  if (status.lastError != null)
                    Text(
                      status.lastError!,
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  if (sync != null)
                    Text(
                      'Last sync: '
                      '${sync.state.lastSyncAt?.toLocal() ?? 'never'}'
                      ' · ${sync.state.pendingOps} pending offline actions'
                      '${sync.state.lastError != null ? ' · sync error: ${sync.state.lastError}' : ''}',
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              FilledButton.icon(
                onPressed: (_busy || engine == null)
                    ? null
                    : () => _run(() => engine.runOnce(manual: true)),
                icon: const Icon(Icons.cloud_upload_outlined, size: 18),
                label: const Text('Back up now'),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: (_busy || engine == null)
                    ? null
                    : () => _run(engine.retryFailed),
                icon: const Icon(Icons.refresh_outlined, size: 18),
                label: const Text('Retry failed'),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: engine == null
                    ? null
                    : () {
                        if (engine.isPaused) {
                          engine.resume();
                        } else {
                          engine.pause();
                        }
                        setState(() {});
                      },
                icon: Icon(
                  engine?.isPaused ?? false
                      ? Icons.play_arrow_outlined
                      : Icons.pause_outlined,
                  size: 18,
                ),
                label: Text(
                  engine?.isPaused ?? false ? 'Resume' : 'Pause',
                ),
              ),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
          ],
          const SizedBox(height: 24),
          Text('Backup settings', style: theme.textTheme.titleMedium),
          SwitchListTile(
            title: const Text('Back up automatically'),
            subtitle: const Text(
              'Scan the camera roll in the background and upload new photos.',
            ),
            value: settings.enabled,
            onChanged: (v) => _saveSettings(settings.copyWith(enabled: v)),
          ),
          SwitchListTile(
            title: const Text('Wi-Fi only'),
            subtitle: const Text(
              'Only upload on unmetered networks. Enforced by the OS for background work.',
            ),
            value: settings.wifiOnly,
            onChanged: (v) => _saveSettings(settings.copyWith(wifiOnly: v)),
          ),
          SwitchListTile(
            title: const Text('Only while charging'),
            subtitle: const Text(
              'Only upload while the device is charging.',
            ),
            value: settings.chargingOnly,
            onChanged: (v) =>
                _saveSettings(settings.copyWith(chargingOnly: v)),
          ),
          SwitchListTile(
            title: const Text('Camera folder only'),
            subtitle: const Text(
              'When off, every local album is scanned (except excluded folders).',
            ),
            value: settings.cameraOnly,
            onChanged: (v) =>
                _saveSettings(settings.copyWith(cameraOnly: v)),
          ),
          const SizedBox(height: 8),
          Text(
            'Resumable uploads: the server has no chunked upload in '
            'v3.4.2, so an interrupted upload restarts from the '
            'beginning. The queue records that honestly — nothing is '
            'marked backed up until the server confirms it.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 24),
          Text('Upload queue', style: theme.textTheme.titleMedium),
          FutureBuilder(
            future: engine?.queueSnapshot(),
            builder: (context, snapshot) {
              final items = snapshot.data ?? const [];
              if (items.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text('Queue is empty — nothing waiting to upload.'),
                );
              }
              final failed = items
                  .where((i) => i.state == UploadQueueState.failed)
                  .toList(growable: false);
              final pending = items
                  .where((i) => i.state == UploadQueueState.pending)
                  .toList(growable: false);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${items.length} queued · '
                    '${pending.length} pending · '
                    '${failed.length} failed',
                  ),
                  const SizedBox(height: 8),
                  ...failed.take(10).map(
                    (item) => ListTile(
                      leading: const Icon(Icons.error_outline),
                      title: Text(item.filename),
                      subtitle: Text(
                        item.lastError ?? 'Upload failed',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 24),
          Text('Thumbnail cache', style: theme.textTheme.titleMedium),
          ListTile(
            leading: const Icon(Icons.image_outlined),
            title: const Text('Cached thumbnails'),
            subtitle: Text(
              _cacheBytes == null
                  ? 'Measuring…'
                  : ThumbnailCacheService.formatBytes(_cacheBytes!),
            ),
            trailing: OutlinedButton(
              onPressed: _busy
                  ? null
                  : () => _run(
                        () => ref
                            .read(thumbnailCacheServiceProvider)
                            .clearCache(),
                      ),
              child: const Text('Clear cache'),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Clearing the cache only removes thumbnails — your photos '
            'stay on the server and in the local mirror.',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
