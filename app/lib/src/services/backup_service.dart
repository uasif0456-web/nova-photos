/// Backup status — the state the app-bar chip and the Backup
/// Dashboard show.
///
/// Track C wires this to the real engine: [BackupService.update] is
/// called by the backup engine on every progress change, and
/// [backupStatusProvider] re-emits it, so the chip always shows real
/// state (idle / backing up with %, paused, error, up-to-date) instead
/// of the Track A placeholder.
library;

import 'dart:async';

/// Backup engine state shown in the app bar.
enum BackupState {
  /// No backup configured yet / engine not started.
  idle,

  /// Backup is running.
  running,

  /// Paused by the user or by policy (e.g. not on Wi-Fi).
  paused,

  /// Finished the last run with nothing left to upload.
  upToDate,

  /// The last run failed (network, server, or quota).
  error,
}

/// Snapshot of backup progress for the app-bar indicator.
class BackupStatus {
  const BackupStatus({
    required this.state,
    this.total = 0,
    this.uploaded = 0,
    this.remaining = 0,
    this.failed = 0,
    this.lastError,
    this.lastRunAt,
    this.lastSuccessfulAt,
  });

  const BackupStatus.idle() : this(state: BackupState.idle);

  final BackupState state;
  final int total;
  final int uploaded;
  final int remaining;

  /// Items that exhausted their retries in the last run.
  final int failed;
  final String? lastError;
  final DateTime? lastRunAt;

  /// Last time a run finished with at least one upload confirmed by
  /// the server (or with nothing left to do).
  final DateTime? lastSuccessfulAt;

  double get progress =>
      total <= 0 ? 0 : (uploaded / total).clamp(0.0, 1.0);

  String get label => switch (state) {
        BackupState.idle => 'Backup not set up',
        BackupState.running => 'Backing up… $uploaded of $total',
        BackupState.paused => 'Backup paused',
        BackupState.upToDate => 'Backed up',
        BackupState.error => 'Backup failed',
      };

  BackupStatus copyWith({
    BackupState? state,
    int? total,
    int? uploaded,
    int? remaining,
    int? failed,
    String? lastError,
    DateTime? lastRunAt,
    DateTime? lastSuccessfulAt,
  }) =>
      BackupStatus(
        state: state ?? this.state,
        total: total ?? this.total,
        uploaded: uploaded ?? this.uploaded,
        remaining: remaining ?? this.remaining,
        failed: failed ?? this.failed,
        lastError: lastError ?? this.lastError,
        lastRunAt: lastRunAt ?? this.lastRunAt,
        lastSuccessfulAt: lastSuccessfulAt ?? this.lastSuccessfulAt,
      );
}

/// The single owner of backup status. The engine calls [update]; the
/// UI watches [stream] (via `backupStatusProvider`). The last status
/// is always available synchronously as [status].
class BackupService {
  BackupStatus _status = const BackupStatus.idle();
  final _controller = StreamController<BackupStatus>.broadcast();

  BackupStatus get status => _status;

  /// Every status change, in order. The current status is emitted to
  /// each new listener first.
  Stream<BackupStatus> get stream async* {
    yield _status;
    yield* _controller.stream;
  }

  /// Called by the backup engine when progress or state changes.
  void update(BackupStatus status) {
    _status = status;
    if (!_controller.isClosed) _controller.add(status);
  }

  void dispose() {
    _controller.close();
  }
}
