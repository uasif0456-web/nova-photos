/// Server info models — `GET /server/version`, `/server/features`,
/// `/server/about`. Hand-written from Immich OpenAPI spec v3.4.2.
library;

import 'parsing.dart';

/// `ServerVersionResponseDto`. `featureLevel` is the compatibility signal
/// (it increments independently of the release version); `major`/`minor`
/// are the SemVer parts. `prerelease` is an integer in the spec (0 when
/// absent on a release build — the live demo returns `null`, so we parse
/// it leniently).
class ServerVersion {
  const ServerVersion({
    required this.major,
    required this.minor,
    required this.patch,
    this.prerelease,
    required this.featureLevel,
  });

  factory ServerVersion.fromJson(Map<String, Object?> json) {
    return ServerVersion(
      major: parseInt(json['major']) ?? 0,
      minor: parseInt(json['minor']) ?? 0,
      patch: parseInt(json['patch']) ?? 0,
      prerelease: parseInt(json['prerelease']),
      featureLevel: parseInt(json['featureLevel']) ?? 0,
    );
  }

  final int major;
  final int minor;
  final int patch;
  final int? prerelease;
  final int featureLevel;

  Map<String, Object?> toJson() => {
        'major': major,
        'minor': minor,
        'patch': patch,
        if (prerelease != null) 'prerelease': prerelease,
        'featureLevel': featureLevel,
      };

  /// NOVA supports Immich server v3.x only (see API_VERSION_COMPATIBILITY.md).
  bool get isSupportedMajor => major == 3;

  /// Older than v3 — refuse to proceed, show an upgrade message.
  bool get isTooOld => major < 3;

  /// Newer than the version NOVA was built for — warn, don't block.
  bool get isNewerMajor => major > 3;

  @override
  String toString() =>
      'ServerVersion($major.$minor.$patch, featureLevel $featureLevel)';
}

/// `ServerFeaturesDto` — feature flags the client must gate on. Every
/// flag defaults to false when the server omits it (fail closed).
class ServerFeatures {
  const ServerFeatures({
    this.smartSearch = false,
    this.facialRecognition = false,
    this.map = false,
    this.trash = false,
    this.oauth = false,
    this.passwordLogin = false,
    this.email = false,
    this.search = false,
    this.sidecar = false,
    this.ocr = false,
    this.duplicateDetection = false,
    this.reverseGeocoding = false,
    this.backups = false,
    this.configFile = false,
    this.importFaces = false,
    this.oauthAutoLaunch = false,
    this.realtimeTranscoding = false,
  });

  factory ServerFeatures.fromJson(Map<String, Object?> json) {
    bool flag(String key) => parseBool(json[key]) ?? false;
    return ServerFeatures(
      smartSearch: flag('smartSearch'),
      facialRecognition: flag('facialRecognition'),
      map: flag('map'),
      trash: flag('trash'),
      oauth: flag('oauth'),
      passwordLogin: flag('passwordLogin'),
      email: flag('email'),
      search: flag('search'),
      sidecar: flag('sidecar'),
      ocr: flag('ocr'),
      duplicateDetection: flag('duplicateDetection'),
      reverseGeocoding: flag('reverseGeocoding'),
      backups: flag('backups'),
      configFile: flag('configFile'),
      importFaces: flag('importFaces'),
      oauthAutoLaunch: flag('oauthAutoLaunch'),
      realtimeTranscoding: flag('realtimeTranscoding'),
    );
  }

  final bool smartSearch;
  final bool facialRecognition;
  final bool map;
  final bool trash;
  final bool oauth;
  final bool passwordLogin;
  final bool email;
  final bool search;
  final bool sidecar;
  final bool ocr;
  final bool duplicateDetection;
  final bool reverseGeocoding;
  final bool backups;
  final bool configFile;
  final bool importFaces;
  final bool oauthAutoLaunch;
  final bool realtimeTranscoding;

  Map<String, Object?> toJson() => {
        'smartSearch': smartSearch,
        'facialRecognition': facialRecognition,
        'map': map,
        'trash': trash,
        'oauth': oauth,
        'passwordLogin': passwordLogin,
        'email': email,
        'search': search,
        'sidecar': sidecar,
        'ocr': ocr,
        'duplicateDetection': duplicateDetection,
        'reverseGeocoding': reverseGeocoding,
        'backups': backups,
        'configFile': configFile,
        'importFaces': importFaces,
        'oauthAutoLaunch': oauthAutoLaunch,
        'realtimeTranscoding': realtimeTranscoding,
      };
}

/// `ServerAboutResponseDto` — build info (subset of fields we display).
class ServerAbout {
  const ServerAbout({
    required this.version,
    this.repository,
    this.sourceRef,
    this.build,
    this.licensed = false,
  });

  factory ServerAbout.fromJson(Map<String, Object?> json) {
    return ServerAbout(
      version: parseString(json['version']) ?? '',
      repository: parseString(json['repository']),
      sourceRef: parseString(json['sourceRef']),
      build: parseString(json['build']),
      licensed: parseBool(json['licensed']) ?? false,
    );
  }

  final String version;
  final String? repository;
  final String? sourceRef;
  final String? build;
  final bool licensed;

  Map<String, Object?> toJson() => {
        'version': version,
        if (repository != null) 'repository': repository,
        if (sourceRef != null) 'sourceRef': sourceRef,
        if (build != null) 'build': build,
        'licensed': licensed,
      };
}
