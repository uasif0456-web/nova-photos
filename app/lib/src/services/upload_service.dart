/// SHA-1 helpers + the upload dedup flow.
///
/// Duplicate detection is SHA-1 of the **whole file contents**
/// (`ChecksumAlgorithm.sha1File`). The flow for every candidate file is:
/// 1. Compute the hex SHA-1 locally.
/// 2. `POST /assets/bulk-upload-check` with all candidates at once —
///    one round-trip instead of one per file.
/// 3. Upload only the `accept`ed files, sending the checksum as the
///    `x-immich-checksum` header so the server can still catch a race.
/// 4. Treat HTTP 200 `status: duplicate` as a success (the server
///    already had the file).
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

/// Hex SHA-1 of [bytes] (lowercase, 40 chars).
String sha1Hex(List<int> bytes) => sha1.convert(bytes).toString();

/// Streaming hex SHA-1 of a file's contents — reads in chunks, so a
/// multi-hundred-MB video never has to sit in memory whole. Used by
/// the backup engine; [sha1Hex] stays for small in-memory inputs.
Future<String> sha1HexOfFile(File file) async {
  final digest = await sha1.bind(file.openRead()).first;
  return digest.toString();
}

/// Hex SHA-1 of a UTF-8 string. Used in tests; files use [sha1Hex].
String sha1HexOfString(String text) => sha1Hex(utf8.encode(text));

/// One local file offered for upload, with its checksum precomputed.
class UploadCandidate {
  const UploadCandidate({
    required this.id,
    required this.filename,
    required this.checksum,
    required this.fileCreatedAt,
    required this.fileModifiedAt,
  });

  /// Client-side echo id (usually the local asset id or filename) —
  /// the server echoes it back in the bulk-check result.
  final String id;
  final String filename;

  /// Hex SHA-1 of the whole file.
  final String checksum;
  final DateTime fileCreatedAt;
  final DateTime fileModifiedAt;

  Map<String, String> toBulkCheckEntry() => {
        'id': id,
        'checksum': checksum,
      };
}

/// Split bulk-check results into "upload these" and "already on the
/// server". Pure function — unit-tested.
({List<UploadCandidate> toUpload, List<UploadCandidate> alreadyPresent})
splitBulkCheckResults(
  List<UploadCandidate> candidates,
  Map<String, String> idToAction,
) {
  final toUpload = <UploadCandidate>[];
  final alreadyPresent = <UploadCandidate>[];
  for (final candidate in candidates) {
    final action = idToAction[candidate.id];
    // Unknown / missing action: fail safe and upload (the server will
    // still answer `duplicate` if it already has the file).
    if (action == 'reject') {
      alreadyPresent.add(candidate);
    } else {
      toUpload.add(candidate);
    }
  }
  return (toUpload: toUpload, alreadyPresent: alreadyPresent);
}
