import 'package:flutter_test/flutter_test.dart';
import 'package:moqui_flutter/core/config.dart';

void main() {
  group('MoquiConfig', () {
    test('baseUrl has a default value', () {
      expect(MoquiConfig.baseUrl, isNotEmpty);
      expect(MoquiConfig.baseUrl, contains('://'));
    });

    test('fappsPath is /fapps', () {
      expect(MoquiConfig.fappsPath, '/fapps');
    });

    test('entityRestPath starts with /', () {
      expect(MoquiConfig.entityRestPath, startsWith('/'));
      expect(MoquiConfig.entityRestPath, contains('rest'));
    });

    test('serviceRestPath starts with /', () {
      expect(MoquiConfig.serviceRestPath, startsWith('/'));
    });

    test('loginPath is /rest/login', () {
      expect(MoquiConfig.loginPath, '/rest/login');
    });

    test('logoutPath is /rest/logout', () {
      expect(MoquiConfig.logoutPath, '/rest/logout');
    });

    test('menuDataPath is /menuData', () {
      expect(MoquiConfig.menuDataPath, '/menuData');
    });

    test('notifyWsPath is /notws', () {
      expect(MoquiConfig.notifyWsPath, '/notws');
    });

    test('defaultPageSize is positive', () {
      expect(MoquiConfig.defaultPageSize, greaterThan(0));
    });

    test('httpTimeoutMs is reasonable', () {
      expect(MoquiConfig.httpTimeoutMs, greaterThan(5000));
      expect(MoquiConfig.httpTimeoutMs, lessThan(120000));
    });

    test('wsReconnectIntervalSec is positive', () {
      expect(MoquiConfig.wsReconnectIntervalSec, greaterThan(0));
    });

    test('wsMaxReconnectAttempts is positive', () {
      expect(MoquiConfig.wsMaxReconnectAttempts, greaterThan(0));
    });

    test('baseUrl is mutable for runtime configuration', () {
      final original = MoquiConfig.baseUrl;
      MoquiConfig.baseUrl = 'https://custom.example.com';
      expect(MoquiConfig.baseUrl, 'https://custom.example.com');
      MoquiConfig.baseUrl = original; // restore
    });
  });
}
