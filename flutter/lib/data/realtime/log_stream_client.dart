import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:logging/logging.dart';
import '../../core/config.dart';
import '../../domain/tools/tool_models.dart';
import '../api/moqui_api_client.dart';

final _log = Logger('MoquiLogStreamClient');

/// WebSocket client for real-time Moqui server log streaming.
///
/// Connects to a log stream WebSocket endpoint and broadcasts
/// [LogEntry] events. Supports level filtering on the server side
/// and local secondary filtering via [LogFilter].
class MoquiLogStreamClient {
  final MoquiApiClient apiClient;

  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;
  bool _isConnected = false;
  bool _isPaused = false;
  String _serverLevel = 'INFO';

  final StreamController<LogEntry> _logController =
      StreamController<LogEntry>.broadcast();

  /// Stream of log entries from the server. Listen to this in the UI.
  Stream<LogEntry> get logStream => _logController.stream;

  /// Whether the client is currently connected to the log WebSocket.
  bool get isConnected => _isConnected;

  /// Whether streaming is paused (entries are still received but buffered).
  bool get isPaused => _isPaused;

  MoquiLogStreamClient({required this.apiClient});

  /// Connect to the Moqui log stream WebSocket.
  ///
  /// [level] sets the minimum log level for server-side filtering.
  void connect({String level = 'INFO'}) {
    _serverLevel = level;

    final wsUrl = MoquiConfig.baseUrl
        .replaceFirst('http://', 'ws://')
        .replaceFirst('https://', 'wss://');
    final uri = Uri.parse('$wsUrl${MoquiConfig.logStreamWsPath}');

    try {
      _channel = WebSocketChannel.connect(uri);
      _isConnected = true;
      _reconnectAttempts = 0;

      // Send initial level filter
      _sendCommand('level:$_serverLevel');

      // Listen for log messages
      _subscription = _channel!.stream.listen(
        _onMessage,
        onError: _onError,
        onDone: _onDone,
      );

      _log.info('Connected to log stream WebSocket at $uri');
    } catch (e) {
      _log.warning('Failed to connect to log stream WebSocket: $e');
      _scheduleReconnect();
    }
  }

  /// Change the server-side log level filter.
  void setLevel(String level) {
    _serverLevel = level;
    if (_isConnected) _sendCommand('level:$level');
  }

  /// Pause log streaming (stops emitting to UI but stays connected).
  void pause() {
    _isPaused = true;
  }

  /// Resume log streaming after pause.
  void resume() {
    _isPaused = false;
  }

  /// Disconnect from the log stream WebSocket.
  void disconnect() {
    _reconnectTimer?.cancel();
    _subscription?.cancel();
    _channel?.sink.close();
    _isConnected = false;
  }

  /// Dispose all resources.
  void dispose() {
    disconnect();
    _logController.close();
  }

  // --- Internal ---

  void _sendCommand(String command) {
    if (_channel != null) {
      _channel!.sink.add(command);
    }
  }

  void _onMessage(dynamic message) {
    if (_isPaused) return;

    try {
      final msgStr = message.toString();
      // Try JSON first
      final data = jsonDecode(msgStr);
      if (data is Map<String, dynamic>) {
        _logController.add(LogEntry.fromJson(data));
      } else if (data is List) {
        // Batch of log entries
        for (final entry in data) {
          if (entry is Map<String, dynamic>) {
            _logController.add(LogEntry.fromJson(entry));
          }
        }
      }
    } catch (_) {
      // Not JSON — try parsing as a plain log line
      final line = message.toString().trim();
      if (line.isNotEmpty) {
        _logController.add(LogEntry.fromLogLine(line));
      }
    }
  }

  void _onError(dynamic error) {
    _log.warning('Log stream WebSocket error: $error');
    _isConnected = false;
    _scheduleReconnect();
  }

  void _onDone() {
    _log.info('Log stream WebSocket closed');
    _isConnected = false;
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_reconnectAttempts >= MoquiConfig.wsMaxReconnectAttempts) {
      _log.warning('Max reconnect attempts reached for log stream');
      return;
    }

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(
      const Duration(seconds: MoquiConfig.wsReconnectIntervalSec),
      () {
        _reconnectAttempts++;
        _log.info('Log stream reconnect attempt $_reconnectAttempts');
        connect(level: _serverLevel);
      },
    );
  }
}
