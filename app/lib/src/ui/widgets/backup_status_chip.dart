/// Backup status indicator for the app bar.
///
/// Track C: reads the live [backupStatusProvider] stream (real engine
/// state — idle / running with %, paused, error, up-to-date) and
/// opens the Backup Dashboard on tap.
library;

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/providers.dart';
import '../../services/backup_service.dart';
import '../screens/backup_dashboard_screen.dart';

class BackupStatusChip extends ConsumerWidget {
  const BackupStatusChip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statusAsync = ref.watch(backupStatusProvider);
    final status = statusAsync.value ?? const BackupStatus.idle();
    final theme = Theme.of(context);
    final icon = switch (status.state) {
      BackupState.idle => Icons.cloud_off_outlined,
      BackupState.running => Icons.cloud_upload_outlined,
      BackupState.paused => Icons.cloud_queue_outlined,
      BackupState.upToDate => Icons.cloud_done_outlined,
      BackupState.error => Icons.cloud_off_outlined,
    };
    return ActionChip(
      avatar: Icon(icon, size: 18, color: theme.colorScheme.primary),
      label: Text(
        status.state == BackupState.running
            ? '${(status.progress * 100).round()}%'
            : status.label,
      ),
      onPressed: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => const BackupDashboardScreen(),
        ),
      ),
    );
  }
}
