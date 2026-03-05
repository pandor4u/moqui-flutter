import 'dart:developer' as dev;
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/config.dart';
import '../api/moqui_api_client.dart';
import '../../core/providers.dart';
import '../../presentation/providers/screen_providers.dart';

/// Authentication state for the app.
enum AuthStatus { unknown, authenticated, unauthenticated, mfaRequired }

class AuthState {
  final AuthStatus status;
  final String? userId;
  final String? username;
  final String? errorMessage;
  final Map<String, dynamic>? mfaInfo;

  const AuthState({
    this.status = AuthStatus.unknown,
    this.userId,
    this.username,
    this.errorMessage,
    this.mfaInfo,
  });

  AuthState copyWith({
    AuthStatus? status,
    String? userId,
    String? username,
    String? errorMessage,
    Map<String, dynamic>? mfaInfo,
  }) {
    return AuthState(
      status: status ?? this.status,
      userId: userId ?? this.userId,
      username: username ?? this.username,
      errorMessage: errorMessage,
      mfaInfo: mfaInfo ?? this.mfaInfo,
    );
  }

  bool get isAuthenticated => status == AuthStatus.authenticated;
}

/// State notifier for authentication.
class AuthNotifier extends StateNotifier<AuthState> {
  final MoquiApiClient _apiClient;
  final Ref _ref;

  AuthNotifier(this._apiClient, this._ref) : super(const AuthState()) {
    // Wire 401 session-expiry detection to auto-logout
    _apiClient.onSessionExpired = _handleSessionExpired;
  }

  void _handleSessionExpired() {
    if (state.status == AuthStatus.authenticated) {
      _apiClient.clearCredentials();
      _invalidateCachedData();
      state = const AuthState(
        status: AuthStatus.unauthenticated,
        errorMessage: 'Session expired — please log in again',
      );
    }
  }

  /// Attempt login with username/password.
  Future<void> login(String username, String password) async {
    try {
      state = state.copyWith(status: AuthStatus.unknown, errorMessage: null);

      final response = await _apiClient.dio.post(
        MoquiConfig.loginPath,
        data: {'username': username, 'password': password},
        options: _noSessionTokenOptions(),
      );

      final data = response.data as Map<String, dynamic>?;
      if (data == null) {
        state = state.copyWith(
          status: AuthStatus.unauthenticated,
          errorMessage: 'Invalid response from server',
        );
        return;
      }

      if (data['mfaRequired'] == true) {
        state = state.copyWith(
          status: AuthStatus.mfaRequired,
          mfaInfo: data,
          username: username,
        );
        return;
      }

      if (data['loggedIn'] == true) {
        // Extract API key if provided, else use session
        final apiKey = data['apiKey']?.toString();
        if (apiKey != null && apiKey.isNotEmpty) {
          await _apiClient.setApiKey(apiKey);
        }

        state = AuthState(
          status: AuthStatus.authenticated,
          userId: data['userId']?.toString(),
          username: data['username']?.toString() ?? username,
        );
        return;
      }

      state = state.copyWith(
        status: AuthStatus.unauthenticated,
        errorMessage: data['errors']?.toString() ?? 'Login failed',
      );
    } catch (e) {
      dev.log('Login error', error: e, name: 'AuthProvider');
      state = state.copyWith(
        status: AuthStatus.unauthenticated,
        errorMessage: 'Login failed. Please check your credentials and try again.',
      );
    }
  }

  /// Send OTP for MFA.
  Future<void> sendOtp(String factorId) async {
    try {
      await _apiClient.dio.post(
        '/rest/sendOtp',
        data: {'factorId': factorId},
      );
    } catch (e) {
      dev.log('Send OTP error', error: e, name: 'AuthProvider');
      state = state.copyWith(errorMessage: 'Failed to send OTP. Please try again.');
    }
  }

  /// Verify OTP code.
  Future<void> verifyOtp(String code) async {
    try {
      final response = await _apiClient.dio.post(
        '/rest/verifyOtp',
        data: {'code': code},
      );

      final data = response.data as Map<String, dynamic>?;
      if (data != null && data['loggedIn'] == true) {
        state = AuthState(
          status: AuthStatus.authenticated,
          userId: data['userId']?.toString(),
          username: data['username']?.toString() ?? state.username,
        );
      } else {
        state = state.copyWith(
          errorMessage: data?['errors']?.toString() ?? 'OTP verification failed',
        );
      }
    } catch (e) {
      dev.log('OTP verify error', error: e, name: 'AuthProvider');
      state = state.copyWith(errorMessage: 'OTP verification failed. Please try again.');
    }
  }

  /// Logout.
  Future<void> logout() async {
    try {
      await _apiClient.dio.get(MoquiConfig.logoutPath);
    } catch (_) {
      // Logout may fail if session already expired
    }
    await _apiClient.clearCredentials();
    _invalidateCachedData();
    state = const AuthState(status: AuthStatus.unauthenticated);
  }

  /// Invalidate all cached screen/menu data to prevent stale data after logout.
  void _invalidateCachedData() {
    _ref.invalidate(screenProvider);
    _ref.invalidate(screenWithParamsProvider);
    _ref.invalidate(menuDataProvider);
    _ref.invalidate(currentScreenPathProvider);
  }

  /// Check if user is already authenticated (e.g. from stored API key).
  Future<void> checkAuth() async {
    await _apiClient.loadApiKey();
    try {
      // Try fetching menuData to verify auth is still valid
      final response = await _apiClient.dio.get(
        '${MoquiConfig.menuDataPath}${MoquiConfig.fappsPath}',
      );
      if (response.statusCode == 200) {
        state = state.copyWith(status: AuthStatus.authenticated);
        return;
      }
    } catch (_) {
      // Auth invalid
    }
    state = const AuthState(status: AuthStatus.unauthenticated);
  }

  Options _noSessionTokenOptions() {
    return Options(headers: {'moquiSessionToken': ''});
  }
}

/// Provider for authentication state.
final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  final apiClient = ref.watch(moquiApiClientProvider);
  return AuthNotifier(apiClient, ref);
});

/// Convenience for checking auth in router guards.
final isAuthenticatedProvider = Provider<bool>((ref) {
  return ref.watch(authProvider).isAuthenticated;
});
