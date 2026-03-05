import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/router.dart';
import 'core/theme.dart';
import 'data/auth/auth_provider.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Global error boundary for production — catches uncaught Flutter errors
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    if (kReleaseMode) {
      // In release mode, log silently instead of crashing
      debugPrint('FlutterError: ${details.exceptionAsString()}');
    }
  };

  // Catch async errors not handled by Flutter framework
  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('PlatformDispatcher error: $error\n$stack');
    return true; // prevent app crash in release mode
  };

  // Override the default red error widget in release mode
  if (kReleaseMode) {
    ErrorWidget.builder = (FlutterErrorDetails details) {
      return const _ProductionErrorWidget();
    };
  }

  runApp(
    const ProviderScope(
      child: MoquiApp(),
    ),
  );
}

/// A user-friendly error widget shown in release mode instead of the red screen.
class _ProductionErrorWidget extends StatelessWidget {
  const _ProductionErrorWidget();

  @override
  Widget build(BuildContext context) {
    return const Material(
      child: Center(
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
      ),
    );
  }
}

class MoquiApp extends ConsumerStatefulWidget {
  const MoquiApp({super.key});

  @override
  ConsumerState<MoquiApp> createState() => _MoquiAppState();
}

class _MoquiAppState extends ConsumerState<MoquiApp> {
  @override
  void initState() {
    super.initState();
    // Check if user is already authenticated (e.g. stored session/api-key).
    Future.microtask(() {
      ref.read(authProvider.notifier).checkAuth();
    });
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final router = ref.watch(routerProvider);

    // Show splash screen while checking authentication
    if (authState.status == AuthStatus.unknown) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: MoquiTheme.light(),
        darkTheme: MoquiTheme.dark(),
        themeMode: ThemeMode.system,
        home: const _SplashScreen(),
      );
    }

    return MaterialApp.router(
      title: 'Moqui',
      debugShowCheckedModeBanner: false,
      theme: MoquiTheme.light(),
      darkTheme: MoquiTheme.dark(),
      themeMode: ThemeMode.system,
      routerConfig: router,
    );
  }
}

/// Branded splash screen shown while checking auth status on startup.
class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

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
