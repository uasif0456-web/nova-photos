/// LIVE smoke test — talks to the PUBLIC Immich demo server.
///
/// Run explicitly only:
///   `DEMO_USER=<demo-email> DEMO_PASS=<demo-password> flutter test --tags live`
///
/// (The public demo credentials are published in Immich's own README;
///  they are supplied here, never written into the repo.)
///
/// Credentials come from the environment (the public demo credentials
/// published in Immich's own README). They are never committed and
/// never stored — this test uses an in-memory token store and a
/// throwaway client. Without DEMO_USER/DEMO_PASS the test skips.
/// Tags: `live` — the default `flutter test` run skips it via the
/// runtime `skip` below (and `--exclude-tags live` works too).
// ignore_for_file: avoid_print

@Tags(['live'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nova_photos/src/api/api_client.dart';
import 'package:nova_photos/src/api/nova_api.dart';
import 'package:nova_photos/src/models/search.dart';

void main() {
  final demoUser = Platform.environment['DEMO_USER'];
  final demoPass = Platform.environment['DEMO_PASS'];
  final skipReason = (demoUser == null || demoUser.isEmpty ||
          demoPass == null || demoPass.isEmpty)
      ? 'Set DEMO_USER and DEMO_PASS to run the live smoke test.'
      : false;

  test('live smoke: demo server login + list + thumbnail', () async {
    final client = ImmichApiClient(serverUrl: 'https://demo.immich.app');
    final api = NovaApi(client);
    try {
      // 1. Connectivity + version (no auth needed for ping; version is
      //    also public on the demo server).
      await api.server.ping();
      final version = await api.server.getVersion();
      print('LIVE: server version $version');
      expect(version.major, 3);
      expect(version.minor, greaterThanOrEqualTo(4));

      // 2. Login with the public demo credentials.
      final login = await api.auth.login(email: demoUser!, password: demoPass!);
      print('LIVE: logged in as ${login.userEmail} (userId ${login.userId})');
      expect(login.accessToken, isNotEmpty);

      // 3. Feature flags + current user.
      final features = await api.server.getFeatures();
      print(
        'LIVE: features smartSearch=${features.smartSearch} '
        'facialRecognition=${features.facialRecognition} '
        'trash=${features.trash}',
      );
      final me = await api.auth.getCurrentUser();
      print('LIVE: current user ${me.name} <${me.email}>');
      expect(me.id, login.userId);

      // 4. Real asset listing via POST /search/metadata.
      final stats = await api.assets.getStatistics();
      print(
        'LIVE: library statistics images=${stats.images} '
        'videos=${stats.videos} total=${stats.total}',
      );
      final page = await api.search.searchMetadata(
        const MetadataSearchRequest(size: 10),
      );
      print(
        'LIVE: search/metadata first page: ${page.items.length} assets '
        '(count=${page.count}, hasNextPage=${page.hasNextPage})',
      );
      expect(page.items, isNotEmpty);
      final first = page.items.first;
      print(
        'LIVE: first asset ${first.id} type=${first.type} '
        'file=${first.originalFileName} '
        'taken=${first.localDateTime.toIso8601String()}',
      );

      // 5. One real thumbnail fetch.
      final thumb = await api.client.getBytes(
        '/assets/${first.id}/thumbnail',
        query: {'size': 'thumbnail'},
      );
      final thumbBytes = api.client.decodeBytes(thumb);
      print('LIVE: thumbnail bytes=${thumbBytes.length}');
      expect(thumbBytes, isNotEmpty);

      // 6. Timeline buckets (the v1 timeline source) + one bucket's assets.
      final buckets = await api.timeline.getBuckets();
      print('LIVE: timeline buckets=${buckets.length}');
      expect(buckets, isNotEmpty);
      final firstBucket = buckets.first;
      print(
        'LIVE: first bucket ${firstBucket.timeBucket.toIso8601String()} '
        'count=${firstBucket.count}',
      );
      final bucketAssets =
          await api.timeline.getBucket(firstBucket.timeBucket);
      print('LIVE: first bucket assets=${bucketAssets.length}');
      expect(bucketAssets.length, firstBucket.count);
    } finally {
      api.dispose();
    }
  }, skip: skipReason, timeout: const Timeout(Duration(seconds: 90)));
}
