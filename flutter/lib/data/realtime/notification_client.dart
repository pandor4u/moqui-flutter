import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import '../../core/config.dart';
import '../../core/providers.dart';
import '../api/moqui_api_client.dart';

final _log = Logger('MoquiNotificationClient');

/// Notification message from the Moqui WebSocket.
class MoquiNotification {
  final String topic;
  final String title;
  final String message;
  final String link;
  final String type; // info, success, warning, danger
  final bool showAlert;

  MoquiNotification({
    required this.topic,
    this.title = '',
    this.message = '',
    this.link = '',
    this.type = 'info',
    this.showAlert = true,
  });

  factory MoquiNotification.fromJson(Map<String, dynamic> json) {
    return MoquiNotification(
      topic: json['topic']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      message: json['message']?.toString() ?? '',
      link: json['link']?.toString() ?? '',
      type: json['type']?.toString() ?? 'info',
      showAlert: json['showAlert'] == true,
    );
  }
}

/// WebSocket client for Moqui real-time notifications.
///
/// Connects to /notws, subscribes to topics, and dispatches
/// notifications via a broadcast StreamController.
class MoquiNotificationClient {
  final MoquiApiClient apiClient;

  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;
  bool _isConnected = false;
  final Set<String> _subscribedTopics = {};

  final StreamController<MoquiNotification> _notificationController =
      StreamController<MoquiNotification>.broadcast();

  /// Stream of notification events. Listen to this in the UI.
  Stream<MoquiNotification> get notifications => _notificationController.stream;

  MoquiNotificationClient({required this.apiClient});

  /// Connect to the Moqui notification WebSocket.
  void connect({List<String> topics = const ['ALL']}) {
    final wsUrl = MoquiConfig.baseUrl
        .replaceFirst('http://', 'ws://')
        .replaceFirst('https://', 'wss://');
    final uri = Uri.parse('$wsUrl${MoquiConfig.notifyWsPath}');

    try {
      _channel = WebSocketChannel.connect(uri);
      _isConnected = true;
      _reconnectAttempts = 0;

      // Subscribe to topics on open
      _subscribedTopics.addAll(topics);
      _sendSubscribe(topics);

      // Listen for messages
      _subscription = _channel!.stream.listen(
        _onMessage,
        onError: _onError,
        onDone: _onDone,
      );

      _log.info('Connected to notification WebSocket at $uri');
    } catch (e) {
      _log.warning('Failed to connect to WebSocket: $e');
      _scheduleReconnect();
    }
  }

  /// Subscribe to additional topics.
  void subscribe(List<String> topics) {
    _subscribedTopics.addAll(topics);
    if (_isConnected) _sendSubscribe(topics);
  }

  /// Unsubscribe from topics.
  void unsubscribe(List<String> topics) {
    _subscribedTopics.removeAll(topics);
    if (_isConnected && _channel != null) {
      _channel!.sink.add('unsubscribe:${topics.join(",")}');
    }
  }

  /// Disconnect and clean up.
  void disconnect() {
    _reconnectTimer?.cancel();
    _subscription?.cancel();
    _channel?.sink.close();
    _isConnected = false;
  }

  void dispose() {
    disconnect();
    _notificationController.close();
  }

  // --- Internal ---

  void _sendSubscribe(List<String> topics) {
    if (_channel != null && topics.isNotEmpty) {
      _channel!.sink.add('subscribe:${topics.join(",")}');
    }
  }

  void _onMessage(dynamic message) {
    try {
      final data = jsonDecode(message.toString());
      if (data is Map<String, dynamic>) {
        final notification = MoquiNotification.fromJson(data);
        _notificationController.add(notification);
      }
    } catch (e) {
      _log.warning('Failed to parse notification: $e');
    }
  }

  void _onError(dynamic error) {
    _log.warning('WebSocket error: $error');
    _isConnected = false;
    _scheduleReconnect();
  }

  void _onDone() {
    _log.info('WebSocket connection closed');
    _isConnected = false;
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_reconnectAttempts >= MoquiConfig.wsMaxReconnectAttempts) {
      _log.warning('Max reconnect attempts reached');
      return;
    }

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(
      const Duration(seconds: MoquiConfig.wsReconnectIntervalSec),
      () {
        _reconnectAttempts++;
        _log.info('Reconnect attempt $_reconnectAttempts');
        connect(topics: _subscribedTopics.toList());
      },
    );
  }
}

/// Riverpod stream provider for notifications.
final notificationStreamProvider =
    StreamProvider<MoquiNotification>((ref) {
  final client = ref.watch(notificationClientProvider);
  return client.notifications;
});
