/// Sync models — `SyncStreamDto`, `SyncAckDto`, and the JSON-Lines
/// stream records of `POST /sync/stream`. Hand-written from spec v3.4.2.
///
/// The stream returns one JSON object per line. Each line is a change
/// record: `{type, data, ack}` — `type` is a `SyncEntityType` such as
/// `AssetV2` or `AlbumDeleteV1`, `data` is the entity payload (or a
/// tombstone id), and `ack` is the checkpoint token to confirm with
/// `POST /sync/ack` once the record has been applied locally.
/// A `SyncCompleteV1` record ends the stream.
library;

import 'parsing.dart';

/// Entity types the client can request in a sync stream
/// (`SyncEntityType`). Only the V2 asset/album/memory types are used by
/// NOVA v1; the full list is in the spec.
class SyncEntityTypes {
  static const String authUserV2 = 'AuthUserV2';
  static const String assetV2 = 'AssetV2';
  static const String assetDeleteV1 = 'AssetDeleteV1';
  static const String assetExifV1 = 'AssetExifV1';
  static const String albumV2 = 'AlbumV2';
  static const String albumDeleteV1 = 'AlbumDeleteV1';
  static const String albumToAssetV1 = 'AlbumToAssetV1';
  static const String albumToAssetDeleteV1 = 'AlbumToAssetDeleteV1';
  static const String memoryV2 = 'MemoryV2';
  static const String memoryDeleteV1 = 'MemoryDeleteV1';
  static const String personV1 = 'PersonV1';
  static const String personDeleteV1 = 'PersonDeleteV1';
  static const String stackV1 = 'StackV1';
  static const String stackDeleteV1 = 'StackDeleteV1';
  static const String syncCompleteV1 = 'SyncCompleteV1';
  static const String syncResetV1 = 'SyncResetV1';

  /// The default set NOVA syncs (full library mirror, Track B).
  static const List<String> defaultTypes = [
    authUserV2,
    assetV2,
    assetDeleteV1,
    assetExifV1,
    albumV2,
    albumDeleteV1,
    albumToAssetV1,
    albumToAssetDeleteV1,
    memoryV2,
    memoryDeleteV1,
    personV1,
    personDeleteV1,
    stackV1,
    stackDeleteV1,
  ];
}

/// Request body for `POST /sync/stream` (`SyncStreamDto`).
class SyncStreamRequest {
  const SyncStreamRequest({required this.types, this.reset = false});

  final List<String> types;

  /// `true` wipes the local mirror and re-syncs everything.
  final bool reset;

  Map<String, Object?> toJson() => {'types': types, 'reset': reset};
}

/// One line of the sync stream.
class SyncRecord {
  const SyncRecord({required this.type, this.data, this.ack});

  factory SyncRecord.fromJson(Map<String, Object?> json) {
    return SyncRecord(
      type: parseString(json['type']) ?? '',
      data: json['data'],
      ack: parseString(json['ack']),
    );
  }

  /// `SyncEntityType` string, e.g. `AssetV2`, `SyncCompleteV1`.
  final String type;

  /// Entity payload — a JSON object for upserts, an id string for
  /// tombstones, null for control records.
  final Object? data;

  /// Checkpoint token for this record; ack it with `POST /sync/ack`.
  final String? ack;

  bool get isComplete => type == SyncEntityTypes.syncCompleteV1;
  bool get isReset => type == SyncEntityTypes.syncResetV1;
  bool get isDelete => type.endsWith('DeleteV1');

  Map<String, Object?> toJson() => {
        'type': type,
        if (data != null) 'data': data,
        if (ack != null) 'ack': ack,
      };
}

/// Request body for `POST /sync/ack` (`SyncAckDto`).
class SyncAckRequest {
  const SyncAckRequest({required this.ack, required this.type});

  final String ack;
  final String type;

  Map<String, Object?> toJson() => {'ack': ack, 'type': type};
}
