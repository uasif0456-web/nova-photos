import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:workmanager/workmanager.dart';

import 'src/providers/providers.dart';
import 'src/services/backup_engine.dart';
import 'src/store/nova_database.dart';
import 'src/ui/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Edge-to-edge: draw behind the system bars; the theme supplies the
  // scrim colours. No immersive/fullscreen hiding — bars stay visible.
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  // Local Drift mirror (Track C). Opened once here and injected via
  // provider override so services share one database instance.
  final database = await openNovaDatabase();
  // Background backup worker (Track C). Best-effort: if WorkManager
  // cannot initialise on this device, foreground backup still works.
  try {
    await Workmanager().initialize(backupCallbackDispatcher);
  } catch (_) {
    // Background backup unavailable; the Dashboard's "Back up now"
    // still works. Deliberately silent — no crash on launch.
  }
  runApp(
    ProviderScope(
      overrides: [databaseProvider.overrideWithValue(database)],
      child: const NovaApp(),
    ),
  );
}
