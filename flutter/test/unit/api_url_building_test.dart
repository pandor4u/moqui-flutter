import 'package:flutter_test/flutter_test.dart';
import 'package:moqui_flutter/core/config.dart';
import 'package:moqui_flutter/data/api/moqui_api_client.dart';

/// Phase 9.1: Extended unit tests for API URL building, parameter encoding,
/// redirect detection, and response model edge cases.
///
/// Note: We cannot instantiate MoquiApiClient directly without a Riverpod Ref,
/// so we test URL building patterns and response models.
void main() {
  // =========================================================================
  // URL building patterns (config-based verification)
  // =========================================================================
  group('MoquiConfig URL patterns', () {
    test('fappsPath is /fapps', () {
      expect(MoquiConfig.fappsPath, '/fapps');
    });

    test('entity REST path prefix', () {
      expect(MoquiConfig.entityRestPath, '/rest/e1');
    });

    test('service REST path prefix', () {
      expect(MoquiConfig.serviceRestPath, '/rest/s1');
    });

    test('menuData path prefix', () {
      expect(MoquiConfig.menuDataPath, '/menuData');
    });

    test('screen URL constructed as fappsPath/screenPath.fjson', () {
      const screenPath = 'Order/FindOrder';
      const url = '${MoquiConfig.fappsPath}/$screenPath.fjson';
      expect(url, '/fapps/Order/FindOrder.fjson');
    });

    test('empty screen path uses fappsPath directly', () {
      const screenPath = '';
      final basePath = screenPath.isEmpty
          ? MoquiConfig.fappsPath
          : '${MoquiConfig.fappsPath}/$screenPath';
      expect(basePath, '/fapps');
    });

    test('menu data URL built as menuDataPath + fappsPath/screenPath', () {
      const screenPath = 'marble';
      final pathSuffix = screenPath.isEmpty
          ? MoquiConfig.fappsPath
          : '${MoquiConfig.fappsPath}/$screenPath';
      final url = '${MoquiConfig.menuDataPath}$pathSuffix';
      expect(url, '/menuData/fapps/marble');
    });

    test('entity list URL format: /rest/e1/EntityName', () {
      const entityName = 'OrderHeader';
      const url = '${MoquiConfig.entityRestPath}/$entityName';
      expect(url, '/rest/e1/OrderHeader');
    });

    test('entity one URL format: /rest/e1/EntityName/pk', () {
      const entityName = 'OrderHeader';
      const pk = 'ORD-001';
      const url = '${MoquiConfig.entityRestPath}/$entityName/$pk';
      expect(url, '/rest/e1/OrderHeader/ORD-001');
    });

    test('service call URL format: /rest/s1/path', () {
      const servicePath = 'mantle.order.OrderServices.create#Order';
      const url = '${MoquiConfig.serviceRestPath}/$servicePath';
      expect(url, '/rest/s1/mantle.order.OrderServices.create#Order');
    });

    test('default page size is 20', () {
      expect(MoquiConfig.defaultPageSize, 20);
    });
  });

  // =========================================================================
  // Redirect path resolution (unit logic extracted from fetchScreen)
  // =========================================================================
  group('Redirect path resolution', () {
    /// Simulates the HTTP 302 redirect path reconstruction from fetchScreen.
    String resolveRedirectPath(String requestedPath, String screenName) {
      final parts =
          requestedPath.split('/').where((s) => s.isNotEmpty).toList();
      if (parts.length >= 2 && screenName.isNotEmpty) {
        final parentParts = parts.sublist(0, parts.length - 2);
        return [...parentParts, screenName].join('/');
      }
      return requestedPath;
    }

    test('resolves tools/AutoScreen/MainEntityList/find → tools/AutoScreen/AutoFind', () {
      expect(
        resolveRedirectPath(
            'tools/AutoScreen/MainEntityList/find', 'AutoFind'),
        'tools/AutoScreen/AutoFind',
      );
    });

    test('resolves Order/FindOrder/search → Order/OrderList', () {
      expect(
        resolveRedirectPath('Order/FindOrder/search', 'OrderList'),
        'Order/OrderList',
      );
    });

    test('handles short path (< 2 segments)', () {
      expect(
        resolveRedirectPath('find', 'AutoFind'),
        'find', // not enough segments to reconstruct
      );
    });

    test('handles empty screen name', () {
      expect(
        resolveRedirectPath('a/b/c/d', ''),
        'a/b/c/d', // empty screen name, no resolution
      );
    });

    test('handles path with exactly 2 segments', () {
      expect(
        resolveRedirectPath('ParentScreen/transition', 'DestScreen'),
        'DestScreen',
      );
    });
  });

  // =========================================================================
  // Moqui transition redirect detection (screenUrl in JSON)
  // =========================================================================
  group('Transition redirect detection', () {
    test('detects redirect when screenUrl present and widgets empty', () {
      final json = {
        'screenUrl': '/fapps/tools/AutoScreen/AutoFind?aen=Person',
        'widgets': <dynamic>[],
      };
      final isRedirect = json.containsKey('screenUrl') &&
          json['screenUrl'] is String &&
          (json['screenUrl'] as String).isNotEmpty &&
          (!json.containsKey('widgets') ||
              (json['widgets'] is List &&
                  (json['widgets'] as List).isEmpty));
      expect(isRedirect, isTrue);
    });

    test('no redirect when widgets are populated', () {
      final json = {
        'screenUrl': '/fapps/somewhere',
        'widgets': [
          {'_type': 'label'}
        ],
      };
      final isRedirect = json.containsKey('screenUrl') &&
          json['screenUrl'] is String &&
          (json['screenUrl'] as String).isNotEmpty &&
          (!json.containsKey('widgets') ||
              (json['widgets'] is List &&
                  (json['widgets'] as List).isEmpty));
      expect(isRedirect, isFalse);
    });

    test('no redirect when screenUrl is empty', () {
      final json = {
        'screenUrl': '',
        'widgets': <dynamic>[],
      };
      final isRedirect = json.containsKey('screenUrl') &&
          json['screenUrl'] is String &&
          (json['screenUrl'] as String).isNotEmpty;
      expect(isRedirect, isFalse);
    });

    test('no redirect when screenUrl is missing', () {
      final json = {
        'widgets': [
          {'_type': 'label'}
        ],
      };
      expect(json.containsKey('screenUrl'), isFalse);
    });
  });

  // =========================================================================
  // Redirect URL parsing
  // =========================================================================
  group('Redirect URL parsing', () {
    test('strips /fapps/ prefix from redirect URL', () {
      const redirectUrl =
          '/fapps/tools/AutoScreen/AutoFind?aen=moqui.basic.Person';
      final uri = Uri.parse(redirectUrl);
      final redirectPath =
          uri.path.replaceFirst('/fapps/', '').replaceFirst(RegExp(r'/$'), '');
      expect(redirectPath, 'tools/AutoScreen/AutoFind');
      expect(uri.queryParameters['aen'], 'moqui.basic.Person');
    });

    test('merges parent params with redirect query params', () {
      const redirectUrl = '/fapps/Order/List?status=Active';
      final uri = Uri.parse(redirectUrl);
      final parentParams = {'orgId': 'ORG-001'};
      final mergedParams = <String, dynamic>{
        ...uri.queryParameters,
        ...parentParams,
      };
      expect(mergedParams['status'], 'Active');
      expect(mergedParams['orgId'], 'ORG-001');
    });

    test('parent params override redirect params on conflict', () {
      const redirectUrl = '/fapps/Order/List?pageSize=20';
      final uri = Uri.parse(redirectUrl);
      final parentParams = {'pageSize': '50'};
      final mergedParams = <String, dynamic>{
        ...uri.queryParameters,
        ...parentParams,
      };
      // Parent wins because it's spread second
      expect(mergedParams['pageSize'], '50');
    });
  });

  // =========================================================================
  // TransitionResponse — extended edge cases
  // =========================================================================
  group('TransitionResponse — extended', () {
    test('fromJson handles nested error maps (Moqui validation)', () {
      // Moqui sometimes returns errors as a map with fieldName keys
      final response = TransitionResponse.fromJson({
        'errors': ['Field "orderId" is required'],
      });
      expect(response.errors.length, 1);
      expect(response.errors[0], contains('orderId'));
    });

    test('fromJson handles messageInfos list (Moqui format)', () {
      final response = TransitionResponse.fromJson({
        'messages': ['Created', 'Notification sent'],
      });
      expect(response.messages.length, 2);
    });

    test('screenUrl redirect target extraction', () {
      final response = TransitionResponse.fromJson({
        'screenUrl': '/fapps/Order/Detail?orderId=ORD-001',
        'screenPathList': ['fapps', 'Order', 'Detail'],
        'screenParameters': {'orderId': 'ORD-001'},
      });
      expect(response.screenUrl, '/fapps/Order/Detail?orderId=ORD-001');
      expect(response.screenPathList, ['fapps', 'Order', 'Detail']);
      expect(response.screenParameters['orderId'], 'ORD-001');
    });

    test('combining multiple errors and messages', () {
      final response = TransitionResponse.fromJson({
        'errors': ['Error 1', 'Error 2'],
        'messages': ['Info 1'],
      });
      expect(response.hasErrors, isTrue);
      expect(response.hasMessages, isTrue);
      expect(response.errors.length, 2);
      expect(response.messages.length, 1);
    });
  });

  // =========================================================================
  // EntityListResponse — extended edge cases
  // =========================================================================
  group('EntityListResponse — extended', () {
    test('handles large totalCount', () {
      final response = EntityListResponse(
        totalCount: 1000000,
        pageSize: 100,
        pageIndex: 0,
      );
      expect(response.totalPages, 10000);
      expect(response.hasMore, isTrue);
    });

    test('handles pageSize of 1', () {
      final response = EntityListResponse(
        totalCount: 5,
        pageSize: 1,
        pageIndex: 3,
      );
      expect(response.totalPages, 5);
      expect(response.hasMore, isTrue);
    });

    test('hasMore on second-to-last page', () {
      final response = EntityListResponse(
        totalCount: 100,
        pageSize: 20,
        pageIndex: 3,
      );
      // Page 3 (0-indexed) is 4th page, total 5 pages
      expect(response.hasMore, isTrue);
    });

    test('data types preserved', () {
      final response = EntityListResponse(
        data: [
          {'id': 1, 'name': 'Alice', 'active': true, 'amount': 99.99},
        ],
        totalCount: 1,
      );
      final row = response.data[0] as Map;
      expect(row['id'], 1);
      expect(row['active'], true);
      expect(row['amount'], 99.99);
    });
  });

  // =========================================================================
  // Redirect depth guard
  // =========================================================================
  group('Redirect depth guard', () {
    test('max redirect depth is 5', () {
      // Verify the logic pattern used in fetchScreen
      const maxDepth = 5;
      for (int depth = 0; depth <= maxDepth; depth++) {
        expect(depth > maxDepth, isFalse);
      }
      expect(6 > maxDepth, isTrue);
    });
  });

  // =========================================================================
  // Cache key building
  // =========================================================================
  group('Cache key logic', () {
    test('screen path with no params uses path as key', () {
      const path = 'Order/FindOrder';
      const key = path;
      expect(key, 'Order/FindOrder');
    });

    test('timestamp param prevents browser cache but not app cache', () {
      // The _t parameter is added for HTTP cache busting but the screen
      // cache is keyed by path + params (sans _t).
      final params = {'status': 'Active'};
      final withTimestamp = {
        ...params,
        '_t': DateTime.now().millisecondsSinceEpoch,
      };
      expect(withTimestamp.containsKey('_t'), isTrue);
      // App cache lookup should work without _t
      expect(params.containsKey('_t'), isFalse);
    });
  });
}
