import 'package:dio/dio.dart';

/// Stub implementation for non-web platforms.
/// Does nothing — CORS credentials are only needed on web.
void configureBrowserAdapter(Dio dio) {
  // No-op on non-web platforms
}
