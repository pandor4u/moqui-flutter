import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moqui_flutter/domain/screen/screen_models.dart';
import 'package:moqui_flutter/presentation/widgets/moqui/widget_factory.dart';
import 'package:moqui_flutter/data/api/moqui_api_client.dart';
import 'package:moqui_flutter/presentation/widgets/fields/field_widget_factory.dart';

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

void main() {
  // ===========================================================================
  // SERVICE REFERENCE SCREEN PATTERNS
  // ===========================================================================
  group('Service Reference Screen Patterns', () {
    testWidgets('renders container-row with row-col layout', (tester) async {
      final node = WidgetNode.fromJson(const {
        '_type': 'container-row',
        'columns': [
          {
            'lg': '6',
            'sm': '12',
            'children': [
              {'_type': 'label', 'text': 'Column 1 Content', 'labelType': 'span'},
            ],
          },
          {
            'lg': '6',
            'sm': '12',
            'children': [
              {'_type': 'label', 'text': 'Column 2 Content', 'labelType': 'span'},
            ],
          },
        ],
      });

      await tester.pumpWidget(_testHarness(
        MoquiWidgetFactory.build(node, _stubContext()),
      ));

      expect(find.text('Column 1 Content'), findsOneWidget);
      expect(find.text('Column 2 Content'), findsOneWidget);
    });

    testWidgets('form-list renders data rows as text', (tester) async {
      // NOTE: Current form-list implementation renders row data as text only
      // Link widgets in field definitions are not rendered in cells
      final node = WidgetNode.fromJson(const {
        '_type': 'form-list',
        'formName': 'ServiceList',
        'listName': 'filteredServiceNames',
        'fields': [
          {
            'name': 'serviceName',
            'title': 'Service Name',
            'widgets': [{'_type': 'display'}],
          },
        ],
        'listData': [
          {'serviceName': 'test.Service#one'},
          {'serviceName': 'test.Service#two'},
        ],
      });

      await tester.pumpWidget(_testHarness(
        MoquiWidgetFactory.build(node, _stubContext()),
      ));

      // Current implementation shows data values as text
      expect(find.text('test.Service#one'), findsOneWidget);
      expect(find.text('test.Service#two'), findsOneWidget);
    });
  });

  // ===========================================================================
  // SERVICE DETAIL SCREEN PATTERNS
  // ===========================================================================
  group('Service Detail Screen Patterns', () {
    testWidgets('container-box with header, toolbar, and body-nopad', (tester) async {
      final node = WidgetNode.fromJson(const {
        '_type': 'container-box',
        'header': [
          {'_type': 'label', 'text': 'org.moqui.test#ServiceName', 'labelType': 'h5'},
        ],
        'toolbar': [
          {'_type': 'link', 'text': 'Service List', 'url': 'serviceReference'},
          {'_type': 'link', 'text': 'Run Service', 'url': 'serviceRun'},
        ],
        'bodyNoPad': [
          {'_type': 'label', 'text': 'Service Details Content', 'labelType': 'p'},
        ],
      });

      await tester.pumpWidget(_testHarness(
        MoquiWidgetFactory.build(node, _stubContext()),
      ));

      expect(find.text('org.moqui.test#ServiceName'), findsOneWidget);
      expect(find.text('Service List'), findsOneWidget);
      expect(find.text('Run Service'), findsOneWidget);
      expect(find.text('Service Details Content'), findsOneWidget);
    });

    testWidgets('nested container-box for parameters', (tester) async {
      final node = WidgetNode.fromJson(const {
        '_type': 'container',
        'children': [
          {
            '_type': 'container-box',
            'header': [
              {'_type': 'label', 'text': 'In Parameters', 'labelType': 'h5'},
            ],
            'bodyNoPad': [
              {'_type': 'label', 'text': 'Parameter List Here', 'labelType': 'span'},
            ],
          },
          {
            '_type': 'container-box',
            'header': [
              {'_type': 'label', 'text': 'Out Parameters', 'labelType': 'h5'},
            ],
            'bodyNoPad': [
              {'_type': 'label', 'text': 'Output List Here', 'labelType': 'span'},
            ],
          },
        ],
      });

      await tester.pumpWidget(_testHarness(
        MoquiWidgetFactory.build(node, _stubContext()),
      ));

      expect(find.text('In Parameters'), findsOneWidget);
      expect(find.text('Out Parameters'), findsOneWidget);
      expect(find.text('Parameter List Here'), findsOneWidget);
      expect(find.text('Output List Here'), findsOneWidget);
    });

    testWidgets('section-iterate renders server-expanded children', (tester) async {
      // Server expands section-iterate by rendering template for each item
      // and sends expanded 'children' instead of widgetTemplate+listData
      final node = WidgetNode.fromJson(const {
        '_type': 'section-iterate',
        'name': 'Secas',
        'list': 'secaList',
        'entry': 'seca',
        // Server-expanded: children already contain rendered items
        'children': [
          {'_type': 'label', 'text': 'Rule 1: Check permissions', 'labelType': 'span'},
          {'_type': 'label', 'text': 'Rule 2: Log activity', 'labelType': 'span'},
        ],
      });

      await tester.pumpWidget(_testHarness(
        MoquiWidgetFactory.build(node, _stubContext()),
      ));

      // section-iterate renders each pre-expanded child
      expect(find.text('Rule 1: Check permissions'), findsOneWidget);
      expect(find.text('Rule 2: Log activity'), findsOneWidget);
    });
  });

  // ===========================================================================
  // SERVICE RUN SCREEN PATTERNS
  // ===========================================================================
  group('Service Run Screen Patterns', () {
    testWidgets('section shows content when widgets present (server-evaluated true)', (tester) async {
      // Section implementation: server evaluates condition and populates 'widgets' if true
      // Client just checks if widgets list is present and non-empty
      final node = WidgetNode.fromJson(const {
        '_type': 'section',
        'name': 'ServiceParametersSection',
        // Server provided widgets because condition passed
        'widgets': [
          {'_type': 'label', 'text': 'Run Service: test.Service#name', 'labelType': 'h3'},
        ],
      });

      await tester.pumpWidget(_testHarness(
        MoquiWidgetFactory.build(node, _stubContext()),
      ));

      expect(find.text('Run Service: test.Service#name'), findsOneWidget);
    });

    testWidgets('section hides content when widgets empty (server-evaluated false)', (tester) async {
      // Section with no widgets means condition failed server-side
      final node = WidgetNode.fromJson(const {
        '_type': 'section',
        'name': 'ServiceResultsSection',
        // No 'widgets' key means condition failed
      });

      await tester.pumpWidget(_testHarness(
        MoquiWidgetFactory.build(node, _stubContext()),
      ));

      // Should render nothing (SizedBox.shrink)
      expect(find.text('Section'), findsNothing);
    });

    testWidgets('section shows failWidgets when condition false', (tester) async {
      // When condition is false, server populates failWidgets instead of widgets
      final node = WidgetNode.fromJson(const {
        '_type': 'section',
        'name': 'OptionalSection',
        'failWidgets': [
          {'_type': 'label', 'text': 'Feature not available', 'labelType': 'span'},
        ],
      });

      await tester.pumpWidget(_testHarness(
        MoquiWidgetFactory.build(node, _stubContext()),
      ));

      expect(find.text('Feature not available'), findsOneWidget);
    });

    testWidgets('label with type h3 renders headline style', (tester) async {
      final node = WidgetNode.fromJson(const {
        '_type': 'label',
        'text': 'Run Service: org.moqui.test#createThing',
        'labelType': 'h3',
      });

      await tester.pumpWidget(_testHarness(
        MoquiWidgetFactory.build(node, _stubContext()),
      ));

      expect(find.text('Run Service: org.moqui.test#createThing'), findsOneWidget);
    });

    testWidgets('form-single renders visible fields only', (tester) async {
      final node = WidgetNode.fromJson(const {
        '_type': 'form-single',
        'formName': 'ServiceParameters',
        'transition': 'run',
        'fields': [
          {
            'name': 'serviceName',
            'title': 'Service Name',
            'hidden': true, // Hidden field
            'widgets': [
              {'_type': 'hidden'},
            ],
          },
          {
            'name': 'inputParam',
            'title': 'Input Parameter',
            'widgets': [
              {'_type': 'text-line'},
            ],
          },
        ],
      });

      await tester.pumpWidget(_formTestHarness(
        MoquiWidgetFactory.build(node, _stubContext()),
      ));

      // Hidden field should not be visible
      expect(find.text('Service Name'), findsNothing);
      // Visible fields should display
      expect(find.text('Input Parameter'), findsOneWidget);
    });
  });

  // ===========================================================================
  // ENTITY LIST SCREEN PATTERNS
  // ===========================================================================
  group('Entity List Screen Patterns', () {
    testWidgets('multiple top-level link widgets with confirmation', (tester) async {
      final node = WidgetNode.fromJson(const {
        '_type': 'container',
        'children': [
          {
            '_type': 'link',
            'text': 'Check/Update All Tables',
            'url': 'checkTables',
            'confirmation': 'Are you sure you want to check all tables?',
          },
          {
            '_type': 'link',
            'text': 'Drop FKs',
            'url': 'dropForeignKeys',
            'confirmation': 'Really drop all known foreign keys?',
          },
          {
            '_type': 'link',
            'text': 'Create FKs',
            'url': 'createForeignKeys',
          },
        ],
      });

      await tester.pumpWidget(_testHarness(
        MoquiWidgetFactory.build(node, _stubContext()),
      ));

      expect(find.text('Check/Update All Tables'), findsOneWidget);
      expect(find.text('Drop FKs'), findsOneWidget);
      expect(find.text('Create FKs'), findsOneWidget);

      // Tap link with confirmation
      await tester.tap(find.text('Drop FKs'));
      await tester.pumpAndSettle();

      // Should show confirmation dialog
      expect(find.text('Really drop all known foreign keys?'), findsOneWidget);
    });

    testWidgets('container-dialog shows button and opens on tap', (tester) async {
      final node = WidgetNode.fromJson(const {
        '_type': 'container-dialog',
        'id': 'LiquibaseInitDialog',
        'buttonText': 'Liquibase Init XML',
        // NOT setting openDialog=true so it doesn't auto-open
        'children': [
          {'_type': 'label', 'text': 'Dialog Content Here', 'labelType': 'p'},
        ],
      });

      await tester.pumpWidget(_testHarness(
        MoquiWidgetFactory.build(node, _stubContext()),
      ));

      // Button should be visible
      expect(find.text('Liquibase Init XML'), findsOneWidget);

      // Tap to open dialog
      await tester.tap(find.text('Liquibase Init XML'));
      await tester.pumpAndSettle();

      expect(find.text('Dialog Content Here'), findsOneWidget);
    });

    testWidgets('form-single with drop-down renders field label', (tester) async {
      final node = WidgetNode.fromJson(const {
        '_type': 'form-single',
        'formName': 'FilterForm',
        'transition': '.',
        'fields': [
          {
            'name': 'filterRegexp',
            'title': 'Filter',
            'widgets': [
              {'_type': 'text-line', 'size': '30'},
            ],
          },
          {
            'name': 'viewOption',
            'title': 'View Option',
            'widgets': [
              {
                '_type': 'drop-down',
                'options': [
                  {'key': 'all', 'text': 'All Entities'},
                  {'key': 'master', 'text': 'Master Entities'},
                ],
              },
            ],
          },
        ],
      });

      await tester.pumpWidget(_formTestHarness(
        MoquiWidgetFactory.build(node, _stubContext()),
      ));

      expect(find.text('Filter'), findsOneWidget);
      expect(find.text('View Option'), findsOneWidget);
    });
  });

  // ===========================================================================
  // SQL RUNNER SCREEN PATTERNS
  // ===========================================================================
  group('SQL Runner Screen Patterns', () {
    testWidgets('text-area field renders', (tester) async {
      final field = _makeField(
        'sql',
        'text-area',
        title: 'SQL Statement',
        widgetAttrs: {'cols': '120', 'rows': '8'},
      );

      await tester.pumpWidget(_formTestHarness(
        FieldWidgetFactory.build(
          field: field,
          formData: {},
          onChanged: (name, value) {},
          ctx: _stubContext(),
        ),
      ));

      expect(find.text('SQL Statement'), findsOneWidget);
      expect(find.byType(TextFormField), findsOneWidget);
    });

    testWidgets('section-iterate with server-expanded messages', (tester) async {
      // Server expands section-iterate and sends pre-rendered children
      final node = WidgetNode.fromJson(const {
        '_type': 'section-iterate',
        'name': 'Messages',
        'list': 'messageList',
        'entry': 'message',
        // Server pre-expanded children
        'children': [
          {'_type': 'label', 'text': 'Query altered 5 rows.', 'labelType': 'p', 'style': 'text-info'},
          {'_type': 'label', 'text': 'Showing all 100 results.', 'labelType': 'p', 'style': 'text-info'},
        ],
      });

      await tester.pumpWidget(_testHarness(
        MoquiWidgetFactory.build(node, _stubContext()),
      ));

      // Should render each pre-expanded message
      expect(find.text('Query altered 5 rows.'), findsOneWidget);
      expect(find.text('Showing all 100 results.'), findsOneWidget);
    });
  });

  // ===========================================================================
  // COMPLEX WIDGET COMBINATIONS
  // ===========================================================================
  group('Complex Widget Combinations', () {
    testWidgets('nested sections with server-evaluated conditions', (tester) async {
      // Section conditionals are server-evaluated - widgets present means true
      final node = WidgetNode.fromJson(const {
        '_type': 'container',
        'children': [
          {
            '_type': 'section',
            'name': 'Section1',
            'widgets': [
              {'_type': 'label', 'text': 'Section 1 Content', 'labelType': 'span'},
            ],
          },
          {
            '_type': 'section',
            'name': 'Section2',
            // No widgets = condition false
          },
          {
            '_type': 'section',
            'name': 'Section3',
            'widgets': [
              {'_type': 'label', 'text': 'Section 3 Content', 'labelType': 'span'},
            ],
          },
        ],
      });

      await tester.pumpWidget(_testHarness(
        MoquiWidgetFactory.build(node, _stubContext()),
      ));

      expect(find.text('Section 1 Content'), findsOneWidget);
      expect(find.text('Section 2 Content'), findsNothing);
      expect(find.text('Section 3 Content'), findsOneWidget);
    });

    testWidgets('form-list renders column headers', (tester) async {
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
            'name': 'description',
            'title': 'Description',
            'widgets': [{'_type': 'display'}],
          },
        ],
        'listData': [
          {'entityName': 'moqui.test.TestEntity', 'description': 'Test entity'},
        ],
      });

      await tester.pumpWidget(_testHarness(
        MoquiWidgetFactory.build(node, _stubContext()),
      ));

      // Column headers
      expect(find.text('Entity Name'), findsOneWidget);
      expect(find.text('Description'), findsOneWidget);
      // Row data
      expect(find.text('moqui.test.TestEntity'), findsOneWidget);
      expect(find.text('Test entity'), findsOneWidget);
    });

    testWidgets('container-box with body containing form-list', (tester) async {
      final node = WidgetNode.fromJson(const {
        '_type': 'container-box',
        'header': [
          {'_type': 'label', 'text': 'In Parameters', 'labelType': 'h5'},
        ],
        'bodyNoPad': [
          {
            '_type': 'form-list',
            'formName': 'InParameters',
            'listName': 'inParameterNodes',
            'skipForm': true,
            'fields': [
              {
                'name': 'name',
                'title': 'Name',
                'widgets': [{'_type': 'display'}],
              },
              {
                'name': 'type',
                'title': 'Type',
                'widgets': [{'_type': 'display'}],
              },
            ],
            'listData': [
              {'name': 'inputParam1', 'type': 'String'},
              {'name': 'inputParam2', 'type': 'Integer'},
            ],
          },
        ],
      });

      await tester.pumpWidget(_testHarness(
        MoquiWidgetFactory.build(node, _stubContext()),
      ));

      expect(find.text('In Parameters'), findsOneWidget);
      expect(find.text('inputParam1'), findsOneWidget);
      expect(find.text('inputParam2'), findsOneWidget);
    });
  });

  // ===========================================================================
  // EDGE CASES FOR SERVICE TOOLS
  // ===========================================================================
  group('Service Tools Edge Cases', () {
    testWidgets('empty form-list renders table gracefully', (tester) async {
      final node = WidgetNode.fromJson(const {
        '_type': 'form-list',
        'formName': 'EmptyList',
        'listName': 'emptyList',
        'fields': [
          {
            'name': 'name',
            'title': 'Name',
            'widgets': [{'_type': 'display'}],
          },
        ],
        'listData': [],
      });

      await tester.pumpWidget(_testHarness(
        MoquiWidgetFactory.build(node, _stubContext()),
      ));

      // Should handle empty list gracefully (renders table headers)
      expect(find.text('Name'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('link navigation is called with url', (tester) async {
      String? capturedPath;

      final ctx = _stubContext(
        navigate: (path, {params}) {
          capturedPath = path;
        },
      );

      final node = WidgetNode.fromJson(const {
        '_type': 'link',
        'text': 'View Entity',
        'url': 'entityDetail',
      });

      await tester.pumpWidget(_testHarness(
        MoquiWidgetFactory.build(node, ctx),
      ));

      await tester.tap(find.text('View Entity'));
      await tester.pumpAndSettle();

      expect(capturedPath, 'entityDetail');
    });

    testWidgets('section with embedded children renders', (tester) async {
      // Section can have direct children as well as widgets attribute
      final ctx = _stubContext(
        contextData: {'serviceName': 'test.Service#run'},
      );

      final node = WidgetNode.fromJson(const {
        '_type': 'section',
        'name': 'ResultsSection',
        'widgets': [
          {'_type': 'label', 'text': 'Results Display', 'labelType': 'h3'},
        ],
      });

      await tester.pumpWidget(_testHarness(
        MoquiWidgetFactory.build(node, ctx),
      ));

      expect(find.text('Results Display'), findsOneWidget);
    });

    testWidgets('label with style applies color', (tester) async {
      final node = WidgetNode.fromJson(const {
        '_type': 'label',
        'text': 'Error Message',
        'labelType': 'span',
        'style': 'text-danger',
      });

      await tester.pumpWidget(_testHarness(
        MoquiWidgetFactory.build(node, _stubContext()),
      ));

      final textWidget = tester.widget<Text>(find.text('Error Message'));
      expect(textWidget.style?.color, Colors.red);
    });

    testWidgets('container with containerType=ul renders list', (tester) async {
      final node = WidgetNode.fromJson(const {
        '_type': 'container',
        'containerType': 'ul',
        'children': [
          {'_type': 'label', 'text': 'Item 1', 'labelType': 'span'},
          {'_type': 'label', 'text': 'Item 2', 'labelType': 'span'},
        ],
      });

      await tester.pumpWidget(_testHarness(
        MoquiWidgetFactory.build(node, _stubContext()),
      ));

      // Should render with bullet points
      expect(find.text('• '), findsNWidgets(2));
      expect(find.text('Item 1'), findsOneWidget);
      expect(find.text('Item 2'), findsOneWidget);
    });
  });
}
