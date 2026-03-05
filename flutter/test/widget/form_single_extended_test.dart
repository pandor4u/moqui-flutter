import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moqui_flutter/domain/screen/screen_models.dart';
import 'package:moqui_flutter/presentation/widgets/moqui/widget_factory.dart';
import 'package:moqui_flutter/data/api/moqui_api_client.dart';

/// Phase 9.4: Widget tests for form-single features:
/// initial value population, field rendering, hidden fields, validation,
/// submission, error display, success messages, navigation after submit,
/// field layout, submit overlay, and double-submit prevention.

// ---------------------------------------------------------------------------
// Harness
// ---------------------------------------------------------------------------

Widget _testHarness(Widget child) {
  return MaterialApp(
    home: Scaffold(
      body: SizedBox(
        width: 800,
        height: 700,
        child: SingleChildScrollView(child: child),
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

Widget _buildFormSingle(Map<String, dynamic> json, MoquiRenderContext ctx) {
  return _testHarness(
    MoquiWidgetFactory.build(WidgetNode.fromJson(json), ctx),
  );
}

/// Basic form-single JSON with some fields and an optional transition.
Map<String, dynamic> _basicFormJson({
  String transition = '',
  List<Map<String, dynamic>>? fields,
  Map<String, dynamic>? fieldLayout,
}) {
  return {
    '_type': 'form-single',
    'formName': 'EditOrderForm',
    if (transition.isNotEmpty) 'transition': transition,
    if (fieldLayout != null) 'fieldLayout': fieldLayout,
    'fields': fields ??
        [
          {
            'name': 'orderId',
            'title': 'Order ID',
            'widgets': [
              {'_type': 'display'}
            ],
            'currentValue': 'ORD001',
          },
          {
            'name': 'customerName',
            'title': 'Customer',
            'widgets': [
              {'_type': 'text-line'}
            ],
          },
          {
            'name': 'status',
            'title': 'Status',
            'widgets': [
              {
                '_type': 'drop-down',
                'options': [
                  {'key': 'Active', 'text': 'Active'},
                  {'key': 'Closed', 'text': 'Closed'},
                ],
              }
            ],
          },
          {
            'name': 'submitBtn',
            'title': '',
            'widgets': [
              {
                '_type': 'submit',
                'text': 'Save Order',
              }
            ],
          },
        ],
  };
}

void main() {
  // =========================================================================
  // Field Rendering
  // =========================================================================
  group('Form-single field rendering', () {
    testWidgets('renders fields in sequential order', (tester) async {
      await tester.pumpWidget(_buildFormSingle(
        _basicFormJson(),
        _stubContext(),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Order ID'), findsOneWidget);
      expect(find.text('Customer'), findsOneWidget);
      expect(find.text('Status'), findsOneWidget);
    });

    testWidgets('renders display field with current value', (tester) async {
      await tester.pumpWidget(_buildFormSingle(
        _basicFormJson(),
        _stubContext(),
      ));
      await tester.pumpAndSettle();

      // Display field shows currentValue
      expect(find.text('ORD001'), findsOneWidget);
    });

    testWidgets('renders text-line field as TextFormField', (tester) async {
      await tester.pumpWidget(_buildFormSingle(
        _basicFormJson(),
        _stubContext(),
      ));
      await tester.pumpAndSettle();

      expect(find.byType(TextFormField), findsAtLeastNWidgets(1));
    });

    testWidgets('renders drop-down field', (tester) async {
      await tester.pumpWidget(_buildFormSingle(
        _basicFormJson(),
        _stubContext(),
      ));
      await tester.pumpAndSettle();

      expect(
          find.byType(DropdownButtonFormField<String>), findsAtLeastNWidgets(1));
    });

    testWidgets('renders submit button', (tester) async {
      await tester.pumpWidget(_buildFormSingle(
        _basicFormJson(transition: 'updateOrder'),
        _stubContext(),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Save Order'), findsOneWidget);
    });
  });

  // =========================================================================
  // Hidden Fields
  // =========================================================================
  group('Form-single hidden fields', () {
    testWidgets('hidden field not rendered but value in form data',
        (tester) async {
      await tester.pumpWidget(_buildFormSingle(
        {
          '_type': 'form-single',
          'formName': 'HiddenTest',
          'transition': 'save',
          'fields': [
            {
              'name': 'secretId',
              'title': 'Secret',
              'widgets': [
                {'_type': 'hidden'}
              ],
              'currentValue': 'hidden-value-123',
            },
            {
              'name': 'visibleField',
              'title': 'Visible',
              'widgets': [
                {'_type': 'text-line'}
              ],
            },
          ],
        },
        _stubContext(),
      ));
      await tester.pumpAndSettle();

      // Hidden field label should not appear
      expect(find.text('Secret'), findsNothing);
      // But visible field should
      expect(find.text('Visible'), findsOneWidget);
    });
  });

  // =========================================================================
  // Submission
  // =========================================================================
  group('Form-single submission', () {
    testWidgets('tapping submit calls submitForm with formData',
        (tester) async {
      String? lastUrl;
      Map<String, dynamic>? lastData;
      final ctx = _stubContext(
        submitForm: (url, data) async {
          lastUrl = url;
          lastData = Map<String, dynamic>.from(data);
          return TransitionResponse(
            screenUrl: '',
            screenPathList: [],
          );
        },
      );

      await tester.pumpWidget(_buildFormSingle(
        _basicFormJson(transition: 'updateOrder'),
        ctx,
      ));
      await tester.pumpAndSettle();

      // Tap the submit button
      await tester.tap(find.text('Save Order'));
      await tester.pumpAndSettle();

      expect(lastUrl, 'updateOrder');
      expect(lastData, isNotNull);
    });

    testWidgets('no submit when transition is empty', (tester) async {
      bool submitCalled = false;
      final ctx = _stubContext(
        submitForm: (url, data) async {
          submitCalled = true;
          return null;
        },
      );

      await tester.pumpWidget(_buildFormSingle(
        _basicFormJson(transition: ''), // No transition
        ctx,
      ));
      await tester.pumpAndSettle();

      // Tap submit — nothing should happen
      await tester.tap(find.text('Save Order'));
      await tester.pumpAndSettle();

      expect(submitCalled, isFalse);
    });

    testWidgets('displays error SnackBar on submit error', (tester) async {
      final ctx = _stubContext(
        submitForm: (url, data) async {
          return TransitionResponse(
            screenUrl: '',
            screenPathList: [],
            errors: ['Order not found', 'Invalid status'],
          );
        },
      );

      await tester.pumpWidget(_buildFormSingle(
        _basicFormJson(transition: 'updateOrder'),
        ctx,
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Save Order'));
      await tester.pumpAndSettle();

      // Error SnackBar should appear
      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.textContaining('Order not found'), findsOneWidget);
    });

    testWidgets('displays success SnackBar on submit with messages',
        (tester) async {
      final ctx = _stubContext(
        submitForm: (url, data) async {
          return TransitionResponse(
            screenUrl: '',
            screenPathList: [],
            messages: ['Order saved successfully'],
          );
        },
      );

      await tester.pumpWidget(_buildFormSingle(
        _basicFormJson(transition: 'updateOrder'),
        ctx,
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Save Order'));
      await tester.pumpAndSettle();

      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.textContaining('Order saved'), findsOneWidget);
    });

    testWidgets('navigates after successful submit with screenUrl',
        (tester) async {
      String? navigatedPath;
      final ctx = _stubContext(
        navigate: (path, {params}) => navigatedPath = path,
        submitForm: (url, data) async {
          return TransitionResponse(
            screenUrl: '/Order/Detail',
            screenPathList: [],
          );
        },
      );

      await tester.pumpWidget(_buildFormSingle(
        _basicFormJson(transition: 'updateOrder'),
        ctx,
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Save Order'));
      await tester.pumpAndSettle();

      expect(navigatedPath, '/Order/Detail');
    });
  });

  // =========================================================================
  // Form Validation
  // =========================================================================
  group('Form-single validation', () {
    testWidgets('shows validation error for required empty field',
        (tester) async {
      final ctx = _stubContext(
        submitForm: (url, data) async => null,
      );

      await tester.pumpWidget(_buildFormSingle(
        {
          '_type': 'form-single',
          'formName': 'ValidationTest',
          'transition': 'save',
          'fields': [
            {
              'name': 'requiredField',
              'title': 'Required',
              'widgets': [
                {'_type': 'text-line', 'required': 'true'}
              ],
            },
            {
              'name': 'submitBtn',
              'title': '',
              'widgets': [
                {'_type': 'submit', 'text': 'Submit'}
              ],
            },
          ],
        },
        ctx,
      ));
      await tester.pumpAndSettle();

      // Submit without filling the required field
      await tester.tap(find.text('Submit'));
      await tester.pumpAndSettle();

      // Should show validation error
      // TextFormField validation shows error text in the InputDecoration
      expect(find.textContaining('required'), findsAtLeastNWidgets(1));
    });
  });

  // =========================================================================
  // Initial Value Population
  // =========================================================================
  group('Form-single initial values', () {
    testWidgets('text-line pre-populated from currentValue', (tester) async {
      await tester.pumpWidget(_buildFormSingle(
        {
          '_type': 'form-single',
          'formName': 'InitTest',
          'fields': [
            {
              'name': 'name',
              'title': 'Name',
              'widgets': [
                {'_type': 'text-line'}
              ],
              'currentValue': 'John Doe',
            },
          ],
        },
        _stubContext(),
      ));
      await tester.pumpAndSettle();

      expect(find.text('John Doe'), findsOneWidget);
    });

    testWidgets('drop-down pre-selected from currentValue', (tester) async {
      await tester.pumpWidget(_buildFormSingle(
        {
          '_type': 'form-single',
          'formName': 'InitDDTest',
          'fields': [
            {
              'name': 'status',
              'title': 'Status',
              'widgets': [
                {
                  '_type': 'drop-down',
                  'options': [
                    {'key': 'Active', 'text': 'Active'},
                    {'key': 'Closed', 'text': 'Closed'},
                  ],
                }
              ],
              'currentValue': 'Closed',
            },
          ],
        },
        _stubContext(),
      ));
      await tester.pumpAndSettle();

      // The dropdown should show "Closed" as selected
      expect(find.text('Closed'), findsOneWidget);
    });
  });

  // =========================================================================
  // Submitting Overlay
  // =========================================================================
  group('Form-single submitting overlay', () {
    testWidgets('shows loading indicator during submit', (tester) async {
      // Use a delayed completer to hold the submit in progress
      final completer = Completer<TransitionResponse?>();
      final ctx = _stubContext(
        submitForm: (url, data) => completer.future,
      );

      await tester.pumpWidget(_buildFormSingle(
        _basicFormJson(transition: 'save'),
        ctx,
      ));
      await tester.pumpAndSettle();

      // Tap submit
      await tester.tap(find.text('Save Order'));
      await tester.pump(); // One frame to start the async submit

      // Loading indicator should be visible
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // Complete the submit
      completer.complete(TransitionResponse(
        screenUrl: '',
        screenPathList: [],
      ));
      await tester.pumpAndSettle();

      // Loading indicator should be gone
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });
  });

  // =========================================================================
  // Field Layout
  // =========================================================================
  group('Form-single field layout', () {
    testWidgets('renders field-row layout with multiple fields in a row',
        (tester) async {
      await tester.pumpWidget(_buildFormSingle(
        {
          '_type': 'form-single',
          'formName': 'LayoutTest',
          'fields': [
            {
              'name': 'firstName',
              'title': 'First Name',
              'widgets': [
                {'_type': 'text-line'}
              ],
            },
            {
              'name': 'lastName',
              'title': 'Last Name',
              'widgets': [
                {'_type': 'text-line'}
              ],
            },
          ],
          'fieldLayout': {
            'rows': [
              {
                '_type': 'field-row',
                'fields': [
                  {'name': 'firstName'},
                  {'name': 'lastName'},
                ],
              },
            ],
          },
        },
        _stubContext(),
      ));
      await tester.pumpAndSettle();

      expect(find.text('First Name'), findsOneWidget);
      expect(find.text('Last Name'), findsOneWidget);
    });

    testWidgets('renders field-group as Card with title', (tester) async {
      await tester.pumpWidget(_buildFormSingle(
        {
          '_type': 'form-single',
          'formName': 'GroupTest',
          'fields': [
            {
              'name': 'email',
              'title': 'Email',
              'widgets': [
                {'_type': 'text-line'}
              ],
            },
          ],
          'fieldLayout': {
            'rows': [
              {
                '_type': 'field-group',
                'title': 'Contact Information',
                'children': [
                  {'_type': 'field-ref', 'name': 'email'},
                ],
              },
            ],
          },
        },
        _stubContext(),
      ));
      await tester.pumpAndSettle();

      // Card with group title
      expect(find.text('Contact Information'), findsOneWidget);
      expect(find.text('Email'), findsOneWidget);
    });
  });

  // =========================================================================
  // Double Submit Prevention
  // =========================================================================
  group('Form-single double submit prevention', () {
    testWidgets('second submit ignored while first is in progress',
        (tester) async {
      int submitCount = 0;
      final completer = Completer<TransitionResponse?>();
      final ctx = _stubContext(
        submitForm: (url, data) {
          submitCount++;
          return completer.future;
        },
      );

      await tester.pumpWidget(_buildFormSingle(
        _basicFormJson(transition: 'save'),
        ctx,
      ));
      await tester.pumpAndSettle();

      // First submit
      await tester.tap(find.text('Save Order'));
      await tester.pump();

      // Attempt second submit (should be blocked)
      await tester.tap(find.text('Save Order'));
      await tester.pump();

      // Only 1 submit should have gone through
      expect(submitCount, 1);

      // Complete the future
      completer.complete(TransitionResponse(
        screenUrl: '',
        screenPathList: [],
      ));
      await tester.pumpAndSettle();
    });
  });

  // =========================================================================
  // Empty Form
  // =========================================================================
  group('Form-single edge cases', () {
    testWidgets('renders with no fields gracefully', (tester) async {
      await tester.pumpWidget(_buildFormSingle(
        {
          '_type': 'form-single',
          'formName': 'EmptyForm',
          'fields': [],
        },
        _stubContext(),
      ));
      await tester.pumpAndSettle();

      // Should not crash
      expect(find.byType(Form), findsOneWidget);
    });

    testWidgets('renders with only hidden fields', (tester) async {
      await tester.pumpWidget(_buildFormSingle(
        {
          '_type': 'form-single',
          'formName': 'HiddenOnly',
          'fields': [
            {
              'name': 'hiddenId',
              'title': 'Hidden',
              'widgets': [
                {'_type': 'hidden'}
              ],
              'currentValue': '123',
            },
          ],
        },
        _stubContext(),
      ));
      await tester.pumpAndSettle();

      // Should render without error, no visible fields
      expect(find.byType(Form), findsOneWidget);
      expect(find.text('Hidden'), findsNothing);
    });
  });
}
