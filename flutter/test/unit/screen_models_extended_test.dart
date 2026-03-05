import 'package:flutter_test/flutter_test.dart';
import 'package:moqui_flutter/domain/screen/screen_models.dart';

/// Phase 9.1: Extended unit tests for screen_models.dart coverage gaps.
/// Targets: ConditionalField, RowFieldGroup, DynamicOptionsConfig,
/// AutocompleteConfig, DependsOn, FormColumn, resolveWidgets, and
/// untested getters/methods on existing classes.
void main() {
  // =========================================================================
  // WidgetNode — untested methods
  // =========================================================================
  group('WidgetNode — extended', () {
    test('intAttr returns parsed integer', () {
      const node = WidgetNode(type: 'input', attributes: {'maxlength': '50'});
      expect(node.intAttr('maxlength'), 50);
    });

    test('intAttr returns default for non-numeric value', () {
      const node = WidgetNode(type: 'input', attributes: {'maxlength': 'abc'});
      expect(node.intAttr('maxlength'), 0);
      expect(node.intAttr('maxlength', 10), 10);
    });

    test('intAttr returns default for missing key', () {
      const node = WidgetNode(type: 'input', attributes: {});
      expect(node.intAttr('missing', 42), 42);
    });

    test('isType matches correctly', () {
      const node = WidgetNode(type: 'label', attributes: {});
      expect(node.isType('label'), isTrue);
      expect(node.isType('link'), isFalse);
    });

    test('fromJson parses children from widgets key', () {
      final json = {
        '_type': 'container',
        'widgets': [
          {'_type': 'label', 'text': 'from-widgets-key'},
        ],
      };
      final node = WidgetNode.fromJson(json);
      expect(node.children.length, 1);
      expect(node.children[0].attr('text'), 'from-widgets-key');
    });

    test('fromJson parses children from widgetTemplate key', () {
      final json = {
        '_type': 'container',
        'widgetTemplate': [
          {'_type': 'link', 'url': '/test'},
        ],
      };
      final node = WidgetNode.fromJson(json);
      expect(node.children.length, 1);
      expect(node.children[0].type, 'link');
    });

    test('fromJson merges children from multiple keys', () {
      final json = {
        '_type': 'container',
        'children': [
          {'_type': 'label', 'text': 'c1'},
        ],
        'widgets': [
          {'_type': 'label', 'text': 'w1'},
        ],
      };
      final node = WidgetNode.fromJson(json);
      expect(node.children.length, 2);
    });

    test('fromJson ignores non-Map items in children list', () {
      final json = {
        '_type': 'container',
        'children': [
          {'_type': 'label'},
          'not-a-map',
          42,
          null,
        ],
      };
      final node = WidgetNode.fromJson(json);
      expect(node.children.length, 1);
    });
  });

  // =========================================================================
  // ScreenNode — untested fields
  // =========================================================================
  group('ScreenNode — extended', () {
    test('resolvedScreenPath parsed from JSON', () {
      final json = {
        'screenName': 'Detail',
        '_resolvedScreenPath': '/fapps/Order/Detail',
        'widgets': <dynamic>[],
      };
      final screen = ScreenNode.fromJson(json);
      expect(screen.resolvedScreenPath, '/fapps/Order/Detail');
    });

    test('type parsed from _type', () {
      final json = {
        '_type': 'screen',
        'widgets': <dynamic>[],
      };
      final screen = ScreenNode.fromJson(json);
      expect(screen.type, 'screen');
    });
  });

  // =========================================================================
  // FormDefinition — untested fields
  // =========================================================================
  group('FormDefinition — extended', () {
    test('fromJson parses rowSelection', () {
      final json = {
        '_type': 'form-list',
        'fields': <dynamic>[],
        'rowSelection': {
          'idField': 'orderId',
          'parameter': 'selectedIds',
        },
      };
      final form = FormDefinition.fromJson(json);
      expect(form.hasRowSelection, isTrue);
      expect(form.rowSelectionIdField, 'orderId');
    });

    test('fromJson parses skipForm', () {
      final json = {
        '_type': 'form-list',
        'fields': <dynamic>[],
        'skipForm': 'true',
      };
      final form = FormDefinition.fromJson(json);
      expect(form.skipForm, isTrue);
    });

    test('fromJson parses headerDialog', () {
      final json = {
        '_type': 'form-list',
        'fields': <dynamic>[],
        'headerDialog': 'true',
      };
      final form = FormDefinition.fromJson(json);
      expect(form.headerDialog, isTrue);
    });

    test('fromJson parses export buttons', () {
      final json = {
        '_type': 'form-list',
        'fields': <dynamic>[],
        'showCsvButton': 'true',
        'showXlsxButton': 'true',
        'exportBaseUrl': '/export/orders',
      };
      final form = FormDefinition.fromJson(json);
      expect(form.showCsvButton, isTrue);
      expect(form.showXlsxButton, isTrue);
      expect(form.exportBaseUrl, '/export/orders');
    });

    test('fromJson parses editUrl', () {
      final json = {
        '_type': 'form-single',
        'fields': <dynamic>[],
        'editUrl': '/Order/Edit',
      };
      final form = FormDefinition.fromJson(json);
      expect(form.editUrl, '/Order/Edit');
    });

    test('fromJson parses savedFinds', () {
      final json = {
        '_type': 'form-list',
        'fields': <dynamic>[],
        'formSavedFindsList': [
          {'description': 'Active Orders', 'findId': 'SF-001'},
          {'description': 'Cancelled', 'findId': 'SF-002'},
        ],
      };
      final form = FormDefinition.fromJson(json);
      expect(form.savedFinds.length, 2);
      expect((form.savedFinds[0] as Map)['description'], 'Active Orders');
    });

    test('fromJson parses allColumns', () {
      final json = {
        '_type': 'form-list',
        'fields': <dynamic>[],
        'allColumns': [
          {'name': 'orderId', 'hidden': false},
          {'name': 'status', 'hidden': false},
          {'name': 'amount', 'hidden': true},
        ],
      };
      final form = FormDefinition.fromJson(json);
      expect(form.allColumns.length, 3);
      expect(form.allColumns[1]['name'], 'status');
    });

    test('fromJson parses columns (FormColumn list)', () {
      final json = {
        '_type': 'form-list',
        'fields': <dynamic>[],
        'columns': [
          {
            'style': 'col-lg-4',
            'fieldRefs': ['orderId', 'status'],
          },
          {
            'style': 'col-lg-8',
            'fieldRefs': ['amount'],
          },
        ],
      };
      final form = FormDefinition.fromJson(json);
      expect(form.columns!.length, 2);
      expect(form.columns![0].style, 'col-lg-4');
      expect(form.columns![0].fieldRefs, ['orderId', 'status']);
      expect(form.columns![1].fieldRefs, ['amount']);
    });
  });

  // =========================================================================
  // ConditionalField — entirely new coverage
  // =========================================================================
  group('ConditionalField', () {
    test('fromJson extracts conditionField from != null pattern', () {
      final json = {
        'condition': 'entityValue != null',
        'widgets': [
          {'_type': 'display', 'resolvedText': 'Has Value'},
        ],
      };
      final cf = ConditionalField.fromJson(json);
      expect(cf.condition, 'entityValue != null');
      expect(cf.conditionField, 'entityValue');
      expect(cf.widgets.length, 1);
    });

    test('fromJson handles condition without space', () {
      final cf = ConditionalField.fromJson(const {
        'condition': 'someField!=null',
        'widgets': <dynamic>[],
      });
      expect(cf.conditionField, 'someField');
    });

    test('fromJson returns empty conditionField for non-matching condition', () {
      final cf = ConditionalField.fromJson(const {
        'condition': 'x == y',
        'widgets': <dynamic>[],
      });
      expect(cf.conditionField, '');
    });

    test('fromJson returns empty conditionField for empty condition', () {
      final cf = ConditionalField.fromJson(const {
        'condition': '',
        'widgets': <dynamic>[],
      });
      expect(cf.conditionField, '');
    });

    test('fromJson parses conditionResult true', () {
      final cf = ConditionalField.fromJson(const {
        'conditionResult': true,
        'widgets': <dynamic>[],
      });
      expect(cf.conditionResult, isTrue);
    });

    test('fromJson parses conditionResult false', () {
      final cf = ConditionalField.fromJson(const {
        'conditionResult': false,
        'widgets': <dynamic>[],
      });
      expect(cf.conditionResult, isFalse);
    });

    test('fromJson parses conditionResult null for string or missing', () {
      final cf1 = ConditionalField.fromJson(const {
        'conditionResult': 'maybe',
        'widgets': <dynamic>[],
      });
      expect(cf1.conditionResult, isNull);

      final cf2 = ConditionalField.fromJson(const {
        'widgets': <dynamic>[],
      });
      expect(cf2.conditionResult, isNull);
    });

    test('fromJson parses title', () {
      final cf = ConditionalField.fromJson(const {
        'title': 'Edit Link',
        'widgets': <dynamic>[],
      });
      expect(cf.title, 'Edit Link');
    });
  });

  // =========================================================================
  // RowFieldGroup — entirely new coverage
  // =========================================================================
  group('RowFieldGroup', () {
    test('fromJson parses all fields', () {
      final json = {
        'rowType': 'first-row-field',
        'title': 'Header Row',
        'widgets': [
          {'_type': 'display', 'text': 'item1'},
          {'_type': 'text-line'},
        ],
      };
      final rfg = RowFieldGroup.fromJson(json);
      expect(rfg.rowType, 'first-row-field');
      expect(rfg.title, 'Header Row');
      expect(rfg.widgets.length, 2);
      expect(rfg.widgets[0].widgetType, 'display');
    });

    test('fromJson handles missing fields', () {
      final rfg = RowFieldGroup.fromJson(const <String, dynamic>{});
      expect(rfg.rowType, '');
      expect(rfg.title, '');
      expect(rfg.widgets, isEmpty);
    });
  });

  // =========================================================================
  // DynamicOptionsConfig — entirely new coverage
  // =========================================================================
  group('DynamicOptionsConfig', () {
    test('fromJson parses all fields', () {
      final json = {
        'transition': 'getStatusOptions',
        'serverSearch': 'true',
        'minLength': '3',
        'dependsOnList': [
          {'field': 'orgId', 'parameter': 'organizationId'},
        ],
      };
      final cfg = DynamicOptionsConfig.fromJson(json);
      expect(cfg.transition, 'getStatusOptions');
      expect(cfg.serverSearch, isTrue);
      expect(cfg.minLength, 3);
      expect(cfg.dependsOn.length, 1);
      expect(cfg.dependsOn[0].field, 'orgId');
      expect(cfg.dependsOn[0].parameter, 'organizationId');
    });

    test('fromJson defaults', () {
      final cfg = DynamicOptionsConfig.fromJson(const <String, dynamic>{});
      expect(cfg.transition, '');
      expect(cfg.serverSearch, isFalse);
      expect(cfg.minLength, 1);
      expect(cfg.dependsOn, isEmpty);
    });
  });

  // =========================================================================
  // AutocompleteConfig — entirely new coverage
  // =========================================================================
  group('AutocompleteConfig', () {
    test('fromJson parses all fields', () {
      final json = {
        'transition': 'searchProducts',
        'delay': '500',
        'minLength': '2',
        'showValue': 'true',
        'useActual': 'true',
      };
      final cfg = AutocompleteConfig.fromJson(json);
      expect(cfg.transition, 'searchProducts');
      expect(cfg.delay, 500);
      expect(cfg.minLength, 2);
      expect(cfg.showValue, isTrue);
      expect(cfg.useActual, isTrue);
    });

    test('fromJson defaults', () {
      final cfg = AutocompleteConfig.fromJson(const <String, dynamic>{});
      expect(cfg.transition, '');
      expect(cfg.delay, 300);
      expect(cfg.minLength, 1);
      expect(cfg.showValue, isFalse);
      expect(cfg.useActual, isFalse);
    });
  });

  // =========================================================================
  // DependsOn — entirely new coverage
  // =========================================================================
  group('DependsOn', () {
    test('fromJson parses field and parameter', () {
      final dep = DependsOn.fromJson(const {
        'field': 'productCategoryId',
        'parameter': 'parentCategoryId',
      });
      expect(dep.field, 'productCategoryId');
      expect(dep.parameter, 'parentCategoryId');
    });

    test('fromJson defaults missing parameter to empty', () {
      final dep = DependsOn.fromJson(const {'field': 'orgId'});
      expect(dep.field, 'orgId');
      expect(dep.parameter, '');
    });
  });

  // =========================================================================
  // FormColumn — entirely new coverage
  // =========================================================================
  group('FormColumn', () {
    test('fromJson parses style and fieldRefs', () {
      final col = FormColumn.fromJson(const {
        'style': 'col-lg-6',
        'fieldRefs': ['name', 'status', 'amount'],
      });
      expect(col.style, 'col-lg-6');
      expect(col.fieldRefs, ['name', 'status', 'amount']);
    });

    test('fromJson handles empty fieldRefs', () {
      final col = FormColumn.fromJson(const {
        'style': 'col-lg-12',
        'fieldRefs': <dynamic>[],
      });
      expect(col.fieldRefs, isEmpty);
    });

    test('fromJson handles missing fields', () {
      final col = FormColumn.fromJson(const <String, dynamic>{});
      expect(col.style, '');
      expect(col.fieldRefs, isEmpty);
    });
  });

  // =========================================================================
  // FieldWidget — untested features
  // =========================================================================
  group('FieldWidget — extended', () {
    test('boolAttr on FieldWidget', () {
      final fw = FieldWidget.fromJson(const {
        '_type': 'text-line',
        'disabled': 'true',
        'required': 'false',
      });
      expect(fw.boolAttr('disabled'), isTrue);
      expect(fw.boolAttr('required'), isFalse);
      expect(fw.boolAttr('missing'), isFalse);
    });

    test('fromJson parses dynamicOptions', () {
      final json = {
        '_type': 'drop-down',
        'dynamicOptions': {
          'transition': 'getOptions',
          'serverSearch': 'true',
        },
      };
      final fw = FieldWidget.fromJson(json);
      expect(fw.dynamicOptions, isNotNull);
      expect(fw.dynamicOptions!.transition, 'getOptions');
      expect(fw.dynamicOptions!.serverSearch, isTrue);
    });

    test('fromJson parses autocomplete', () {
      final json = {
        '_type': 'text-line',
        'autocomplete': {
          'transition': 'searchProducts',
          'minLength': '2',
        },
      };
      final fw = FieldWidget.fromJson(json);
      expect(fw.autocomplete, isNotNull);
      expect(fw.autocomplete!.transition, 'searchProducts');
      expect(fw.autocomplete!.minLength, 2);
    });

    test('fromJson parses dependsOnList', () {
      final json = {
        '_type': 'drop-down',
        'dependsOnList': [
          {'field': 'orgId', 'parameter': 'organizationId'},
          {'field': 'storeId'},
        ],
      };
      final fw = FieldWidget.fromJson(json);
      expect(fw.dependsOn.length, 2);
      expect(fw.dependsOn[0].field, 'orgId');
      expect(fw.dependsOn[0].parameter, 'organizationId');
      expect(fw.dependsOn[1].field, 'storeId');
    });

    test('fromJson parses dependsOnField single fallback', () {
      final json = {
        '_type': 'drop-down',
        'dependsOnField': 'parentId',
      };
      final fw = FieldWidget.fromJson(json);
      expect(fw.dependsOn.length, 1);
      expect(fw.dependsOn[0].field, 'parentId');
    });

    test('fromJson no depends when none specified', () {
      final json = {'_type': 'text-line'};
      final fw = FieldWidget.fromJson(json);
      expect(fw.dependsOn, isEmpty);
    });
  });

  // =========================================================================
  // FieldDefinition — untested features
  // =========================================================================
  group('FieldDefinition — extended', () {
    test('primaryWidgetType returns display when no widgets', () {
      final field = FieldDefinition.fromJson(const {
        'name': 'empty',
        'widgets': <dynamic>[],
      });
      expect(field.primaryWidgetType, 'display');
    });

    test('hide and align parsed', () {
      final field = FieldDefinition.fromJson(const {
        'name': 'hidden',
        'hide': 'true',
        'align': 'right',
        'widgets': <dynamic>[],
      });
      expect(field.hide, 'true');
      expect(field.align, 'right');
    });

    test('conditionalFields parsed', () {
      final field = FieldDefinition.fromJson(const {
        'name': 'action',
        'widgets': [
          {'_type': 'display', 'text': ' '},
        ],
        'conditionalFields': [
          {
            'condition': 'entityValue != null',
            'conditionResult': true,
            'widgets': [
              {'_type': 'link', 'text': 'Edit', 'url': '/edit'},
            ],
          },
        ],
      });
      expect(field.conditionalFields.length, 1);
      expect(field.conditionalFields[0].conditionField, 'entityValue');
      expect(field.conditionalFields[0].widgets[0].widgetType, 'link');
    });

    test('rowFields parsed', () {
      final field = FieldDefinition.fromJson(const {
        'name': 'multi',
        'widgets': [
          {'_type': 'display'},
        ],
        'rowFields': [
          {
            'rowType': 'first-row-field',
            'title': 'Row 1',
            'widgets': [
              {'_type': 'text-line'},
            ],
          },
        ],
      });
      expect(field.rowFields.length, 1);
      expect(field.rowFields[0].rowType, 'first-row-field');
      expect(field.rowFields[0].title, 'Row 1');
    });

    test('resolveWidgets returns default when no conditionalFields', () {
      final field = FieldDefinition.fromJson(const {
        'name': 'simple',
        'widgets': [
          {'_type': 'text-line'},
        ],
      });
      final resolved = field.resolveWidgets({'simple': 'value'});
      expect(resolved.length, 1);
      expect(resolved[0].widgetType, 'text-line');
    });

    test('resolveWidgets returns conditional widget when conditionResult is true', () {
      final field = FieldDefinition.fromJson(const {
        'name': 'action',
        'widgets': [
          {'_type': 'display', 'text': 'default'},
        ],
        'conditionalFields': [
          {
            'condition': 'entityValue != null',
            'conditionResult': true,
            'widgets': [
              {'_type': 'link', 'text': 'Edit'},
            ],
          },
        ],
      });
      final resolved = field.resolveWidgets({'entityValue': 'X'});
      expect(resolved.length, 1);
      expect(resolved[0].widgetType, 'link');
    });

    test('resolveWidgets uses client-side fallback when conditionField has value', () {
      final field = FieldDefinition.fromJson(const {
        'name': 'action',
        'widgets': [
          {'_type': 'display', 'text': 'default'},
        ],
        'conditionalFields': [
          {
            'condition': 'entityValue != null',
            'widgets': [
              {'_type': 'link', 'text': 'Edit'},
            ],
          },
        ],
      });
      // conditionResult is null, but rowData has the field
      final resolved = field.resolveWidgets({'entityValue': 'exists'});
      expect(resolved[0].widgetType, 'link');
    });

    test('resolveWidgets returns default when condition field is null in rowData', () {
      final field = FieldDefinition.fromJson(const {
        'name': 'action',
        'widgets': [
          {'_type': 'display', 'text': 'default'},
        ],
        'conditionalFields': [
          {
            'condition': 'entityValue != null',
            'widgets': [
              {'_type': 'link', 'text': 'Edit'},
            ],
          },
        ],
      });
      final resolved = field.resolveWidgets({'otherField': 'x'});
      expect(resolved[0].widgetType, 'display');
    });
  });

  // =========================================================================
  // MenuSubscreenItem — untested fields
  // =========================================================================
  group('MenuSubscreenItem — extended', () {
    test('fromJson parses all fields', () {
      final json = {
        'name': 'overview',
        'title': 'Overview',
        'path': 'overview',
        'pathWithParams': 'overview?mode=detail',
        'image': 'fa-eye',
        'imageType': 'icon',
        'menuInclude': true,
        'active': false,
        'disableLink': true,
      };
      final item = MenuSubscreenItem.fromJson(json);
      expect(item.name, 'overview');
      expect(item.title, 'Overview');
      expect(item.path, 'overview');
      expect(item.pathWithParams, 'overview?mode=detail');
      expect(item.image, 'fa-eye');
      expect(item.imageType, 'icon');
      expect(item.menuInclude, isTrue);
      expect(item.active, isFalse);
      expect(item.disableLink, isTrue);
    });

    test('fromJson defaults for missing fields', () {
      final item = MenuSubscreenItem.fromJson(const <String, dynamic>{});
      expect(item.name, '');
      expect(item.pathWithParams, '');
      expect(item.image, '');
      expect(item.imageType, '');
      expect(item.menuInclude, isTrue);
      expect(item.disableLink, isFalse);
    });
  });

  // =========================================================================
  // Equatable / props — ensure equality works
  // =========================================================================
  group('Equatable behavior', () {
    test('WidgetNode equality', () {
      const a = WidgetNode(type: 'label', attributes: {'text': 'Hi'});
      const b = WidgetNode(type: 'label', attributes: {'text': 'Hi'});
      const c = WidgetNode(type: 'link', attributes: {'text': 'Hi'});
      expect(a, equals(b));
      expect(a, isNot(equals(c)));
    });

    test('FieldOption equality', () {
      const a = FieldOption(key: 'Y', text: 'Yes');
      const b = FieldOption(key: 'Y', text: 'Yes');
      const c = FieldOption(key: 'N', text: 'No');
      expect(a, equals(b));
      expect(a, isNot(equals(c)));
    });
  });
}
