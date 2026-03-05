import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/api/moqui_api_client.dart';
import '../data/realtime/notification_client.dart';
import '../data/realtime/log_stream_client.dart';

/// Global Riverpod providers for dependency injection.

/// The Dio-based API client for all Moqui HTTP communication.
final moquiApiClientProvider = Provider<MoquiApiClient>((ref) {
  return MoquiApiClient(ref: ref);
});

/// Notification WebSocket client.
final notificationClientProvider = Provider<MoquiNotificationClient>((ref) {
  final apiClient = ref.watch(moquiApiClientProvider);
  return MoquiNotificationClient(apiClient: apiClient);
});

/// Log stream WebSocket client.
final logStreamClientProvider = Provider<MoquiLogStreamClient>((ref) {
  final apiClient = ref.watch(moquiApiClientProvider);
  return MoquiLogStreamClient(apiClient: apiClient);
});
