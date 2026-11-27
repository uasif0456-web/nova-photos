/// Track C unit tests — upload queue state machine, retry/backoff,
/// SHA-1 dedup split, sync-stream JSONL parsing, pending-ops replay
/// order, Drift DAOs, and the backup engine end-to-end (fake scanner
/// + MockClient server, no network, no device).
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nova_photos/src/api/api_client.dart';
import 'package:nova_photos/src/api/nova_api.dart';
import 'package:nova_photos/src/models/asset.dart';
import 'package:nova_photos/src/models/sync.dart';
import 'package:nova_photos/src/services/backup_engine.dart';
import 'package:nova_photos/src/services/backup_service.dart';
import 'package:nova_photos/src/services/backup_settings.dart';
import 'package:nova_photos/src/services/pending_ops_service.dart';
import 'package:nova_photos/src/services/sync_service.dart';
import 'package:nova_photos/src/services/upload_service.dart';
import 'package:nova_photos/src/store/daos.dart';
import 'package:nova_photos/src/store/nova_database.dart';
import 'package:nova_photos/src/store/upload_queue.dart';

NovaApi _mockApi(MockClient client) => NovaApi(
      ImmichApiClient(serverUrl: 'https://example.invalid', httpClient: client),
    );

Map<String, Object?> _assetJson(String id) => {
      'id': id,
      'type': 'IMAGE',
      'checksum': 'abc123',
      'originalFileName': 'IMG_0001.jpg',
      'originalPath': '/photos/IMG_0001.jpg',
      'fileCreatedAt': '2026-11-01T10:00:00.000Z',
      'fileModifiedAt': '2026-11-01T10:00:00.000Z',
      'localDateTime': '2026-11-01T10:00:00.000Z',
      'createdAt': '2026-11-01T10:00:00.000Z',
      'updatedAt': '2026-11-01T10:00:00.000Z',
      'width': 4000,
      'height': 3000,
      'isFavorite': false,
      'isArchived': false,
      'isTrashed': false,
      'visibility': 'timeline',
      'ownerId': 'owner-1',
      'thumbhash': 'abc',
    };

class _FakeScanner implements LocalMediaScanner {
  _FakeScanner(this.files);

  final List<LocalMediaFile> files;

  @override
  Future<List<LocalMediaFile>> scan(BackupSettings settings) async =>
      files;
}

void main() {
  group('upload queue state machine', () {
    test('legal transitions only', () {
      expect(canTransition(UploadQueueState.pending, UploadQueueState.uploading), isTrue);
      expect(canTransition(UploadQueueState.uploading, UploadQueueState.done), isTrue);
      expect(canTransition(UploadQueueState.uploading, UploadQueueState.failed), isTrue);
      expect(canTransition(UploadQueueState.failed, UploadQueueState.pending), isTrue);
      expect(canTransition(UploadQueueState.failed, UploadQueueState.uploading), isTrue);
      expect(canTransition(UploadQueueState.uploading, UploadQueueState.pending), isTrue);
      // Illegal: done is terminal; pending never jumps to done/failed.
      expect(canTransition(UploadQueueState.done, UploadQueueState.pending), isFalse);
      expect(canTransition(UploadQueueState.done, UploadQueueState.uploading), isFalse);
      expect(canTransition(UploadQueueState.pending, UploadQueueState.done), isFalse);
      expect(canTransition(UploadQueueState.pending, UploadQueueState.failed), isFalse);
      expect(canTransition(UploadQueueState.failed, UploadQueueState.done), isFalse);
    });

    test('round-trips through strings', () {
      for (final state in UploadQueueState.values) {
        expect(
          uploadQueueStateFromString(uploadQueueStateToString(state)),
          state,
        );
      }
      expect(uploadQueueStateFromString('bogus'), UploadQueueState.pending);
    });
  });

  group('retry / backoff', () {
    test('max 3 attempts, then failed is terminal', () {
      expect(shouldRetry(0), isTrue);
      expect(shouldRetry(1), isTrue);
      expect(shouldRetry(2), isTrue);
      expect(shouldRetry(3), isFalse);
      expect(shouldRetry(10), isFalse);
    });

    test('exponential backoff 2s, 4s, 8s, capped at 60s', () {
      expect(retryDelay(1), const Duration(seconds: 2));
      expect(retryDelay(2), const Duration(seconds: 4));
      expect(retryDelay(3), const Duration(seconds: 8));
      expect(retryDelay(99), const Duration(seconds: 60));
    });

    test('socket reconnect backoff 1s doubling, capped at 30s', () {
      expect(socketReconnectDelay(0), const Duration(seconds: 1));
      expect(socketReconnectDelay(1), const Duration(seconds: 2));
      expect(socketReconnectDelay(4), const Duration(seconds: 16));
      expect(socketReconnectDelay(99), const Duration(seconds: 30));
    });
  });

  group('SHA-1 dedup split', () {
    test('bulk-check reject (200 duplicate) is a success, not an error', () {
      final candidates = [
        UploadCandidate(
          id: 'a',
          filename: 'a.jpg',
          checksum: 'aaa',
          fileCreatedAt: DateTime.utc(2026, 11, 1),
          fileModifiedAt: DateTime.utc(2026, 11, 1),
        ),
        UploadCandidate(
          id: 'b',
          filename: 'b.jpg',
          checksum: 'bbb',
          fileCreatedAt: DateTime.utc(2026, 11, 1),
          fileModifiedAt: DateTime.utc(2026, 11, 1),
        ),
      ];
      final split = splitBulkCheckResults(candidates, {
        'a': 'reject', // server already has it
        'b': 'accept',
      });
      expect(split.alreadyPresent.map((c) => c.id), ['a']);
      expect(split.toUpload.map((c) => c.id), ['b']);
    });

    test('streaming file SHA-1 matches the in-memory vector', () async {
      final dir = await Directory.systemTemp.createTemp('nova_sha1');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/x.bin');
      await file.writeAsBytes(utf8.encode('abc'));
      expect(
        await sha1HexOfFile(file),
        'a9993e364706816aba3e25717850c26c9cd0d89d',
      );
    });
  });

  group('sync-stream JSONL parsing', () {
    test('parses records, skips blank + malformed lines, keeps acks', () {
      const body = '''
{"type":"AssetV2","data":{"id":"asset-1"},"ack":"ack-1"}

not json at all
{"type":"AssetDeleteV1","data":{"assetId":"asset-2"},"ack":"ack-2"}
{"type":"SyncCompleteV1"}
''';
      final records = parseSyncJsonLines(body);
      expect(records.length, 3);
      expect(records[0].type, 'AssetV2');
      expect(records[0].ack, 'ack-1');
      expect(records[1].type, 'AssetDeleteV1');
      expect(records[1].isDelete, isTrue);
      expect(records[2].isComplete, isTrue);
    });

    test('empty body parses to no records', () {
      expect(parseSyncJsonLines(''), isEmpty);
      expect(parseSyncJsonLines('\n\n'), isEmpty);
    });

    test('syncRecordId reads delete payloads', () {
      final record = SyncRecord.fromJson({
        'type': 'AssetDeleteV1',
        'data': {'assetId': 'asset-9'},
      });
      expect(syncRecordId(record, 'assetId'), 'asset-9');
      final bare = SyncRecord(type: 'AssetDeleteV1', data: 'asset-10');
      expect(syncRecordId(bare), 'asset-10');
    });

    test('entity types translate to SyncRequestType values', () {
      expect(
        syncRequestTypesFor(SyncEntityTypes.defaultTypes),
        [
          'AuthUsersV2',
          'AssetsV2',
          'AssetExifsV1',
          'AlbumsV2',
          'AlbumToAssetsV1',
          'MemoriesV2',
          'PeopleV1',
          'StacksV1',
        ],
      );
    });
  });

  group('backup settings', () {
    test('defaults are safe: disabled, wifi-only, camera-only', () {
      const settings = BackupSettings();
      expect(settings.enabled, isFalse);
      expect(settings.wifiOnly, isTrue);
      expect(settings.chargingOnly, isFalse);
      expect(settings.cameraOnly, isTrue);
    });

    test('folderInScope honours camera-only + exclusions', () {
      const settings = BackupSettings();
      expect(settings.folderInScope('Camera'), isTrue);
      expect(settings.folderInScope('DCIM'), isTrue);
      expect(settings.folderInScope('Screenshots'), isFalse);
      const custom = BackupSettings(
        cameraOnly: false,
        excludedFolders: ['Memes'],
      );
      expect(custom.folderInScope('Screenshots'), isTrue);
      expect(custom.folderInScope('Memes'), isFalse);
    });

    test('round-trips through the settings map', () {
      const settings = BackupSettings(
        enabled: true,
        wifiOnly: false,
        chargingOnly: true,
        cameraOnly: false,
        includedFolders: ['Camera', 'Screenshots'],
        excludedFolders: ['Memes'],
      );
      final restored = BackupSettings.fromMap(settings.toMap());
      expect(restored.enabled, isTrue);
      expect(restored.wifiOnly, isFalse);
      expect(restored.chargingOnly, isTrue);
      expect(restored.includedFolders, ['Camera', 'Screenshots']);
      expect(restored.excludedFolders, ['Memes']);
    });
  });

  group('Drift DAOs (in-memory)', () {
    late NovaDatabase db;

    setUp(() {
      db = NovaDatabase.memory();
    });

    tearDown(() async {
      await db.close();
    });

    test('asset mirror upsert / list / delete', () async {
      final dao = AssetDao(db);
      final asset = NovaAsset.fromJson(_assetJson('asset-1'));
      await dao.upsert(asset);
      expect(await dao.count(), 1);
      final listed = await dao.listNewest();
      expect(listed.first.id, 'asset-1');
      expect(listed.first.originalFileName, 'IMG_0001.jpg');
      // Upsert replaces server-wins (favorite flipped by the server).
      await dao.upsert(
        NovaAsset.fromJson({..._assetJson('asset-1'), 'isFavorite': true}),
      );
      expect((await dao.getById('asset-1'))!.isFavorite, isTrue);
      expect(await dao.count(), 1);
      await dao.deleteById('asset-1');
      expect(await dao.count(), 0);
    });

    test('upload queue: enqueue dedupes, illegal transitions refused',
        () async {
      final dao = UploadQueueDao(db);
      final now = DateTime.utc(2026, 11, 22);
      final item = UploadQueueItem(
        id: 'local-1',
        localPath: '/x/a.jpg',
        filename: 'a.jpg',
        sha1: 'aaa',
        sizeBytes: 10,
        state: UploadQueueState.pending,
        retryCount: 0,
        fileCreatedAt: now,
        fileModifiedAt: now,
        createdAt: now,
      );
      await dao.enqueue(item);
      await dao.enqueue(item); // same id: ignored, not duplicated
      expect(await dao.countByState(UploadQueueState.pending), 1);
      expect((await dao.getBySha1('aaa'))!.filename, 'a.jpg');
      expect(await dao.setState('local-1', UploadQueueState.done), isFalse);
      expect(await dao.setState('local-1', UploadQueueState.uploading), isTrue);
      expect(await dao.setState('local-1', UploadQueueState.done), isTrue);
      expect(await dao.countByState(UploadQueueState.done), 1);
    });

    test('crash recovery re-queues stuck uploading items', () async {
      final dao = UploadQueueDao(db);
      final now = DateTime.utc(2026, 11, 22);
      await dao.enqueue(
        UploadQueueItem(
          id: 'local-9',
          localPath: '/x/b.jpg',
          filename: 'b.jpg',
          sha1: 'bbb',
          sizeBytes: 10,
          state: UploadQueueState.uploading,
          retryCount: 0,
          fileCreatedAt: now,
          fileModifiedAt: now,
          createdAt: now,
        ),
      );
      expect(await dao.resetStuckUploading(), 1);
      expect(await dao.countByState(UploadQueueState.pending), 1);
    });

    test('pending ops are FIFO by id', () async {
      final dao = PendingOpsDao(db);
      final first = await dao.enqueue(kind: 'favorite', assetId: 'a1');
      final second = await dao.enqueue(kind: 'delete', assetId: 'a1');
      final third = await dao.enqueue(kind: 'archive', assetId: 'a1');
      expect(await dao.count(), 3);
      final rows = await dao.listOldestFirst();
      expect(rows.map((r) => r.id), [first, second, third]);
      expect(
        sortPendingOpsForReplay(rows.reversed.toList())
            .map((r) => r.id),
        [first, second, third],
      );
    });

    test('sync checkpoints + settings round-trip', () async {
      final checkpoints = SyncCheckpointDao(db);
      await checkpoints.save('AssetV2', 'ack-42');
      expect(await checkpoints.get('AssetV2'), 'ack-42');
      final settings = SettingsDao(db);
      await settings.set('backup.wifi_only', 'true');
      expect(await settings.get('backup.wifi_only'), 'true');
      expect(await settings.get('missing'), isNull);
    });
  });

  group('SyncService.applyRecord', () {
    late NovaDatabase db;

    setUp(() {
      db = NovaDatabase.memory();
    });

    tearDown(() async {
      await db.close();
    });

    test('AssetV2 upserts, AssetDeleteV1 removes, album membership tracks',
        () async {
      final api = _mockApi(MockClient((_) async => http.Response('{}', 200)));
      final sync = SyncService(api: api, db: db);
      addTearDown(sync.dispose);
      await sync.applyRecord(
        SyncRecord(type: 'AssetV2', data: _assetJson('asset-1')),
      );
      expect(await AssetDao(db).count(), 1);
      await sync.applyRecord(
        const SyncRecord(
          type: 'AlbumToAssetV1',
          data: {'albumId': 'album-1', 'assetId': 'asset-1'},
        ),
      );
      await sync.applyRecord(
        SyncRecord(type: 'AssetDeleteV1', data: {'assetId': 'asset-1'}),
      );
      expect(await AssetDao(db).count(), 0);
    });
  });

  group('pending-ops replay order', () {
    test('replays favorite → archive → delete in user order', () async {
      final seen = <String>[];
      final api = _mockApi(
        MockClient((request) async {
          seen.add('${request.method} ${request.url.path}');
          return http.Response('{}', 200);
        }),
      );
      final db = NovaDatabase.memory();
      addTearDown(() => db.close());
      final ops = PendingOpsService(api: api, db: db);
      addTearDown(ops.dispose);
      await ops.enqueue(
        kind: 'favorite',
        assetId: 'asset-1',
        payload: {'isFavorite': true},
      );
      await ops.enqueue(
        kind: 'archive',
        assetId: 'asset-1',
        payload: {'archived': true},
      );
      await ops.enqueue(
        kind: 'delete',
        assetId: 'asset-1',
        payload: {'force': false},
      );
      final results = await ops.replayAll();
      expect(results.map((r) => r.outcome), ['replayed', 'replayed', 'replayed']);
      expect(seen, [
        'PUT /api/assets/asset-1',
        'PUT /api/assets/asset-1',
        'DELETE /api/assets',
      ]);
      expect(await ops.pendingCount, 0);
    });

    test('a 404 on replay drops the op (server-wins) and continues',
        () async {
      final api = _mockApi(
        MockClient((request) async {
          if (request.url.path == '/api/assets/gone') {
            return http.Response('{"message":"not found"}', 404);
          }
          return http.Response('{}', 200);
        }),
      );
      final db = NovaDatabase.memory();
      addTearDown(() => db.close());
      final ops = PendingOpsService(api: api, db: db);
      addTearDown(ops.dispose);
      await ops.enqueue(
        kind: 'favorite',
        assetId: 'gone',
        payload: {'isFavorite': true},
      );
      await ops.enqueue(
        kind: 'favorite',
        assetId: 'asset-1',
        payload: {'isFavorite': true},
      );
      final results = await ops.replayAll();
      expect(results[0].outcome, 'dropped_conflict');
      expect(results[1].outcome, 'replayed');
      expect(await ops.pendingCount, 0);
    });
  });

  group('BackupEngine end-to-end (fake scanner + mock server)', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('nova_backup');
    });

    tearDown(() async {
      await tempDir.delete(recursive: true);
    });

    Future<LocalMediaFile> makeFile(String name, String contents) async {
      final file = File('${tempDir.path}/$name');
      await file.writeAsString(contents);
      return LocalMediaFile(
        id: name,
        path: file.path,
        filename: name,
        sizeBytes: contents.length,
        createdAt: DateTime.utc(2026, 11, 1),
        modifiedAt: DateTime.utc(2026, 11, 1),
        isVideo: false,
        folderName: 'Camera',
      );
    }

    test('duplicate is skipped, new file uploads, chip ends up-to-date',
        () async {
      final dup = await makeFile('dup.jpg', 'already-there');
      final fresh = await makeFile('fresh.jpg', 'brand-new');
      var uploads = 0;
      final api = _mockApi(
        MockClient((request) async {
          final path = request.url.path;
          if (path == '/api/assets/bulk-upload-check') {
            final body = jsonDecode(request.body) as Map<String, Object?>;
            final assets = (body['assets'] as List).cast<Map<String, Object?>>();
            return http.Response(
              jsonEncode({
                'results': [
                  for (final a in assets)
                    {
                      'id': a['id'],
                      'checksum': a['checksum'],
                      // local-dup.jpg is the duplicate
                      'action': (a['id'] as String).contains('dup')
                          ? 'reject'
                          : 'accept',
                    },
                ],
              }),
              200,
            );
          }
          if (path == '/api/assets' && request.method == 'POST') {
            uploads++;
            return http.Response(
              '{"id":"srv-fresh","status":"created"}',
              201,
            );
          }
          return http.Response('{}', 200);
        }),
      );
      final db = NovaDatabase.memory();
      addTearDown(() => db.close());
      final backupService = BackupService();
      addTearDown(backupService.dispose);
      final engine = BackupEngine(
        api: api,
        db: db,
        backupService: backupService,
        scanner: _FakeScanner([dup, fresh]),
        sleeper: (_) async {},
      );
      await engine.runOnce(manual: true);
      expect(uploads, 1, reason: 'only the non-duplicate is uploaded');
      final queue = UploadQueueDao(db);
      expect(await queue.countByState(UploadQueueState.done), 2);
      expect(backupService.status.state, BackupState.upToDate);
      expect(backupService.status.uploaded, 2);
    });

    test('failed upload retries with backoff, then succeeds', () async {
      final file = await makeFile('flaky.jpg', 'flaky-contents');
      var attempts = 0;
      final api = _mockApi(
        MockClient((request) async {
          final path = request.url.path;
          if (path == '/api/assets/bulk-upload-check') {
            final body = jsonDecode(request.body) as Map<String, Object?>;
            final assets = (body['assets'] as List).cast<Map<String, Object?>>();
            return http.Response(
              jsonEncode({
                'results': [
                  for (final a in assets)
                    {'id': a['id'], 'checksum': a['checksum'], 'action': 'accept'},
                ],
              }),
              200,
            );
          }
          if (path == '/api/assets' && request.method == 'POST') {
            attempts++;
            if (attempts < 3) {
              return http.Response('{"message":"boom"}', 500);
            }
            return http.Response('{"id":"srv-1","status":"created"}', 201);
          }
          return http.Response('{}', 200);
        }),
      );
      final db = NovaDatabase.memory();
      addTearDown(() => db.close());
      final backupService = BackupService();
      addTearDown(backupService.dispose);
      final delays = <Duration>[];
      final engine = BackupEngine(
        api: api,
        db: db,
        backupService: backupService,
        scanner: _FakeScanner([file]),
        sleeper: (d) async {
          delays.add(d);
        },
      );
      await engine.runOnce(manual: true);
      expect(attempts, 3);
      expect(delays, [const Duration(seconds: 2), const Duration(seconds: 4)]);
      expect(
        await UploadQueueDao(db).countByState(UploadQueueState.done),
        1,
      );
      expect(backupService.status.state, BackupState.upToDate);
    });

    test('exhausted retries leave the item failed with an error state',
        () async {
      final file = await makeFile('dead.jpg', 'never-uploads');
      final api = _mockApi(
        MockClient((request) async {
          final path = request.url.path;
          if (path == '/api/assets/bulk-upload-check') {
            return http.Response(
              jsonEncode({
                'results': [
                  {'id': 'local-dead.jpg', 'checksum': 'x', 'action': 'accept'},
                ],
              }),
              200,
            );
          }
          if (path == '/api/assets') {
            return http.Response('{"message":"boom"}', 500);
          }
          return http.Response('{}', 200);
        }),
      );
      final db = NovaDatabase.memory();
      addTearDown(() => db.close());
      final backupService = BackupService();
      addTearDown(backupService.dispose);
      final engine = BackupEngine(
        api: api,
        db: db,
        backupService: backupService,
        scanner: _FakeScanner([file]),
        sleeper: (_) async {},
      );
      await engine.runOnce(manual: true);
      final failed =
          await UploadQueueDao(db).listByState(UploadQueueState.failed);
      expect(failed.length, 1);
      expect(failed.first.retryCount, 3);
      expect(failed.first.lastError, isNotNull);
      expect(backupService.status.state, BackupState.error);
    });
  });
}
