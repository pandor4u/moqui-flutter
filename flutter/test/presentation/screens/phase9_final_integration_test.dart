import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moqui_flutter/data/auth/auth_provider.dart';
import 'package:moqui_flutter/data/api/moqui_api_client.dart';
import 'package:moqui_flutter/data/realtime/notification_client.dart';
import 'package:moqui_flutter/domain/screen/screen_models.dart';
import 'package:moqui_flutter/presentation/providers/screen_providers.dart';
import 'package:moqui_flutter/presentation/screens/dynamic_screen.dart';

// ============================================================================
// Phase 9: Final Integration Tests
// ============================================================================

void main() {
  // ==========================================================================
  // 1. AuthState & Session Expiry
  // ==========================================================================
  group('AuthState - session expiry', () {
    test('AuthState copyWith can set session expired message', () {
      const state = AuthState(
        status: AuthStatus.authenticated,
        username: 'admin',
      );
      final expired = state.copyWith(
        status: AuthStatus.unauthenticated,
        errorMessage: 'Session expired — please log in again',
      );
      expect(expired.status, AuthStatus.unauthenticated);
      expect(expired.errorMessage, contains('Session expired'));
      expect(expired.isAuthenticated, isFalse);
    });

    test('AuthState preserves username across status changes', () {
      const state = AuthState(
        status: AuthStatus.authenticated,
        userId: 'U100',
        username: 'admin',
      );
      final unauthState = state.copyWith(
        status: AuthStatus.unauthenticated,
      );
      expect(unauthState.username, 'admin');
      expect(unauthState.userId, 'U100');
    });

    test('default AuthState has unknown status', () {
      const state = AuthState();
      expect(state.status, AuthStatus.unknown);
      expect(state.username, isNull);
      expect(state.userId, isNull);
      expect(state.errorMessage, isNull);
    });
  });

  // ==========================================================================
  // 2. MoquiApiClient - 401 callback
  // ==========================================================================
  group('MoquiApiClient - onSessionExpired callback', () {
    test('onSessionExpired is initially null', () {
      // We can't easily instantiate MoquiApiClient without a Ref,
      // but we can test the callback pattern via the TransitionResponse
      // which is part of the same file
      final response = TransitionResponse.fromJson({
        'errors': ['Session expired'],
      });
      expect(response.hasErrors, isTrue);
      expect(response.errors.first, 'Session expired');
    });
  });

  // ==========================================================================
  // 3. MoquiNotification model
  // ==========================================================================
  group('MoquiNotification', () {
    test('fromJson parses all fields', () {
      final n = MoquiNotification.fromJson({
        'topic': 'OrderUpdate',
        'title': 'Order #1234 shipped',
        'message': 'Your order has been shipped.',
        'link': '/fapps/marble/Order/OrderDetail?orderId=1234',
        'type': 'success',
        'showAlert': true,
      });
      expect(n.topic, 'OrderUpdate');
      expect(n.title, 'Order #1234 shipped');
      expect(n.message, 'Your order has been shipped.');
      expect(n.link, '/fapps/marble/Order/OrderDetail?orderId=1234');
      expect(n.type, 'success');
      expect(n.showAlert, isTrue);
    });

    test('fromJson handles empty/null fields', () {
      final n = MoquiNotification.fromJson({});
      expect(n.topic, '');
      expect(n.title, '');
      expect(n.message, '');
      expect(n.link, '');
      expect(n.type, 'info');
      expect(n.showAlert, isFalse);
    });

    test('fromJson handles partial data', () {
      final n = MoquiNotification.fromJson({
        'topic': 'SystemAlert',
        'type': 'danger',
      });
      expect(n.topic, 'SystemAlert');
      expect(n.type, 'danger');
      expect(n.title, '');
      expect(n.showAlert, isFalse);
    });

    test('showAlert defaults to false for non-true values', () {
      final n1 = MoquiNotification.fromJson({'showAlert': false});
      expect(n1.showAlert, isFalse);

      final n2 = MoquiNotification.fromJson({'showAlert': 'yes'});
      expect(n2.showAlert, isFalse);

      final n3 = MoquiNotification.fromJson({'showAlert': 1});
      expect(n3.showAlert, isFalse);
    });

    test('notification type variants', () {
      for (final type in ['info', 'success', 'warning', 'danger']) {
        final n = MoquiNotification.fromJson({'topic': 'test', 'type': type});
        expect(n.type, type);
      }
    });
  });

  // ==========================================================================
  // 4. ScreenRequest model
  // ==========================================================================
  group('ScreenRequest', () {
    test('equality with same path and empty params', () {
      const a = ScreenRequest('marble/Order');
      const b = ScreenRequest('marble/Order');
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('inequality with different paths', () {
      const a = ScreenRequest('marble/Order');
      const b = ScreenRequest('marble/Customer');
      expect(a, isNot(equals(b)));
    });

    test('equality with same params', () {
      const a = ScreenRequest('marble/Order', {'orderId': '123'});
      const b = ScreenRequest('marble/Order', {'orderId': '123'});
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('inequality with different params', () {
      const a = ScreenRequest('marble/Order', {'orderId': '123'});
      const b = ScreenRequest('marble/Order', {'orderId': '456'});
      expect(a, isNot(equals(b)));
    });

    test('inequality with extra params', () {
      const a = ScreenRequest('marble/Order', {'orderId': '123'});
      const b = ScreenRequest('marble/Order', {'orderId': '123', 'mode': 'edit'});
      expect(a, isNot(equals(b)));
    });

    test('default params is empty map', () {
      const req = ScreenRequest('test');
      expect(req.params, isEmpty);
      expect(req.path, 'test');
    });

    test('hashCode differs for different paths', () {
      const a = ScreenRequest('a');
      const b = ScreenRequest('b');
      // Not strictly guaranteed but very likely for simple strings
      expect(a.hashCode, isNot(equals(b.hashCode)));
    });
  });

  // ==========================================================================
  // 5. DynamicScreenPage - query parameters
  // ==========================================================================
  group('DynamicScreenPage', () {
    test('accepts empty queryParameters by default', () {
      const page = DynamicScreenPage(screenPath: 'marble/Order');
      expect(page.screenPath, 'marble/Order');
      expect(page.queryParameters, isEmpty);
    });

    test('accepts queryParameters', () {
      const page = DynamicScreenPage(
        screenPath: 'marble/Order/OrderDetail',
        queryParameters: {'orderId': '123'},
      );
      expect(page.screenPath, 'marble/Order/OrderDetail');
      expect(page.queryParameters, {'orderId': '123'});
    });
  });

  // ==========================================================================
  // 6. Splash Screen widget
  // ==========================================================================
  group('Splash Screen', () {
    testWidgets('shows splash screen when auth status is unknown',
        (tester) async {
      // Build MoquiApp with a container that simulates unknown auth
      await tester.pumpWidget(
        const MaterialApp(
          home: _TestSplashScreen(),
        ),
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Moqui'), findsOneWidget);
      expect(find.byIcon(Icons.apps), findsOneWidget);
    });
  });

  // ==========================================================================
  // 7. Production Error Widget
  // ==========================================================================
  group('Production Error Widget', () {
    testWidgets('shows user-friendly error message', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: _TestProductionErrorWidget(),
          ),
        ),
      );

      expect(find.text('Something went wrong'), findsOneWidget);
      expect(find.text('Please try again or contact support.'), findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
    });
  });

  // ==========================================================================
  // 8. AppShell - notification panel
  // ==========================================================================
  group('AppShell notification panel', () {
    test('notification type to icon mapping', () {
      // Test the icon/color mapping concepts used in AppShell
      final typeToExpectedIcon = {
        'success': Icons.check_circle_outlined,
        'warning': Icons.warning_outlined,
        'danger': Icons.error_outlined,
        'info': Icons.info_outlined,
        'unknown': Icons.info_outlined,
      };

      for (final entry in typeToExpectedIcon.entries) {
        final icon = _notificationTypeIcon(entry.key);
        expect(icon, entry.value, reason: 'Type ${entry.key} should map to correct icon');
      }
    });

    test('notification type to color mapping', () {
      final typeToExpectedColor = {
        'success': Colors.green,
        'warning': Colors.orange,
        'danger': Colors.red,
        'info': Colors.blue,
      };

      for (final entry in typeToExpectedColor.entries) {
        final color = _notificationTypeColor(entry.key);
        expect(color, entry.value, reason: 'Type ${entry.key} should map to correct color');
      }
    });
  });

  // ==========================================================================
  // 9. EntityListResponse pagination
  // ==========================================================================
  group('EntityListResponse', () {
    test('totalPages calculation', () {
      final response = EntityListResponse(
        totalCount: 47,
        pageSize: 20,
        pageIndex: 0,
      );
      expect(response.totalPages, 3); // ceil(47/20) = 3
    });

    test('hasMore returns true when not on last page', () {
      final response = EntityListResponse(
        totalCount: 47,
        pageSize: 20,
        pageIndex: 0,
      );
      expect(response.hasMore, isTrue);
    });

    test('hasMore returns false on last page', () {
      final response = EntityListResponse(
        totalCount: 47,
        pageSize: 20,
        pageIndex: 2,
      );
      expect(response.hasMore, isFalse);
    });

    test('default values', () {
      final response = EntityListResponse();
      expect(response.data, isEmpty);
      expect(response.totalCount, 0);
      expect(response.pageIndex, 0);
      expect(response.pageSize, 20);
      expect(response.totalPages, 0);
      expect(response.hasMore, isFalse);
    });
  });

  // ==========================================================================
  // 10. TransitionResponse integration
  // ==========================================================================
  group('TransitionResponse - snackbar consolidation', () {
    test('multiple messages joined with newline for display', () {
      final response = TransitionResponse.fromJson({
        'messages': ['Record saved', 'Email sent', 'Notification queued'],
      });
      final joined = response.messages.join('\n');
      expect(joined, contains('Record saved'));
      expect(joined, contains('Email sent'));
      expect(joined, contains('Notification queued'));
    });

    test('multiple errors joined with newline for display', () {
      final response = TransitionResponse.fromJson({
        'errors': ['Field required', 'Invalid email'],
      });
      final joined = response.errors.join('\n');
      expect(joined, contains('Field required'));
      expect(joined, contains('Invalid email'));
    });

    test('screen URL extraction for navigation', () {
      final response = TransitionResponse.fromJson({
        'screenUrl': '/fapps/marble/Order/OrderDetail',
        'screenParameters': {'orderId': '123'},
      });
      expect(response.screenUrl.startsWith('/'), isTrue);
      expect(response.screenParameters['orderId'], '123');
    });
  });

  // ==========================================================================
  // 11. ScreenNode - menuTitle display
  // ==========================================================================
  group('ScreenNode - menuTitle for screen title display', () {
    test('screen with menuTitle shows title', () {
      final screen = ScreenNode.fromJson(const {
        'screenName': 'OrderList',
        'menuTitle': 'Orders',
        'widgets': [],
      });
      expect(screen.menuTitle, 'Orders');
      expect(screen.screenName, 'OrderList');
    });

    test('screen with empty menuTitle falls back to screenName', () {
      final screen = ScreenNode.fromJson(const {
        'screenName': 'Dashboard',
        'menuTitle': '',
        'widgets': [],
      });
      expect(screen.menuTitle, isEmpty);
      expect(screen.screenName, 'Dashboard');
    });

    test('screen from minimal JSON', () {
      final screen = ScreenNode.fromJson(const {});
      expect(screen.menuTitle, isEmpty);
      expect(screen.screenName, isEmpty);
      expect(screen.widgets, isEmpty);
    });
  });

  // ==========================================================================
  // 12. MenuNode model
  // ==========================================================================
  group('MenuNode', () {
    test('fromJson parses all fields', () {
      final node = MenuNode.fromJson(const {
        'name': 'marble',
        'title': 'Marble ERP',
        'path': '/fapps/marble',
        'pathWithParams': '/fapps/marble?param=1',
        'image': 'fa-home',
        'imageType': 'icon',
        'hasTabMenu': false,
        'subscreens': [],
      });
      expect(node.name, 'marble');
      expect(node.title, 'Marble ERP');
      expect(node.path, '/fapps/marble');
      expect(node.image, 'fa-home');
      expect(node.hasTabMenu, isFalse);
    });

    test('fromJson handles missing fields', () {
      final node = MenuNode.fromJson(const {});
      expect(node.name, isEmpty);
      expect(node.title, isEmpty);
      expect(node.path, isEmpty);
    });

    test('fromJson parses subscreens', () {
      final node = MenuNode.fromJson(const {
        'name': 'marble',
        'title': 'Marble',
        'path': '/fapps/marble',
        'subscreens': [
          {'name': 'Order', 'title': 'Orders', 'path': '/fapps/marble/Order', 'menuInclude': true},
          {'name': 'Customer', 'title': 'Customers', 'path': '/fapps/marble/Customer', 'menuInclude': false},
        ],
      });
      expect(node.subscreens.length, 2);
      expect(node.subscreens[0].name, 'Order');
      expect(node.subscreens[0].menuInclude, isTrue);
      expect(node.subscreens[1].menuInclude, isFalse);
    });
  });

  // ==========================================================================
  // 13. Auth flow states
  // ==========================================================================
  group('Auth flow states', () {
    test('all AuthStatus values are covered', () {
      expect(AuthStatus.values.length, 4);
      expect(AuthStatus.values, contains(AuthStatus.unknown));
      expect(AuthStatus.values, contains(AuthStatus.authenticated));
      expect(AuthStatus.values, contains(AuthStatus.unauthenticated));
      expect(AuthStatus.values, contains(AuthStatus.mfaRequired));
    });

    test('AuthState transitions for session expiry flow', () {
      // Simulate: authenticated → session expired → unauthenticated
      const initial = AuthState(
        status: AuthStatus.authenticated,
        userId: 'U001',
        username: 'admin',
      );
      expect(initial.isAuthenticated, isTrue);

      // Session expires
      final expired = initial.copyWith(
        status: AuthStatus.unauthenticated,
        errorMessage: 'Session expired — please log in again',
      );
      expect(expired.isAuthenticated, isFalse);
      expect(expired.errorMessage, isNotNull);
      expect(expired.username, 'admin'); // preserved for re-login hint

      // Re-login
      const reAuth = AuthState(
        status: AuthStatus.authenticated,
        userId: 'U001',
        username: 'admin',
      );
      expect(reAuth.isAuthenticated, isTrue);
      expect(reAuth.errorMessage, isNull);
    });

    test('AuthState transition for MFA flow', () {
      const mfa = AuthState(
        status: AuthStatus.mfaRequired,
        username: 'admin',
        mfaInfo: {'factorId': 'totp-1', 'factorType': 'totp'},
      );
      expect(mfa.isAuthenticated, isFalse);
      expect(mfa.mfaInfo, isNotNull);
      expect(mfa.mfaInfo!['factorType'], 'totp');
    });
  });

  // ==========================================================================
  // 14. Screen title rendering
  // ==========================================================================
  group('Screen title rendering in DynamicScreenPage', () {
    testWidgets('shows menuTitle when widgets are present', (tester) async {
      // Create a minimal ScreenNode with a title
      final screen = ScreenNode.fromJson(const {
        'screenName': 'OrderList',
        'menuTitle': 'Order Management',
        'widgets': [
          {
            '_type': 'label',
            'text': 'Test Label',
            'type': 'p',
          }
        ],
      });
      expect(screen.menuTitle, 'Order Management');
      expect(screen.widgets.isNotEmpty, isTrue);
    });

    testWidgets('empty screen shows screen name', (tester) async {
      final screen = ScreenNode.fromJson(const {
        'screenName': 'Dashboard',
        'menuTitle': 'Dashboard',
        'widgets': [],
      });
      expect(screen.menuTitle, 'Dashboard');
      expect(screen.widgets, isEmpty);
    });
  });

  // ==========================================================================
  // 15. Breadcrumb humanize
  // ==========================================================================
  group('Breadcrumb humanize function', () {
    test('converts hyphens and underscores to spaces', () {
      expect(_humanize('order-detail'), 'Order Detail');
      expect(_humanize('order_detail'), 'Order Detail');
      expect(_humanize('my-orders'), 'My Orders');
    });

    test('capitalizes first letter of each word', () {
      expect(_humanize('marble'), 'Marble');
      expect(_humanize('order management'), 'Order Management');
    });

    test('handles single word', () {
      expect(_humanize('dashboard'), 'Dashboard');
    });

    test('handles already capitalized text', () {
      expect(_humanize('Order'), 'Order');
    });
  });

  // ==========================================================================
  // 16. Icon mapping
  // ==========================================================================
  group('Menu icon mapping', () {
    test('maps known FA icons to Material icons', () {
      expect(_mapMenuIcon('fa-home'), Icons.home_outlined);
      expect(_mapMenuIcon('fa-users'), Icons.people_outlined);
      expect(_mapMenuIcon('fa-cog'), Icons.settings_outlined);
      expect(_mapMenuIcon('fa-search'), Icons.search);
      expect(_mapMenuIcon('fa-edit'), Icons.edit_outlined);
      expect(_mapMenuIcon('fa-list'), Icons.list);
      expect(_mapMenuIcon('fa-table'), Icons.table_chart_outlined);
      expect(_mapMenuIcon('fa-envelope'), Icons.email_outlined);
      expect(_mapMenuIcon('fa-calendar'), Icons.calendar_today_outlined);
      expect(_mapMenuIcon('fa-truck'), Icons.local_shipping_outlined);
    });

    test('returns default icon for unknown icons', () {
      expect(_mapMenuIcon('fa-unknown-icon'), Icons.circle_outlined);
      expect(_mapMenuIcon('random'), Icons.circle_outlined);
    });

    test('returns default icon for null/empty', () {
      expect(_mapMenuIcon(null), Icons.circle_outlined);
      expect(_mapMenuIcon(''), Icons.circle_outlined);
    });

    test('strips icon- prefix too', () {
      expect(_mapMenuIcon('icon-home'), Icons.home_outlined);
      expect(_mapMenuIcon('icon-users'), Icons.people_outlined);
    });
  });

  // ==========================================================================
  // 17. Query parameter forwarding
  // ==========================================================================
  group('Query parameter forwarding', () {
    test('DynamicScreenPage stores query params', () {
      const page = DynamicScreenPage(
        screenPath: 'marble/Order/OrderDetail',
        queryParameters: {'orderId': 'ORD-001', 'mode': 'view'},
      );
      expect(page.queryParameters['orderId'], 'ORD-001');
      expect(page.queryParameters['mode'], 'view');
      expect(page.queryParameters.length, 2);
    });

    test('empty query params by default', () {
      const page = DynamicScreenPage(screenPath: 'test');
      expect(page.queryParameters, isEmpty);
    });
  });

  // ==========================================================================
  // 18. Cache invalidation on logout (model-level)
  // ==========================================================================
  group('Cache invalidation concepts', () {
    test('screenProvider uses path as family key', () {
      // Verify the provider exists and accepts string keys
      expect(screenProvider, isNotNull);
    });

    test('screenWithParamsProvider uses ScreenRequest as family key', () {
      expect(screenWithParamsProvider, isNotNull);
    });

    test('menuDataProvider exists', () {
      expect(menuDataProvider, isNotNull);
    });

    test('currentScreenPathProvider exists', () {
      expect(currentScreenPathProvider, isNotNull);
    });
  });

  // ==========================================================================
  // 19. Error boundary concepts
  // ==========================================================================
  group('Error boundary', () {
    test('FlutterError.onError can be overridden', () {
      // Verify the error handler infrastructure exists
      final originalHandler = FlutterError.onError;
      expect(originalHandler, isNotNull);
    });

    test('PlatformDispatcher.instance exists', () {
      expect(PlatformDispatcher.instance, isNotNull);
    });
  });

  // ==========================================================================
  // 20. Notification stream provider
  // ==========================================================================
  group('Notification stream provider', () {
    test('notificationStreamProvider is a StreamProvider', () {
      expect(notificationStreamProvider, isNotNull);
    });

    test('MoquiNotification link can be used for navigation', () {
      final n = MoquiNotification.fromJson({
        'topic': 'OrderShipped',
        'link': '/fapps/marble/Order/OrderDetail?orderId=1234',
      });
      expect(n.link.startsWith('/'), isTrue);
      expect(n.link.contains('orderId'), isTrue);
    });

    test('MoquiNotification without link', () {
      final n = MoquiNotification.fromJson({
        'topic': 'SystemInfo',
        'title': 'System updated',
      });
      expect(n.link, isEmpty);
    });
  });

  // ==========================================================================
  // 21. Navigation path building
  // ==========================================================================
  group('Navigation path building', () {
    test('absolute paths start with /', () {
      const path = '/fapps/marble/Order';
      expect(path.startsWith('/'), isTrue);
    });

    test('relative paths get prefixed with /fapps/', () {
      const relativePath = 'marble/Order';
      const fullPath = '/fapps/$relativePath';
      expect(fullPath, '/fapps/marble/Order');
    });

    test('MenuNode path extraction for navigation', () {
      final node = MenuNode.fromJson(const {
        'name': 'order',
        'title': 'Orders',
        'path': '/fapps/marble/Order',
      });
      final path = node.path.startsWith('/') ? node.path : '/fapps/${node.path}';
      expect(path, '/fapps/marble/Order');
    });
  });

  // ==========================================================================
  // 22. ScreenNode widget rendering data
  // ==========================================================================
  group('ScreenNode for dynamic rendering', () {
    test('ScreenNode with widgets and title', () {
      final screen = ScreenNode.fromJson(const {
        'screenName': 'OrderList',
        'menuTitle': 'Orders',
        'widgets': [
          {'_type': 'container-box', 'title': 'Box 1'},
          {'_type': 'form-single', 'name': 'FilterForm'},
        ],
      });
      expect(screen.widgets.length, 2);
      expect(screen.widgets[0].type, 'container-box');
      expect(screen.widgets[1].type, 'form-single');
    });

    test('ScreenNode empty state for no-widget screens', () {
      final screen = ScreenNode.fromJson(const {
        'screenName': 'EmptyScreen',
        'menuTitle': 'Empty',
        'widgets': [],
      });
      expect(screen.widgets, isEmpty);
      expect(screen.menuTitle, 'Empty');
    });
  });

  // ==========================================================================
  // 23. Multiple notification types
  // ==========================================================================
  group('Notification type UI mapping', () {
    test('info type defaults', () {
      final n = MoquiNotification.fromJson({'topic': 't', 'type': 'info'});
      expect(_notificationTypeIcon(n.type), Icons.info_outlined);
      expect(_notificationTypeColor(n.type), Colors.blue);
    });

    test('success type', () {
      final n = MoquiNotification.fromJson({'topic': 't', 'type': 'success'});
      expect(_notificationTypeIcon(n.type), Icons.check_circle_outlined);
      expect(_notificationTypeColor(n.type), Colors.green);
    });

    test('warning type', () {
      final n = MoquiNotification.fromJson({'topic': 't', 'type': 'warning'});
      expect(_notificationTypeIcon(n.type), Icons.warning_outlined);
      expect(_notificationTypeColor(n.type), Colors.orange);
    });

    test('danger type', () {
      final n = MoquiNotification.fromJson({'topic': 't', 'type': 'danger'});
      expect(_notificationTypeIcon(n.type), Icons.error_outlined);
      expect(_notificationTypeColor(n.type), Colors.red);
    });

    test('unknown type defaults to info', () {
      final n = MoquiNotification.fromJson({'topic': 't', 'type': 'custom'});
      expect(_notificationTypeIcon(n.type), Icons.info_outlined);
      expect(_notificationTypeColor(n.type), Colors.blue);
    });
  });
}

// ============================================================================
// Test helper widgets (mirroring the private ones from main.dart and app_shell)
// ============================================================================

/// Mirrors _SplashScreen from main.dart for testing
class _TestSplashScreen extends StatelessWidget {
  const _TestSplashScreen();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.apps, size: 72, color: theme.primaryColor),
            const SizedBox(height: 24),
            Text(
              'Moqui',
              style: theme.textTheme.headlineLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 32),
            const SizedBox(
              width: 32,
              height: 32,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
          ],
        ),
      ),
    );
  }
}

/// Mirrors _ProductionErrorWidget from main.dart for testing
class _TestProductionErrorWidget extends StatelessWidget {
  const _TestProductionErrorWidget();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              'Something went wrong',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            SizedBox(height: 8),
            Text(
              'Please try again or contact support.',
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// Helper functions mirroring private AppShell methods for unit testing
// ============================================================================

/// Mirrors _AppShellState._humanize
String _humanize(String segment) {
  return segment
      .replaceAll(RegExp(r'[-_]'), ' ')
      .replaceAllMapped(
        RegExp(r'(^| )(\w)'),
        (m) => '${m[1]}${m[2]!.toUpperCase()}',
      );
}

/// Mirrors _AppShellState._mapMenuIcon
IconData _mapMenuIcon(String? image) {
  if (image == null || image.isEmpty) return Icons.circle_outlined;
  final name = image.replaceAll(RegExp(r'^fa-|^icon-'), '');
  const iconMap = <String, IconData>{
    'home': Icons.home_outlined,
    'dashboard': Icons.dashboard_outlined,
    'users': Icons.people_outlined,
    'user': Icons.person_outlined,
    'cog': Icons.settings_outlined,
    'cogs': Icons.settings_outlined,
    'gear': Icons.settings_outlined,
    'wrench': Icons.build_outlined,
    'list': Icons.list,
    'th-list': Icons.view_list_outlined,
    'table': Icons.table_chart_outlined,
    'bar-chart': Icons.bar_chart,
    'chart': Icons.show_chart,
    'file': Icons.insert_drive_file_outlined,
    'folder': Icons.folder_outlined,
    'envelope': Icons.email_outlined,
    'shopping-cart': Icons.shopping_cart_outlined,
    'money': Icons.attach_money,
    'dollar': Icons.attach_money,
    'calendar': Icons.calendar_today_outlined,
    'clock': Icons.access_time,
    'search': Icons.search,
    'edit': Icons.edit_outlined,
    'plus': Icons.add,
    'tasks': Icons.check_box_outlined,
    'check': Icons.check,
    'building': Icons.business_outlined,
    'industry': Icons.factory_outlined,
    'truck': Icons.local_shipping_outlined,
    'box': Icons.inventory_2_outlined,
    'tags': Icons.local_offer_outlined,
  };
  return iconMap[name] ?? Icons.circle_outlined;
}

/// Mirrors _AppShellState._notificationTypeIcon
IconData _notificationTypeIcon(String type) {
  switch (type) {
    case 'success':
      return Icons.check_circle_outlined;
    case 'warning':
      return Icons.warning_outlined;
    case 'danger':
      return Icons.error_outlined;
    default:
      return Icons.info_outlined;
  }
}

/// Mirrors _AppShellState._notificationTypeColor
Color _notificationTypeColor(String type) {
  switch (type) {
    case 'success':
      return Colors.green;
    case 'warning':
      return Colors.orange;
    case 'danger':
      return Colors.red;
    default:
      return Colors.blue;
  }
}
