/// Moqui Flutter — Core configuration constants.
class MoquiConfig {
  MoquiConfig._();

  /// The base URL of the Moqui server (override via environment or runtime config).
  static String baseUrl = const String.fromEnvironment(
    'MOQUI_BASE_URL',
    defaultValue: 'http://localhost:8080',
  );

  /// Path prefix for the Flutter JSON render-mode screens.
  static const String fappsPath = '/fapps';

  /// Path prefix for the entity REST API.
  static const String entityRestPath = '/rest/e1';

  /// Path prefix for the service REST API.
  static const String serviceRestPath = '/rest/s1';

  /// Path for login endpoint.
  static const String loginPath = '/rest/login';

  /// Path for logout endpoint.
  static const String logoutPath = '/rest/logout';

  /// Path for menuData endpoint.
  static const String menuDataPath = '/menuData';

  /// WebSocket path for notifications.
  static const String notifyWsPath = '/notws';

  /// WebSocket path for log streaming.
  static const String logStreamWsPath = '/logws';

  /// Default page size for paginated lists.
  static const int defaultPageSize = 20;

  /// HTTP timeout in milliseconds.
  static const int httpTimeoutMs = 30000;

  /// WebSocket reconnect interval in seconds.
  static const int wsReconnectIntervalSec = 30;

  /// WebSocket max reconnect attempts.
  static const int wsMaxReconnectAttempts = 6;
}
