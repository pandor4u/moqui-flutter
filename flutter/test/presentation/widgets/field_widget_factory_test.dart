import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moqui_flutter/domain/screen/screen_models.dart';
import 'package:moqui_flutter/presentation/widgets/fields/field_widget_factory.dart';
import 'package:moqui_flutter/presentation/widgets/moqui/widget_factory.dart';

/// A helper that wraps a widget in MaterialApp with a Form ancestor for testing.
Widget _testHarness(Widget child) {
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

/// Stub render context.
MoquiRenderContext _stubContext() {
  return MoquiRenderContext(
    navigate: (path, {params}) {},
    submitForm: (url, data) async { return null; },
    loadDynamic: (transition, params) async => <String, dynamic>{},
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
  group('FieldWidgetFactory — text-line', () {
    testWidgets('renders text input with label', (tester) async {
      final field = _makeField('username', 'text-line', title: 'Username');

      await tester.pumpWidget(_testHarness(
        FieldWidgetFactory.build(
          field: field,
          formData: {},
          onChanged: (name, value) {},
          ctx: _stubContext(),
        ),
      ));

      expect(find.text('Username'), findsOneWidget);
      expect(find.byType(TextFormField), findsOneWidget);
    });

    testWidgets('populates initial value from formData', (tester) async {
      final field = _makeField('email', 'text-line', title: 'Email');

      await tester.pumpWidget(_testHarness(
        FieldWidgetFactory.build(
          field: field,
          formData: {'email': 'test@example.com'},
          onChanged: (name, value) {},
          ctx: _stubContext(),
        ),
      ));

      expect(find.text('test@example.com'), findsOneWidget);
    });

    testWidgets('calls onChanged when text entered', (tester) async {
      String? changedName;
      dynamic changedValue;
      final field = _makeField('name', 'text-line', title: 'Name');

      await tester.pumpWidget(_testHarness(
        FieldWidgetFactory.build(
          field: field,
          formData: {},
          onChanged: (name, value) {
            changedName = name;
            changedValue = value;
          },
          ctx: _stubContext(),
        ),
      ));

      await tester.enterText(find.byType(TextFormField), 'Alice');
      expect(changedName, 'name');
      expect(changedValue, 'Alice');
    });
  });

  group('FieldWidgetFactory — text-area', () {
    testWidgets('renders multiline text field', (tester) async {
      final field = _makeField('description', 'text-area', title: 'Description');

      await tester.pumpWidget(_testHarness(
        FieldWidgetFactory.build(
          field: field,
          formData: {},
          onChanged: (name, value) {},
          ctx: _stubContext(),
        ),
      ));

      expect(find.text('Description'), findsOneWidget);
      expect(find.byType(TextFormField), findsOneWidget);
    });
  });

  group('FieldWidgetFactory — drop-down', () {
    testWidgets('renders dropdown with options', (tester) async {
      final field = _makeField(
        'status',
        'drop-down',
        title: 'Status',
        options: [
          const FieldOption(key: 'active', text: 'Active'),
          const FieldOption(key: 'inactive', text: 'Inactive'),
        ],
      );

      await tester.pumpWidget(_testHarness(
        FieldWidgetFactory.build(
          field: field,
          formData: {},
          onChanged: (name, value) {},
          ctx: _stubContext(),
        ),
      ));

      expect(find.text('Status'), findsOneWidget);
    });
  });

  group('FieldWidgetFactory — display', () {
    testWidgets('renders non-editable display text', (tester) async {
      final field = _makeField(
        'orderId',
        'display',
        title: 'Order ID',
        currentValue: 'ORD-1234',
      );

      await tester.pumpWidget(_testHarness(
        FieldWidgetFactory.build(
          field: field,
          formData: {'orderId': 'ORD-1234'},
          onChanged: (name, value) {},
          ctx: _stubContext(),
        ),
      ));

      expect(find.text('ORD-1234'), findsOneWidget);
    });
  });

  group('FieldWidgetFactory — hidden', () {
    testWidgets('renders SizedBox.shrink for hidden field', (tester) async {
      final field = _makeField('secretId', 'hidden');

      await tester.pumpWidget(_testHarness(
        FieldWidgetFactory.build(
          field: field,
          formData: {},
          onChanged: (name, value) {},
          ctx: _stubContext(),
        ),
      ));

      // SizedBox.shrink takes no space
      expect(find.byType(SizedBox), findsOneWidget);
    });
  });

  group('FieldWidgetFactory — ignored', () {
    testWidgets('renders SizedBox.shrink for ignored field', (tester) async {
      final field = _makeField('ignoredField', 'ignored');

      await tester.pumpWidget(_testHarness(
        FieldWidgetFactory.build(
          field: field,
          formData: {},
          onChanged: (name, value) {},
          ctx: _stubContext(),
        ),
      ));

      expect(find.byType(SizedBox), findsOneWidget);
    });
  });

  group('FieldWidgetFactory — check', () {
    testWidgets('renders checkbox with options', (tester) async {
      final field = _makeField(
        'isActive',
        'check',
        title: 'Active',
        options: [const FieldOption(key: 'Y', text: 'Yes')],
      );

      await tester.pumpWidget(_testHarness(
        FieldWidgetFactory.build(
          field: field,
          formData: {},
          onChanged: (name, value) {},
          ctx: _stubContext(),
        ),
      ));

      expect(find.byType(CheckboxListTile), findsOneWidget);
      expect(find.text('Yes'), findsOneWidget);
    });

    testWidgets('checkbox responds to tap', (tester) async {
      String? changedName;
      dynamic changedValue;
      final field = _makeField(
        'isActive',
        'check',
        title: 'Active',
        options: [const FieldOption(key: 'Y', text: 'Yes')],
      );

      await tester.pumpWidget(_testHarness(
        FieldWidgetFactory.build(
          field: field,
          formData: {},
          onChanged: (name, value) {
            changedName = name;
            changedValue = value;
          },
          ctx: _stubContext(),
        ),
      ));

      await tester.tap(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();

      expect(changedName, 'isActive');
      expect(changedValue, isNotNull);
    });
  });

  group('FieldWidgetFactory — password', () {
    testWidgets('renders obscured text field', (tester) async {
      final field = _makeField('password', 'password', title: 'Password');

      await tester.pumpWidget(_testHarness(
        FieldWidgetFactory.build(
          field: field,
          formData: {},
          onChanged: (name, value) {},
          ctx: _stubContext(),
        ),
      ));

      expect(find.text('Password'), findsOneWidget);
      expect(find.byType(TextFormField), findsOneWidget);
    });
  });

  group('FieldWidgetFactory — submit', () {
    testWidgets('renders submit button with text', (tester) async {
      final field = _makeField(
        'submitBtn',
        'submit',
        title: 'Save',
        widgetAttrs: {'transition': 'saveOrder', 'text': 'Save'},
      );

      final widget = FieldWidgetFactory.build(
        field: field,
        formData: {},
        onChanged: (name, value) {},
        ctx: _stubContext(),
      );

      await tester.pumpWidget(_testHarness(widget));
      await tester.pumpAndSettle();

      // The submit widget uses Builder → Padding → ElevatedButton.icon
      // Just ensure it renders without crashing and contains the text
      expect(find.text('Save'), findsOneWidget);
    });
  });

  group('FieldWidgetFactory — empty widgets', () {
    testWidgets('renders SizedBox.shrink when field has no widgets', (tester) async {
      const field = FieldDefinition(name: 'empty', widgets: []);

      await tester.pumpWidget(_testHarness(
        FieldWidgetFactory.build(
          field: field,
          formData: {},
          onChanged: (name, value) {},
          ctx: _stubContext(),
        ),
      ));

      expect(find.byType(SizedBox), findsOneWidget);
    });
  });

  group('FieldWidgetFactory — unknown type', () {
    testWidgets('renders default text field for unknown type', (tester) async {
      final field = _makeField('custom', 'some-unknown-widget-type', title: 'Custom');

      await tester.pumpWidget(_testHarness(
        FieldWidgetFactory.build(
          field: field,
          formData: {},
          onChanged: (name, value) {},
          ctx: _stubContext(),
        ),
      ));

      // Should render without crashing
      expect(tester.takeException(), isNull);
    });
  });

  group('FieldWidgetFactory — date-time', () {
    testWidgets('renders date picker field', (tester) async {
      final field = _makeField('orderDate', 'date-time', title: 'Order Date');

      await tester.pumpWidget(_testHarness(
        FieldWidgetFactory.build(
          field: field,
          formData: {},
          onChanged: (name, value) {},
          ctx: _stubContext(),
        ),
      ));

      expect(find.text('Order Date'), findsOneWidget);
    });
  });

  group('FieldWidgetFactory — file', () {
    testWidgets('renders file upload widget', (tester) async {
      final field = _makeField('attachment', 'file', title: 'Upload File');

      await tester.pumpWidget(_testHarness(
        FieldWidgetFactory.build(
          field: field,
          formData: {},
          onChanged: (name, value) {},
          ctx: _stubContext(),
        ),
      ));

      // Should render some form of file picker or button
      expect(tester.takeException(), isNull);
    });
  });
}
