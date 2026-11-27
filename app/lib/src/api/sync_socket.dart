/// Live-update socket — Socket.IO client for the Immich server's
/// push events. Hand-written from the server's websocket behaviour
/// (documented in IMMICH_API_CATALOGUE.md §5.17; the Socket.IO
/// handshake is NOT in the OpenAPI spec).
///
/// Server: Socket.IO v4 at `wss://<host>/api/socket.io/`, transports
/// `websocket` only. Auth uses the same session JWT as REST — sent as
/// the Socket.IO `auth` payload (`{token: <jwt>}`).
///
/// The socket is a *hint*, not the source of truth: on connect (and
/// reconnect) the caller should run a `/sync/stream` catch-up. Events
/// are exposed as a broadcast stream of [NovaSocketEvent].
library;

import 'dart:async';

import 'package:socket_io_client/socket_io_client.dart' as io;

import 'api_client.dart';

/// One server-pushed event.
class NovaSocketEvent {
  const NovaSocketEvent({required this.name, this.payload});

  /// e.g. `on_upload_success`, `on_asset_update`, `on_asset_delete`,
  /// `on_asset_trash`, `on_asset_restore`, `on_server_version`,
  /// `on_config_update`, `on_session_delete`, `on_notification`.
  final String name;

  /// Decoded payload (usually a Map, sometimes a String id or a List).
  final Object? payload;

  @override
  String toString() => 'NovaSocketEvent($name)';
}

/// Socket.IO connection to one Immich server.
class NovaSocket {
  NovaSocket({required this.client});

  final ImmichApiClient client;

  io.Socket? _socket;
  final _eventsController = StreamController<NovaSocketEvent>.broadcast();
  final _connectionController = StreamController<bool>.broadcast();

  /// All server events, in arrival order.
  Stream<NovaSocketEvent> get events => _eventsController.stream;

  /// `true` on connect, `false` on disconnect.
  Stream<bool> get connectionChanges => _connectionController.stream;

  bool get isConnected => _socket?.connected ?? false;

  /// Events NOVA subscribes to (the live-update set from the catalogue).
  static const List<String> subscribedEvents = [
    'on_upload_success',
    'on_asset_update',
    'on_asset_delete',
    'on_asset_trash',
    'on_asset_restore',
    'on_asset_hidden',
    'on_asset_stack_update',
    'on_person_thumbnail',
    'on_server_version',
    'on_config_update',
    'on_new_release',
    'on_notification',
    'on_session_delete',
    'ResourceEventV1',
    'AppRestartV1',
  ];

  /// Connect with the current session token. Safe to call when already
  /// connected (no-op) or after a disconnect (reconnects).
  void connect({required String accessToken}) {
    if (_socket?.connected ?? false) return;
    disconnect();
    final socket = io.io(
      client.serverUrl,
      io.OptionBuilder()
          .setPath(MediaUrls(client).socketIoPath)
          .setTransports(['websocket'])
          .setAuth({'token': accessToken})
          .enableReconnection()
          .enableForceNew()
          .build(),
    );
    _socket = socket;
    socket.onConnect((_) => _connectionController.add(true));
    socket.onDisconnect((_) => _connectionController.add(false));
    socket.onConnectError((_) => _connectionController.add(false));
    for (final event in subscribedEvents) {
      socket.on(event, (data) {
        _eventsController.add(NovaSocketEvent(name: event, payload: data));
      });
    }
    socket.connect();
  }

  void disconnect() {
    _socket?.disconnect();
    _socket?.dispose();
    _socket = null;
  }

  void dispose() {
    disconnect();
    _eventsController.close();
    _connectionController.close();
  }
}
