/// Upload-queue state machine (pure logic, unit-tested).
///
/// States: `pending` → `uploading` → `done`, or `uploading` →
/// `failed` (retryable) → `pending` again, up to [maxUploadAttempts]
/// total attempts; after that the item stays `failed` for the user to
/// retry manually from the Backup Dashboard. `done` and `failed`
/// (exhausted) are terminal for the automatic engine.
library;

/// States of one row in the `upload_queue` table.
enum UploadQueueState { pending, uploading, failed, done }

/// Maximum upload attempts per queue item (1 first try + 2 retries).
const int maxUploadAttempts = 3;

UploadQueueState uploadQueueStateFromString(String value) =>
    switch (value) {
      'uploading' => UploadQueueState.uploading,
      'failed' => UploadQueueState.failed,
      'done' => UploadQueueState.done,
      _ => UploadQueueState.pending,
    };

String uploadQueueStateToString(UploadQueueState state) => state.name;

/// Legal transitions of the queue state machine. Anything not listed
/// is rejected (the DAO refuses the write and the caller logs it).
bool canTransition(UploadQueueState from, UploadQueueState to) =>
    switch ((from, to)) {
      (UploadQueueState.pending, UploadQueueState.uploading) => true,
      (UploadQueueState.uploading, UploadQueueState.done) => true,
      (UploadQueueState.uploading, UploadQueueState.failed) => true,
      // Retry: a failed item goes back to pending (attempt counter
      // decides whether the engine picks it up again).
      (UploadQueueState.failed, UploadQueueState.pending) => true,
      // Manual retry from the dashboard re-queues a failed item.
      (UploadQueueState.failed, UploadQueueState.uploading) => true,
      // Crash recovery: an item left `uploading` by a killed process
      // is re-queued as pending on the next run.
      (UploadQueueState.uploading, UploadQueueState.pending) => true,
      _ => false,
    };

/// Whether the engine may still retry this item automatically.
bool shouldRetry(int retryCount) => retryCount < maxUploadAttempts;

/// Delay before attempt [attempt] (1-based). Exponential backoff,
/// 2s → 4s → 8s, capped at 60s so a flapping network does not spin.
Duration retryDelay(int attempt) {
  final seconds = 2 * (1 << (attempt - 1).clamp(0, 5));
  return Duration(seconds: seconds > 60 ? 60 : seconds);
}

/// Socket reconnect backoff: 1s, 2s, 4s, 8s, 16s, then 30s cap.
/// A successful reconnect resets the attempt counter to 0.
Duration socketReconnectDelay(int attempt) {
  final seconds = 1 << attempt.clamp(0, 5);
  return Duration(seconds: seconds > 30 ? 30 : seconds);
}
