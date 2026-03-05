import 'dart:async';
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
  Future<TransitionResponse?> Function(String url, Map<String, dynamic> data)?
      submitForm,
  Future<Map<String, dynamic>> Function(
          String transition, Map<String, dynamic> params)?
      loadDynamic,
  Map<String, dynamic>? contextData,
}) {
  return MoquiRenderContext(
    navigate: navigate ?? (path, {params}) {},
    submitForm: submitForm ?? (url, data) async {
      return null;
    },
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
  // FIELD VALIDATION
  // ===========================================================================

  group('Field Validation', () {
    testWidgets('required text-line shows error when empty', (tester) async {
      final field = _makeField('username', 'text-line',
          title: 'Username', widgetAttrs: {'required': 'true'});

      await tester.pumpWidget(_formTestHarness(
        FieldWidgetFactory.build(
          field: field,
          formData: {},
          onChanged: (name, value) {},
          ctx: _stubContext(),
        ),
      ));

      final formState = tester.state<FormState>(find.byType(Form));
      final isValid = formState.validate();
      await tester.pump();

      expect(isValid, isFalse);
      expect(find.text('Username is required'), findsOneWidget);
    });

    testWidgets('required text-line passes when filled', (tester) async {
      final field = _makeField('username', 'text-line',
          title: 'Username',
          widgetAttrs: {'required': 'true'},
          currentValue: 'admin');

      await tester.pumpWidget(_formTestHarness(
        FieldWidgetFactory.build(
          field: field,
          formData: {'username': 'admin'},
          onChanged: (name, value) {},
          ctx: _stubContext(),
        ),
      ));

      final formState = tester.state<FormState>(find.byType(Form));
      final isValid = formState.validate();
      await tester.pump();

      expect(isValid, isTrue);
      expect(find.text('Username is required'), findsNothing);
    });

    testWidgets('minlength validation shows error for short input',
        (tester) async {
      final field = _makeField('password', 'text-line',
          title: 'Password', widgetAttrs: {'minlength': '8'});

      await tester.pumpWidget(_formTestHarness(
        FieldWidgetFactory.build(
          field: field,
          formData: {'password': 'abc'},
          onChanged: (name, value) {},
          ctx: _stubContext(),
        ),
      ));

      final formState = tester.state<FormState>(find.byType(Form));
      formState.validate();
      await tester.pump();

      expect(find.text('Minimum 8 characters'), findsOneWidget);
    });

    testWidgets('regex validation shows error for invalid format',
        (tester) async {
      final field = _makeField('email', 'text-line',
          title: 'Email',
          widgetAttrs: {'regexp': r'^[\w.]+@[\w.]+\.\w+$'});

      await tester.pumpWidget(_formTestHarness(
        FieldWidgetFactory.build(
          field: field,
          formData: {'email': 'not-an-email'},
          onChanged: (name, value) {},
          ctx: _stubContext(),
        ),
      ));

      final formState = tester.state<FormState>(find.byType(Form));
      formState.validate();
      await tester.pump();

      expect(find.text('Invalid format'), findsOneWidget);
    });

    testWidgets('regex validation passes for valid input', (tester) async {
      final field = _makeField('email', 'text-line',
          title: 'Email',
          widgetAttrs: {'regexp': r'^[\w.]+@[\w.]+\.\w+$'});

      await tester.pumpWidget(_formTestHarness(
        FieldWidgetFactory.build(
          field: field,
          formData: {'email': 'test@example.com'},
          onChanged: (name, value) {},
          ctx: _stubContext(),
        ),
      ));

      final formState = tester.state<FormState>(find.byType(Form));
      final isValid = formState.validate();
      await tester.pump();

      expect(isValid, isTrue);
    });

    testWidgets('text-area validates required', (tester) async {
      final field = _makeField('description', 'text-area',
          title: 'Description', widgetAttrs: {'required': 'true'});

      await tester.pumpWidget(_formTestHarness(
        FieldWidgetFactory.build(
          field: field,
          formData: {},
          onChanged: (name, value) {},
          ctx: _stubContext(),
        ),
      ));

      final formState = tester.state<FormState>(find.byType(Form));
      formState.validate();
      await tester.pump();

      expect(find.text('Description is required'), findsOneWidget);
    });

    testWidgets('non-required empty field passes validation', (tester) async {
      final field = _makeField('notes', 'text-line', title: 'Notes');

      await tester.pumpWidget(_formTestHarness(
        FieldWidgetFactory.build(
          field: field,
          formData: {},
          onChanged: (name, value) {},
          ctx: _stubContext(),
        ),
      ));

      final formState = tester.state<FormState>(find.byType(Form));
      final isValid = formState.validate();
      await tester.pump();

      expect(isValid, isTrue);
    });

    testWidgets('drop-down validates required when no value selected',
        (tester) async {
      final field = _makeField('status', 'drop-down',
          title: 'Status',
          widgetAttrs: {'required': 'true'},
          options: [
            const FieldOption(key: 'active', text: 'Active'),
            const FieldOption(key: 'inactive', text: 'Inactive'),
          ]);

      await tester.pumpWidget(_formTestHarness(
        FieldWidgetFactory.build(
          field: field,
          formData: {},
          onChanged: (name, value) {},
          ctx: _stubContext(),
        ),
      ));

      final formState = tester.state<FormState>(find.byType(Form));
      formState.validate();
      await tester.pump();

      expect(find.text('Status is required'), findsOneWidget);
    });

    testWidgets('multiple validators - minlength fails before regex',
        (tester) async {
      final field = _makeField('code', 'text-line',
          title: 'Code',
          widgetAttrs: {
            'required': 'true',
            'minlength': '3',
            'regexp': r'^[A-Z]+$',
          });

      await tester.pumpWidget(_formTestHarness(
        FieldWidgetFactory.build(
          field: field,
          formData: {'code': 'AB'},
          onChanged: (name, value) {},
          ctx: _stubContext(),
        ),
      ));

      final formState = tester.state<FormState>(find.byType(Form));
      formState.validate();
      await tester.pump();

      // minlength should fail (AB is 2 chars, minimum is 3)
      expect(find.text('Minimum 3 characters'), findsOneWidget);
    });
  });

  // ===========================================================================
  // FORM-SINGLE SUBMISSION + TRANSITION RESPONSE
  // ===========================================================================

  group('Form-Single Submission & Transition Response', () {
    testWidgets('submit calls submitForm with transition and formData',
        (tester) async {
      String? capturedUrl;
      Map<String, dynamic>? capturedData;

      final ctx = _stubContext(
        submitForm: (url, data) async {
          capturedUrl = url;
          capturedData = data;
          return null;
        },
      );

      await tester.pumpWidget(_testHarness(
        MoquiWidgetFactory.build(
          WidgetNode.fromJson(const {
            '_type': 'form-single',
            'formName': 'UpdateService',
            'transition': 'updateService',
            'fields': [
              {
                'name': 'serviceName',
                'title': 'Service Name',
                'widgets': [
                  {'_type': 'text-line'}
                ],
              },
              {
                'name': 'submit',
                'title': 'Save',
                'widgets': [
                  {'_type': 'submit', 'text': 'Save'}
                ],
              },
            ],
          }),
          ctx,
        ),
      ));

      // Type into the text field
      await tester.enterText(find.byType(TextFormField).first, 'MyService');
      await tester.pump();

      // Tap Save button
      final saveBtn = _findButtonWithText('Save');
      expect(saveBtn, findsOneWidget);
      await tester.tap(saveBtn.first);
      await tester.pumpAndSettle();

      expect(capturedUrl, equals('updateService'));
      expect(capturedData?['serviceName'], equals('MyService'));
    });

    testWidgets('submit shows error SnackBar on server errors',
        (tester) async {
      final ctx = _stubContext(
        submitForm: (url, data) async {
          return TransitionResponse(
            errors: ['Entity already exists', 'Duplicate key violation'],
          );
        },
      );

      await tester.pumpWidget(_testHarness(
        MoquiWidgetFactory.build(
          WidgetNode.fromJson(const {
            '_type': 'form-single',
            'formName': 'CreateEntity',
            'transition': 'createEntity',
            'fields': [
              {
                'name': 'entityName',
                'title': 'Entity Name',
                'widgets': [
                  {'_type': 'text-line'}
                ],
              },
              {
                'name': 'submit',
                'title': 'Create',
                'widgets': [
                  {'_type': 'submit', 'text': 'Create'}
                ],
              },
            ],
          }),
          ctx,
        ),
      ));

      await tester.enterText(find.byType(TextFormField).first, 'TestEntity');
      await tester.pump();

      await tester.tap(_findButtonWithText('Create').first);
      await tester.pumpAndSettle();

      // Error SnackBar should appear with joined error messages
      expect(find.text('Entity already exists\nDuplicate key violation'),
          findsOneWidget);
    });

    testWidgets('submit shows success message SnackBar', (tester) async {
      final ctx = _stubContext(
        submitForm: (url, data) async {
          return TransitionResponse(
            messages: ['Entity updated successfully'],
          );
        },
      );

      await tester.pumpWidget(_testHarness(
        MoquiWidgetFactory.build(
          WidgetNode.fromJson(const {
            '_type': 'form-single',
            'formName': 'UpdateEntity',
            'transition': 'updateEntity',
            'fields': [
              {
                'name': 'name',
                'title': 'Name',
                'widgets': [
                  {'_type': 'text-line'}
                ],
              },
              {
                'name': 'submit',
                'title': 'Update',
                'widgets': [
                  {'_type': 'submit', 'text': 'Update'}
                ],
              },
            ],
          }),
          ctx,
        ),
      ));

      await tester.enterText(find.byType(TextFormField).first, 'Updated');
      await tester.pump();

      await tester.tap(_findButtonWithText('Update').first);
      await tester.pumpAndSettle();

      expect(find.text('Entity updated successfully'), findsOneWidget);
    });

    testWidgets('submit navigates on screenUrl redirect', (tester) async {
      String? navigatedPath;
      Map<String, dynamic>? navigatedParams;

      final ctx = _stubContext(
        navigate: (path, {params}) {
          navigatedPath = path;
          navigatedParams = params;
        },
        submitForm: (url, data) async {
          return TransitionResponse(
            screenUrl: '/app/detail',
            screenParameters: {'id': '123'},
            messages: ['Created'],
          );
        },
      );

      await tester.pumpWidget(_testHarness(
        MoquiWidgetFactory.build(
          WidgetNode.fromJson(const {
            '_type': 'form-single',
            'formName': 'CreateForm',
            'transition': 'createThing',
            'fields': [
              {
                'name': 'name',
                'title': 'Name',
                'widgets': [
                  {'_type': 'text-line'}
                ],
              },
              {
                'name': 'submit',
                'title': 'Create',
                'widgets': [
                  {'_type': 'submit', 'text': 'Create'}
                ],
              },
            ],
          }),
          ctx,
        ),
      ));

      await tester.enterText(find.byType(TextFormField).first, 'Thing');
      await tester.pump();

      await tester.tap(_findButtonWithText('Create').first);
      await tester.pumpAndSettle();

      expect(navigatedPath, equals('/app/detail'));
      expect(navigatedParams?['id'], equals('123'));
    });

    testWidgets('validation prevents submit when required field empty',
        (tester) async {
      bool submitCalled = false;

      final ctx = _stubContext(
        submitForm: (url, data) async {
          submitCalled = true;
          return null;
        },
      );

      await tester.pumpWidget(_testHarness(
        MoquiWidgetFactory.build(
          WidgetNode.fromJson(const {
            '_type': 'form-single',
            'formName': 'RequiredForm',
            'transition': 'processRequired',
            'fields': [
              {
                'name': 'name',
                'title': 'Name',
                'widgets': [
                  {'_type': 'text-line', 'required': 'true'}
                ],
              },
              {
                'name': 'submit',
                'title': 'Submit',
                'widgets': [
                  {'_type': 'submit', 'text': 'Submit'}
                ],
              },
            ],
          }),
          ctx,
        ),
      ));

      // Don't enter anything - tap Submit with empty required field
      await tester.tap(_findButtonWithText('Submit').first);
      await tester.pumpAndSettle();

      // Submit should NOT be called due to validation failure
      expect(submitCalled, isFalse);
      expect(find.text('Name is required'), findsOneWidget);
    });

    testWidgets('errors SnackBar takes priority over messages',
        (tester) async {
      final ctx = _stubContext(
        submitForm: (url, data) async {
          return TransitionResponse(
            messages: ['Partial success'],
            errors: ['Critical error'],
          );
        },
      );

      await tester.pumpWidget(_testHarness(
        MoquiWidgetFactory.build(
          WidgetNode.fromJson(const {
            '_type': 'form-single',
            'formName': 'MixedResponse',
            'transition': 'mixed',
            'fields': [
              {
                'name': 'val',
                'title': 'Value',
                'widgets': [
                  {'_type': 'text-line'}
                ],
              },
              {
                'name': 'submit',
                'title': 'Send',
                'widgets': [
                  {'_type': 'submit', 'text': 'Send'}
                ],
              },
            ],
          }),
          ctx,
        ),
      ));

      await tester.enterText(find.byType(TextFormField).first, 'test');
      await tester.pump();
      await tester.tap(_findButtonWithText('Send').first);
      await tester.pumpAndSettle();

      // When there are errors, the error SnackBar is shown (with return)
      // so messages SnackBar should not appear
      expect(find.text('Critical error'), findsOneWidget);
      expect(find.text('Partial success'), findsNothing);
    });
  });

  // ===========================================================================
  // LOADING INDICATOR
  // ===========================================================================

  group('Form-Single Loading Indicator', () {
    testWidgets('shows loading spinner during submission', (tester) async {
      final completer = Completer<TransitionResponse?>();

      final ctx = _stubContext(
        submitForm: (url, data) => completer.future,
      );

      await tester.pumpWidget(_testHarness(
        MoquiWidgetFactory.build(
          WidgetNode.fromJson(const {
            '_type': 'form-single',
            'formName': 'SlowForm',
            'transition': 'slowProcess',
            'fields': [
              {
                'name': 'data',
                'title': 'Data',
                'widgets': [
                  {'_type': 'text-line'}
                ],
              },
              {
                'name': 'submit',
                'title': 'Process',
                'widgets': [
                  {'_type': 'submit', 'text': 'Process'}
                ],
              },
            ],
          }),
          ctx,
        ),
      ));

      await tester.enterText(find.byType(TextFormField).first, 'test');
      await tester.pump();

      // Tap submit - should show spinner while waiting
      await tester.tap(_findButtonWithText('Process').first);
      await tester.pump(); // Process one frame

      // CircularProgressIndicator should be visible
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // Complete the submission
      completer.complete(null);
      await tester.pumpAndSettle();

      // Spinner should be gone
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });
  });

  // ===========================================================================
  // FORM-LIST COLUMN SORTING
  // ===========================================================================

  group('Form-List Column Sorting', () {
    testWidgets('clicking column header triggers sort via loadDynamic',
        (tester) async {
      Map<String, dynamic>? capturedParams;

      final ctx = _stubContext(
        loadDynamic: (transition, params) async {
          capturedParams = params;
          return <String, dynamic>{};
        },
      );

      await tester.pumpWidget(_testHarness(
        MoquiWidgetFactory.build(
          WidgetNode.fromJson(const {
            '_type': 'form-list',
            'formName': 'SortableList',
            'listName': 'testList',
            'fields': [
              {
                'name': 'name',
                'title': 'Name',
                'widgets': [
                  {'_type': 'display'}
                ],
              },
              {
                'name': 'status',
                'title': 'Status',
                'widgets': [
                  {'_type': 'display'}
                ],
              },
            ],
            'listData': [
              {'name': 'Alpha', 'status': 'Active'},
              {'name': 'Beta', 'status': 'Inactive'},
            ],
          }),
          ctx,
        ),
      ));

      // Tap the Name column header
      final nameHeader = find.text('Name');
      expect(nameHeader, findsOneWidget);
      await tester.tap(nameHeader);
      await tester.pumpAndSettle();

      expect(capturedParams, isNotNull);
      expect(capturedParams!['orderByField'], equals('name'));
      expect(capturedParams!['pageIndex'], equals('0'));
    });

    testWidgets('second click on same column reverses sort direction',
        (tester) async {
      final capturedCalls = <Map<String, dynamic>>[];

      final ctx = _stubContext(
        loadDynamic: (transition, params) async {
          capturedCalls.add(Map.from(params));
          return <String, dynamic>{};
        },
      );

      await tester.pumpWidget(_testHarness(
        MoquiWidgetFactory.build(
          WidgetNode.fromJson(const {
            '_type': 'form-list',
            'formName': 'SortList2',
            'listName': 'list2',
            'fields': [
              {
                'name': 'id',
                'title': 'ID',
                'widgets': [
                  {'_type': 'display'}
                ],
              },
              {
                'name': 'label',
                'title': 'Label',
                'widgets': [
                  {'_type': 'display'}
                ],
              },
            ],
            'listData': [
              {'id': '1', 'label': 'First'},
              {'id': '2', 'label': 'Second'},
            ],
          }),
          ctx,
        ),
      ));

      // First click: ascending
      await tester.tap(find.text('ID'));
      await tester.pumpAndSettle();
      expect(capturedCalls.last['orderByField'], equals('id'));

      // Second click: toggles to descending
      await tester.tap(find.text('ID'));
      await tester.pumpAndSettle();
      expect(capturedCalls.last['orderByField'], equals('-id'));
    });

    testWidgets('sort initializes from paginateInfo orderByField descending',
        (tester) async {
      await tester.pumpWidget(_testHarness(
        MoquiWidgetFactory.build(
          WidgetNode.fromJson(const {
            '_type': 'form-list',
            'formName': 'PreSortedList',
            'listName': 'sortedList',
            'paginate': 'true',
            'paginateInfo': {
              'pageIndex': 0,
              'pageMaxIndex': 3,
              'count': 40,
              'pageRangeLow': 1,
              'pageRangeHigh': 10,
              'orderByField': '-status',
            },
            'fields': [
              {
                'name': 'name',
                'title': 'Name',
                'widgets': [
                  {'_type': 'display'}
                ],
              },
              {
                'name': 'status',
                'title': 'Status',
                'widgets': [
                  {'_type': 'display'}
                ],
              },
            ],
            'listData': [
              {'name': 'Zeta', 'status': 'Inactive'},
              {'name': 'Alpha', 'status': 'Active'},
            ],
          }),
          _stubContext(),
        ),
      ));

      final dt = tester.widget<DataTable>(find.byType(DataTable));
      expect(dt.sortColumnIndex, equals(1)); // Status is column index 1
      expect(dt.sortAscending, isFalse); // '-' prefix = descending
    });

    testWidgets('sort initializes from ascending orderByField',
        (tester) async {
      await tester.pumpWidget(_testHarness(
        MoquiWidgetFactory.build(
          WidgetNode.fromJson(const {
            '_type': 'form-list',
            'formName': 'AscSortedList',
            'listName': 'ascList',
            'paginate': 'true',
            'paginateInfo': {
              'pageIndex': 0,
              'pageMaxIndex': 0,
              'count': 2,
              'pageRangeLow': 1,
              'pageRangeHigh': 2,
              'orderByField': 'name',
            },
            'fields': [
              {
                'name': 'name',
                'title': 'Name',
                'widgets': [
                  {'_type': 'display'}
                ],
              },
            ],
            'listData': [
              {'name': 'Alpha'},
              {'name': 'Beta'},
            ],
          }),
          _stubContext(),
        ),
      ));

      final dt = tester.widget<DataTable>(find.byType(DataTable));
      expect(dt.sortColumnIndex, equals(0)); // Name is column index 0
      expect(dt.sortAscending, isTrue); // no '-' prefix = ascending
    });

    testWidgets(
        'non-existent orderByField produces -1 sortColumnIndex',
        (tester) async {
      await tester.pumpWidget(_testHarness(
        MoquiWidgetFactory.build(
          WidgetNode.fromJson(const {
            '_type': 'form-list',
            'formName': 'SafeSort',
            'listName': 'safeList',
            'paginate': 'true',
            'paginateInfo': {
              'pageIndex': 0,
              'pageMaxIndex': 0,
              'count': 1,
              'pageRangeLow': 1,
              'pageRangeHigh': 1,
              'orderByField': 'nonExistentField',
            },
            'fields': [
              {
                'name': 'name',
                'title': 'Name',
                'widgets': [
                  {'_type': 'display'}
                ],
              },
            ],
            'listData': [
              {'name': 'test'},
            ],
          }),
          _stubContext(),
        ),
      ));

      // indexWhere returns -1 when field not found, code converts to null
      final dt = tester.widget<DataTable>(find.byType(DataTable));
      expect(dt.sortColumnIndex, isNull);
    });
  });

  // ===========================================================================
  // FORM-LIST INLINE EDITING
  // ===========================================================================

  group('Form-List Inline Editing', () {
    testWidgets(
        'text-line cells render as TextFormField in editable form-list',
        (tester) async {
      await tester.pumpWidget(_testHarness(
        MoquiWidgetFactory.build(
          WidgetNode.fromJson(const {
            '_type': 'form-list',
            'formName': 'EditableList',
            'listName': 'editList',
            'transition': 'updateRows',
            'skipForm': 'false',
            'fields': [
              {
                'name': 'name',
                'title': 'Name',
                'widgets': [
                  {'_type': 'text-line'}
                ],
              },
              {
                'name': 'value',
                'title': 'Value',
                'widgets': [
                  {'_type': 'text-line'}
                ],
              },
            ],
            'listData': [
              {'name': 'key1', 'value': 'val1'},
              {'name': 'key2', 'value': 'val2'},
            ],
          }),
          _stubContext(),
        ),
      ));

      // 2 rows x 2 editable fields = 4 TextFormFields
      expect(find.byType(TextFormField), findsNWidgets(4));
    });

    testWidgets('skip-form form-list renders text-line as plain Text',
        (tester) async {
      await tester.pumpWidget(_testHarness(
        MoquiWidgetFactory.build(
          WidgetNode.fromJson(const {
            '_type': 'form-list',
            'formName': 'ReadOnlyList',
            'listName': 'readList',
            'skipForm': 'true',
            'fields': [
              {
                'name': 'name',
                'title': 'Name',
                'widgets': [
                  {'_type': 'text-line'}
                ],
              },
            ],
            'listData': [
              {'name': 'readOnlyVal'},
            ],
          }),
          _stubContext(),
        ),
      ));

      // skip-form should render text-line as plain Text, not TextFormField
      expect(find.byType(TextFormField), findsNothing);
      expect(find.text('readOnlyVal'), findsOneWidget);
    });

    testWidgets(
        'drop-down cells render as DropdownButtonFormField in editable list',
        (tester) async {
      await tester.pumpWidget(_testHarness(
        MoquiWidgetFactory.build(
          WidgetNode.fromJson(const {
            '_type': 'form-list',
            'formName': 'DropdownList',
            'listName': 'ddList',
            'transition': 'updateItems',
            'skipForm': 'false',
            'fields': [
              {
                'name': 'status',
                'title': 'Status',
                'widgets': [
                  {
                    '_type': 'drop-down',
                    'options': [
                      {'key': 'active', 'text': 'Active'},
                      {'key': 'inactive', 'text': 'Inactive'},
                    ],
                  }
                ],
              },
            ],
            'listData': [
              {'status': 'active'},
            ],
          }),
          _stubContext(),
        ),
      ));

      expect(
          find.byType(DropdownButtonFormField<String>), findsOneWidget);
    });

    testWidgets('check cells render as CheckboxListTile in editable list',
        (tester) async {
      // Suppress overflow errors since CheckboxListTile in DataCell
      // will overflow in test environment due to constrained row height
      final oldHandler = FlutterError.onError;
      FlutterError.onError = (details) {
        if (details.toString().contains('overflowed')) return;
        oldHandler?.call(details);
      };
      addTearDown(() => FlutterError.onError = oldHandler);

      await tester.pumpWidget(_testHarness(
        MoquiWidgetFactory.build(
          WidgetNode.fromJson(const {
            '_type': 'form-list',
            'formName': 'CheckList',
            'listName': 'chkList',
            'transition': 'updateChecks',
            'skipForm': 'false',
            'fields': [
              {
                'name': 'active',
                'title': 'Active',
                'widgets': [
                  {
                    '_type': 'check',
                    'options': [
                      {'key': 'Y', 'text': 'Yes'},
                    ],
                  }
                ],
              },
            ],
            'listData': [
              {'active': 'Y'},
            ],
          }),
          _stubContext(),
        ),
      ));

      // _buildCheck renders CheckboxListTile for each option
      expect(find.byType(CheckboxListTile), findsOneWidget);
    });

    testWidgets('editable cell value is pre-populated from row data',
        (tester) async {
      await tester.pumpWidget(_testHarness(
        MoquiWidgetFactory.build(
          WidgetNode.fromJson(const {
            '_type': 'form-list',
            'formName': 'PrePopList',
            'listName': 'prepopList',
            'transition': 'save',
            'skipForm': 'false',
            'fields': [
              {
                'name': 'description',
                'title': 'Description',
                'widgets': [
                  {'_type': 'text-line'}
                ],
              },
            ],
            'listData': [
              {'description': 'Original value'},
            ],
          }),
          _stubContext(),
        ),
      ));

      // The TextFormField should show the pre-populated value
      final tf = tester.widget<TextFormField>(find.byType(TextFormField));
      expect(tf.initialValue, equals('Original value'));
    });
  });

  // ===========================================================================
  // FORM-SINGLE WITH FIELD LAYOUT + VALIDATION
  // ===========================================================================

  group('Form-Single Field Layout with Validation', () {
    testWidgets('field-row layout validates required fields on submit',
        (tester) async {
      bool submitCalled = false;

      final ctx = _stubContext(
        submitForm: (url, data) async {
          submitCalled = true;
          return null;
        },
      );

      await tester.pumpWidget(_testHarness(
        MoquiWidgetFactory.build(
          WidgetNode.fromJson(const {
            '_type': 'form-single',
            'formName': 'LayoutForm',
            'transition': 'saveLayout',
            'fields': [
              {
                'name': 'firstName',
                'title': 'First Name',
                'widgets': [
                  {'_type': 'text-line', 'required': 'true'}
                ],
              },
              {
                'name': 'lastName',
                'title': 'Last Name',
                'widgets': [
                  {'_type': 'text-line', 'required': 'true'}
                ],
              },
              {
                'name': 'nickname',
                'title': 'Nickname',
                'widgets': [
                  {'_type': 'text-line'}
                ],
              },
              {
                'name': 'submit',
                'title': 'Save',
                'widgets': [
                  {'_type': 'submit', 'text': 'Save'}
                ],
              },
            ],
            'fieldLayout': {
              'rows': [
                {
                  '_type': 'field-row',
                  'fields': [
                    {'name': 'firstName'},
                    {'name': 'lastName'}
                  ]
                },
                {'_type': 'field-ref', 'name': 'nickname'},
                {'_type': 'field-ref', 'name': 'submit'},
              ],
            },
          }),
          ctx,
        ),
      ));

      // All 3 text fields should be rendered
      expect(find.byType(TextFormField), findsNWidgets(3));

      // Try to submit without filling required fields
      await tester.tap(_findButtonWithText('Save').first);
      await tester.pumpAndSettle();

      expect(submitCalled, isFalse);
      expect(find.text('First Name is required'), findsOneWidget);
      expect(find.text('Last Name is required'), findsOneWidget);
      expect(find.text('Nickname is required'), findsNothing);
    });
  });

  // ===========================================================================
  // MODEL PARSING - Phase 6 Enhancements
  // ===========================================================================

  group('Model Parsing - Phase 6', () {
    test('FieldWidget required attribute is accessible', () {
      final fw = FieldWidget.fromJson(const {
        '_type': 'text-line',
        'required': 'true',
        'minlength': '5',
        'maxlength': '100',
        'regexp': r'^\w+$',
      });

      expect(fw.boolAttr('required'), isTrue);
      expect(fw.attr('minlength'), equals('5'));
      expect(fw.attr('maxlength'), equals('100'));
      expect(fw.attr('regexp'), equals(r'^\w+$'));
    });

    test('FieldWidget dependsOn list is parsed', () {
      final fw = FieldWidget.fromJson(const {
        '_type': 'drop-down',
        'dependsOnList': [
          {'field': 'parentId', 'parameter': 'parent'},
        ],
      });

      expect(fw.dependsOn.length, equals(1));
      expect(fw.dependsOn.first.field, equals('parentId'));
      expect(fw.dependsOn.first.parameter, equals('parent'));
    });

    test('DynamicOptionsConfig is parsed from widget', () {
      final fw = FieldWidget.fromJson(const {
        '_type': 'drop-down',
        'dynamicOptions': {
          'transition': 'getOptions',
          'serverSearch': 'true',
          'minLength': '2',
        },
      });

      expect(fw.dynamicOptions, isNotNull);
      expect(fw.dynamicOptions!.transition, equals('getOptions'));
      expect(fw.dynamicOptions!.serverSearch, isTrue);
      expect(fw.dynamicOptions!.minLength, equals(2));
    });

    test('AutocompleteConfig is parsed from widget', () {
      final fw = FieldWidget.fromJson(const {
        '_type': 'text-find-autocomplete',
        'autocomplete': {
          'transition': 'searchEntities',
          'delay': '500',
          'minLength': '3',
          'showValue': 'true',
        },
      });

      expect(fw.autocomplete, isNotNull);
      expect(fw.autocomplete!.transition, equals('searchEntities'));
      expect(fw.autocomplete!.delay, equals(500));
      expect(fw.autocomplete!.minLength, equals(3));
      expect(fw.autocomplete!.showValue, isTrue);
    });

    test('TransitionResponse with empty lists', () {
      final resp = TransitionResponse();
      expect(resp.hasErrors, isFalse);
      expect(resp.hasMessages, isFalse);
      expect(resp.screenUrl, isEmpty);
      expect(resp.errors, isEmpty);
      expect(resp.messages, isEmpty);
    });

    test('TransitionResponse with errors', () {
      final resp = TransitionResponse(errors: ['Bad input']);
      expect(resp.hasErrors, isTrue);
      expect(resp.hasMessages, isFalse);
      expect(resp.errors.length, equals(1));
    });

    test('TransitionResponse with messages and screenUrl', () {
      final resp = TransitionResponse(
        messages: ['Created successfully'],
        screenUrl: '/app/entity/view',
        screenParameters: {'entityId': '42'},
      );
      expect(resp.hasErrors, isFalse);
      expect(resp.hasMessages, isTrue);
      expect(resp.screenUrl, equals('/app/entity/view'));
      expect(resp.screenParameters['entityId'], equals('42'));
    });
  });

  // ===========================================================================
  // EDGE CASES
  // ===========================================================================

  group('Phase 6 Edge Cases', () {
    testWidgets('empty transition skips form submission', (tester) async {
      bool submitCalled = false;

      final ctx = _stubContext(
        submitForm: (url, data) async {
          submitCalled = true;
          return null;
        },
      );

      await tester.pumpWidget(_testHarness(
        MoquiWidgetFactory.build(
          WidgetNode.fromJson(const {
            '_type': 'form-single',
            'formName': 'NoTransition',
            'transition': '',
            'fields': [
              {
                'name': 'data',
                'title': 'Data',
                'widgets': [
                  {'_type': 'text-line'}
                ],
              },
              {
                'name': 'submit',
                'title': 'Go',
                'widgets': [
                  {'_type': 'submit', 'text': 'Go'}
                ],
              },
            ],
          }),
          ctx,
        ),
      ));

      await tester.enterText(find.byType(TextFormField).first, 'test');
      await tester.pump();
      await tester.tap(_findButtonWithText('Go').first);
      await tester.pumpAndSettle();

      expect(submitCalled, isFalse);
    });

    testWidgets('form-single with hidden field includes it in form data',
        (tester) async {
      Map<String, dynamic>? capturedData;

      final ctx = _stubContext(
        submitForm: (url, data) async {
          capturedData = data;
          return null;
        },
      );

      await tester.pumpWidget(_testHarness(
        MoquiWidgetFactory.build(
          WidgetNode.fromJson(const {
            '_type': 'form-single',
            'formName': 'HiddenForm',
            'transition': 'processHidden',
            'fields': [
              {
                'name': 'visibleField',
                'title': 'Visible',
                'widgets': [
                  {'_type': 'text-line'}
                ],
              },
              {
                'name': 'hiddenId',
                'title': 'ID',
                'currentValue': '42',
                'widgets': [
                  {'_type': 'hidden'}
                ],
              },
              {
                'name': 'submit',
                'title': 'Submit',
                'widgets': [
                  {'_type': 'submit', 'text': 'Submit'}
                ],
              },
            ],
          }),
          ctx,
        ),
      ));

      await tester.enterText(find.byType(TextFormField).first, 'visible');
      await tester.pump();

      await tester.tap(_findButtonWithText('Submit').first);
      await tester.pumpAndSettle();

      expect(capturedData?['hiddenId'], equals('42'));
      expect(capturedData?['visibleField'], equals('visible'));
    });

    testWidgets('form-list with no listData renders empty table',
        (tester) async {
      await tester.pumpWidget(_testHarness(
        MoquiWidgetFactory.build(
          WidgetNode.fromJson(const {
            '_type': 'form-list',
            'formName': 'EmptyList',
            'listName': 'emptyList',
            'fields': [
              {
                'name': 'col1',
                'title': 'Column 1',
                'widgets': [
                  {'_type': 'display'}
                ],
              },
            ],
            'listData': [],
          }),
          _stubContext(),
        ),
      ));

      // DataTable should exist with an empty-state row ("No records found")
      final dt = tester.widget<DataTable>(find.byType(DataTable));
      expect(dt.rows, hasLength(1));
      expect(find.text('No records found'), findsOneWidget);
    });
  });
}
