/// `NovaApi` — the single entry point to every domain API.
///
/// One [ImmichApiClient] (transport + auth) shared by all domain APIs,
/// so the token, cookie and server URL live in exactly one place.
/// Track B/C code takes a [NovaApi] (or one domain API) from the
/// providers in `lib/src/providers/`, never constructs clients itself.
library;

import 'albums_api.dart';
import 'api_client.dart';
import 'assets_api.dart';
import 'auth_api.dart';
import 'memories_api.dart';
import 'people_api.dart';
import 'search_api.dart';
import 'server_api.dart';
import 'shared_links_api.dart';
import 'sync_api.dart';
import 'sync_socket.dart';
import 'tags_api.dart';
import 'timeline_api.dart';
import 'trash_api.dart';

class NovaApi {
  NovaApi(this.client)
      : server = ServerApi(client),
        auth = AuthApi(client),
        assets = AssetsApi(client),
        search = SearchApi(client),
        timeline = TimelineApi(client),
        albums = AlbumsApi(client),
        people = PeopleApi(client),
        memories = MemoriesApi(client),
        tags = TagsApi(client),
        trash = TrashApi(client),
        sharedLinks = SharedLinksApi(client),
        sync = SyncApi(client),
        socket = NovaSocket(client: client),
        media = MediaUrls(client);

  final ImmichApiClient client;
  final ServerApi server;
  final AuthApi auth;
  final AssetsApi assets;
  final SearchApi search;
  final TimelineApi timeline;
  final AlbumsApi albums;
  final PeopleApi people;
  final MemoriesApi memories;
  final TagsApi tags;
  final TrashApi trash;
  final SharedLinksApi sharedLinks;
  final SyncApi sync;

  /// Live-update socket (connect after login).
  final NovaSocket socket;

  /// Media URL builders (thumbnails, originals, playback).
  final MediaUrls media;

  void dispose() {
    socket.dispose();
    client.close();
  }
}
