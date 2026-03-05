import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:file_picker/file_picker.dart';
import '../../core/config.dart';
import '../../domain/tools/tool_models.dart';
import '../cache/screen_cache.dart';
import 'web_adapter_stub.dart' if (dart.library.html) 'web_adapter_web.dart';

/// Dio-based HTTP client for all Moqui server communication.
///
/// Handles:
/// - Base URL configuration
/// - API key / session cookie authentication
/// - CSRF token (`moquiSessionToken`) injection
/// - Standard Moqui JSON response parsing
class MoquiApiClient {
  late final Dio dio;
  final Ref ref;
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  String? _apiKey;
  String? _csrfToken;

  MoquiApiClient({required this.ref}) {
    dio = Dio(BaseOptions(
      baseUrl: MoquiConfig.baseUrl,
      connectTimeout: const Duration(milliseconds: MoquiConfig.httpTimeoutMs),
      receiveTimeout: const Duration(milliseconds: MoquiConfig.httpTimeoutMs),
      headers: {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      },
      // Enable cookies/credentials for web browser CORS with Moqui session
      extra: {'withCredentials': true},
    ));

    // On web, set the browser HTTP adapter with withCredentials for CORS cookies
    if (kIsWeb) {
      configureBrowserAdapter(dio);
    }

    dio.interceptors.add(InterceptorsWrapper(
      onRequest: _onRequest,
      onResponse: _onResponse,
      onError: _onError,
    ));
  }

  // --- Auth ---

  /// Set API key for stateless authentication (mobile).
  Future<void> setApiKey(String key) async {
    _apiKey = key;
    await _secureStorage.write(key: 'moqui_api_key', value: key);
  }

  /// Load stored API key on startup.
  Future<void> loadApiKey() async {
    _apiKey = await _secureStorage.read(key: 'moqui_api_key');
  }

  /// Clear stored credentials.
  Future<void> clearCredentials() async {
    _apiKey = null;
    _csrfToken = null;
    await _secureStorage.delete(key: 'moqui_api_key');
  }

  String? get csrfToken => _csrfToken;

  String get baseUrl => MoquiConfig.baseUrl;

  // --- Screen Fetching ---

  /// Fetch a screen rendered as JSON (fjson render mode) for Flutter.
  ///
  /// Uses the .fjson URL extension which triggers Moqui's always-standalone
  /// rendering, returning only the target screen's JSON (not parent screens).
  ///
  /// [_redirectDepth] tracks Moqui transition redirects to prevent infinite loops.
  Future<Map<String, dynamic>> fetchScreen(String screenPath,
      {Map<String, dynamic>? params, int redirectDepth = 0}) async {
    // Guard against redirect loops (max 5 hops)
    if (redirectDepth > 5) {
      throw Exception(
        'Redirect loop detected: exceeded 5 redirects fetching screen "$screenPath". '
        'Check server-side transition configuration.',
      );
    }

    // Check LRU cache first (skip for redirects — they should always re-fetch)
    if (redirectDepth == 0) {
      final cached = ScreenCache.instance.get(screenPath, params: params);
      if (cached != null) return cached;
    }

    // Build the URL: /fapps/path.fjson (extension triggers standalone render)
    final basePath = screenPath.isEmpty
        ? MoquiConfig.fappsPath
        : '${MoquiConfig.fappsPath}/$screenPath';
    final url = '$basePath.fjson';
    // Add cache-busting parameter to prevent browser HTTP caching of .fjson
    // responses. The server now sends no-cache headers, but stale entries from
    // before the fix (max-age=86400) may still linger in the browser cache.
    final queryParams = <String, dynamic>{
      ...?params,
      '_t': DateTime.now().millisecondsSinceEpoch,
    };
    final response = await dio.get(url, queryParameters: queryParams);
    final json = _parseJsonResponse(response);

    // Inject the actual screen path when an HTTP 302 redirect was followed.
    //
    // On Flutter web, Dio's response.realUri does NOT contain the final URL
    // because the browser follows 302 redirects transparently via XHR, and the
    // dio_web_adapter never populates the redirects list — only sets isRedirect.
    //
    // Instead we use response.isRedirect (which IS set from
    // xhr.responseURL != options.uri) together with the screenName in the
    // JSON response to reconstruct the resolved path.
    //
    // Moqui convention: a transition redirect url is always "../<ScreenName>",
    // so from "tools/AutoScreen/MainEntityList/find" the redirect goes to
    // "tools/AutoScreen/AutoFind". We reconstruct this by stripping the last 2
    // path segments (transition + containing screen) and appending screenName.
    final requestedPath = basePath
        .replaceFirst('${MoquiConfig.fappsPath}/', '')
        .replaceFirst(MoquiConfig.fappsPath, '');
    if (response.isRedirect && !json.containsKey('_resolvedScreenPath')) {
      final screenName = json['screenName']?.toString() ?? '';
      if (screenName.isNotEmpty) {
        final parts =
            requestedPath.split('/').where((s) => s.isNotEmpty).toList();
        if (parts.length >= 2) {
          // Remove the transition name (last) and its containing screen (second-
          // to-last), then append the destination screenName.
          final parentParts = parts.sublist(0, parts.length - 2);
          final resolved = [...parentParts, screenName].join('/');
          json['_resolvedScreenPath'] = resolved;
        }
      }
    }

    // Detect Moqui transition redirect response: the server returns a
    // JSON object with a `screenUrl` key (and no `widgets`) when a GET
    // request hits a transition URL (e.g. MainEntityList/find → AutoFind).
    // In this case we follow the redirect and fetch the target screen.
    if (json.containsKey('screenUrl') &&
        json['screenUrl'] is String &&
        (json['screenUrl'] as String).isNotEmpty &&
        (!json.containsKey('widgets') ||
            (json['widgets'] is List && (json['widgets'] as List).isEmpty))) {
      final redirectUrl = json['screenUrl'] as String;
      // screenUrl is absolute like /fapps/tools/AutoScreen/AutoFind?aen=...
      // Strip the /fapps/ prefix and any existing query params before fetching
      final uri = Uri.parse(redirectUrl);
      final redirectPath = uri.path.replaceFirst('/fapps/', '').replaceFirst(RegExp(r'/$'), '');
      // Merge parent params with redirect URL's own query params
      final redirectParams = <String, dynamic>{
        ...uri.queryParameters,
        ...?params,
      };
      // Recursively call fetchScreen with incremented depth counter
      final redirectJson = await fetchScreen(
        redirectPath,
        params: redirectParams,
        redirectDepth: redirectDepth + 1,
      );
      // Inject the resolved screen path so widget rendering uses correct base.
      if (!redirectJson.containsKey('_resolvedScreenPath')) {
        final cleanRedirectPath =
            redirectPath.replaceAll(RegExp(r'\.fjson$'), '');
        if (cleanRedirectPath.isNotEmpty) {
          redirectJson['_resolvedScreenPath'] = cleanRedirectPath;
        }
      }
      return redirectJson;
    }

    // Store in LRU cache
    ScreenCache.instance.put(screenPath, json, params: params);

    return json;
  }

  /// Fetch menu data for navigation.
  ///
  /// Moqui's menuData transition returns an array of screen nodes with
  /// their subscreens. The URL format is: /menuData/fapps/path
  Future<List<dynamic>> fetchMenuData(String screenPath) async {
    // URL: /menuData/fapps or /menuData/fapps/marble etc.
    final pathSuffix = screenPath.isEmpty
        ? MoquiConfig.fappsPath
        : '${MoquiConfig.fappsPath}/$screenPath';
    final url = '${MoquiConfig.menuDataPath}$pathSuffix';
    final response = await dio.get(url);
    if (response.data is List) return response.data as List;
    if (response.data is String) {
      return _parseList(response.data as String);
    }
    return [];
  }

  // --- Transition POST (dynamic options, server search) ---

  /// POST to a screen transition and return the raw JSON response.
  ///
  /// Moqui requires POST for non-read-only transitions (security: params must
  /// travel in the request body, not the URL). The response may be a JSON array
  /// (dynamic-options list) or a JSON object — we normalise both to a Map.
  Future<Map<String, dynamic>> postTransition(
    String screenPath,
    String transition,
    Map<String, dynamic> params,
  ) async {
    final basePath = screenPath.isEmpty
        ? MoquiConfig.fappsPath
        : '${MoquiConfig.fappsPath}/$screenPath';
    final url = transition.isEmpty
        ? '$basePath.fjson'
        : '$basePath/$transition.fjson';

    final response = await dio.post(url, data: params);

    // Moqui transition responses can be:
    // - a JSON array   →  wrap as {"options": [...]}
    // - a JSON object   →  return as-is
    if (response.data is List) {
      return {'options': response.data as List};
    }
    if (response.data is Map) {
      return response.data as Map<String, dynamic>;
    }
    if (response.data is String) {
      try {
        final decoded = json.decode(response.data as String);
        if (decoded is List) return {'options': decoded};
        if (decoded is Map) return decoded as Map<String, dynamic>;
      } catch (_) {}
    }
    return {};
  }

  // --- Transitions (Form Submissions) ---

  /// Submit a form to a transition and get the JSON redirect response.
  ///
  /// Moqui returns JSON when the Accept header contains application/json
  /// (set in Dio base options). Do NOT append .json to the URL — Moqui does
  /// not recognise "json" as a render-mode extension, so the request would 404.
  Future<TransitionResponse> submitTransition(
    String transitionUrl,
    Map<String, dynamic> formData,
  ) async {
    final response = await dio.post(
      transitionUrl,
      data: formData,
    );
    final data = _parseJsonResponse(response);
    final result = TransitionResponse.fromJson(data);

    // Invalidate cache for the affected screen path so stale data is re-fetched
    final basePath = transitionUrl
        .replaceAll(RegExp(r'/[^/]+$'), '') // strip transition name
        .replaceFirst(RegExp(r'^/fapps/'), '');
    if (basePath.isNotEmpty) {
      ScreenCache.instance.invalidateForPath(basePath);
    }

    return result;
  }

  // --- Entity REST API ---

  /// List entities with optional pagination and filters.
  Future<EntityListResponse> entityList(
    String entityName, {
    int pageIndex = 0,
    int pageSize = 20,
    Map<String, dynamic>? filters,
    String? orderBy,
  }) async {
    final params = <String, dynamic>{
      'pageIndex': pageIndex,
      'pageSize': pageSize,
      ...?filters,
    };
    if (orderBy != null) params['orderByField'] = orderBy;

    final response = await dio.get(
      '${MoquiConfig.entityRestPath}/$entityName',
      queryParameters: params,
    );

    return EntityListResponse(
      data: response.data is List ? response.data as List : [],
      totalCount: int.tryParse(
              response.headers.value('X-Total-Count') ?? '') ??
          0,
      pageIndex: int.tryParse(
              response.headers.value('X-Page-Index') ?? '') ??
          pageIndex,
      pageSize: int.tryParse(
              response.headers.value('X-Page-Size') ?? '') ??
          pageSize,
    );
  }

  /// Get a single entity by primary key.
  Future<Map<String, dynamic>> entityOne(
      String entityName, String pkValue) async {
    final response =
        await dio.get('${MoquiConfig.entityRestPath}/$entityName/$pkValue');
    return _parseJsonResponse(response);
  }

  /// Create an entity.
  Future<Map<String, dynamic>> entityCreate(
      String entityName, Map<String, dynamic> data) async {
    final response =
        await dio.post('${MoquiConfig.entityRestPath}/$entityName', data: data);
    return _parseJsonResponse(response);
  }

  /// Update an entity by primary key.
  Future<Map<String, dynamic>> entityUpdate(
      String entityName, String pkValue, Map<String, dynamic> data) async {
    final response = await dio.patch(
        '${MoquiConfig.entityRestPath}/$entityName/$pkValue',
        data: data);
    return _parseJsonResponse(response);
  }

  /// Delete an entity by primary key.
  Future<void> entityDelete(String entityName, String pkValue) async {
    await dio.delete('${MoquiConfig.entityRestPath}/$entityName/$pkValue');
  }

  // --- Service REST API ---

  /// Call a service REST endpoint.
  Future<Map<String, dynamic>> serviceCall(
    String servicePath, {
    String method = 'GET',
    Map<String, dynamic>? data,
    Map<String, dynamic>? params,
  }) async {
    final url = '${MoquiConfig.serviceRestPath}/$servicePath';
    late Response response;

    switch (method.toUpperCase()) {
      case 'POST':
        response = await dio.post(url, data: data, queryParameters: params);
        break;
      case 'PUT':
        response = await dio.put(url, data: data, queryParameters: params);
        break;
      case 'DELETE':
        response = await dio.delete(url, queryParameters: params);
        break;
      default:
        response = await dio.get(url, queryParameters: params);
    }

    return _parseJsonResponse(response);
  }

  // --- File Upload ---

  /// Upload a file or files using multipart/form-data.
  /// 
  /// Supports single file (PlatformFile), multiple files (List<PlatformFile>),
  /// or file bytes directly for web compatibility.
  Future<TransitionResponse> uploadFile(
    String transitionUrl, {
    required dynamic file,
    required String fieldName,
    Map<String, dynamic>? additionalFields,
    void Function(int sent, int total)? onProgress,
  }) async {
    final formData = FormData();

    // Add additional form fields
    if (additionalFields != null) {
      for (final entry in additionalFields.entries) {
        if (entry.value != null) {
          formData.fields.add(MapEntry(entry.key, entry.value.toString()));
        }
      }
    }

    // Add file(s)
    if (file is PlatformFile) {
      formData.files.add(MapEntry(
        fieldName,
        _platformFileToMultipart(file),
      ));
    } else if (file is List<PlatformFile>) {
      for (final f in file) {
        formData.files.add(MapEntry(
          fieldName,
          _platformFileToMultipart(f),
        ));
      }
    }

    final response = await dio.post(
      transitionUrl,
      data: formData,
      options: Options(
        contentType: 'multipart/form-data',
      ),
      onSendProgress: onProgress,
    );

    final data = _parseJsonResponse(response);
    return TransitionResponse.fromJson(data);
  }

  MultipartFile _platformFileToMultipart(PlatformFile file) {
    if (file.bytes != null) {
      // Web (small files) or any platform with eagerly-loaded bytes
      return MultipartFile.fromBytes(
        file.bytes!,
        filename: file.name,
      );
    } else if (kIsWeb && file.readStream != null) {
      // Web: stream large files (>5MB picked with withReadStream: true)
      return MultipartFile.fromStream(
        () => file.readStream!,
        file.size,
        filename: file.name,
      );
    } else if (file.path != null) {
      // Mobile: use file path
      return MultipartFile.fromFileSync(
        file.path!,
        filename: file.name,
      );
    }
    throw Exception('File has no bytes, stream, or path: ${file.name}');
  }

  // --- Autocomplete Search ---

  /// Search for autocomplete suggestions from a server transition.
  Future<List<Map<String, dynamic>>> autocompleteSearch(
    String transition,
    String term, {
    Map<String, dynamic>? params,
  }) async {
    final queryParams = <String, dynamic>{
      'term': term,
      ...?params,
    };

    final response = await dio.get(
      transition,
      queryParameters: queryParams,
    );

    if (response.data is List) {
      return (response.data as List)
          .whereType<Map<String, dynamic>>()
          .toList();
    }
    if (response.data is Map && response.data['options'] is List) {
      return (response.data['options'] as List)
          .whereType<Map<String, dynamic>>()
          .toList();
    }
    return [];
  }

  // --- Cache Management ---

  /// Fetch the list of all caches with stats.
  Future<List<CacheInfo>> getCacheList() async {
    final result = await serviceCall(
      'moqui.impl.ServerServices.getCacheList',
    );
    final cacheList = result['cacheList'] as List? ?? [];
    return cacheList
        .whereType<Map<String, dynamic>>()
        .map(CacheInfo.fromJson)
        .toList();
  }

  /// Clear a specific cache by name.
  Future<void> clearCache(String cacheName) async {
    await serviceCall(
      'moqui.impl.ServerServices.clearCache',
      method: 'POST',
      data: {'cacheName': cacheName},
    );
  }

  /// Clear all caches.
  Future<void> clearAllCaches() async {
    await serviceCall(
      'moqui.impl.ServerServices.clearAllCaches',
      method: 'POST',
    );
  }

  // --- Log Viewer ---

  /// Fetch recent log entries with optional filters.
  Future<List<LogEntry>> getLogEntries({
    LogFilter? filter,
    int maxRows = 500,
  }) async {
    final params = <String, dynamic>{
      'maxRows': maxRows,
      ...?(filter?.toParams()),
    };
    final result = await serviceCall(
      'moqui.impl.ServerServices.getLogEntries',
      params: params,
    );
    final logList = result['logEntries'] as List? ?? [];
    return logList
        .whereType<Map<String, dynamic>>()
        .map(LogEntry.fromJson)
        .toList();
  }

  /// Get the current server log level.
  Future<String> getLogLevel() async {
    final result = await serviceCall(
      'moqui.impl.ServerServices.getLogLevel',
    );
    return result['logLevel']?.toString() ?? 'INFO';
  }

  /// Set the server log level at runtime.
  Future<void> setLogLevel(String level) async {
    await serviceCall(
      'moqui.impl.ServerServices.setLogLevel',
      method: 'POST',
      data: {'logLevel': level},
    );
  }

  // --- Interceptors ---

  void _onRequest(
      RequestOptions options, RequestInterceptorHandler handler) {
    // Add API key header if available
    if (_apiKey != null && _apiKey!.isNotEmpty) {
      options.headers['api_key'] = _apiKey;
    }

    // Add CSRF token for non-GET requests
    if (_csrfToken != null &&
        _csrfToken!.isNotEmpty &&
        options.method.toUpperCase() != 'GET') {
      options.headers['X-CSRF-Token'] = _csrfToken;
      options.headers['moquiSessionToken'] = _csrfToken;
    }

    handler.next(options);
  }

  void _onResponse(Response response, ResponseInterceptorHandler handler) {
    // Extract CSRF token from response headers if present.
    // Moqui sends it as both 'X-CSRF-Token' and 'moquiSessionToken'.
    final csrfHeader = response.headers.value('X-CSRF-Token') ??
        response.headers.value('moquiSessionToken');
    if (csrfHeader != null && csrfHeader.isNotEmpty) {
      _csrfToken = csrfHeader;
    }
    handler.next(response);
  }

  /// Callback invoked when a 401 response is detected.
  /// Set by the auth layer to trigger session-expiry logout.
  void Function()? onSessionExpired;

  void _onError(DioException e, ErrorInterceptorHandler handler) {
    // Detect 401 Unauthorized → session expired, trigger auto-logout
    if (e.response?.statusCode == 401) {
      onSessionExpired?.call();
      handler.reject(DioException(
        requestOptions: e.requestOptions,
        response: e.response,
        message: 'Session expired — please log in again',
        type: DioExceptionType.badResponse,
      ));
      return;
    }

    // Transform Moqui error responses into structured errors
    if (e.response?.data is Map) {
      final data = e.response!.data as Map;
      final errors = data['errors'] as List?;
      if (errors != null && errors.isNotEmpty) {
        handler.reject(DioException(
          requestOptions: e.requestOptions,
          response: e.response,
          message: errors.join('; '),
          type: e.type,
        ));
        return;
      }
    }
    handler.next(e);
  }

  // --- Helpers ---

  Map<String, dynamic> _parseJsonResponse(Response response) {
    if (response.data is Map) return response.data as Map<String, dynamic>;
    if (response.data is String) {
      try {
        final decoded = json.decode(response.data as String);
        if (decoded is Map) return decoded as Map<String, dynamic>;
      } catch (_) {}
    }
    return {};
  }

  List<dynamic> _parseList(String text) {
    try {
      final decoded = json.decode(text);
      if (decoded is List) return decoded;
      return [];
    } catch (_) {
      return [];
    }
  }
}

/// Response from a screen transition (form submission).
class TransitionResponse {
  final List<String> screenPathList;
  final Map<String, dynamic> screenParameters;
  final String screenUrl;
  final List<String> messages;
  final List<String> errors;

  TransitionResponse({
    this.screenPathList = const [],
    this.screenParameters = const {},
    this.screenUrl = '',
    this.messages = const [],
    this.errors = const [],
  });

  factory TransitionResponse.fromJson(Map<String, dynamic> json) {
    // Moqui sends success messages as `messageInfos` (array of {message, type})
    // rather than a flat `messages` array. Extract the message text from each.
    List<String> messages = [];
    final messageInfos = json['messageInfos'] as List?;
    if (messageInfos != null) {
      for (final mi in messageInfos) {
        if (mi is Map) {
          final msg = mi['message']?.toString();
          if (msg != null && msg.isNotEmpty) messages.add(msg);
        } else {
          messages.add(mi.toString());
        }
      }
    }
    // Also check for a flat 'messages' key as fallback
    if (messages.isEmpty && json['messages'] is List) {
      messages = (json['messages'] as List).map((e) => e.toString()).toList();
    }

    return TransitionResponse(
      screenPathList: (json['screenPathList'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      screenParameters:
          (json['screenParameters'] as Map<String, dynamic>?) ?? {},
      screenUrl: json['screenUrl']?.toString() ?? '',
      messages: messages,
      errors: (json['errors'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
    );
  }

  bool get hasErrors => errors.isNotEmpty;
  bool get hasMessages => messages.isNotEmpty;
}

/// Response from an entity list query.
class EntityListResponse {
  final List<dynamic> data;
  final int totalCount;
  final int pageIndex;
  final int pageSize;

  EntityListResponse({
    this.data = const [],
    this.totalCount = 0,
    this.pageIndex = 0,
    this.pageSize = 20,
  });

  int get totalPages => (totalCount / pageSize).ceil();
  bool get hasMore => pageIndex < totalPages - 1;
}
