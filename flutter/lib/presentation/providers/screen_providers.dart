import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers.dart';
import '../../domain/screen/screen_models.dart';

/// Request key for fetching a screen with optional query parameters.
class ScreenRequest {
  final String path;
  final Map<String, dynamic> params;

  const ScreenRequest(this.path, [this.params = const {}]);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ScreenRequest &&
          runtimeType == other.runtimeType &&
          path == other.path &&
          _mapEquals(params, other.params);

  @override
  int get hashCode => Object.hash(path, Object.hashAllUnordered(
    params.entries.map((e) => Object.hash(e.key, e.value)),
  ));

  static bool _mapEquals(Map a, Map b) {
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (a[key] != b[key]) return false;
    }
    return true;
  }
}

/// Provider that fetches and caches screen JSON from the server.
///
/// Uses path as the family key. Returns a fully parsed [ScreenNode].
/// Supports both simple string paths (backward compatible) and ScreenRequest with params.
final screenProvider =
    FutureProvider.family<ScreenNode, String>((ref, screenPath) async {
  final apiClient = ref.watch(moquiApiClientProvider);
  final json = await apiClient.fetchScreen(screenPath);
  return ScreenNode.fromJson(json);
});

/// Provider that fetches a screen with query parameters.
final screenWithParamsProvider =
    FutureProvider.family<ScreenNode, ScreenRequest>((ref, request) async {
  final apiClient = ref.watch(moquiApiClientProvider);
  final json = await apiClient.fetchScreen(
    request.path,
    params: request.params.isNotEmpty ? request.params : null,
  );
  return ScreenNode.fromJson(json);
});

/// Provider that fetches navigation menu data for a given screen path.
///
/// The Moqui /menuData endpoint returns an array of screen nodes. For the
/// top-level menu, we look at the first node's `subscreens` array to get
/// the list of available applications (marble, my, system, tools, etc.).
final menuDataProvider =
    FutureProvider.family<List<MenuNode>, String>((ref, screenPath) async {
  final apiClient = ref.watch(moquiApiClientProvider);
  final rawList = await apiClient.fetchMenuData(screenPath);

  // The Moqui menuData response is an array of screen path nodes.
  // Each node may have a 'subscreens' array. We want the first node that
  // has subscreens with menuInclude=true to build our navigation.
  final menuNodes = <MenuNode>[];
  for (final item in rawList) {
    if (item is Map<String, dynamic>) {
      final node = MenuNode.fromJson(item);
      // If this node has subscreens, add each subscreen as a top-level menu item
      if (node.subscreens.isNotEmpty) {
        for (final sub in node.subscreens) {
          if (sub.menuInclude) {
            menuNodes.add(MenuNode(
              name: sub.name,
              title: sub.title,
              path: sub.path,
              pathWithParams: sub.pathWithParams,
              image: sub.image,
              imageType: sub.imageType,
            ));
          }
        }
        break; // use subscreens from the first matching node
      }
    }
  }
  return menuNodes;
});

/// Provider for the current active screen path (for navigation state).
final currentScreenPathProvider = StateProvider<String>((ref) => '');
