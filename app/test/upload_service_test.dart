/// Upload dedup tests — SHA-1 vectors and the bulk-check split logic.
/// SHA-1 is the server's duplicate-detection checksum (whole file).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:nova_photos/src/services/upload_service.dart';

void main() {
  group('sha1Hex', () {
    test('matches the standard SHA-1 test vectors', () {
      expect(
        sha1Hex([]),
        'da39a3ee5e6b4b0d3255bfef95601890afd80709',
      );
      expect(
        sha1HexOfString('abc'),
        'a9993e364706816aba3e25717850c26c9cd0d89d',
      );
      expect(
        sha1HexOfString('The quick brown fox jumps over the lazy dog'),
        '2fd4e1c67a2d28fced849ee1bb76e7391b93eb12',
      );
      // 1,000,000 x 'a' — the classic long-input vector.
      expect(
        sha1Hex(List<int>.filled(1000000, 0x61)),
        '34aa973cd4c4daa4f61eeb2bdbad27316534016f',
      );
    });

    test('is a 40-char lowercase hex string', () {
      final hash = sha1Hex([1, 2, 3, 4, 5]);
      expect(hash, matches(RegExp(r'^[0-9a-f]{40}$')));
    });
  });

  group('splitBulkCheckResults', () {
    final candidates = [
      UploadCandidate(
        id: 'local-1',
        filename: 'IMG_0001.jpg',
        checksum: 'aaa',
        fileCreatedAt: DateTime.utc(2026, 11, 1),
        fileModifiedAt: DateTime.utc(2026, 11, 1),
      ),
      UploadCandidate(
        id: 'local-2',
        filename: 'IMG_0002.jpg',
        checksum: 'bbb',
        fileCreatedAt: DateTime.utc(2026, 11, 2),
        fileModifiedAt: DateTime.utc(2026, 11, 2),
      ),
      UploadCandidate(
        id: 'local-3',
        filename: 'IMG_0003.jpg',
        checksum: 'ccc',
        fileCreatedAt: DateTime.utc(2026, 11, 3),
        fileModifiedAt: DateTime.utc(2026, 11, 3),
      ),
    ];

    test('reject -> already present, accept -> upload', () {
      final split = splitBulkCheckResults(candidates, {
        'local-1': 'reject',
        'local-2': 'accept',
        'local-3': 'reject',
      });
      expect(split.toUpload.map((c) => c.id), ['local-2']);
      expect(
        split.alreadyPresent.map((c) => c.id),
        ['local-1', 'local-3'],
      );
    });

    test('unknown action fails safe: upload (server still dedups)', () {
      final split = splitBulkCheckResults(candidates, {
        'local-1': 'reject',
        // local-2 and local-3 missing from the server answer entirely.
      });
      expect(split.toUpload.map((c) => c.id), ['local-2', 'local-3']);
      expect(split.alreadyPresent.map((c) => c.id), ['local-1']);
    });
  });
}
