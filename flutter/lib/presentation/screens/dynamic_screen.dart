import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import '../providers/screen_providers.dart';
import '../widgets/moqui/widget_factory.dart';
import '../../core/providers.dart';
import '../../core/theme.dart';
import '../../data/api/moqui_api_client.dart';
import '../../domain/screen/screen_models.dart';

/// Generic screen page that dynamically renders Moqui screens from JSON metadata.
///
/// Receives a route path, fetches the screen JSON via the `fjson` render mode,
/// parses it into a [ScreenNode] tree, and passes it to [MoquiWidgetFactory]
/// to build native Flutter widgets.
class DynamicScreenPage extends ConsumerStatefulWidget {
  final String screenPath;
  final Map<String, String> queryParameters;

  const DynamicScreenPage({
    super.key,
    required this.screenPath,
    this.queryParameters = const {},
  });

  @override
  ConsumerState<DynamicScreenPage> createState() => _DynamicScreenPageState();
}

class _DynamicScreenPageState extends ConsumerState<DynamicScreenPage> {
  /// The effective screen path used for relative URL resolution.
  /// Set from the ScreenNode's resolvedScreenPath when a server redirect occurred,
  /// otherwise defaults to widget.screenPath.
  String _effectiveScreenPath = '';

  /// Scroll controller for the main content area — used for scroll restoration.
  final ScrollController _scrollController = ScrollController();

  /// Static map to persist scroll positions across navigations.
  /// Key is the screenPath, value is the scroll offset.
  static final Map<String, double> _savedScrollOffsets = {};
  static const int _maxSavedScrollEntries = 50;

  @override
  void initState() {
    super.initState();
    _effectiveScreenPath = widget.screenPath;
    // Update the current screen path state
    Future.microtask(() {
      ref.read(currentScreenPathProvider.notifier).state = widget.screenPath;
    });
  }

  @override
  void dispose() {
    // Save scroll offset before the widget is disposed
    if (_scrollController.hasClients) {
      _savedScrollOffsets[widget.screenPath] = _scrollController.offset;
      // Evict oldest entries to prevent unbounded growth
      while (_savedScrollOffsets.length > _maxSavedScrollEntries) {
        _savedScrollOffsets.remove(_savedScrollOffsets.keys.first);
      }
    }
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<ScreenNode> screenAsync;

    if (widget.queryParameters.isNotEmpty) {
      final request = ScreenRequest(
        widget.screenPath,
        Map<String, dynamic>.from(widget.queryParameters),
      );
      screenAsync = ref.watch(screenWithParamsProvider(request));
    } else {
      screenAsync = ref.watch(screenProvider(widget.screenPath));
    }

    return screenAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stack) => _buildError(context, error),
      data: (screen) => _buildScreen(context, screen),
    );
  }

  Widget _buildScreen(BuildContext context, ScreenNode screen) {
    final apiClient = ref.read(moquiApiClientProvider);

    // Resolve the effective screen path: prefer the server-supplied resolved
    // path (set when a server-side redirect was followed) so that relative
    // URLs like ../AutoEdit/AutoEditMaster resolve against the real screen
    // location, not the URL-parameter path.
    final resolved = screen.resolvedScreenPath.isNotEmpty
        ? screen.resolvedScreenPath
        : widget.screenPath;

    // Set immediately so this build frame and all closures below use the
    // correct path.  Also schedule a setState so child StatefulWidgets that
    // capture ctx in didUpdateWidget receive an updated render context.
    if (resolved != _effectiveScreenPath) {
      _effectiveScreenPath = resolved;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() { _effectiveScreenPath = resolved; });
      });
    }

    final ctx = MoquiRenderContext(
      navigate: (path, {Map<String, dynamic>? params}) {
        _navigate(path, params: params);
      },
      submitForm: (transitionUrl, formData) async {
        return await _submitTransition(transitionUrl, formData);
      },
      loadDynamic: (transition, params) async {
        final basePath = _effectiveScreenPath.isNotEmpty
            ? _effectiveScreenPath
            : widget.screenPath;
        final fetchPath =
            transition.isEmpty ? basePath : '$basePath/$transition';
        // Merge top-level queryParameters into the first loadDynamic call
        // so subscreen-panels inherit URL parameters (e.g. orderId=12345).
        final mergedParams = <String, dynamic>{
          ...widget.queryParameters,
          ...params,
        };
        return apiClient.fetchScreen(fetchPath, params: mergedParams);
      },
      postDynamic: (transition, params) async {
        final basePath = _effectiveScreenPath.isNotEmpty
            ? _effectiveScreenPath
            : widget.screenPath;
        final mergedParams = <String, dynamic>{
          ...widget.queryParameters,
          ...params,
        };
        return apiClient.postTransition(basePath, transition, mergedParams);
      },
      contextData: {
        'baseUrl': apiClient.baseUrl,
        if (widget.queryParameters.isNotEmpty)
          'queryParameters': widget.queryParameters,
      },
      currentScreenPath: _effectiveScreenPath,
      launchExportUrl: (url) => _launchExport(apiClient, url),
    );

    if (screen.widgets.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.dashboard, size: 64, color: Theme.of(context).colorScheme.onSurfaceVariant),
            const SizedBox(height: 16),
            Text(
              screen.menuTitle.isNotEmpty ? screen.menuTitle : screen.screenName,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              'Screen loaded — no widgets defined at this level',
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      );
    }

    // Restore saved scroll offset after the frame renders
    final savedOffset = _savedScrollOffsets.remove(widget.screenPath);
    if (savedOffset != null && savedOffset > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.jumpTo(
            savedOffset.clamp(0.0, _scrollController.position.maxScrollExtent),
          );
        }
      });
    }

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(screenProvider(widget.screenPath));
        if (widget.queryParameters.isNotEmpty) {
          final request = ScreenRequest(
            widget.screenPath,
            Map<String, dynamic>.from(widget.queryParameters),
          );
          ref.invalidate(screenWithParamsProvider(request));
        }
      },
      child: SingleChildScrollView(
        controller: _scrollController,
        padding: const EdgeInsets.all(16),
        physics: const AlwaysScrollableScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Show screen title if available
            if (screen.menuTitle.isNotEmpty) ...[
              Text(
                screen.menuTitle,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(height: 16),
            ],
            ...screen.widgets
                .map((widgetNode) => MoquiWidgetFactory.build(widgetNode, ctx))
                ,
          ],
        ),
      ),
    );
  }

  Widget _buildError(BuildContext context, Object error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 64, color: context.moquiColors.errorIcon),
            const SizedBox(height: 16),
            Text(
              'Failed to load screen',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              error.toString(),
              textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
              onPressed: () {
                ref.invalidate(screenProvider(widget.screenPath));
              },
            ),
          ],
        ),
      ),
    );
  }

  void _navigate(String path, {Map<String, dynamic>? params}) {
    // Ignore empty paths
    if (path.isEmpty) return;

    // External URLs (http/https) — open in browser
    if (path.startsWith('http://') || path.startsWith('https://')) {
      _openUrlInNewTab(path);
      return;
    }

    // Save current scroll position before navigating away
    if (_scrollController.hasClients) {
      _savedScrollOffsets[widget.screenPath] = _scrollController.offset;
    }

    String fullPath;
    if (path.startsWith('/')) {
      // Absolute path (already resolved by server, e.g. '/fapps/tools/ArtifactStats')
      fullPath = path;
      // Strip any accidental double /fapps prefix
      if (fullPath.startsWith('/fapps/fapps')) {
        fullPath = fullPath.replaceFirst('/fapps', '');
      }
    } else {
      // Relative path — resolve against the EFFECTIVE screen path (after redirects).
      // Example: effective='tools/AutoScreen/AutoFind', url='../AutoEdit/AutoEditMaster'
      //          → 'tools/AutoScreen/AutoEdit/AutoEditMaster'
      final resolvePath = _effectiveScreenPath.isNotEmpty
          ? _effectiveScreenPath
          : widget.screenPath;
      final currentParts = resolvePath
          .split('/')
          .where((s) => s.isNotEmpty)
          .toList();
      final urlParts = path.split('/').where((s) => s.isNotEmpty).toList();
      final resolved = List<String>.from(currentParts);
      for (final segment in urlParts) {
        if (segment == '..') {
          if (resolved.isNotEmpty) resolved.removeLast();
        } else if (segment != '.') {
          resolved.add(segment);
        }
      }
      fullPath = '/fapps/${resolved.join('/')}';
    }

    // Append query parameters from the params map
    if (params != null && params.isNotEmpty) {
      final nonEmpty = params.entries
          .where((e) => e.value != null && e.value.toString().isNotEmpty)
          .toList();
      if (nonEmpty.isNotEmpty) {
        final queryString = nonEmpty
            .map((e) =>
                '${Uri.encodeQueryComponent(e.key)}='
                '${Uri.encodeQueryComponent(e.value.toString())}')
            .join('&');
        // Use '&' if path already has query parameters, otherwise '?'
        final separator = fullPath.contains('?') ? '&' : '?';
        fullPath = '$fullPath$separator$queryString';
      }
    }

    // Use GoRouter for navigation
    GoRouter.of(context).go(fullPath);
  }

  Future<TransitionResponse?> _submitTransition(
      String transitionUrl, Map<String, dynamic> formData) async {
    final apiClient = ref.read(moquiApiClientProvider);

    // Moqui convention: transition="." means "reload same screen as GET with
    // the form fields as query parameters".  Instead of POSTing to a transition
    // endpoint, navigate to the current screen path with the form data added
    // as query parameters.  GoRouter will rebuild DynamicScreenPage which will
    // fetch the screen JSON with those parameters, returning the filtered data.
    if (transitionUrl == '.') {
      final basePath = _effectiveScreenPath.isNotEmpty
          ? _effectiveScreenPath
          : widget.screenPath;
      // Pass as absolute path so _navigate doesn't resolve it as relative
      final absPath = basePath.startsWith('/') ? basePath : '/fapps/$basePath';
      _navigate(absPath, params: formData);
      return null;
    }

    try {
      // Build the transition URL:
      // - If already absolute (starts with /), use as-is (server-resolved URL)
      // - Otherwise, it's relative to the current screen path
      //   Prefix with /fapps/ so the full URL resolves correctly against the
      //   Dio base URL (http://localhost:8080).
      final String fullTransitionUrl;
      if (transitionUrl.startsWith('/')) {
        fullTransitionUrl = transitionUrl;
      } else {
        final basePath = _effectiveScreenPath.isNotEmpty
            ? _effectiveScreenPath
            : widget.screenPath;
        fullTransitionUrl = '/fapps/$basePath/$transitionUrl';
      }

      // Detect file uploads and route to multipart endpoint with progress
      final hasFiles = formData.remove('_hasFileUploads') == true;
      final TransitionResponse response;

      if (hasFiles) {
        // Extract PlatformFile entries from formData
        final fileFields = <String, dynamic>{};
        final plainFields = <String, dynamic>{};
        for (final entry in formData.entries) {
          if (entry.value is PlatformFile || (entry.value is List && (entry.value as List).any((e) => e is PlatformFile))) {
            fileFields[entry.key] = entry.value;
          } else {
            plainFields[entry.key] = entry.value;
          }
        }
        // Use the first file field for upload (most forms have one file field)
        final firstFileEntry = fileFields.entries.first;
        response = await apiClient.uploadFile(
          fullTransitionUrl,
          file: firstFileEntry.value,
          fieldName: firstFileEntry.key,
          additionalFields: plainFields,
        );
      } else {
        response = await apiClient.submitTransition(
          fullTransitionUrl,
          formData,
        );
      }

      if (!mounted) return response;

      // SnackBar feedback is NOT shown here — the calling widget
      // (form-single _submit, form-list _submitEdits, etc.) handles
      // SnackBars based on the returned TransitionResponse.  Showing
      // SnackBars here would cause double-display for form submissions
      // while fire-and-forget callers (link clicks, filter buttons) rely
      // on navigation + screen refresh below.

      // Navigate to the response screen URL or refresh current screen
      if (!response.hasErrors && response.screenUrl.isNotEmpty) {
        _navigate(response.screenUrl,
            params: response.screenParameters.isNotEmpty
                ? response.screenParameters
                : null);
      } else {
        // Refresh current screen so updated data is visible
        ref.invalidate(screenProvider(widget.screenPath));
      }

      return response;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return null;
    }
  }

  /// Launch an export URL for CSV/XLSX download.
  /// On web, opens a new browser tab. On mobile, would use Dio download.
  void _launchExport(MoquiApiClient apiClient, String url) {
    // Resolve relative URLs against the API base
    final resolvedUrl = url.startsWith('http')
        ? url
        : '${apiClient.baseUrl}$url';

    if (kIsWeb) {
      // On web: open a new tab which triggers browser download
      // We use JS interop to avoid importing dart:html directly
      _openUrlInNewTab(resolvedUrl);
    } else {
      // On mobile: log for now — full Dio download + share can be added later
      debugPrint('Export download: $resolvedUrl');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export: $resolvedUrl')),
        );
      }
    }
  }

  /// Open a URL in a new browser tab (web) or via OS launcher (mobile).
  static Future<void> _openUrlInNewTab(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}
