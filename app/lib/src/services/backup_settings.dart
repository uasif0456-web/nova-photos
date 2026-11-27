/// Backup preferences — stored in the Drift `settings` table (never
/// in secure storage: these are prefs, not secrets; the server URL
/// and session stay in the keystore).
library;

import 'dart:convert';

/// Backup preferences, with the safe defaults.
class BackupSettings {
  const BackupSettings({
    this.enabled = false,
    this.wifiOnly = true,
    this.chargingOnly = false,
    this.cameraOnly = true,
    this.includedFolders = const [],
    this.excludedFolders = const [],
  });

  factory BackupSettings.fromMap(Map<String, String> stored) {
    bool boolOf(String key, bool fallback) =>
        stored[key] == null ? fallback : stored[key] == 'true';
    List<String> listOf(String key) {
      final raw = stored[key];
      if (raw == null || raw.isEmpty) return const [];
      try {
        final decoded = jsonDecode(raw);
        return decoded is List
            ? decoded.map((e) => e.toString()).toList(growable: false)
            : const [];
      } catch (_) {
        return const [];
      }
    }

    return BackupSettings(
      enabled: boolOf('backup.enabled', false),
      wifiOnly: boolOf('backup.wifi_only', true),
      chargingOnly: boolOf('backup.charging_only', false),
      cameraOnly: boolOf('backup.camera_only', true),
      includedFolders: listOf('backup.included_folders'),
      excludedFolders: listOf('backup.excluded_folders'),
    );
  }

  /// Backup is switched on at all (default off: nothing uploads
  /// before the user opts in on the Backup Dashboard).
  final bool enabled;

  /// Upload only on unmetered (Wi-Fi) networks.
  final bool wifiOnly;

  /// Upload only while the device is charging.
  final bool chargingOnly;

  /// Only the camera folder (DCIM / Camera) is scanned; when false,
  /// every local album is scanned.
  final bool cameraOnly;

  /// Folder names to include when [cameraOnly] is false. Empty means
  /// "all folders".
  final List<String> includedFolders;

  /// Folder names to skip, always.
  final List<String> excludedFolders;

  Map<String, String> toMap() => {
        'backup.enabled': enabled.toString(),
        'backup.wifi_only': wifiOnly.toString(),
        'backup.charging_only': chargingOnly.toString(),
        'backup.camera_only': cameraOnly.toString(),
        'backup.included_folders': jsonEncode(includedFolders),
        'backup.excluded_folders': jsonEncode(excludedFolders),
      };

  BackupSettings copyWith({
    bool? enabled,
    bool? wifiOnly,
    bool? chargingOnly,
    bool? cameraOnly,
    List<String>? includedFolders,
    List<String>? excludedFolders,
  }) =>
      BackupSettings(
        enabled: enabled ?? this.enabled,
        wifiOnly: wifiOnly ?? this.wifiOnly,
        chargingOnly: chargingOnly ?? this.chargingOnly,
        cameraOnly: cameraOnly ?? this.cameraOnly,
        includedFolders: includedFolders ?? this.includedFolders,
        excludedFolders: excludedFolders ?? this.excludedFolders,
      );

  /// Whether a local album (folder) named [folderName] is in scope.
  bool folderInScope(String folderName) {
    if (excludedFolders.contains(folderName)) return false;
    if (cameraOnly) {
      // Camera-only means exactly the camera roll; photo_manager
      // reports it as "Camera" / "DCIM" depending on device.
      return folderName == 'Camera' ||
          folderName == 'DCIM' ||
          folderName == 'All Photos';
    }
    if (includedFolders.isEmpty) return true;
    return includedFolders.contains(folderName);
  }
}
