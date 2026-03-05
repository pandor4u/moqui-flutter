import 'package:dio/dio.dart';
import 'package:dio/browser.dart';

/// Web implementation — enables withCredentials for CORS cookie handling.
void configureBrowserAdapter(Dio dio) {
  dio.httpClientAdapter = BrowserHttpClientAdapter(withCredentials: true);
}
