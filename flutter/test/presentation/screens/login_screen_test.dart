import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:moqui_flutter/data/auth/auth_provider.dart';
import 'package:moqui_flutter/presentation/screens/login_screen.dart';

/// A fake AuthNotifier that doesn't make real HTTP calls.
class FakeAuthNotifier extends StateNotifier<AuthState>
    implements AuthNotifier {
  FakeAuthNotifier([AuthState? initial])
      : super(initial ?? const AuthState(status: AuthStatus.unauthenticated));

  @override
  Future<void> login(String username, String password) async {
    state = state.copyWith(status: AuthStatus.unknown);
    // Simulate success
    state = AuthState(
      status: AuthStatus.authenticated,
      userId: '1',
      username: username,
    );
  }

  @override
  Future<void> logout() async {
    state = const AuthState(status: AuthStatus.unauthenticated);
  }

  @override
  Future<void> sendOtp(String factorId) async {}

  @override
  Future<void> verifyOtp(String code) async {
    state = const AuthState(status: AuthStatus.authenticated);
  }

  @override
  Future<void> checkAuth() async {}
}

void main() {
  Widget buildTestApp({AuthState? initialState}) {
    final fakeNotifier = FakeAuthNotifier(initialState);
    return ProviderScope(
      overrides: [
        authProvider.overrideWith((_) => fakeNotifier),
      ],
      child: const MaterialApp(
        home: LoginScreen(),
      ),
    );
  }

  group('LoginScreen', () {
    testWidgets('renders login form with username and password fields',
        (tester) async {
      await tester.pumpWidget(buildTestApp());
      await tester.pumpAndSettle();

      expect(find.text('Moqui'), findsOneWidget);
      expect(find.text('Sign in to continue'), findsOneWidget);
      expect(find.text('Username'), findsOneWidget);
      expect(find.text('Password'), findsOneWidget);
      expect(find.text('Sign In'), findsOneWidget);
    });

    testWidgets('shows validation errors on empty submit', (tester) async {
      await tester.pumpWidget(buildTestApp());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Sign In'));
      await tester.pumpAndSettle();

      expect(find.text('Username is required'), findsOneWidget);
      expect(find.text('Password is required'), findsOneWidget);
    });

    testWidgets('password visibility toggle works', (tester) async {
      await tester.pumpWidget(buildTestApp());
      await tester.pumpAndSettle();

      // Initially password is obscured — visibility_off icon is shown
      expect(find.byIcon(Icons.visibility_off), findsOneWidget);

      // Tap the visibility toggle
      await tester.tap(find.byIcon(Icons.visibility_off));
      await tester.pumpAndSettle();

      // Should now show visibility icon (not obscured)
      expect(find.byIcon(Icons.visibility), findsOneWidget);
    });

    testWidgets('shows error message from auth state', (tester) async {
      await tester.pumpWidget(buildTestApp(
        initialState: const AuthState(
          status: AuthStatus.unauthenticated,
          errorMessage: 'Invalid credentials',
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Invalid credentials'), findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
    });

    testWidgets('shows MFA form when status is mfaRequired', (tester) async {
      await tester.pumpWidget(buildTestApp(
        initialState: const AuthState(status: AuthStatus.mfaRequired),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Enter the verification code sent to your device.'),
          findsOneWidget);
      expect(find.text('Verification Code'), findsOneWidget);
      expect(find.text('Verify'), findsOneWidget);
      expect(find.text('Back to login'), findsOneWidget);
    });

    testWidgets('can enter username and password', (tester) async {
      await tester.pumpWidget(buildTestApp());
      await tester.pumpAndSettle();

      await tester.enterText(
          find.widgetWithText(TextFormField, 'Username'), 'admin');
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Password'), 'secret');

      expect(find.text('admin'), findsOneWidget);
      expect(find.text('secret'), findsOneWidget);
    });

    testWidgets('shows app icon', (tester) async {
      await tester.pumpWidget(buildTestApp());
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.apps), findsOneWidget);
    });
  });
}
