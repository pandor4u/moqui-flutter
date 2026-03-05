import 'package:flutter_test/flutter_test.dart';
import 'package:moqui_flutter/data/api/moqui_api_client.dart';

void main() {
  group('TransitionResponse', () {
    test('fromJson parses complete response', () {
      final json = {
        'screenPathList': ['fapps', 'dashboard'],
        'screenParameters': {'id': '123', 'mode': 'edit'},
        'screenUrl': '/fapps/dashboard',
        'messages': ['Saved successfully'],
        'errors': [],
      };
      final response = TransitionResponse.fromJson(json);
      expect(response.screenPathList, ['fapps', 'dashboard']);
      expect(response.screenParameters, {'id': '123', 'mode': 'edit'});
      expect(response.screenUrl, '/fapps/dashboard');
      expect(response.messages, ['Saved successfully']);
      expect(response.errors, isEmpty);
      expect(response.hasErrors, isFalse);
      expect(response.hasMessages, isTrue);
    });

    test('fromJson handles null/missing fields', () {
      final response = TransitionResponse.fromJson({});
      expect(response.screenPathList, isEmpty);
      expect(response.screenParameters, isEmpty);
      expect(response.screenUrl, '');
      expect(response.messages, isEmpty);
      expect(response.errors, isEmpty);
    });

    test('hasErrors returns true when errors present', () {
      final response = TransitionResponse.fromJson({
        'errors': ['Field required'],
      });
      expect(response.hasErrors, isTrue);
    });

    test('hasMessages returns true when messages present', () {
      final response = TransitionResponse.fromJson({
        'messages': ['Record created'],
      });
      expect(response.hasMessages, isTrue);
    });

    test('fromJson converts non-string list elements to strings', () {
      final response = TransitionResponse.fromJson({
        'screenPathList': [123, true, 'path'],
        'messages': [456],
        'errors': [false],
      });
      expect(response.screenPathList, ['123', 'true', 'path']);
      expect(response.messages, ['456']);
      expect(response.errors, ['false']);
    });

    test('default constructor has empty defaults', () {
      final response = TransitionResponse();
      expect(response.screenPathList, const []);
      expect(response.screenParameters, const {});
      expect(response.screenUrl, '');
      expect(response.messages, const []);
      expect(response.errors, const []);
    });
  });

  group('EntityListResponse', () {
    test('default constructor values', () {
      final response = EntityListResponse();
      expect(response.data, isEmpty);
      expect(response.totalCount, 0);
      expect(response.pageIndex, 0);
      expect(response.pageSize, 20);
    });

    test('totalPages calculation', () {
      final response = EntityListResponse(
        totalCount: 100,
        pageSize: 20,
      );
      expect(response.totalPages, 5);
    });

    test('totalPages rounds up for partial pages', () {
      final response = EntityListResponse(
        totalCount: 101,
        pageSize: 20,
      );
      expect(response.totalPages, 6);
    });

    test('totalPages is 0 when totalCount is 0', () {
      final response = EntityListResponse(totalCount: 0, pageSize: 20);
      expect(response.totalPages, 0);
    });

    test('hasMore is true when more pages exist', () {
      final response = EntityListResponse(
        totalCount: 100,
        pageSize: 20,
        pageIndex: 2,
      );
      expect(response.hasMore, isTrue);
    });

    test('hasMore is false on last page', () {
      final response = EntityListResponse(
        totalCount: 100,
        pageSize: 20,
        pageIndex: 4,
      );
      expect(response.hasMore, isFalse);
    });

    test('hasMore is false when only one page', () {
      final response = EntityListResponse(
        totalCount: 5,
        pageSize: 20,
        pageIndex: 0,
      );
      expect(response.hasMore, isFalse);
    });

    test('stores data list', () {
      final response = EntityListResponse(
        data: [
          {'id': '1', 'name': 'Alice'},
          {'id': '2', 'name': 'Bob'},
        ],
        totalCount: 2,
      );
      expect(response.data.length, 2);
      expect((response.data[0] as Map)['name'], 'Alice');
    });
  });
}
