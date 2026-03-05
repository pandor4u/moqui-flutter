import 'package:flutter_test/flutter_test.dart';
import 'package:moqui_flutter/domain/screen/screen_models.dart';

void main() {
  group('ScreenNode', () {
    test('fromJson parses basic screen', () {
      final json = {
        'screenName': 'TestScreen',
        'renderMode': 'fjson',
        'menuTitle': 'Test',
        'widgets': [
          {'_type': 'label', 'text': 'Hello World'},
          {'_type': 'container', 'style': 'card', 'children': []},
        ],
      };
      final screen = ScreenNode.fromJson(json);
      expect(screen.screenName, 'TestScreen');
      expect(screen.renderMode, 'fjson');
      expect(screen.widgets.length, 2);
      expect(screen.menuTitle, 'Test');
    });

    test('fromJson handles empty widget list', () {
      final json = {
        'screenName': 'Empty',
        'screenPath': '/empty',
        'widgets': <dynamic>[],
      };
      final screen = ScreenNode.fromJson(json);
      expect(screen.widgets, isEmpty);
    });

    test('fromJson handles missing optional fields', () {
      final json = <String, dynamic>{
        'widgets': <dynamic>[],
      };
      final screen = ScreenNode.fromJson(json);
      expect(screen.screenName, '');
      expect(screen.renderMode, 'fjson');
      expect(screen.menuTitle, '');
    });
  });

  group('WidgetNode', () {
    test('fromJson parses type and attributes', () {
      final json = {
        '_type': 'label',
        'text': 'Hello',
        'style': 'h3',
      };
      final node = WidgetNode.fromJson(json);
      expect(node.type, 'label');
      expect(node.attr('text'), 'Hello');
      expect(node.attr('style'), 'h3');
    });

    test('attr returns default when missing', () {
      const node = WidgetNode(type: 'label', attributes: {});
      expect(node.attr('missing', 'fallback'), 'fallback');
      expect(node.attr('missing'), '');
    });

    test('boolAttr returns correct values', () {
      const node = WidgetNode(type: 'field', attributes: {
        'disabled': 'true',
        'enabled': 'false',
        'checked': true,
      });
      expect(node.boolAttr('disabled'), isTrue);
      expect(node.boolAttr('enabled'), isFalse);
      expect(node.boolAttr('checked'), isTrue);
      expect(node.boolAttr('missing'), isFalse);
    });

    test('children parsed from attributes', () {
      final json = {
        '_type': 'container',
        'children': [
          {'_type': 'label', 'text': 'child1'},
          {'_type': 'label', 'text': 'child2'},
        ],
      };
      final node = WidgetNode.fromJson(json);
      expect(node.children.length, 2);
      expect(node.children[0].type, 'label');
      expect(node.children[1].attr('text'), 'child2');
    });

    test('children empty when absent', () {
      const node = WidgetNode(type: 'label', attributes: {});
      expect(node.children, isEmpty);
    });
  });

  group('FormDefinition', () {
    test('fromJson parses form-single', () {
      final json = {
        '_type': 'form-single',
        'formName': 'CreateOrder',
        'transition': 'createOrder',
        'fields': [
          {
            'name': 'orderId',
            'title': 'Order ID',
            'widgets': [
              {'widgetType': 'text-line', 'inputType': 'text'}
            ],
          },
        ],
        'headerFields': <dynamic>[],
      };
      final form = FormDefinition.fromJson(json);
      expect(form.formType, 'form-single');
      expect(form.formName, 'CreateOrder');
      expect(form.transition, 'createOrder');
      expect(form.isSingle, isTrue);
      expect(form.isList, isFalse);
      expect(form.fields.length, 1);
      expect(form.fields.first.name, 'orderId');
    });

    test('fromJson parses form-list with listData', () {
      final json = {
        '_type': 'form-list',
        'formName': 'OrderList',
        'list': 'orderList',
        'paginate': 'true',
        'fields': [
          {
            'name': 'orderId',
            'title': 'Order ID',
            'widgets': [
              {'widgetType': 'display'}
            ],
          },
          {
            'name': 'status',
            'title': 'Status',
            'widgets': [
              {'widgetType': 'display'}
            ],
          },
        ],
        'headerFields': <dynamic>[],
        'listData': [
          {'orderId': 'ORD-001', 'status': 'Active'},
          {'orderId': 'ORD-002', 'status': 'Cancelled'},
        ],
        'paginateInfo': {
          'pageIndex': 0,
          'pageSize': 20,
          'count': 2,
          'pageMaxIndex': 0,
          'pageRangeLow': 1,
          'pageRangeHigh': 2,
        },
      };
      final form = FormDefinition.fromJson(json);
      expect(form.isList, isTrue);
      expect(form.listName, 'orderList');
      expect(form.paginate, isTrue);
      expect(form.listData.length, 2);
      expect(form.listData[0]['orderId'], 'ORD-001');
      expect(form.paginateInfo['count'], 2);
      expect(form.paginateInfo['pageMaxIndex'], 0);
    });

    test('fromJson handles missing listData gracefully', () {
      final json = {
        '_type': 'form-list',
        'fields': <dynamic>[],
      };
      final form = FormDefinition.fromJson(json);
      expect(form.listData, isEmpty);
      expect(form.paginateInfo, isEmpty);
    });

    test('fromJson parses field layout', () {
      final json = {
        '_type': 'form-single',
        'fields': <dynamic>[],
        'fieldLayout': {
          'rows': [
            {'_type': 'field-ref', 'name': 'orderId'},
            {
              '_type': 'field-row',
              'fields': [
                {'name': 'firstName'},
                {'name': 'lastName'},
              ],
            },
          ],
        },
      };
      final form = FormDefinition.fromJson(json);
      expect(form.fieldLayout, isNotNull);
      expect(form.fieldLayout!.rows.length, 2);
      expect(form.fieldLayout!.rows[0].type, 'field-ref');
      expect(form.fieldLayout!.rows[0].name, 'orderId');
      expect(form.fieldLayout!.rows[1].type, 'field-row');
    });
  });

  group('FieldDefinition', () {
    test('fromJson parses field with widgets', () {
      final json = {
        'name': 'username',
        'title': 'Username',
        'tooltip': 'Enter your username',
        'from': 'UserAccount',
        'widgets': [
          {
            '_type': 'text-line',
            'inputType': 'text',
            'maxlength': '50',
          },
        ],
      };
      final field = FieldDefinition.fromJson(json);
      expect(field.name, 'username');
      expect(field.title, 'Username');
      expect(field.tooltip, 'Enter your username');
      expect(field.from, 'UserAccount');
      expect(field.widgets.length, 1);
      expect(field.widgets.first.widgetType, 'text-line');
    });

    test('isHidden detects hidden widget type', () {
      final hidden1 = FieldDefinition.fromJson(const {
        'name': 'secret',
        'widgets': [
          {'_type': 'hidden'},
        ],
      });
      expect(hidden1.isHidden, isTrue);

      final hidden2 = FieldDefinition.fromJson(const {
        'name': 'ignored',
        'widgets': [
          {'_type': 'ignored'},
        ],
      });
      expect(hidden2.isHidden, isTrue);

      final visible = FieldDefinition.fromJson(const {
        'name': 'visible',
        'widgets': [
          {'_type': 'text-line'},
        ],
      });
      expect(visible.isHidden, isFalse);
    });

    test('currentValue from field-level attribute', () {
      final field = FieldDefinition.fromJson(const {
        'name': 'status',
        'currentValue': 'Active',
        'widgets': [
          {
            '_type': 'display',
          },
        ],
      });
      expect(field.currentValue, 'Active');
    });
  });

  group('FieldWidget', () {
    test('fromJson parses all attributes', () {
      final json = {
        '_type': 'drop-down',
        'allowEmpty': 'true',
        'currentValue': 'USD',
        'options': [
          {'key': 'USD', 'text': 'US Dollar'},
          {'key': 'EUR', 'text': 'Euro'},
        ],
      };
      final widget = FieldWidget.fromJson(json);
      expect(widget.widgetType, 'drop-down');
      expect(widget.attr('allowEmpty'), 'true');
      expect(widget.options.length, 2);
      expect(widget.options[0].key, 'USD');
      expect(widget.options[0].text, 'US Dollar');
    });
  });

  group('FieldOption', () {
    test('fromJson parses key and text', () {
      final opt = FieldOption.fromJson(const {'key': 'Y', 'text': 'Yes'});
      expect(opt.key, 'Y');
      expect(opt.text, 'Yes');
    });

    test('fromJson handles missing text', () {
      final opt = FieldOption.fromJson(const {'key': 'X'});
      expect(opt.key, 'X');
      expect(opt.text, '');
    });
  });

  group('MenuNode', () {
    test('fromJson parses menu data', () {
      final json = {
        'title': 'Dashboard',
        'path': 'dashboard',
        'image': 'fa-dashboard',
        'imageType': 'icon',
        'hasTabMenu': true,
        'subscreens': [
          {
            'title': 'Overview',
            'path': 'overview',
            'active': true,
          },
        ],
      };
      final menu = MenuNode.fromJson(json);
      expect(menu.title, 'Dashboard');
      expect(menu.path, 'dashboard');
      expect(menu.image, 'fa-dashboard');
      expect(menu.hasTabMenu, isTrue);
      expect(menu.subscreens.length, 1);
      expect(menu.subscreens.first.title, 'Overview');
      expect(menu.subscreens.first.active, isTrue);
    });
  });

  group('FieldLayout', () {
    test('fromJson parses rows', () {
      final json = {
        'rows': [
          {'_type': 'field-ref', 'name': 'field1'},
          {
            '_type': 'field-group',
            'title': 'Group 1',
            'children': [
              {'_type': 'field-ref', 'name': 'field2'},
            ],
          },
        ],
      };
      final layout = FieldLayout.fromJson(json);
      expect(layout.rows.length, 2);
      expect(layout.rows[0].type, 'field-ref');
      expect(layout.rows[0].name, 'field1');
      expect(layout.rows[1].type, 'field-group');
      expect(layout.rows[1].title, 'Group 1');
      expect(layout.rows[1].children.length, 1);
    });

    test('fromJson handles empty rows', () {
      final layout = FieldLayout.fromJson(const {'rows': <dynamic>[]});
      expect(layout.rows, isEmpty);
    });
  });
}
