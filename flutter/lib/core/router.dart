import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../data/auth/auth_provider.dart';
import '../presentation/providers/screen_providers.dart';
import '../presentation/screens/login_screen.dart';
import '../presentation/screens/app_shell.dart';
import '../presentation/screens/dynamic_screen.dart';
import '../presentation/screens/cache_list_screen.dart';
import '../presentation/screens/log_viewer_screen.dart';

/// GoRouter configuration with auth redirect and dynamic catch-all route.
final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/fapps',
    debugLogDiagnostics: true,

    // Redirect guard — push to /login when unauthenticated.
    redirect: (context, state) {
      final authState = ref.read(authProvider);
      final isLoggedIn = authState.status == AuthStatus.authenticated;
      final isLoggingIn = state.matchedLocation == '/login';

      // Handle logout path
      if (state.matchedLocation == '/logout') {
        ref.read(authProvider.notifier).logout();
        return '/login';
      }

      // Not logged in and not on login page → redirect to login
      if (!isLoggedIn && !isLoggingIn) {
        return '/login';
      }

      // Logged in and on login page → redirect to app (default subscreen)
      if (isLoggedIn && isLoggingIn) {
        return '/fapps/marble';
      }

      // If at bare /fapps with no subscreen, redirect to default subscreen
      if (isLoggedIn && state.matchedLocation == '/fapps' && state.uri.path == '/fapps') {
        return '/fapps/marble';
      }

      return null; // no redirect
    },

    // Listen for auth state changes to trigger re-evaluation of redirects.
    refreshListenable: _AuthRefreshListenable(ref),

    routes: [
      // Login route
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginScreen(),
      ),

      // Logout pseudo-route (handled by redirect)
      GoRoute(
        path: '/logout',
        builder: (context, state) => const SizedBox.shrink(),
      ),

      // App shell wrapping all fapps screens
      ShellRoute(
        builder: (context, state, child) {
          final screenPath = state.uri.path.replaceFirst('/fapps', '').replaceAll(RegExp(r'^/'), '');
          // Sync screen path provider
          WidgetsBinding.instance.addPostFrameCallback((_) {
            ref.read(currentScreenPathProvider.notifier).state = screenPath;
          });
          return AppShell(
            currentPath: screenPath,
            child: child,
          );
        },
        routes: [
          // Tools — native screens with richer UX than dynamic fjson rendering
          GoRoute(
            path: '/fapps/tools/CacheList',
            builder: (context, state) => const CacheListScreen(),
          ),
          GoRoute(
            path: '/fapps/tools/LogViewer',
            builder: (context, state) => const LogViewerScreen(),
          ),

          // Catch-all route for dynamic Moqui screens — supports any depth
          GoRoute(
            path: '/fapps',
            builder: (context, state) {
              return DynamicScreenPage(
                screenPath: '',
                queryParameters: state.uri.queryParameters,
              );
            },
            routes: [
              GoRoute(
                path: ':rest(.*)',
                builder: (context, state) {
                  // Extract the full sub-path from the URI rather than relying
                  // on a fixed number of path parameters.
                  final fullPath = state.uri.path;
                  final screenPath = fullPath
                      .replaceFirst('/fapps/', '')
                      .replaceFirst('/fapps', '');
                  return DynamicScreenPage(
                    screenPath: screenPath,
                    queryParameters: state.uri.queryParameters,
                  );
                },
              ),
            ],
          ),
        ],
      ),
    ],

    errorBuilder: (context, state) => Scaffold(
      appBar: AppBar(title: const Text('Not Found')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            Text('Page not found: ${state.uri}'),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => context.go('/fapps'),
              child: const Text('Go Home'),
            ),
          ],
        ),
      ),
    ),
  );
});

/// A ChangeNotifier that listens to the auth state via Riverpod
/// and notifies GoRouter when a refresh (redirect re-evaluation) is needed.
class _AuthRefreshListenable extends ChangeNotifier {
  _AuthRefreshListenable(this._ref) {
    _ref.listen<AuthState>(authProvider, (_, __) {
      notifyListeners();
    });
  }

  final Ref _ref;
}
