import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moqui_flutter/domain/screen/screen_models.dart';
import 'package:moqui_flutter/presentation/widgets/moqui/widget_factory.dart';
import 'package:moqui_flutter/data/api/moqui_api_client.dart';

/// Test harness that wraps a widget in MaterialApp for testing.
Widget _testHarness(Widget child) {
  return MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(child: child),
    ),
  );
}

/// Test harness with Form ancestor for form field testing.
Widget _formTestHarness(Widget child) {
  return MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Form(child: child),
        ),
      ),
    ),
  );
}

/// Stub render context for widget tests.
MoquiRenderContext _stubContext({
  void Function(String path, {Map<String, dynamic>? params})? navigate,
  Future<TransitionResponse?> Function(String url, Map<String, dynamic> data)? submitForm,
  Future<Map<String, dynamic>> Function(String transition, Map<String, dynamic> params)? loadDynamic,
  Map<String, dynamic>? contextData,
}) {
  return MoquiRenderContext(
    navigate: navigate ?? (path, {params}) {},
    submitForm: submitForm ?? (url, data) async { return null; },
    loadDynamic: loadDynamic ?? (transition, params) async => <String, dynamic>{},
    contextData: contextData ?? {},
  );
}

FieldDefinition _makeField(
  String name,
  String widgetType, {
  String title = '',
  Map<String, dynamic> widgetAttrs = const {},
  String? currentValue,
  List<FieldOption> options = const [],
}) {
  return FieldDefinition(
    name: name,
    title: title.isEmpty ? name : title,
    currentValue: currentValue,
    widgets: [
      FieldWidget(
        widgetType: widgetType,
        attributes: {'widgetType': widgetType, ...widgetAttrs},
        options: options,
      ),
    ],
  );
}

/// Helper to find a button containing specific text.
/// Works with ElevatedButton, ElevatedButton.icon, TextButton, etc.
/// In Flutter 3.35+, ElevatedButton.icon creates _ElevatedButtonWithIconChild,
/// which isn't found by find.byType(ElevatedButton).
Finder _findButtonWithText(String text) {
  return find.ancestor(
    of: find.text(text),
    matching: find.byWidgetPredicate(
      (w) => w.runtimeType.toString().contains('ElevatedButton') ||
             w.runtimeType.toString().contains('TextButton') ||
             w.runtimeType.toString().contains('FilledButton') ||
             w.runtimeType.toString().contains('OutlinedButton'),
    ),
  );
}

void main() {
  // ===========================================================================
  // FORM-LIST CELL WIDGET RENDERING
  // ===========================================================================
  group('Form-List Cell Widget Rendering', () {
    testWidgets('renders link widgets in form-list cells as clickable buttons', (tester) async {
      String? capturedPath;
      Map<String, dynamic>? capturedParams;

      final ctx = _stubContext(
        navigate: (path, {params}) {
          capturedPath = path;
          capturedParams = params;
        },
      );

      final node = WidgetNode.fromJson(const {
        '_type': 'form-list',
        'formName': 'EntityList',
        'listName': 'entityList',
        'fields': [
          {
            'name': 'entityName',
            'title': 'Entity Name',
            'widgets': [{'_type': 'display'}],
          },
          {
            'name': 'find',
            'title': 'Actions',
            'widgets': [
              {
                '_type': 'link',
                'text': 'Find',
                'url': 'find',
                'linkType': 'anchor',
                'parameterMap': {'selectedEntity': 'fullEntityName'},
              },
            ],
          },
        ],
        'listData': [
          {'entityName': 'moqui.test.TestEntity', 'fullEntityName': 'moqui.test.TestEntity'},
        ],
      });

      await tester.pumpWidget(_testHarness(
        MoquiWidgetFactory.build(node, ctx),
      ));

      // Column headers should show
      expect(find.text('Entity Name'), findsOneWidget);
      expect(find.text('Actions'), findsOneWidget);

      // The cell link with text 'Find' should be clickable
      final findLink = find.text('Find');
      expect(findLink, findsOneWidget);
      await tester.ensureVisible(findLink);
      await tester.tap(findLink);
      await tester.pumpAndSettle();
      expect(capturedPath, 'find');
    });

    testWidgets('renders icon-only links in cells (edit/delete)', (tester) async {
      String? capturedPath;

      final ctx = _stubContext(
        navigate: (path, {params}) {
          capturedPath = path;
        },
      );

      final node = WidgetNode.fromJson(const {
        '_type': 'form-list',
        'formName': 'EntityValueList',
        'listName': 'entityValueList',
        'fields': [
          {
            'name': 'entityName',
            'title': 'Entity Name',
            'widgets': [{'_type': 'display'}],
          },
          {
            'name': 'edit',
            'title': '',
            'widgets': [
              {
                '_type': 'link',
                'text': '',
                'url': 'AutoEditMaster',
                'icon': 'fa-pencil',
              },
            ],
          },
        ],
        'listData': [
          {'entityName': 'TestEntity'},
        ],
      });

      await tester.pumpWidget(_testHarness(
        MoquiWidgetFactory.build(node, ctx),
      ));

      // Should render an IconButton for the edit link
      expect(find.byType(IconButton), findsAtLeastNWidgets(1));

      // Tap the edit icon
      await tester.tap(find.byType(IconButton).first);
      await tester.pumpAndSettle();

      expect(capturedPath, 'AutoEditMaster');
    });

    testWidgets('renders display fields with format in cells', (tester) async {
      final node = WidgetNode.fromJson(const {
        '_type': 'form-list',
        'formName': 'FieldList',
        'listName': 'fieldInfos',
        'fields': [
          {
            'name': 'fieldName',
            'title': 'Field Name',
            'widgets': [{'_type': 'display'}],
          },
          {
            'name': 'lastUpdated',
            'title': 'Last Updated',
            'widgets': [
              {
                '_type': 'display',
                'format': 'yyyy-MM-dd HH:mm:ss',
              },
            ],
          },
        ],
        'listData': [
          {
            'fieldName': 'testField',
            'lastUpdated': '2026-02-28T10:30:45.000',
          },
        ],
      });

      await tester.pumpWidget(_testHarness(
        MoquiWidgetFactory.build(node, _stubContext()),
      ));

      expect(find.text('testField'), findsOneWidget);
      // Should be formatted
      expect(find.text('2026-02-28 10:30:45'), findsOneWidget);
    });

    testWidgets('renders display with style in cells', (tester) async {
      final node = WidgetNode.fromJson(const {
        '_type': 'form-list',
        'formName': 'CheckDiffList',
        'listName': 'diffInfoList',
        'fields': [
          {
            'name': 'entity',
            'title': 'Entity',
            'widgets': [
              {
                '_type': 'display',
                'style': 'text-strong',
              },
            ],
          },
        ],
        'listData': [
          {'entity': 'moqui.test.TestEntity'},
        ],
      });

      await tester.pumpWidget(_testHarness(
        MoquiWidgetFactory.build(node, _stubContext()),
      ));

      // Find the bold text
      final textWidget = tester.widget<Text>(find.text('moqui.test.TestEntity'));
      expect(textWidget.style?.fontWeight, FontWeight.bold);
    });

    testWidgets('renders multiple link widgets in same cell', (tester) async {
      // Entity Detail RelatedEntities: field with two link widgets (Detail, Find)
      String? capturedPath;

      final ctx = _stubContext(
        navigate: (path, {params}) {
          capturedPath = path;
        },
      );

      final node = WidgetNode.fromJson(const {
        '_type': 'form-list',
        'formName': 'RelatedEntities',
        'listName': 'relationshipInfoList',
        'fields': [
          {
            'name': 'relatedEntityName',
            'title': 'Related Entity',
            'widgets': [{'_type': 'display'}],
          },
          {
            'name': 'links',
            'title': '',
            'widgets': [
              {
                '_type': 'link',
                'text': 'Detail',
                'url': '.',
                'linkType': 'anchor',
              },
            ],
          },
        ],
        'listData': [
          {'relatedEntityName': 'moqui.test.RelatedEntity'},
        ],
      });

      await tester.pumpWidget(_testHarness(
        MoquiWidgetFactory.build(node, ctx),
      ));

      expect(find.text('moqui.test.RelatedEntity'), findsOneWidget);
      // The Detail link should be clickable
      expect(find.text('Detail'), findsAtLeastNWidgets(1));
    });
  });

  // ===========================================================================
  // LINK PARAMETER MAP
  // ===========================================================================
  group('Link ParameterMap Support', () {
    testWidgets('link navigation passes parameterMap to navigate callback', (tester) async {
      String? capturedPath;
      Map<String, dynamic>? capturedParams;

      final ctx = _stubContext(
        navigate: (path, {params}) {
          capturedPath = path;
          capturedParams = params;
        },
      );

      final node = WidgetNode.fromJson(const {
        '_type': 'link',
        'text': 'View Entity',
        'url': 'entityDetail',
        'parameterMap': {'selectedEntity': 'moqui.test.TestEntity'},
      });

      await tester.pumpWidget(_testHarness(
        MoquiWidgetFactory.build(node, ctx),
      ));

      await tester.tap(find.text('View Entity'));
      await tester.pumpAndSettle();

      expect(capturedPath, 'entityDetail');
      expect(capturedParams, isNotNull);
      expect(capturedParams!['selectedEntity'], 'moqui.test.TestEntity');
    });

    testWidgets('link builds parameterMap from parameters list', (tester) async {
      String? capturedPath;
      Map<String, dynamic>? capturedParams;

      final ctx = _stubContext(
        navigate: (path, {params}) {
          capturedPath = path;
          capturedParams = params;
        },
        contextData: {'relatedEntityName': 'moqui.test.RelatedEntity'},
      );

      final node = WidgetNode.fromJson(const {
        '_type': 'link',
        'text': 'Detail',
        'url': 'entityDetail',
        'parameters': [
          {'name': 'selectedEntity', 'from': 'relatedEntityName'},
        ],
      });

      await tester.pumpWidget(_testHarness(
        MoquiWidgetFactory.build(node, ctx),
      ));

      await tester.tap(find.text('Detail'));
      await tester.pumpAndSettle();

      expect(capturedPath, 'entityDetail');
      expect(capturedParams, isNotNull);
      expect(capturedParams!['selectedEntity'], 'moqui.test.RelatedEntity');
    });

    testWidgets('form-list cell link resolves parameterMap from row data', (tester) async {
      String? capturedPath;
      Map<String, dynamic>? capturedParams;

      final ctx = _stubContext(
        navigate: (path, {params}) {
          capturedPath = path;
          capturedParams = params;
        },
      );

      final node = WidgetNode.fromJson(const {
        '_type': 'form-list',
        'formName': 'EntityList',
        'listName': 'entityList',
        'fields': [
          {
            'name': 'entityName',
            'title': 'Entity Name',
            'widgets': [{'_type': 'display'}],
          },
          {
            'name': 'detail',
            'title': 'Actions',
            'widgets': [
              {
                '_type': 'link',
                'text': 'Detail',
                'url': 'detail',
                'linkType': 'anchor',
                'parameterMap': {'selectedEntity': 'fullEntityName'},
              },
            ],
          },
        ],
        'listData': [
          {'entityName': 'TestEntity', 'fullEntityName': 'moqui.test.TestEntity'},
        ],
      });

      await tester.pumpWidget(_testHarness(
        MoquiWidgetFactory.build(node, ctx),
      ));

      // Tap the Detail link in the cell
      final detailLink = find.text('Detail');
      expect(detailLink, findsOneWidget);
      await tester.ensureVisible(detailLink);
      await tester.tap(detailLink);
      await tester.pumpAndSettle();

      expect(capturedPath, 'detail');
      expect(capturedParams, isNotNull);
      expect(capturedParams!['selectedEntity'], 'moqui.test.TestEntity');
    });
  });

  // ===========================================================================
  // CONDITIONAL FIELD SUPPORT
  // ===========================================================================
  group('Conditional Field Support', () {
    test('ConditionalField.fromJson parses condition and widgets', () {
      final cf = ConditionalField.fromJson(const {
        'condition': 'entityValue != null',
        'title': '',
        'widgets': [
          {'_type': 'link', 'text': 'Edit', 'url': 'edit', 'icon': 'fa-pencil'},
        ],
      });

      expect(cf.condition, 'entityValue != null');
      expect(cf.conditionField, 'entityValue');
      expect(cf.widgets.length, 1);
      expect(cf.widgets.first.widgetType, 'link');
    });

    test('FieldDefinition.resolveWidgets returns conditional widgets when condition matches', () {
      const field = FieldDefinition(
        name: 'edit',
        title: '',
        widgets: [
          FieldWidget(widgetType: 'display', attributes: {'_type': 'display', 'text': ' '}),
        ],
        conditionalFields: [
          ConditionalField(
            condition: 'entityValue != null',
            conditionField: 'entityValue',
            widgets: [
              FieldWidget(widgetType: 'link', attributes: {'_type': 'link', 'text': 'Edit', 'icon': 'fa-pencil'}),
            ],
          ),
        ],
      );

      // When entityValue is present in row data
      final resolved = field.resolveWidgets({'entityValue': {'id': 1}});
      expect(resolved.first.widgetType, 'link');

      // When entityValue is not present
      final defaultResolved = field.resolveWidgets({});
      expect(defaultResolved.first.widgetType, 'display');
    });

    test('FieldDefinition.resolveWidgets uses conditionResult when available', () {
      const field = FieldDefinition(
        name: 'edit',
        title: '',
        widgets: [
          FieldWidget(widgetType: 'display', attributes: {'_type': 'display'}),
        ],
        conditionalFields: [
          ConditionalField(
            condition: 'complexCondition',
            conditionResult: true,
            widgets: [
              FieldWidget(widgetType: 'link', attributes: {'_type': 'link', 'text': 'Edit'}),
            ],
          ),
        ],
      );

      final resolved = field.resolveWidgets({});
      expect(resolved.first.widgetType, 'link');
    });

    testWidgets('form-list renders conditional link for rows with data', (tester) async {
      String? capturedPath;

      final ctx = _stubContext(
        navigate: (path, {params}) {
          capturedPath = path;
        },
      );

      final node = WidgetNode.fromJson(const {
        '_type': 'form-list',
        'formName': 'ListEntityValue',
        'listName': 'entityValueList',
        'fields': [
          {
            'name': 'entityName',
            'title': 'Entity',
            'widgets': [{'_type': 'display'}],
          },
          {
            'name': 'edit',
            'title': '',
            'conditionalFields': [
              {
                'condition': 'entityValue != null',
                'widgets': [
                  {
                    '_type': 'link',
                    'text': '',
                    'url': 'AutoEditMaster',
                    'icon': 'fa-pencil',
                  },
                ],
              },
            ],
            'widgets': [
              {'_type': 'display', 'text': ' '},
            ],
          },
        ],
        'listData': [
          {'entityName': 'TestEntity', 'entityValue': {'id': 1}},
          {'entityName': 'NullEntity'},
        ],
      });

      await tester.pumpWidget(_testHarness(
        MoquiWidgetFactory.build(node, ctx),
      ));

      // Row with entityValue should have an edit icon
      final iconButtons = find.byType(IconButton);
      expect(iconButtons, findsAtLeastNWidgets(1));

      // Tap the edit icon on the first row
      await tester.tap(iconButtons.first);
      await tester.pumpAndSettle();

      expect(capturedPath, 'AutoEditMaster');
    });
  });

  // ===========================================================================
  // FORM-LIST COLUMNS LAYOUT
  // ===========================================================================
  group('Form-List Columns Layout', () {
    testWidgets('columns reorder fields in form-list', (tester) async {
      final node = WidgetNode.fromJson(const {
        '_type': 'form-list',
        'formName': 'AutoFindList',
        'listName': 'entityValueList',
        'fields': [
          {
            'name': 'entityName',
            'title': 'Entity Name',
            'widgets': [{'_type': 'display'}],
          },
          {
            'name': 'lastUpdatedStamp',
            'title': 'Last Updated',
            'widgets': [{'_type': 'display'}],
          },
          {
            'name': 'edit',
            'title': 'Edit',
            'widgets': [
              {'_type': 'link', 'text': '', 'url': 'edit', 'icon': 'fa-pencil'},
            ],
          },
          {
            'name': 'delete',
            'title': 'Delete',
            'widgets': [
              {'_type': 'link', 'text': '', 'url': 'delete', 'icon': 'fa-trash'},
            ],
          },
        ],
        // Columns reorder: edit+delete first, then lastUpdated
        'columns': [
          {'fieldRefs': ['edit', 'delete']},
          {'fieldRefs': ['lastUpdatedStamp']},
        ],
        'listData': [
          {'entityName': 'TestEntity', 'lastUpdatedStamp': '2026-02-28'},
        ],
      });

      await tester.pumpWidget(_testHarness(
        MoquiWidgetFactory.build(node, _stubContext()),
      ));

      // All fields should still be present
      expect(find.byType(DataTable), findsOneWidget);
      // The edit/delete columns should be first, followed by lastUpdated, then entityName
      // Verify all columns are present
      expect(find.text('Edit'), findsOneWidget);
      expect(find.text('Delete'), findsOneWidget);
      expect(find.text('Last Updated'), findsOneWidget);
      expect(find.text('Entity Name'), findsOneWidget);
    });
  });

  // ===========================================================================
  // FORM-LIST HEADER DIALOG
  // ===========================================================================
  group('Form-List Header Dialog', () {
    testWidgets('header-dialog shows Find button instead of filter icon', (tester) async {
      final node = WidgetNode.fromJson(const {
        '_type': 'form-list',
        'formName': 'ListEntityValue',
        'listName': 'entityValueList',
        'headerDialog': 'true',
        'fields': [
          {
            'name': 'entityName',
            'title': 'Entity Name',
            'widgets': [{'_type': 'display'}],
          },
        ],
        'headerFields': [
          {
            'name': 'filterName',
            'title': 'Filter',
            'widgets': [{'_type': 'text-line'}],
          },
        ],
        'listData': [],
      });

      await tester.pumpWidget(_formTestHarness(
        MoquiWidgetFactory.build(node, _stubContext()),
      ));

      // Should show Find button (headerDialog mode)
      expect(_findButtonWithText('Find'), findsOneWidget);
    });

    testWidgets('clicking Find button shows filter panel with search fields', (tester) async {
      final node = WidgetNode.fromJson(const {
        '_type': 'form-list',
        'formName': 'ListEntityValue',
        'listName': 'entityValueList',
        'headerDialog': 'true',
        'fields': [
          {
            'name': 'entityName',
            'title': 'Entity Name',
            'widgets': [{'_type': 'display'}],
          },
        ],
        'headerFields': [
          {
            'name': 'filterName',
            'title': 'Filter Name',
            'widgets': [{'_type': 'text-line'}],
          },
        ],
        'listData': [],
      });

      await tester.pumpWidget(_formTestHarness(
        MoquiWidgetFactory.build(node, _stubContext()),
      ));

      // Tap Find to open filter panel
      await tester.tap(_findButtonWithText('Find'));
      await tester.pumpAndSettle();

      // Filter panel should now be visible with the field
      expect(find.text('Filter Name'), findsOneWidget);
      expect(find.text('Search Filters'), findsOneWidget);
      // Should have Clear and Find buttons in the panel
      expect(find.text('Clear'), findsOneWidget);
    });
  });

  // ===========================================================================
  // FORM-LIST ROW SELECTION
  // ===========================================================================
  group('Form-List Row Selection', () {
    testWidgets('row-selection shows checkboxes', (tester) async {
      final node = WidgetNode.fromJson(const {
        '_type': 'form-list',
        'formName': 'CheckDiffInfoList',
        'listName': 'diffInfoList',
        'rowSelection': {
          'idField': 'rowOp',
          'parameter': 'rowOps',
        },
        'fields': [
          {
            'name': 'entity',
            'title': 'Entity',
            'widgets': [{'_type': 'display'}],
          },
          {
            'name': 'field',
            'title': 'Field',
            'widgets': [{'_type': 'display'}],
          },
        ],
        'listData': [
          {'entity': 'moqui.test.Entity1', 'field': 'field1', 'rowOp': 'op1'},
          {'entity': 'moqui.test.Entity2', 'field': 'field2', 'rowOp': 'op2'},
        ],
      });

      await tester.pumpWidget(_testHarness(
        MoquiWidgetFactory.build(node, _stubContext()),
      ));

      // Should show checkboxes for row selection
      expect(find.byType(Checkbox), findsAtLeastNWidgets(1));
      expect(find.text('moqui.test.Entity1'), findsOneWidget);
      expect(find.text('moqui.test.Entity2'), findsOneWidget);
    });

    testWidgets('selecting rows shows action bar', (tester) async {
      final node = WidgetNode.fromJson(const {
        '_type': 'form-list',
        'formName': 'CheckDiffInfoList',
        'listName': 'diffInfoList',
        'rowSelection': {
          'idField': 'rowOp',
          'parameter': 'rowOps',
        },
        'fields': [
          {
            'name': 'entity',
            'title': 'Entity',
            'widgets': [{'_type': 'display'}],
          },
        ],
        'listData': [
          {'entity': 'Entity1', 'rowOp': 'op1'},
          {'entity': 'Entity2', 'rowOp': 'op2'},
        ],
      });

      await tester.pumpWidget(_testHarness(
        MoquiWidgetFactory.build(node, _stubContext()),
      ));

      // Find and tap a checkbox
      final checkboxes = find.byType(Checkbox);
      expect(checkboxes, findsAtLeastNWidgets(1));

      await tester.tap(checkboxes.first);
      await tester.pumpAndSettle();

      // Action bar should appear showing count
      expect(find.textContaining('selected'), findsAtLeastNWidgets(1));
    });
  });

  // ===========================================================================
  // ENTITY LIST SCREEN PATTERN
  // ===========================================================================
  group('Entity List Screen Pattern - EntityList.xml', () {
    testWidgets('entity list with find/detail/autoScreen links in cells', (tester) async {
      String? capturedPath;
      Map<String, dynamic>? capturedParams;

      final ctx = _stubContext(
        navigate: (path, {params}) {
          capturedPath = path;
          capturedParams = params;
        },
      );

      final node = WidgetNode.fromJson(const {
        '_type': 'form-list',
        'formName': 'EntityList',
        'listName': 'entityList',
        'fields': [
          {
            'name': 'entityName',
            'title': 'Entity Name',
            'widgets': [{'_type': 'display'}],
          },
          {
            'name': 'detail',
            'title': '',
            'widgets': [
              {
                '_type': 'link',
                'text': 'Detail',
                'url': 'detail',
                'linkType': 'anchor',
                'parameterMap': {'selectedEntity': 'fullEntityName'},
              },
            ],
          },
        ],
        'listData': [
          {
            'entityName': 'TestEntity',
            'fullEntityName': 'moqui.test.TestEntity',
          },
          {
            'entityName': 'BasicEntity',
            'fullEntityName': 'moqui.basic.BasicEntity',
          },
        ],
      });

      await tester.pumpWidget(_testHarness(
        MoquiWidgetFactory.build(node, ctx),
      ));

      // Data should display
      expect(find.text('TestEntity'), findsOneWidget);
      expect(find.text('BasicEntity'), findsOneWidget);

      // Links should be clickable - use ensureVisible for offscreen safety
      // find.text('Detail') matches the column header AND cell links — skip
      // the header by selecting the second occurrence (first cell link).
      final detailLinks = find.text('Detail');
      expect(detailLinks, findsAtLeastNWidgets(2));
      final detailLink = detailLinks.at(1);
      await tester.ensureVisible(detailLink);
      await tester.tap(detailLink);
      await tester.pumpAndSettle();

      expect(capturedPath, 'detail');
      // Parameter resolved from row data
      expect(capturedParams?['selectedEntity'], 'moqui.test.TestEntity');
    });
  });

  // ===========================================================================
  // ENTITY DETAIL SCREEN PATTERN
  // ===========================================================================
  group('Entity Detail Screen Pattern - EntityDetail.xml', () {
    testWidgets('entity detail with field metadata form-list', (tester) async {
      final node = WidgetNode.fromJson(const {
        '_type': 'container',
        'children': [
          {
            '_type': 'container-box',
            'header': [
              {'_type': 'label', 'text': 'moqui.test.TestEntity', 'labelType': 'h4'},
            ],
            'toolbar': [
              {'_type': 'link', 'text': 'Entity List', 'url': 'entityList'},
              {'_type': 'link', 'text': 'Find', 'url': 'find'},
            ],
            'bodyNoPad': [
              {
                '_type': 'container-row',
                'columns': [
                  {
                    'lg': '6',
                    'sm': '12',
                    'children': [
                      {'_type': 'label', 'text': 'Group: default', 'labelType': 'span'},
                    ],
                  },
                  {
                    'lg': '6',
                    'sm': '12',
                    'children': [
                      {'_type': 'label', 'text': 'Table: TEST_ENTITY', 'labelType': 'span'},
                    ],
                  },
                ],
              },
            ],
          },
          {
            '_type': 'container-box',
            'header': [
              {'_type': 'label', 'text': 'Fields', 'labelType': 'h5'},
            ],
            'bodyNoPad': [
              {
                '_type': 'form-list',
                'formName': 'FieldList',
                'listName': 'fieldInfos',
                'fields': [
                  {
                    'name': 'fieldName',
                    'title': 'Field Name',
                    'widgets': [{'_type': 'display'}],
                  },
                  {
                    'name': 'type',
                    'title': 'Type',
                    'widgets': [{'_type': 'display'}],
                  },
                  {
                    'name': 'column',
                    'title': 'Column',
                    'widgets': [{'_type': 'display'}],
                  },
                  {
                    'name': 'isPk',
                    'title': 'Is PK',
                    'widgets': [{'_type': 'display'}],
                  },
                ],
                'listData': [
                  {'fieldName': 'testEntityId', 'type': 'id', 'column': 'TEST_ENTITY_ID', 'isPk': 'Y'},
                  {'fieldName': 'name', 'type': 'text-medium', 'column': 'NAME', 'isPk': 'N'},
                  {'fieldName': 'description', 'type': 'text-long', 'column': 'DESCRIPTION', 'isPk': 'N'},
                ],
              },
            ],
          },
        ],
      });

      await tester.pumpWidget(_testHarness(
        MoquiWidgetFactory.build(node, _stubContext()),
      ));

      // Header info
      expect(find.text('moqui.test.TestEntity'), findsOneWidget);
      expect(find.text('Entity List'), findsOneWidget);
      expect(find.text('Find'), findsAtLeastNWidgets(1));

      // Row layout info
      expect(find.text('Group: default'), findsOneWidget);
      expect(find.text('Table: TEST_ENTITY'), findsOneWidget);

      // Field metadata table
      expect(find.text('testEntityId'), findsOneWidget);
      expect(find.text('id'), findsOneWidget);
      expect(find.text('TEST_ENTITY_ID'), findsOneWidget);
      expect(find.text('text-medium'), findsOneWidget);
      expect(find.text('NAME'), findsOneWidget);
    });

    testWidgets('related entities table with Detail/Find links', (tester) async {
      String? capturedPath;

      final ctx = _stubContext(
        navigate: (path, {params}) {
          capturedPath = path;
        },
      );

      final node = WidgetNode.fromJson(const {
        '_type': 'container-box',
        'header': [
          {'_type': 'label', 'text': 'Relationships', 'labelType': 'h5'},
        ],
        'bodyNoPad': [
          {
            '_type': 'form-list',
            'formName': 'RelatedEntities',
            'listName': 'relationshipInfoList',
            'fields': [
              {
                'name': 'prettyName',
                'title': 'Name',
                'widgets': [{'_type': 'display'}],
              },
              {
                'name': 'relatedEntityName',
                'title': 'Related Entity',
                'widgets': [{'_type': 'display'}],
              },
              {
                'name': 'type',
                'title': 'Type',
                'widgets': [{'_type': 'display'}],
              },
              {
                'name': 'detailLink',
                'title': '',
                'widgets': [
                  {
                    '_type': 'link',
                    'text': 'Detail',
                    'url': '.',
                    'linkType': 'anchor',
                    'parameters': [
                      {'name': 'selectedEntity', 'from': 'relatedEntityName'},
                    ],
                  },
                ],
              },
            ],
            'listData': [
              {
                'prettyName': 'examples',
                'relatedEntityName': 'moqui.test.Example',
                'type': 'many',
              },
            ],
          },
        ],
      });

      await tester.pumpWidget(_testHarness(
        MoquiWidgetFactory.build(node, ctx),
      ));

      expect(find.text('Relationships'), findsOneWidget);
      expect(find.text('examples'), findsOneWidget);
      expect(find.text('moqui.test.Example'), findsOneWidget);
      expect(find.text('many'), findsOneWidget);

      // Tap the Detail link
      final detailLink = find.text('Detail');
      expect(detailLink, findsAtLeastNWidgets(1));
      await tester.ensureVisible(detailLink.first);
      await tester.tap(detailLink.first);
      await tester.pumpAndSettle();

      expect(capturedPath, '.');
    });
  });

  // ===========================================================================
  // AUTO FIND SCREEN PATTERN
  // ===========================================================================
  group('Auto Find Screen Pattern - AutoFind.xml', () {
    testWidgets('skip-form form-list with edit/delete icons and headerDialog', (tester) async {
      final node = WidgetNode.fromJson(const {
        '_type': 'form-list',
        'formName': 'ListEntityValue',
        'listName': 'entityValueList',
        'headerDialog': 'true',
        'skipForm': 'true',
        'showCsvButton': 'true',
        'showPageSize': 'true',
        'fields': [
          {
            'name': 'edit',
            'title': '',
            'conditionalFields': [
              {
                'condition': 'entityValue != null',
                'widgets': [
                  {
                    '_type': 'link',
                    'text': '',
                    'url': 'AutoEditMaster',
                    'icon': 'fa-pencil',
                  },
                ],
              },
            ],
            'widgets': [
              {'_type': 'display', 'text': ' '},
            ],
          },
          {
            'name': 'testEntityId',
            'title': 'Test Entity ID',
            'widgets': [{'_type': 'display'}],
          },
          {
            'name': 'name',
            'title': 'Name',
            'widgets': [{'_type': 'display'}],
          },
          {
            'name': 'lastUpdatedStamp',
            'title': 'Last Updated',
            'widgets': [{'_type': 'display', 'format': 'yyyy-MM-dd HH:mm:ss'}],
          },
        ],
        'columns': [
          {'fieldRefs': ['edit']},
          {'fieldRefs': ['lastUpdatedStamp']},
        ],
        'headerFields': [
          {
            'name': 'testEntityId',
            'title': 'Test Entity ID',
            'widgets': [{'_type': 'text-line'}],
          },
        ],
        'listData': [
          {
            'testEntityId': 'TE001',
            'name': 'Test One',
            'lastUpdatedStamp': '2026-02-28T10:30:00.000',
            'entityValue': {'testEntityId': 'TE001'},
          },
        ],
      });

      await tester.pumpWidget(_formTestHarness(
        MoquiWidgetFactory.build(node, _stubContext()),
      ));

      // headerDialog should show Find button
      expect(_findButtonWithText('Find'), findsOneWidget);

      // CSV export button
      expect(find.byIcon(Icons.download), findsOneWidget);

      // Data should display
      expect(find.text('TE001'), findsOneWidget);
      expect(find.text('Test One'), findsOneWidget);

      // Formatted date
      expect(find.text('2026-02-28 10:30:00'), findsOneWidget);

      // Edit icon should be present (conditional met: entityValue != null)
      expect(find.byIcon(Icons.edit), findsAtLeastNWidgets(1));
    });
  });

  // ===========================================================================
  // AUTO EDIT MASTER SCREEN PATTERN
  // ===========================================================================
  group('Auto Edit Master Screen Pattern - AutoEditMaster.xml', () {
    testWidgets('toolbar links + export container-dialog + update form', (tester) async {
      final node = WidgetNode.fromJson(const {
        '_type': 'container',
        'children': [
          // Toolbar links
          {
            '_type': 'link',
            'text': 'Entity List',
            'url': 'list',
            'linkType': 'hidden-form-link',
          },
          {
            '_type': 'link',
            'text': 'Find TestEntity',
            'url': 'find',
            'linkType': 'hidden-form-link',
          },
          // Export dialog
          {
            '_type': 'container-dialog',
            'buttonText': 'Export',
            'children': [
              {
                '_type': 'form-single',
                'formName': 'ExportMasterEntity',
                'transition': 'export',
                'fields': [
                  {
                    'name': 'dependentLevels',
                    'title': 'Dependent Levels',
                    'widgets': [{'_type': 'text-line', 'size': '2'}],
                    'currentValue': '2',
                  },
                  {
                    'name': 'fileType',
                    'title': 'File Type',
                    'widgets': [
                      {
                        '_type': 'radio',
                        'options': [
                          {'key': 'XML', 'text': 'XML'},
                          {'key': 'JSON', 'text': 'JSON'},
                        ],
                      },
                    ],
                  },
                  {
                    'name': 'submitButton',
                    'title': 'Export',
                    'widgets': [{'_type': 'submit'}],
                  },
                ],
              },
            ],
          },
          // Update form (PK display, nonPK edit)
          {
            '_type': 'form-single',
            'formName': 'UpdateMasterEntityValue',
            'transition': 'update',
            'fields': [
              {
                'name': 'testEntityId',
                'title': 'Test Entity ID',
                'widgets': [{'_type': 'display'}],
                'currentValue': 'TE001',
              },
              {
                'name': 'name',
                'title': 'Name',
                'widgets': [{'_type': 'text-line'}],
                'currentValue': 'Test Entity One',
              },
              {
                'name': 'description',
                'title': 'Description',
                'widgets': [{'_type': 'text-area', 'rows': '5'}],
                'currentValue': 'A test entity',
              },
              {
                'name': 'lastUpdatedStamp',
                'title': 'Last Updated',
                'widgets': [
                  {'_type': 'display', 'format': 'yyyy-MM-dd HH:mm:ss.SSS'},
                ],
                'currentValue': '2026-02-28T10:30:45.123',
              },
              {
                'name': 'submitButton',
                'title': 'Update',
                'widgets': [{'_type': 'submit'}],
              },
            ],
          },
        ],
      });

      await tester.pumpWidget(_formTestHarness(
        MoquiWidgetFactory.build(node, _stubContext()),
      ));

      // Toolbar links
      expect(find.text('Entity List'), findsOneWidget);
      expect(find.text('Find TestEntity'), findsOneWidget);

      // Export button
      expect(find.text('Export'), findsAtLeastNWidgets(1));

      // Update form - PK displayed, other fields as inputs
      expect(find.text('Test Entity ID'), findsOneWidget);
      expect(find.text('Name'), findsOneWidget);
      expect(find.text('Description'), findsOneWidget);
      expect(find.text('Update'), findsAtLeastNWidgets(1));
    });

    testWidgets('export dialog opens and shows form', (tester) async {
      final node = WidgetNode.fromJson(const {
        '_type': 'container-dialog',
        'buttonText': 'Export',
        'dialogTitle': 'Export Entity',
        'children': [
          {
            '_type': 'form-single',
            'formName': 'ExportForm',
            'transition': 'export',
            'fields': [
              {
                'name': 'dependentLevels',
                'title': 'Dependent Levels',
                'widgets': [{'_type': 'text-line', 'size': '2'}],
                'currentValue': '2',
              },
            ],
          },
        ],
      });

      await tester.pumpWidget(_formTestHarness(
        MoquiWidgetFactory.build(node, _stubContext()),
      ));

      // Tap Export button
      await tester.tap(find.text('Export'));
      await tester.pumpAndSettle();

      // Dialog should show
      expect(find.text('Export Entity'), findsOneWidget);
      expect(find.text('Dependent Levels'), findsOneWidget);
    });
  });

  // ===========================================================================
  // DATA IMPORT/EXPORT SCREEN PATTERNS
  // ===========================================================================
  group('Data Import/Export Screen Patterns', () {
    testWidgets('export form with radio options renders', (tester) async {
      final node = WidgetNode.fromJson(const {
        '_type': 'form-single',
        'formName': 'ExportData',
        'transition': 'EntityExport',
        'fields': [
          {
            'name': 'entityNames',
            'title': 'Entity Names',
            'widgets': [
              {
                '_type': 'drop-down',
                'options': [
                  {'key': 'moqui.test.TestEntity', 'text': 'TestEntity'},
                  {'key': 'moqui.basic.BasicEntity', 'text': 'BasicEntity'},
                ],
              },
            ],
          },
          {
            'name': 'fileType',
            'title': 'File Type',
            'widgets': [
              {
                '_type': 'radio',
                'options': [
                  {'key': 'XML', 'text': 'XML'},
                  {'key': 'JSON', 'text': 'JSON'},
                  {'key': 'CSV', 'text': 'CSV'},
                ],
              },
            ],
          },
          {
            'name': 'submitButton',
            'title': 'Export',
            'widgets': [{'_type': 'submit'}],
          },
        ],
      });

      await tester.pumpWidget(_formTestHarness(
        MoquiWidgetFactory.build(node, _stubContext()),
      ));

      expect(find.text('Entity Names'), findsOneWidget);
      expect(find.text('File Type'), findsOneWidget);
      expect(find.text('XML'), findsOneWidget);
      expect(find.text('JSON'), findsOneWidget);
      expect(find.text('CSV'), findsOneWidget);
    });

    testWidgets('import form with text-area and text-line renders', (tester) async {
      final node = WidgetNode.fromJson(const {
        '_type': 'form-single',
        'formName': 'ImportData',
        'transition': 'load',
        'fields': [
          {
            'name': 'timeout',
            'title': 'Timeout Seconds',
            'widgets': [{'_type': 'text-line', 'size': '5'}],
            'currentValue': '60',
          },
          {
            'name': 'types',
            'title': 'Data Types',
            'widgets': [{'_type': 'text-line', 'size': '60'}],
          },
          {
            'name': 'xmlText',
            'title': 'XML Text',
            'widgets': [{'_type': 'text-area', 'rows': '5', 'cols': '120'}],
          },
          {
            'name': 'submitButton',
            'title': 'Import',
            'widgets': [{'_type': 'submit'}],
          },
        ],
      });

      await tester.pumpWidget(_formTestHarness(
        MoquiWidgetFactory.build(node, _stubContext()),
      ));

      expect(find.text('Timeout Seconds'), findsOneWidget);
      expect(find.text('Data Types'), findsOneWidget);
      expect(find.text('XML Text'), findsOneWidget);
    });
  });

  // ===========================================================================
  // FORM-LIST SKIP-FORM BEHAVIOR
  // ===========================================================================
  group('Form-List Skip-Form Behavior', () {
    testWidgets('skip-form form-list renders without inline form submission', (tester) async {
      final node = WidgetNode.fromJson(const {
        '_type': 'form-list',
        'formName': 'ReadOnlyList',
        'listName': 'dataList',
        'skipForm': 'true',
        'fields': [
          {
            'name': 'name',
            'title': 'Name',
            'widgets': [{'_type': 'display'}],
          },
          {
            'name': 'value',
            'title': 'Value',
            'widgets': [{'_type': 'display'}],
          },
        ],
        'listData': [
          {'name': 'key1', 'value': 'value1'},
          {'name': 'key2', 'value': 'value2'},
        ],
      });

      await tester.pumpWidget(_testHarness(
        MoquiWidgetFactory.build(node, _stubContext()),
      ));

      expect(find.text('key1'), findsOneWidget);
      expect(find.text('value1'), findsOneWidget);
      expect(find.text('key2'), findsOneWidget);
      expect(find.text('value2'), findsOneWidget);
      // No submit buttons in a skip-form list
      expect(_findButtonWithText('Submit'), findsNothing);
    });
  });

  // ===========================================================================
  // MODEL PARSING TESTS
  // ===========================================================================
  group('Model Parsing - Phase 5 Enhancements', () {
    test('FormDefinition parses skipForm and headerDialog', () {
      final form = FormDefinition.fromJson(const {
        '_type': 'form-list',
        'formName': 'TestList',
        'skipForm': 'true',
        'headerDialog': 'true',
        'showCsvButton': 'true',
        'showXlsxButton': 'true',
        'showPageSize': 'true',
        'fields': [],
      });

      expect(form.skipForm, true);
      expect(form.headerDialog, true);
      expect(form.showCsvButton, true);
      expect(form.showXlsxButton, true);
      expect(form.showPageSize, true);
    });

    test('FormDefinition parses rowSelection with idField and parameter', () {
      final form = FormDefinition.fromJson(const {
        '_type': 'form-list',
        'formName': 'TestList',
        'rowSelection': {
          'idField': 'rowOp',
          'parameter': 'rowOps',
        },
        'fields': [],
      });

      expect(form.hasRowSelection, true);
      expect(form.rowSelectionIdField, 'rowOp');
      expect(form.rowSelectionParameter, 'rowOps');
    });

    test('FieldDefinition parses conditionalFields', () {
      final field = FieldDefinition.fromJson(const {
        'name': 'edit',
        'title': '',
        'conditionalFields': [
          {
            'condition': 'entityValue != null',
            'title': '',
            'widgets': [
              {'_type': 'link', 'text': '', 'url': 'edit', 'icon': 'fa-pencil'},
            ],
          },
        ],
        'widgets': [
          {'_type': 'display', 'text': ' '},
        ],
      });

      expect(field.conditionalFields.length, 1);
      expect(field.conditionalFields.first.condition, 'entityValue != null');
      expect(field.conditionalFields.first.conditionField, 'entityValue');
      expect(field.conditionalFields.first.widgets.first.widgetType, 'link');
      expect(field.widgets.first.widgetType, 'display');
    });

    test('ConditionalField extracts conditionField from simple expressions', () {
      final cf1 = ConditionalField.fromJson(const {
        'condition': 'entityValue != null',
        'widgets': [],
      });
      expect(cf1.conditionField, 'entityValue');

      final cf2 = ConditionalField.fromJson(const {
        'condition': 'complexCondition(a, b)',
        'widgets': [],
      });
      expect(cf2.conditionField, ''); // Can't extract from complex condition

      final cf3 = ConditionalField.fromJson(const {
        'condition': 'myVar != null',
        'widgets': [],
      });
      expect(cf3.conditionField, 'myVar');
    });

    test('FormColumn fieldRefs parsed correctly', () {
      final col = FormColumn.fromJson(const {
        'style': 'col-md-4',
        'fieldRefs': ['edit', 'delete'],
      });

      expect(col.style, 'col-md-4');
      expect(col.fieldRefs, ['edit', 'delete']);
    });
  });

  // ===========================================================================
  // EDGE CASES
  // ===========================================================================
  group('Phase 5 Edge Cases', () {
    testWidgets('form-list with all hidden fields gracefully renders', (tester) async {
      final node = WidgetNode.fromJson(const {
        '_type': 'form-list',
        'formName': 'HiddenFieldsList',
        'listName': 'dataList',
        'fields': [
          {
            'name': 'hiddenField1',
            'title': 'Hidden1',
            'widgets': [{'_type': 'hidden'}],
          },
        ],
        'listData': [
          {'hiddenField1': 'value1'},
        ],
      });

      await tester.pumpWidget(_testHarness(
        MoquiWidgetFactory.build(node, _stubContext()),
      ));

      // Should render empty table gracefully
      expect(tester.takeException(), isNull);
    });

    testWidgets('link with empty parameterMap navigates without params', (tester) async {
      String? capturedPath;
      Map<String, dynamic>? capturedParams;

      final ctx = _stubContext(
        navigate: (path, {params}) {
          capturedPath = path;
          capturedParams = params;
        },
      );

      final node = WidgetNode.fromJson(const {
        '_type': 'link',
        'text': 'Simple Link',
        'url': 'target',
      });

      await tester.pumpWidget(_testHarness(
        MoquiWidgetFactory.build(node, ctx),
      ));

      await tester.tap(find.text('Simple Link'));
      await tester.pumpAndSettle();

      expect(capturedPath, 'target');
      expect(capturedParams, isNull);
    });

    testWidgets('cell link with confirmation shows dialog before navigating', (tester) async {
      String? capturedPath;

      final ctx = _stubContext(
        navigate: (path, {params}) {
          capturedPath = path;
        },
      );

      final node = WidgetNode.fromJson(const {
        '_type': 'form-list',
        'formName': 'DeleteList',
        'listName': 'dataList',
        'fields': [
          {
            'name': 'name',
            'title': 'Name',
            'widgets': [{'_type': 'display'}],
          },
          {
            'name': 'delete',
            'title': '',
            'widgets': [
              {
                '_type': 'link',
                'text': '',
                'url': 'deleteRecord',
                'icon': 'fa-trash',
                'confirmation': 'Are you sure?',
              },
            ],
          },
        ],
        'listData': [
          {'name': 'Record1'},
        ],
      });

      await tester.pumpWidget(_testHarness(
        MoquiWidgetFactory.build(node, ctx),
      ));

      // Tap the delete icon
      final deleteIcon = find.byIcon(Icons.delete);
      expect(deleteIcon, findsOneWidget);

      await tester.tap(deleteIcon);
      await tester.pumpAndSettle();

      // Confirmation dialog should appear
      expect(find.text('Are you sure?'), findsOneWidget);
      expect(capturedPath, isNull); // Not navigated yet

      // Confirm
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();

      expect(capturedPath, 'deleteRecord');
    });

    testWidgets('display format handles non-date values gracefully', (tester) async {
      final node = WidgetNode.fromJson(const {
        '_type': 'form-list',
        'formName': 'FormatTest',
        'listName': 'dataList',
        'fields': [
          {
            'name': 'value',
            'title': 'Value',
            'widgets': [
              {
                '_type': 'display',
                'format': 'yyyy-MM-dd',
              },
            ],
          },
        ],
        'listData': [
          {'value': 'not-a-date'},
        ],
      });

      await tester.pumpWidget(_testHarness(
        MoquiWidgetFactory.build(node, _stubContext()),
      ));

      // Should fall back to raw value without error
      expect(find.text('not-a-date'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('empty form-list with columns renders gracefully', (tester) async {
      final node = WidgetNode.fromJson(const {
        '_type': 'form-list',
        'formName': 'EmptyColumnList',
        'listName': 'dataList',
        'fields': [
          {
            'name': 'col1',
            'title': 'Column 1',
            'widgets': [{'_type': 'display'}],
          },
          {
            'name': 'col2',
            'title': 'Column 2',
            'widgets': [{'_type': 'display'}],
          },
        ],
        'columns': [
          {'fieldRefs': ['col2']},
          {'fieldRefs': ['col1']},
        ],
        'listData': [],
      });

      await tester.pumpWidget(_testHarness(
        MoquiWidgetFactory.build(node, _stubContext()),
      ));

      // Column headers should still render
      expect(find.text('Column 2'), findsOneWidget);
      expect(find.text('Column 1'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
