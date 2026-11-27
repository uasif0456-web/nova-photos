/// Trash API — `POST /trash/restore`, `/trash/restore/assets`,
/// `/trash/empty`. Hand-written from spec v3.4.2.
///
/// There is no `GET /trash` list endpoint — trashed assets are listed
/// via `POST /search/metadata` with `isTrashed: true` (or
/// `GET /timeline/buckets?isTrashed=true`). Emptying the trash is
/// permanent and irreversible.
library;

import 'api_client.dart';

class TrashApi {
  const TrashApi(this.client);

  final ImmichApiClient client;

  /// `POST /trash/restore` — restore everything in the trash.
  Future<void> restoreAll() async {
    final response = await client.post('/trash/restore');
    client.decodeJson(response);
  }

  /// `POST /trash/restore/assets` — restore specific assets.
  Future<void> restoreAssets(List<String> assetIds) async {
    final response = await client.post('/trash/restore/assets', body: {
      'ids': assetIds,
    });
    client.decodeJson(response);
  }

  /// `POST /trash/empty` — permanently delete everything in the trash.
  /// Irreversible. Only call after an explicit user confirmation.
  Future<void> emptyTrash() async {
    final response = await client.post('/trash/empty');
    client.decodeJson(response);
  }
}
