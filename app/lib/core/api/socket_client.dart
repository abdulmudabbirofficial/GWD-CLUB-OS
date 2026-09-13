import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

/// One live event from the server.
class LiveEvent {
  const LiveEvent(this.name, this.data);
  final String name;
  final Map<String, dynamic> data;
}

enum LiveStatus {
  idle,
  connecting,
  connected,
  disconnected,

  /// The server rejected our token. Retrying cannot fix this, so we stop.
  unauthorized,
}

/// The Socket.IO connection.
///
/// The server only emits to rooms this user belongs to, so anything arriving
/// here is already scoped — the client never has to filter for permission,
/// only for relevance to the screen currently on top.
class SocketClient {
  SocketClient({required String Function() baseUrlProvider})
      : _baseUrlProvider = baseUrlProvider;

  /// Resolved at connect time, so changing the server address reconnects to the
  /// new one instead of silently talking to the old.
  final String Function() _baseUrlProvider;
  String get baseUrl => _baseUrlProvider();

  io.Socket? _socket;

  final _events = StreamController<LiveEvent>.broadcast();
  Stream<LiveEvent> get events => _events.stream;

  final ValueNotifier<LiveStatus> status = ValueNotifier(LiveStatus.idle);

  /// Every event the server can push. Listed explicitly rather than using a
  /// catch-all so an unexpected event name is a visible gap, not a silent drop.
  static const _eventNames = <String>[
    'task:created',
    'task:updated',
    'notification:new',
    'taskRequest:created',
    'taskRequest:updated',
    'accessRequest:created',
    'accessRequest:updated',
    'calendarEvent:created',
    'calendarEvent:updated',
    'calendarEvent:deleted',
    'department:created',
    'department:updated',
    'department:deleted',
    'user:updated',
  ];

  bool get isConnected => _socket?.connected ?? false;

  /// Raised when the handshake is rejected, so the app can drop to sign-in
  /// instead of spinning.
  VoidCallback? onUnauthorized;

  void connect(String token) {
    disconnect();
    status.value = LiveStatus.connecting;

    final socket = io.io(
      baseUrl.isEmpty ? '/' : baseUrl,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .setAuth({'token': token})
          .enableReconnection()
          // Mobile networks drop constantly; back off rather than hammering.
          .setReconnectionDelay(1000)
          .setReconnectionDelayMax(10000)
          .setReconnectionAttempts(999)
          .disableAutoConnect()
          .build(),
    );

    socket.onConnect((_) => status.value = LiveStatus.connected);
    socket.onDisconnect((_) {
      if (status.value != LiveStatus.unauthorized) {
        status.value = LiveStatus.disconnected;
      }
    });
    socket.onConnectError((error) {
      final message = '$error';
      // A rejected token never becomes valid by trying again. Left retrying, it
      // reconnects roughly once a second, and every attempt rebuilds the whole
      // widget tree — which makes the UI feel frozen and swallows taps.
      if (message.contains('Authentication')
          || message.contains('Account not found')
          || message.contains('awaiting approval')) {
        status.value = LiveStatus.unauthorized;
        socket.dispose();
        _socket = null;
        debugPrint('[socket] handshake rejected, giving up: $message');
        onUnauthorized?.call();
        return;
      }
      status.value = LiveStatus.disconnected;
      debugPrint('[socket] connect error: $message');
    });

    socket.on('ready', (data) {
      status.value = LiveStatus.connected;
      if (data is Map) _emit('ready', data);
    });

    for (final name in _eventNames) {
      socket.on(name, (data) {
        if (data is Map) _emit(name, data);
      });
    }

    _socket = socket;
    socket.connect();
  }

  void _emit(String name, Map data) {
    if (_events.isClosed) return;
    _events.add(LiveEvent(name, data.cast<String, dynamic>()));
  }

  void disconnect() {
    _socket?.dispose();
    _socket = null;
    status.value = LiveStatus.idle;
  }

  void dispose() {
    disconnect();
    _events.close();
    status.dispose();
  }
}
