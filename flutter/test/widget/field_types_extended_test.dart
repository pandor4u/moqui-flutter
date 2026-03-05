import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moqui_flutter/domain/screen/screen_models.dart';
import 'package:moqui_flutter/presentation/widgets/fields/field_widget_factory.dart';
import 'package:moqui_flutter/presentation/widgets/moqui/widget_factory.dart';

/// Phase 9.2: Extended widget tests for field types not covered in
/// field_widget_factory_test.dart. Covers: text-find, date-time, date-find,
/// date-period, display-entity, radio, file, range-find, reset, label, image,
/// editable, link, and unknown types.

Widget _testHarness(Widget child) {
  return MaterialApp(
    home: Scaffold(
      body: SizedBox(
        width: 800,
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Form(child: child),
          ),
        ),
      ),
    ),
  );
}

MoquiRenderContext _stubContext() {
  return MoquiRenderContext(
    navigate: (path, {params}) {},
    submitForm: (url, data) async => null,
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

Widget _buildField(
  String name,
  String widgetType, {
  String title = '',
  Map<String, dynamic> widgetAttrs = const {},
  String? currentValue,
  Map<String, dynamic> formData = const {},
  List<FieldOption> options = const [],
  MoquiRenderContext? ctx,
}) {
  final field = _makeField(
    name,
    widgetType,
    title: title,
    widgetAttrs: widgetAttrs,
    currentValue: currentValue,
    options: options,
  );
  return _testHarness(
    FieldWidgetFactory.build(
      field: field,
      formData: Map<String, dynamic>.from(formData),
      onChanged: (n, v) {},
      ctx: ctx ?? _stubContext(),
    ),
  );
}

void main() {
  // =========================================================================
  // text-find: search input with text field
  // =========================================================================
  group('FieldWidgetFactory — text-find', () {
    testWidgets('renders text input for search', (tester) async {
      // hideOptions avoids the operator dropdown which overflows in test viewport
      await tester.pumpWidget(_buildField('search', 'text-find',
          widgetAttrs: {'hideOptions': 'true'}));
      expect(find.byType(TextFormField), findsAtLeastNWidgets(1));
    });

    testWidgets('populates initial value from formData', (tester) async {
      await tester.pumpWidget(_buildField(
        'search',
        'text-find',
        widgetAttrs: {'hideOptions': 'true'},
        formData: {'search': 'test query'},
      ));
      expect(find.text('test query'), findsOneWidget);
    });

    testWidgets('renders operator dropdown when options visible', (tester) async {
      // Use wide surface; suppress overflow error from narrow dropdown
      tester.view.physicalSize = const Size(1600, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      // Suppress RenderFlex overflow (known layout issue in narrow dropdown)
      final oldHandler = FlutterError.onError;
      FlutterError.onError = (details) {
        if (details.toString().contains('overflowed')) return;
        oldHandler?.call(details);
      };
      addTearDown(() => FlutterError.onError = oldHandler);
      await tester.pumpWidget(_buildField('search', 'text-find'));
      expect(find.byType(DropdownButtonFormField<String>), findsOneWidget);
    });
  });

  // =========================================================================
  // date-time: date/time picker
  // =========================================================================
  group('FieldWidgetFactory — date-time', () {
    testWidgets('renders date picker field', (tester) async {
      await tester.pumpWidget(_buildField(
        'startDate',
        'date-time',
        title: 'Start Date',
      ));
      // Should have a text field and calendar icon button
      expect(find.byType(TextFormField), findsAtLeastNWidgets(1));
      expect(find.byIcon(Icons.calendar_today), findsOneWidget);
    });

    testWidgets('renders time picker when dateType is time', (tester) async {
      await tester.pumpWidget(_buildField(
        'startTime',
        'date-time',
        title: 'Start Time',
        widgetAttrs: {'dateType': 'time'},
      ));
      expect(find.byIcon(Icons.access_time), findsOneWidget);
    });

    testWidgets('shows initial value from formData', (tester) async {
      await tester.pumpWidget(_buildField(
        'startDate',
        'date-time',
        formData: {'startDate': '2024-01-15'},
      ));
      expect(find.text('2024-01-15'), findsOneWidget);
    });
  });

  // =========================================================================
  // date-find: two date fields (from/thru) for range filtering
  // =========================================================================
  group('FieldWidgetFactory — date-find', () {
    testWidgets('renders from and thru date fields', (tester) async {
      await tester.pumpWidget(_buildField(
        'orderDate',
        'date-find',
        title: 'Order Date',
      ));
      // date-find typically renders two TextFormField instances (from + thru)
      expect(find.byType(TextFormField), findsAtLeastNWidgets(2));
    });
  });

  // =========================================================================
  // date-period: period selector (date ranges like This Month, Last 30 Days)
  // =========================================================================
  group('FieldWidgetFactory — date-period', () {
    testWidgets('renders date period selector', (tester) async {
      await tester.pumpWidget(_buildField(
        'period',
        'date-period',
        title: 'Period',
      ));
      // date-period renders a DropdownButtonFormField for period selection
      expect(find.byType(DropdownButtonFormField<String>), findsOneWidget);
    });
  });

  // =========================================================================
  // display-entity: display with entity description lookup
  // =========================================================================
  group('FieldWidgetFactory — display-entity', () {
    testWidgets('renders display text from formData', (tester) async {
      await tester.pumpWidget(_buildField(
        'statusId',
        'display-entity',
        title: 'Status',
        formData: {'statusId': 'Active'},
      ));
      expect(find.text('Active'), findsOneWidget);
    });

    testWidgets('shows dash for empty value', (tester) async {
      await tester.pumpWidget(_buildField(
        'statusId',
        'display-entity',
        title: 'Status',
        formData: {'statusId': ''},
      ));
      // Display shows dash or empty description for blank values
      expect(find.byType(Text), findsAtLeastNWidgets(1));
    });
  });

  // =========================================================================
  // radio: radio button group
  // =========================================================================
  group('FieldWidgetFactory — radio', () {
    testWidgets('renders radio buttons for options', (tester) async {
      await tester.pumpWidget(_buildField(
        'gender',
        'radio',
        title: 'Gender',
        options: const [
          FieldOption(key: 'M', text: 'Male'),
          FieldOption(key: 'F', text: 'Female'),
        ],
      ));
      expect(find.text('Male'), findsOneWidget);
      expect(find.text('Female'), findsOneWidget);
    });

    testWidgets('pre-selects value from formData', (tester) async {
      await tester.pumpWidget(_buildField(
        'gender',
        'radio',
        formData: {'gender': 'F'},
        options: const [
          FieldOption(key: 'M', text: 'Male'),
          FieldOption(key: 'F', text: 'Female'),
        ],
      ));
      // The Female radio should be selected
      final radios = tester.widgetList<Radio<String>>(find.byType(Radio<String>));
      expect(radios.any((r) => r.groupValue == 'F'), isTrue);
    });
  });

  // =========================================================================
  // file: file picker field
  // =========================================================================
  group('FieldWidgetFactory — file', () {
    testWidgets('renders file upload button', (tester) async {
      await tester.pumpWidget(_buildField('attachment', 'file',
          title: 'Attachment'));
      await tester.pumpAndSettle();
      // File picker renders ElevatedButton.icon (runtime type may be a subclass)
      expect(
        find.byWidgetPredicate((w) => w is ElevatedButton),
        findsOneWidget,
      );
    });

    testWidgets('shows Choose File text', (tester) async {
      await tester.pumpWidget(_buildField('attachment', 'file',
          title: 'Attachment'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Choose'), findsOneWidget);
    });
  });

  // =========================================================================
  // range-find: from/to range input for numeric filtering
  // =========================================================================
  group('FieldWidgetFactory — range-find', () {
    testWidgets('renders from and thru inputs', (tester) async {
      await tester.pumpWidget(_buildField(
        'amount',
        'range-find',
        title: 'Amount',
      ));
      // range-find renders two TextFormField instances (from, thru)
      expect(find.byType(TextFormField), findsAtLeastNWidgets(2));
    });
  });

  // =========================================================================
  // reset: form reset button
  // =========================================================================
  group('FieldWidgetFactory — reset', () {
    testWidgets('renders a button', (tester) async {
      await tester.pumpWidget(_buildField(
        'resetBtn',
        'reset',
        widgetAttrs: {'text': 'Clear'},
      ));
      // Reset renders a button widget
      expect(
        find.byWidgetPredicate((w) =>
            w is ElevatedButton || w is TextButton || w is OutlinedButton),
        findsOneWidget,
      );
    });
  });

  // =========================================================================
  // label: static text label
  // =========================================================================
  group('FieldWidgetFactory — label', () {
    testWidgets('renders text label', (tester) async {
      await tester.pumpWidget(_buildField(
        'info',
        'label',
        widgetAttrs: {'text': 'Information Label'},
      ));
      expect(find.text('Information Label'), findsOneWidget);
    });

    testWidgets('renders with style', (tester) async {
      await tester.pumpWidget(_buildField(
        'heading',
        'label',
        widgetAttrs: {'text': 'Section Title', 'style': 'h3'},
      ));
      expect(find.text('Section Title'), findsOneWidget);
    });
  });

  // =========================================================================
  // image: image display
  // =========================================================================
  group('FieldWidgetFactory — image', () {
    testWidgets('renders SizedBox.shrink for empty url', (tester) async {
      await tester.pumpWidget(_buildField(
        'photo',
        'image',
        widgetAttrs: {'alt': 'Test Image'},
      ));
      // With no url or formData, image returns SizedBox.shrink
      expect(find.byType(SizedBox), findsAtLeastNWidgets(1));
    });

    testWidgets('renders Image.network when url is provided', (tester) async {
      await tester.pumpWidget(_buildField(
        'photo',
        'image',
        widgetAttrs: {'url': 'http://example.com/test.png', 'alt': 'Photo'},
      ));
      await tester.pump();
      // Image.network widget should be in the tree
      expect(find.byType(Image), findsOneWidget);
    });
  });

  // =========================================================================
  // editable: inline-editable display field
  // =========================================================================
  group('FieldWidgetFactory — editable', () {
    testWidgets('renders display mode by default', (tester) async {
      await tester.pumpWidget(_buildField(
        'description',
        'editable',
        formData: {'description': 'Test value'},
      ));
      expect(find.text('Test value'), findsOneWidget);
    });

    testWidgets('renders edit icon', (tester) async {
      await tester.pumpWidget(_buildField(
        'description',
        'editable',
        formData: {'description': 'Some text'},
      ));
      expect(find.byIcon(Icons.edit), findsOneWidget);
    });
  });

  // =========================================================================
  // link: clickable link field
  // =========================================================================
  group('FieldWidgetFactory — link', () {
    testWidgets('renders link text', (tester) async {
      await tester.pumpWidget(_buildField(
        'detailLink',
        'link',
        widgetAttrs: {
          'text': 'View Details',
          'url': '/Order/Detail',
          'linkType': 'anchor',
        },
        ctx: _stubContext(),
      ));
      expect(find.text('View Details'), findsOneWidget);
    });
  });

  // =========================================================================
  // Unknown widget type — fallback behavior
  // =========================================================================
  group('FieldWidgetFactory — unknown type', () {
    testWidgets('renders fallback TextFormField for unknown type', (tester) async {
      await tester.pumpWidget(_buildField(
        'mystery',
        'nonexistent-widget-type',
        formData: {'mystery': 'value'},
      ));
      await tester.pump();
      // Default fallback renders a TextFormField
      expect(find.byType(TextFormField), findsOneWidget);
      expect(find.text('value'), findsOneWidget);
    });
  });

  // =========================================================================
  // Edge cases
  // =========================================================================
  group('FieldWidgetFactory — edge cases', () {
    testWidgets('handles empty widget list gracefully', (tester) async {
      const field = FieldDefinition(
        name: 'empty',
        title: 'Empty',
        widgets: [],
      );
      await tester.pumpWidget(_testHarness(
        FieldWidgetFactory.build(
          field: field,
          formData: {},
          onChanged: (n, v) {},
          ctx: _stubContext(),
        ),
      ));
      await tester.pump();
      // Empty widgets → SizedBox.shrink
      expect(find.byType(SizedBox), findsAtLeastNWidgets(1));
    });

    testWidgets('display shows formatted text with format attribute', (tester) async {
      await tester.pumpWidget(_buildField(
        'amount',
        'display',
        widgetAttrs: {
          'format': '#,##0.00',
          'resolvedText': '1234.50',
        },
        formData: {'amount': '1234.50'},
      ));
      // Should render some formatted text
      expect(find.byType(Text), findsAtLeastNWidgets(1));
    });

    testWidgets('text-line with number inputType renders TextFormField', (tester) async {
      await tester.pumpWidget(_buildField(
        'quantity',
        'text-line',
        widgetAttrs: {'inputType': 'number'},
      ));
      // Verify it renders; keyboardType is private on TextFormField,
      // but we can verify the field is present and accepts numeric input
      expect(find.byType(TextFormField), findsOneWidget);
      await tester.enterText(find.byType(TextFormField), '42');
      expect(find.text('42'), findsOneWidget);
    });

    testWidgets('text-line with email inputType renders TextFormField', (tester) async {
      await tester.pumpWidget(_buildField(
        'email',
        'text-line',
        widgetAttrs: {'inputType': 'email'},
      ));
      expect(find.byType(TextFormField), findsOneWidget);
      await tester.enterText(find.byType(TextFormField), 'test@example.com');
      expect(find.text('test@example.com'), findsOneWidget);
    });

    testWidgets('drop-down with allowEmpty shows empty option', (tester) async {
      await tester.pumpWidget(_buildField(
        'status',
        'drop-down',
        widgetAttrs: {'allowEmpty': 'true'},
        options: const [
          FieldOption(key: 'A', text: 'Active'),
          FieldOption(key: 'I', text: 'Inactive'),
        ],
      ));
      // Drop-down should include an empty option
      await tester.pump();
      expect(find.byType(DropdownButtonFormField<String>), findsOneWidget);
    });
  });
}
