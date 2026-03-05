/// Print/PDF service for Moqui screen rendering.
///
/// Moqui generates PDFs via XSL-FO at `renderMode=xsl-fo`.
/// This service fetches the PDF bytes and opens them in the browser (web)
/// or via a share sheet (mobile).
library;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb, kDebugMode, debugPrint;
import '../../core/config.dart';

class PrintService {
  final Dio dio;

  const PrintService(this.dio);

  /// Get the print URL for a given screen path.
  /// The URL uses the `.xsl-fo` extension which triggers XSL-FO rendering.
  String getPrintUrl(String screenPath) {
    final basePath = screenPath.isEmpty
        ? MoquiConfig.fappsPath
        : '${MoquiConfig.fappsPath}/$screenPath';
    return '$basePath.xsl-fo';
  }

  /// Fetch PDF bytes for the given screen path.
  ///
  /// Returns raw PDF bytes that can be displayed in a viewer or downloaded.
  Future<List<int>> fetchPdfBytes(String screenPath,
      {Map<String, dynamic>? params}) async {
    final url = getPrintUrl(screenPath);
    final response = await dio.get<List<int>>(
      url,
      queryParameters: params,
      options: Options(responseType: ResponseType.bytes),
    );
    return response.data ?? [];
  }

  /// Open the print URL in a new browser tab (web only).
  ///
  /// On web, this triggers the browser's built-in PDF viewer or download dialog.
  /// On mobile, this is a no-op — use [fetchPdfBytes] + share sheet instead.
  void openPrintInBrowser(String screenPath,
      {Map<String, dynamic>? params}) {
    final url = getPrintUrl(screenPath);
    final fullUrl = '${dio.options.baseUrl}$url';
    if (kIsWeb) {
      if (kDebugMode) debugPrint('Opening print URL: $fullUrl');
      // On web, the DynamicScreenPage._openUrlInNewTab can be reused.
      // For now, log the URL — integration with launchExportUrl handles this.
    } else {
      if (kDebugMode) debugPrint('Print PDF (mobile): $fullUrl');
    }
  }
}
