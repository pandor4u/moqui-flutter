import 'package:flutter_test/flutter_test.dart';
import 'package:moqui_flutter/data/auth/auth_provider.dart';

void main() {
  group('AuthStatus', () {
    test('has all expected values', () {
      expect(AuthStatus.values, containsAll([
        AuthStatus.unknown,
        AuthStatus.authenticated,
        AuthStatus.unauthenticated,
        AuthStatus.mfaRequired,
      ]));
    });
  });

  group('AuthState', () {
    test('default constructor has unknown status', () {
      const state = AuthState();
      expect(state.status, AuthStatus.unknown);
      expect(state.userId, isNull);
      expect(state.username, isNull);
      expect(state.errorMessage, isNull);
      expect(state.mfaInfo, isNull);
      expect(state.isAuthenticated, isFalse);
    });

    test('isAuthenticated returns true only for authenticated status', () {
      const authState = AuthState(status: AuthStatus.authenticated);
      expect(authState.isAuthenticated, isTrue);

      const unauthState = AuthState(status: AuthStatus.unauthenticated);
      expect(unauthState.isAuthenticated, isFalse);

      const mfaState = AuthState(status: AuthStatus.mfaRequired);
      expect(mfaState.isAuthenticated, isFalse);

      const unknownState = AuthState(status: AuthStatus.unknown);
      expect(unknownState.isAuthenticated, isFalse);
    });

    test('copyWith preserves existing values when not overridden', () {
      const original = AuthState(
        status: AuthStatus.authenticated,
        userId: '100',
        username: 'admin',
      );

      final copied = original.copyWith(errorMessage: 'Session warning');
      expect(copied.status, AuthStatus.authenticated);
      expect(copied.userId, '100');
      expect(copied.username, 'admin');
      expect(copied.errorMessage, 'Session warning');
    });

    test('copyWith overrides specified values', () {
      const original = AuthState(
        status: AuthStatus.authenticated,
        userId: '100',
        username: 'admin',
      );

      final copied = original.copyWith(
        status: AuthStatus.unauthenticated,
        username: 'guest',
      );
      expect(copied.status, AuthStatus.unauthenticated);
      expect(copied.username, 'guest');
      expect(copied.userId, '100'); // unchanged
    });

    test('copyWith clears errorMessage when set to null', () {
      const original = AuthState(
        status: AuthStatus.unauthenticated,
        errorMessage: 'Bad password',
      );

      // Note: copyWith uses `errorMessage` positionally without ??
      // so passing null should clear it
      final copied = original.copyWith(
        status: AuthStatus.unknown,
        errorMessage: null,
      );
      expect(copied.errorMessage, isNull);
    });

    test('can hold MFA info', () {
      const state = AuthState(
        status: AuthStatus.mfaRequired,
        mfaInfo: {'factorId': 'totp-123', 'factorType': 'totp'},
      );
      expect(state.mfaInfo, isNotNull);
      expect(state.mfaInfo!['factorId'], 'totp-123');
    });

    test('constructs with all fields', () {
      const state = AuthState(
        status: AuthStatus.authenticated,
        userId: 'U001',
        username: 'john.doe',
        errorMessage: null,
        mfaInfo: {'key': 'value'},
      );
      expect(state.status, AuthStatus.authenticated);
      expect(state.userId, 'U001');
      expect(state.username, 'john.doe');
      expect(state.isAuthenticated, isTrue);
      expect(state.mfaInfo, {'key': 'value'});
    });
  });
}
