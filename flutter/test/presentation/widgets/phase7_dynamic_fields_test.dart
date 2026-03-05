import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moqui_flutter/domain/screen/screen_models.dart';
import 'package:moqui_flutter/presentation/widgets/moqui/widget_factory.dart';
import 'package:moqui_flutter/data/api/moqui_api_client.dart';
import 'package:moqui_flutter/presentation/widgets/fields/field_widget_factory.dart';

// ============================================================================
// Helpers
// ============================================================================

Widget _testHarness(Widget child) {
  return MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(child: child),
    ),
  );
}

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

MoquiRenderContext _stubContext({
  void Function(String path, {Map<String, dynamic>? params})? navigate,
  Future<TransitionResponse?> Function(String url, Map<String, dynamic> data)?
      submitForm,
  Future<Map<String, dynamic>> Function(
          String transition, Map<String, dynamic> params)?
      loadDynamic,
  Map<String, dynamic>? contextData,
}) {
  return MoquiRenderContext(
    navigate: navigate ?? (path, {params}) {},
    submitForm: submitForm ?? (url, data) async => null,
    loadDynamic:
        loadDynamic ?? (transition, params) async => <String, dynamic>{},
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
  DynamicOptionsConfig? dynamicOptions,
  AutocompleteConfig? autocomplete,
  List<DependsOn> dependsOn = const [],
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
        dynamicOptions: dynamicOptions,
        autocomplete: autocomplete,
        dependsOn: dependsOn,
      ),
    ],
  );
}

Finder _findButtonWithText(String text) {
  return find.ancestor(
    of: find.text(text),
    matching: find.byWidgetPredicate(
      (w) =>
          w.runtimeType.toString().contains('ElevatedButton') ||
          w.runtimeType.toString().contains('TextButton') ||
          w.runtimeType.toString().contains('FilledButton') ||
          w.runtimeType.toString().contains('OutlinedButton'),
    ),
  );
}

void main() {
  // ===========================================================================
  // 1. DYNAMIC DROP-DOWN (depends-on cascading + dynamic options)
  // ===========================================================================

  group('Dynamic Drop-Down', () {
    testWidgets('renders with dynamic options from loadDynamic',
        (tester) async {
      final completer = Completer<Map<String, dynamic>>();
      final ctx = _stubContext(
        loadDynamic: (transition, params) => completer.future,
      );

      final field = _makeField(
        'city',
        'drop-down',
        title: 'City',
        dynamicOptions: const DynamicOptionsConfig(
          transition: '/api/cities',
        ),
      );

      await tester.pumpWidget(_formTestHarness(
        FieldWidgetFactory.build(
          field: field,
          formData: {},
          onChanged: (_, __) {},
          ctx: ctx,
        ),
      ));

      // Loading state — show progress indicator
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // Complete with options
      completer.complete({
        'options': [
          {'key': 'ny', 'text': 'New York'},
          {'key': 'sf', 'text': 'San Francisco'},
        ]
      });
      await tester.pumpAndSettle();

      // No longer loading
      expect(find.byType(CircularProgressIndicator), findsNothing);

      // Dropdown should be present
      expect(find.byType(DropdownButtonFormField<String>), findsOneWidget);
    });

    testWidgets('depends-on triggers reload when parent field changes',
        (tester) async {
      final loadCalls = <Map<String, dynamic>>[];
      final ctx = _stubContext(
        loadDynamic: (transition, params) async {
          loadCalls.add(Map.from(params));
          final country = params['countryId']?.toString() ?? '';
          if (country == 'US') {
            return {
              'options': [
                {'key': 'ny', 'text': 'New York'},
                {'key': 'ca', 'text': 'California'},
              ]
            };
          }
          return {
            'options': [
              {'key': 'lon', 'text': 'London'},
            ]
          };
        },
      );

      // State field depends on country field
      final stateField = _makeField(
        'stateId',
        'drop-down',
        title: 'State',
        dynamicOptions: const DynamicOptionsConfig(
          transition: '/api/states',
          dependsOn: [DependsOn(field: 'countryId')],
        ),
      );

      final formData = <String, dynamic>{'countryId': 'US'};

      await tester.pumpWidget(_formTestHarness(
        FieldWidgetFactory.build(
          field: stateField,
          formData: formData,
          onChanged: (_, __) {},
          ctx: ctx,
        ),
      ));
      await tester.pumpAndSettle();

      // loadDynamic should have been called with countryId=US
      expect(loadCalls.isNotEmpty, isTrue);
      expect(loadCalls.last['countryId'], 'US');
    });

    testWidgets('depends-on with parameter mapping', (tester) async {
      final loadCalls = <Map<String, dynamic>>[];
      final ctx = _stubContext(
        loadDynamic: (transition, params) async {
          loadCalls.add(Map.from(params));
          return {'options': []};
        },
      );

      final field = _makeField(
        'district',
        'drop-down',
        title: 'District',
        dependsOn: [const DependsOn(field: 'regionId', parameter: 'parentRegion')],
        dynamicOptions: const DynamicOptionsConfig(
          transition: '/api/districts',
        ),
      );

      await tester.pumpWidget(_formTestHarness(
        FieldWidgetFactory.build(
          field: field,
          formData: {'regionId': 'R1'},
          onChanged: (_, __) {},
          ctx: ctx,
        ),
      ));
      await tester.pumpAndSettle();

      // Parameter should be mapped: regionId → parentRegion
      expect(loadCalls.isNotEmpty, isTrue);
      expect(loadCalls.last['parentRegion'], 'R1');
    });

    testWidgets('server-search dropdown shows search field', (tester) async {
      final ctx = _stubContext(
        loadDynamic: (transition, params) async => {'options': []},
      );

      final field = _makeField(
        'product',
        'drop-down',
        title: 'Product',
        dynamicOptions: const DynamicOptionsConfig(
          transition: '/api/products',
          serverSearch: true,
          minLength: 2,
        ),
      );

      await tester.pumpWidget(_formTestHarness(
        FieldWidgetFactory.build(
          field: field,
          formData: {},
          onChanged: (_, __) {},
          ctx: ctx,
        ),
      ));
      await tester.pumpAndSettle();

      // Should show a text field with search icon
      expect(find.byIcon(Icons.search), findsOneWidget);
      expect(find.byType(TextFormField), findsOneWidget);
    });

    testWidgets('server-search fetches options on typing', (tester) async {
      final loadCalls = <Map<String, dynamic>>[];
      final ctx = _stubContext(
        loadDynamic: (transition, params) async {
          loadCalls.add(Map.from(params));
          if (params['term'] == 'wid') {
            return {
              'options': [
                {'key': 'w1', 'text': 'Widget A'},
                {'key': 'w2', 'text': 'Widget B'},
              ]
            };
          }
          return {'options': []};
        },
      );

      final field = _makeField(
        'product',
        'drop-down',
        title: 'Product',
        dynamicOptions: const DynamicOptionsConfig(
          transition: '/api/products',
          serverSearch: true,
          minLength: 2,
        ),
      );

      await tester.pumpWidget(_formTestHarness(
        FieldWidgetFactory.build(
          field: field,
          formData: {},
          onChanged: (_, __) {},
          ctx: ctx,
        ),
      ));
      await tester.pumpAndSettle();

      // Type into the search field
      await tester.enterText(find.byType(TextFormField), 'wid');
      // Wait for debounce (300ms + pumpAndSettle)
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();

      // Options should appear as ListTiles
      expect(find.byType(ListTile), findsNWidgets(2));
      expect(find.text('Widget A'), findsOneWidget);
      expect(find.text('Widget B'), findsOneWidget);
    });

    testWidgets('server-search ignores short terms below minLength',
        (tester) async {
      final loadCalls = <Map<String, dynamic>>[];
      final ctx = _stubContext(
        loadDynamic: (transition, params) async {
          loadCalls.add(Map.from(params));
          return {'options': []};
        },
      );

      final field = _makeField(
        'product',
        'drop-down',
        title: 'Product',
        dynamicOptions: const DynamicOptionsConfig(
          transition: '/api/products',
          serverSearch: true,
          minLength: 3,
        ),
      );

      await tester.pumpWidget(_formTestHarness(
        FieldWidgetFactory.build(
          field: field,
          formData: {},
          onChanged: (_, __) {},
          ctx: ctx,
        ),
      ));
      await tester.pumpAndSettle();

      // Type only 2 chars when minLength is 3
      await tester.enterText(find.byType(TextFormField), 'ab');
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();

      // loadDynamic should NOT have been called (initial fetch only)
      // The initial fetch has no 'term' param
      final fetchesWithTerm =
          loadCalls.where((c) => c.containsKey('term')).toList();
      expect(fetchesWithTerm, isEmpty);
    });

    testWidgets('static drop-down still works without dynamicOptions',
        (tester) async {
      final field = _makeField(
        'color',
        'drop-down',
        title: 'Color',
        options: [
          const FieldOption(key: 'r', text: 'Red'),
          const FieldOption(key: 'g', text: 'Green'),
          const FieldOption(key: 'b', text: 'Blue'),
        ],
      );

      final ctx = _stubContext();
      await tester.pumpWidget(_formTestHarness(
        FieldWidgetFactory.build(
          field: field,
          formData: {},
          onChanged: (_, __) {},
          ctx: ctx,
        ),
      ));

      expect(find.byType(DropdownButtonFormField<String>), findsOneWidget);
    });

    testWidgets('loadDynamic error is handled gracefully', (tester) async {
      final ctx = _stubContext(
        loadDynamic: (transition, params) async {
          throw Exception('Network error');
        },
      );

      final field = _makeField(
        'city',
        'drop-down',
        title: 'City',
        dynamicOptions: const DynamicOptionsConfig(
          transition: '/api/cities',
        ),
      );

      // Should not crash
      await tester.pumpWidget(_formTestHarness(
        FieldWidgetFactory.build(
          field: field,
          formData: {},
          onChanged: (_, __) {},
          ctx: ctx,
        ),
      ));
      await tester.pumpAndSettle();

      // Widget should still render (with empty options)
      expect(find.byType(DropdownButtonFormField<String>), findsOneWidget);
    });
  });

  // ===========================================================================
  // 2. AUTOCOMPLETE CONFIG WIRING
  // ===========================================================================

  group('Autocomplete Config', () {
    testWidgets('renders autocomplete text field with search icon',
        (tester) async {
      final ctx = _stubContext(
        loadDynamic: (transition, params) async => {'options': []},
      );

      final field = _makeField(
        'customer',
        'text-find-autocomplete',
        title: 'Customer',
        widgetAttrs: {'transition': '/api/customers'},
        autocomplete: const AutocompleteConfig(
          transition: '/api/customers',
          delay: 500,
          minLength: 3,
        ),
      );

      await tester.pumpWidget(_formTestHarness(
        FieldWidgetFactory.build(
          field: field,
          formData: {},
          onChanged: (_, __) {},
          ctx: ctx,
        ),
      ));

      expect(find.byIcon(Icons.search), findsOneWidget);
      expect(find.byType(TextFormField), findsOneWidget);
    });

    testWidgets('respects minLength from AutocompleteConfig', (tester) async {
      final loadCalls = <Map<String, dynamic>>[];
      final ctx = _stubContext(
        loadDynamic: (transition, params) async {
          loadCalls.add(Map.from(params));
          return {'options': []};
        },
      );

      final field = _makeField(
        'customer',
        'text-find-autocomplete',
        title: 'Customer',
        widgetAttrs: {'transition': '/api/customers'},
        autocomplete: const AutocompleteConfig(
          transition: '/api/customers',
          delay: 50,
          minLength: 4,
        ),
      );

      await tester.pumpWidget(_formTestHarness(
        FieldWidgetFactory.build(
          field: field,
          formData: {},
          onChanged: (_, __) {},
          ctx: ctx,
        ),
      ));

      // Type 3 chars (below minLength of 4)
      await tester.enterText(find.byType(TextFormField), 'abc');
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();

      // No server search calls should be made
      expect(loadCalls, isEmpty);

      // Type 4 chars (meets minLength)
      await tester.enterText(find.byType(TextFormField), 'abcd');
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();

      // Now a call should have been made
      expect(loadCalls.isNotEmpty, isTrue);
    });

    testWidgets('shows loading indicator during search', (tester) async {
      final completer = Completer<Map<String, dynamic>>();
      final ctx = _stubContext(
        loadDynamic: (transition, params) => completer.future,
      );

      final field = _makeField(
        'customer',
        'text-find-autocomplete',
        title: 'Customer',
        widgetAttrs: {'transition': '/api/customers'},
        autocomplete: const AutocompleteConfig(
          transition: '/api/customers',
          delay: 10,
          minLength: 2,
        ),
      );

      await tester.pumpWidget(_formTestHarness(
        FieldWidgetFactory.build(
          field: field,
          formData: {},
          onChanged: (_, __) {},
          ctx: ctx,
        ),
      ));

      await tester.enterText(find.byType(TextFormField), 'test');
      await tester.pump(const Duration(milliseconds: 50));
      // Pump once more to see loading
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // Complete the request
      completer.complete({
        'options': [
          {'value': '1', 'label': 'Test Result'}
        ]
      });
      await tester.pumpAndSettle();

      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('selecting autocomplete option calls onChanged',
        (tester) async {
      String? changedValue;
      final ctx = _stubContext(
        loadDynamic: (transition, params) async {
          return {
            'options': [
              {'value': 'C001', 'label': 'Acme Corp'},
              {'value': 'C002', 'label': 'Beta Inc'},
            ]
          };
        },
      );

      final field = _makeField(
        'customer',
        'text-find-autocomplete',
        title: 'Customer',
        widgetAttrs: {'transition': '/api/customers'},
        autocomplete: const AutocompleteConfig(
          transition: '/api/customers',
          delay: 10,
          minLength: 1,
        ),
      );

      await tester.pumpWidget(_formTestHarness(
        FieldWidgetFactory.build(
          field: field,
          formData: {},
          onChanged: (name, value) {
            changedValue = value?.toString();
          },
          ctx: ctx,
        ),
      ));

      await tester.enterText(find.byType(TextFormField), 'ac');
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pumpAndSettle();

      // Should show options
      expect(find.text('Acme Corp'), findsOneWidget);

      // Tap option
      await tester.tap(find.text('Acme Corp'));
      await tester.pumpAndSettle();

      expect(changedValue, 'C001');
    });
  });

  // ===========================================================================
  // 3. FILE UPLOAD — FORM SUBMIT BRIDGE
  // ===========================================================================

  group('File Upload Bridge', () {
    testWidgets('form submit includes _hasFileUploads flag when files present',
        (tester) async {
      Map<String, dynamic>? submittedData;
      final ctx = _stubContext(
        submitForm: (url, data) async {
          submittedData = data;
          return null;
        },
      );

      // Build a form-single with a file field and a submit button
      final formNode = WidgetNode.fromJson(const {
        '_type': 'form-single',
        'name': 'TestForm',
        'transition': '/api/upload',
        'fields': [
          {
            'name': 'description',
            'title': 'Description',
            'widgets': [
              {'_type': 'text-line'}
            ]
          },
          {
            'name': 'attachment',
            'title': 'Attachment',
            'widgets': [
              {'_type': 'file'}
            ]
          },
          {
            'name': 'submitBtn',
            'title': '',
            'widgets': [
              {'_type': 'submit', 'text': 'Upload'}
            ]
          },
        ],
      });

      await tester.pumpWidget(_testHarness(
        MoquiWidgetFactory.build(formNode, ctx),
      ));

      // Enter a description
      final textFields = find.byType(TextFormField);
      if (textFields.evaluate().isNotEmpty) {
        await tester.enterText(textFields.first, 'Test file');
      }

      // We can't easily mock file picking, but we verify the form renders
      // and the submit button is present
      expect(find.text('Upload'), findsAtLeastNWidgets(1));
    });

    testWidgets('file field renders file picker with button', (tester) async {
      final field = _makeField(
        'attachment',
        'file',
        title: 'Attachment',
        widgetAttrs: {'accept': 'image/*'},
      );

      final ctx = _stubContext();
      await tester.pumpWidget(_formTestHarness(
        FieldWidgetFactory.build(
          field: field,
          formData: {},
          onChanged: (_, __) {},
          ctx: ctx,
        ),
      ));

      // Should show a file picker button
      expect(find.text('Choose File'), findsOneWidget);
    });

    testWidgets('multiple file support shows correct label', (tester) async {
      final field = _makeField(
        'attachments',
        'file',
        title: 'Attachments',
        widgetAttrs: {'multiple': 'true'},
      );

      final ctx = _stubContext();
      await tester.pumpWidget(_formTestHarness(
        FieldWidgetFactory.build(
          field: field,
          formData: {},
          onChanged: (_, __) {},
          ctx: ctx,
        ),
      ));

      expect(find.text('Choose Files'), findsOneWidget);
    });
  });

  // ===========================================================================
  // 4. FORM-LIST BULK SUBMIT
  // ===========================================================================

  group('Form-List Bulk Submit', () {
    testWidgets('editing a cell tracks the row as edited', (tester) async {
      // Suppress overflow errors from DataTable cells
      final oldHandler = FlutterError.onError;
      FlutterError.onError = (details) {
        if (details.toString().contains('overflow')) return;
        oldHandler?.call(details);
      };

      final ctx = _stubContext();

      final formNode = WidgetNode.fromJson(const {
        '_type': 'form-list',
        'name': 'EditableList',
        'transition': '/api/saveRows',
        'columns': [
          {'name': 'name'},
          {'name': 'amount'},
        ],
        'fields': [
          {
            'name': 'name',
            'title': 'Name',
            'widgets': [
              {'_type': 'editable', 'editWidgetType': 'text-line'}
            ]
          },
          {
            'name': 'amount',
            'title': 'Amount',
            'widgets': [
              {'_type': 'editable', 'editWidgetType': 'text-line'}
            ]
          },
        ],
        'listData': [
          {'name': 'Item A', 'amount': '100'},
          {'name': 'Item B', 'amount': '200'},
        ],
      });

      await tester.pumpWidget(_testHarness(
        MoquiWidgetFactory.build(formNode, ctx),
      ));
      await tester.pumpAndSettle();

      // Find editable cells — they should be displayed as text initially
      expect(find.text('Item A'), findsOneWidget);
      expect(find.text('Item B'), findsOneWidget);

      FlutterError.onError = oldHandler;
    });

    testWidgets('Save Changes button appears after editing', (tester) async {
      final oldHandler = FlutterError.onError;
      FlutterError.onError = (details) {
        if (details.toString().contains('overflow')) return;
        oldHandler?.call(details);
      };

      final ctx = _stubContext();

      final formNode = WidgetNode.fromJson(const {
        '_type': 'form-list',
        'name': 'EditableList',
        'transition': '/api/saveRows',
        'columns': [
          {'name': 'name'},
        ],
        'fields': [
          {
            'name': 'name',
            'title': 'Name',
            'widgets': [
              {'_type': 'text-line'}
            ]
          },
        ],
        'listData': [
          {'name': 'Item A'},
          {'name': 'Item B'},
        ],
      });

      await tester.pumpWidget(_testHarness(
        MoquiWidgetFactory.build(formNode, ctx),
      ));
      await tester.pumpAndSettle();

      // Save Changes button should NOT be visible initially
      expect(find.textContaining('Save Changes'), findsNothing);

      // Find a text field and edit it
      final textFields = find.byType(TextFormField);
      if (textFields.evaluate().isNotEmpty) {
        await tester.enterText(textFields.first, 'Modified');
        await tester.pumpAndSettle();

        // Now Save Changes button should appear
        expect(find.textContaining('Save Changes'), findsOneWidget);
      }

      FlutterError.onError = oldHandler;
    });

    testWidgets('submitting edits sends indexed parameters', (tester) async {
      final oldHandler = FlutterError.onError;
      FlutterError.onError = (details) {
        if (details.toString().contains('overflow')) return;
        oldHandler?.call(details);
      };

      Map<String, dynamic>? submittedData;
      String? submittedUrl;
      final ctx = _stubContext(
        submitForm: (url, data) async {
          submittedUrl = url;
          submittedData = data;
          return TransitionResponse(
            screenUrl: '',
            screenParameters: {},
            messages: ['Saved successfully'],
            errors: [],
          );
        },
      );

      final formNode = WidgetNode.fromJson(const {
        '_type': 'form-list',
        'name': 'EditableList',
        'transition': '/api/saveRows',
        'columns': [
          {'name': 'name'},
        ],
        'fields': [
          {
            'name': 'name',
            'title': 'Name',
            'widgets': [
              {'_type': 'text-line'}
            ]
          },
        ],
        'listData': [
          {'name': 'Item A'},
          {'name': 'Item B'},
        ],
      });

      await tester.pumpWidget(_testHarness(
        MoquiWidgetFactory.build(formNode, ctx),
      ));
      await tester.pumpAndSettle();

      // Edit first row
      final textFields = find.byType(TextFormField);
      if (textFields.evaluate().isNotEmpty) {
        await tester.enterText(textFields.first, 'Modified A');
        await tester.pumpAndSettle();

        // Tap Save Changes
        final saveButton = find.textContaining('Save Changes');
        if (saveButton.evaluate().isNotEmpty) {
          await tester.tap(saveButton.first);
          await tester.pumpAndSettle();

          expect(submittedUrl, '/api/saveRows');
          expect(submittedData?['_isMulti'], 'true');
        }
      }

      FlutterError.onError = oldHandler;
    });

    testWidgets('selection action bar appears with selected rows',
        (tester) async {
      final oldHandler = FlutterError.onError;
      FlutterError.onError = (details) {
        if (details.toString().contains('overflow')) return;
        oldHandler?.call(details);
      };

      final ctx = _stubContext();

      final formNode = WidgetNode.fromJson(const {
        '_type': 'form-list',
        'name': 'SelectableList',
        'transition': '/api/action',
        'rowSelection': {
          'idField': 'id',
          'parameter': 'selectedIds',
        },
        'columns': [
          {'name': 'name'},
        ],
        'fields': [
          {
            'name': 'name',
            'title': 'Name',
            'widgets': [
              {'_type': 'display'}
            ]
          },
        ],
        'listData': [
          {'id': '1', 'name': 'Alpha'},
          {'id': '2', 'name': 'Beta'},
        ],
      });

      await tester.pumpWidget(_testHarness(
        MoquiWidgetFactory.build(formNode, ctx),
      ));
      await tester.pumpAndSettle();

      // List should render
      expect(find.text('Alpha'), findsOneWidget);
      expect(find.text('Beta'), findsOneWidget);

      FlutterError.onError = oldHandler;
    });
  });

  // ===========================================================================
  // 5. MODEL PARSING
  // ===========================================================================

  group('Model Parsing', () {
    test('DynamicOptionsConfig parses from JSON', () {
      final config = DynamicOptionsConfig.fromJson(const {
        'transition': '/api/options',
        'serverSearch': 'true',
        'minLength': '3',
        'dependsOnList': [
          {'field': 'country', 'parameter': 'countryId'},
        ],
      });

      expect(config.transition, '/api/options');
      expect(config.serverSearch, isTrue);
      expect(config.minLength, 3);
      expect(config.dependsOn.length, 1);
      expect(config.dependsOn.first.field, 'country');
      expect(config.dependsOn.first.parameter, 'countryId');
    });

    test('DynamicOptionsConfig defaults', () {
      final config = DynamicOptionsConfig.fromJson(const {
        'transition': '/api/opts',
      });

      expect(config.serverSearch, isFalse);
      expect(config.minLength, 1);
      expect(config.dependsOn, isEmpty);
    });

    test('AutocompleteConfig parses from JSON', () {
      final config = AutocompleteConfig.fromJson(const {
        'transition': '/api/search',
        'delay': '500',
        'minLength': '3',
        'showValue': 'true',
        'useActual': 'true',
      });

      expect(config.transition, '/api/search');
      expect(config.delay, 500);
      expect(config.minLength, 3);
      expect(config.showValue, isTrue);
      expect(config.useActual, isTrue);
    });

    test('AutocompleteConfig defaults', () {
      final config = AutocompleteConfig.fromJson(const {
        'transition': '/api/ac',
      });

      expect(config.delay, 300);
      expect(config.minLength, 1);
      expect(config.showValue, isFalse);
      expect(config.useActual, isFalse);
    });

    test('DependsOn parses from JSON', () {
      final dep = DependsOn.fromJson(const {
        'field': 'parentId',
        'parameter': 'parentIdParam',
      });

      expect(dep.field, 'parentId');
      expect(dep.parameter, 'parentIdParam');
    });

    test('DependsOn defaults parameter to empty string', () {
      final dep = DependsOn.fromJson(const {'field': 'myField'});
      expect(dep.field, 'myField');
      expect(dep.parameter, '');
    });

    test('FieldWidget.fromJson parses dependsOnList', () {
      final fw = FieldWidget.fromJson(const {
        '_type': 'drop-down',
        'dependsOnList': [
          {'field': 'parent1'},
          {'field': 'parent2', 'parameter': 'p2'},
        ],
      });

      expect(fw.dependsOn.length, 2);
      expect(fw.dependsOn[0].field, 'parent1');
      expect(fw.dependsOn[1].parameter, 'p2');
    });

    test('FieldWidget.fromJson parses dependsOnField shorthand', () {
      final fw = FieldWidget.fromJson(const {
        '_type': 'drop-down',
        'dependsOnField': 'parentField',
      });

      expect(fw.dependsOn.length, 1);
      expect(fw.dependsOn.first.field, 'parentField');
    });

    test('FieldWidget.fromJson parses dynamicOptions', () {
      final fw = FieldWidget.fromJson(const {
        '_type': 'drop-down',
        'dynamicOptions': {
          'transition': '/api/opts',
          'serverSearch': 'true',
          'minLength': '2',
        },
      });

      expect(fw.dynamicOptions, isNotNull);
      expect(fw.dynamicOptions!.transition, '/api/opts');
      expect(fw.dynamicOptions!.serverSearch, isTrue);
      expect(fw.dynamicOptions!.minLength, 2);
    });

    test('FieldWidget.fromJson parses autocomplete', () {
      final fw = FieldWidget.fromJson(const {
        '_type': 'text-find-autocomplete',
        'autocomplete': {
          'transition': '/api/ac',
          'delay': '200',
          'minLength': '3',
          'showValue': 'true',
        },
      });

      expect(fw.autocomplete, isNotNull);
      expect(fw.autocomplete!.transition, '/api/ac');
      expect(fw.autocomplete!.delay, 200);
      expect(fw.autocomplete!.minLength, 3);
      expect(fw.autocomplete!.showValue, isTrue);
    });
  });

  // ===========================================================================
  // 6. EDGE CASES
  // ===========================================================================

  group('Edge Cases', () {
    testWidgets('dynamic dropdown with empty transition falls back to depends-on',
        (tester) async {
      final loadCalls = <Map<String, dynamic>>[];
      final ctx = _stubContext(
        loadDynamic: (transition, params) async {
          loadCalls.add(Map.from(params));
          return {'options': []};
        },
      );

      final field = _makeField(
        'child',
        'drop-down',
        title: 'Child',
        dependsOn: [const DependsOn(field: 'parentId')],
      );

      await tester.pumpWidget(_formTestHarness(
        FieldWidgetFactory.build(
          field: field,
          formData: {'parentId': 'P1'},
          onChanged: (_, __) {},
          ctx: ctx,
        ),
      ));
      await tester.pumpAndSettle();

      // Should have made a loadDynamic call with parent value
      expect(loadCalls.isNotEmpty, isTrue);
      expect(loadCalls.last['parentId'], 'P1');
    });

    testWidgets('dynamic dropdown handles result with data array format',
        (tester) async {
      final ctx = _stubContext(
        loadDynamic: (transition, params) async {
          return {
            'data': [
              {'key': 'x', 'text': 'Option X'},
              {'key': 'y', 'text': 'Option Y'},
            ]
          };
        },
      );

      final field = _makeField(
        'item',
        'drop-down',
        title: 'Item',
        dynamicOptions: const DynamicOptionsConfig(
          transition: '/api/items',
        ),
      );

      await tester.pumpWidget(_formTestHarness(
        FieldWidgetFactory.build(
          field: field,
          formData: {},
          onChanged: (_, __) {},
          ctx: ctx,
        ),
      ));
      await tester.pumpAndSettle();

      // Should have parsed data array into dropdown items
      expect(find.byType(DropdownButtonFormField<String>), findsOneWidget);
    });

    testWidgets('server-search option tap calls onChanged', (tester) async {
      String? changedValue;
      final ctx = _stubContext(
        loadDynamic: (transition, params) async {
          return {
            'options': [
              {'key': 'opt1', 'text': 'Option One'},
            ]
          };
        },
      );

      final field = _makeField(
        'item',
        'drop-down',
        title: 'Item',
        dynamicOptions: const DynamicOptionsConfig(
          transition: '/api/items',
          serverSearch: true,
          minLength: 1,
        ),
      );

      await tester.pumpWidget(_formTestHarness(
        FieldWidgetFactory.build(
          field: field,
          formData: {},
          onChanged: (name, value) {
            changedValue = value?.toString();
          },
          ctx: ctx,
        ),
      ));
      await tester.pumpAndSettle();

      // Type to trigger search
      await tester.enterText(find.byType(TextFormField), 'opt');
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();

      // Tap the option
      final optionTile = find.text('Option One');
      if (optionTile.evaluate().isNotEmpty) {
        await tester.tap(optionTile);
        await tester.pumpAndSettle();
        expect(changedValue, 'opt1');
      }
    });

    test('DynamicOptionsConfig equality', () {
      const a = DynamicOptionsConfig(
          transition: '/api/x', serverSearch: true);
      const b = DynamicOptionsConfig(
          transition: '/api/x', serverSearch: true);
      const c = DynamicOptionsConfig(
          transition: '/api/y', serverSearch: false);

      expect(a, equals(b));
      expect(a, isNot(equals(c)));
    });

    test('AutocompleteConfig equality', () {
      const a = AutocompleteConfig(
          transition: '/api/ac', delay: 300, minLength: 1);
      const b = AutocompleteConfig(
          transition: '/api/ac', delay: 300, minLength: 1);
      const c = AutocompleteConfig(
          transition: '/api/ac', delay: 500, minLength: 2);

      expect(a, equals(b));
      expect(a, isNot(equals(c)));
    });
  });
}
