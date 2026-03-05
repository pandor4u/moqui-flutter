import 'package:flutter_test/flutter_test.dart';
import 'package:moqui_flutter/data/realtime/notification_client.dart';

void main() {
  group('MoquiNotification', () {
    test('fromJson parses complete notification', () {
      final json = {
        'topic': 'OrderUpdate',
        'title': 'Order Shipped',
        'message': 'Your order #1234 has shipped.',
        'link': '/fapps/orders/1234',
        'type': 'success',
        'showAlert': true,
      };
      final n = MoquiNotification.fromJson(json);
      expect(n.topic, 'OrderUpdate');
      expect(n.title, 'Order Shipped');
      expect(n.message, 'Your order #1234 has shipped.');
      expect(n.link, '/fapps/orders/1234');
      expect(n.type, 'success');
      expect(n.showAlert, isTrue);
    });

    test('fromJson handles empty/missing fields with defaults', () {
      final n = MoquiNotification.fromJson({});
      expect(n.topic, '');
      expect(n.title, '');
      expect(n.message, '');
      expect(n.link, '');
      expect(n.type, 'info');
      expect(n.showAlert, isFalse); // showAlert defaults to false when null
    });

    test('fromJson converts non-string values to strings', () {
      final n = MoquiNotification.fromJson({
        'topic': 123,
        'title': true,
        'message': 45.6,
      });
      expect(n.topic, '123');
      expect(n.title, 'true');
      expect(n.message, '45.6');
    });

    test('showAlert is false when value is not true', () {
      expect(
        MoquiNotification.fromJson({'showAlert': false}).showAlert,
        isFalse,
      );
      expect(
        MoquiNotification.fromJson({'showAlert': 'yes'}).showAlert,
        isFalse,
      );
      expect(
        MoquiNotification.fromJson({'showAlert': 1}).showAlert,
        isFalse,
      );
    });

    test('showAlert is true only when value is boolean true', () {
      expect(
        MoquiNotification.fromJson({'showAlert': true}).showAlert,
        isTrue,
      );
    });

    test('type defaults to info', () {
      final n = MoquiNotification.fromJson({'topic': 'Test'});
      expect(n.type, 'info');
    });

    test('various notification types', () {
      for (final type in ['info', 'success', 'warning', 'danger']) {
        final n = MoquiNotification.fromJson({'type': type});
        expect(n.type, type);
      }
    });

    test('constructor with required and optional params', () {
      final n = MoquiNotification(
        topic: 'MyTopic',
        title: 'My Title',
        message: 'My Message',
        link: '/some/path',
        type: 'warning',
        showAlert: false,
      );
      expect(n.topic, 'MyTopic');
      expect(n.title, 'My Title');
      expect(n.message, 'My Message');
      expect(n.link, '/some/path');
      expect(n.type, 'warning');
      expect(n.showAlert, isFalse);
    });

    test('constructor defaults for optional params', () {
      final n = MoquiNotification(topic: 'MinimalTopic');
      expect(n.title, '');
      expect(n.message, '');
      expect(n.link, '');
      expect(n.type, 'info');
      expect(n.showAlert, isTrue);
    });
  });
}
