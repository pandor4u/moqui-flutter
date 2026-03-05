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
  Map<String, dynamic> contextData = const {},
}) {
  return MoquiRenderContext(
    navigate: navigate ?? (path, {params}) {},
    submitForm: submitForm ?? (url, data) async { return null; },
    loadDynamic: loadDynamic ?? (transition, params) async => <String, dynamic>{},
    contextData: contextData,
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
  // PHASE 1: Link Enhancements
  // ===========================================================================
  group('Link Widget - Condition Handling', () {
    testWidgets('hides link when condition is false', (tester) async {
      const node = WidgetNode(
        type: 'link',
        attributes: {
          '_type': 'link',
          'text': 'Hidden Link',
          'url': '/test',
          'condition': 'false',
        },
      );

      await tester.pumpWidget(_testHarness(
        MoquiWidgetFactory.build(node, _stubContext()),
      ));

      expect(find.text('Hidden Link'), findsNothing);
      expect(find.byType(SizedBox), findsWidgets);
    });

    testWidgets('shows link when condition is true or not set', (tester) async {
      const node = WidgetNode(
        type: 'link',
        attributes: {
          '_type': 'link',
          'text': 'Visible Link',
          'url': '/test',
          'condition': 'true',
        },
      );

      await tester.pumpWidget(_testHarness(
        MoquiWidgetFactory.build(node, _stubContext()),
      ));

      expect(find.text('Visible Link'), findsOneWidget);
    });

    testWidgets('shows link when condition is missing', (tester) async {
      const node = WidgetNode(
        type: 'link',
        attributes: {
          '_type': 'link',
          'text': 'Default Visible',
          'url': '/test',
        },
      );

      await tester.pumpWidget(_testHarness(
        MoquiWidgetFactory.build(node, _stubContext()),
      ));

      expect(find.text('Default Visible'), findsOneWidget);
    });
  });

  group('Link Widget - Tooltip', () {
    testWidgets('wraps link in Tooltip when tooltip is set', (tester) async {
      const node = WidgetNode(
        type: 'link',
        attributes: {
          '_type': 'link',
          'text': 'Hover Me',
          'url': '/test',
          'tooltip': 'This is a helpful tooltip',
        },
      );

      await tester.pumpWidget(_testHarness(
        MoquiWidgetFactory.build(node, _stubContext()),
      ));

      expect(find.text('Hover Me'), findsOneWidget);
      expect(find.byType(Tooltip), findsOneWidget);
    });

    testWidgets('no Tooltip when tooltip is empty', (tester) async {
      const node = WidgetNode(
        type: 'link',
        attributes: {
          '_type': 'link',
          'text': 'No Tooltip',
          'url': '/test',
          'tooltip': '',
        },
      );

      await tester.pumpWidget(_testHarness(
        MoquiWidgetFactory.build(node, _stubContext()),
      ));

      expect(find.text('No Tooltip'), findsOneWidget);
      expect(find.byType(Tooltip), findsNothing);
    });
  });

  group('Link Widget - Confirmation Dialog', () {
    testWidgets('shows confirmation dialog when confirmation attr is set', (tester) async {
      bool navigated = false;
      const node = WidgetNode(
        type: 'link',
        attributes: {
          '_type': 'link',
          'text': 'Delete Item',
          'url': '/delete',
          'confirmation': 'Are you sure you want to delete?',
        },
      );

      await tester.pumpWidget(_testHarness(
        MoquiWidgetFactory.build(node, _stubContext(
          navigate: (path, {params}) {
            navigated = true;
          },
        )),
      ));

      // Tap the link
      await tester.tap(find.text('Delete Item'));
      await tester.pumpAndSettle();

      // Should show confirmation dialog
      expect(find.text('Confirm Action'), findsOneWidget);
      expect(find.text('Are you sure you want to delete?'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Confirm'), findsOneWidget);

      // Navigation should NOT have happened yet
      expect(navigated, false);

      // Tap Cancel
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      // Dialog should close, navigation should not happen
      expect(find.text('Confirm Action'), findsNothing);
      expect(navigated, false);
    });

    testWidgets('POSTs after confirming in dialog (confirmed = destructive)', (tester) async {
      bool submitted = false;
      String? submittedUrl;
      const node = WidgetNode(
        type: 'link',
        attributes: {
          '_type': 'link',
          'text': 'Confirm Action',
          'url': '/confirmed-action',
          'confirmation': 'Proceed?',
        },
      );

      await tester.pumpWidget(_testHarness(
        MoquiWidgetFactory.build(node, _stubContext(
          submitForm: (url, data) async {
            submitted = true;
            submittedUrl = url;
            return null;
          },
        )),
      ));

      // Tap the link
      await tester.tap(find.text('Confirm Action'));
      await tester.pumpAndSettle();

      // Tap Confirm
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();

      // Confirmed links always POST (destructive actions)
      expect(submitted, true);
      expect(submittedUrl, '/confirmed-action');
    });
  });

  // ===========================================================================
  // PHASE 1: Container-Dialog Enhancements
  // ===========================================================================
  group('Container-Dialog Widget', () {
    testWidgets('hides button when condition is false', (tester) async {
      const node = WidgetNode(
        type: 'container-dialog',
        attributes: {
          '_type': 'container-dialog',
          'buttonText': 'Open Dialog',
          'condition': 'false',
        },
      );

      await tester.pumpWidget(_testHarness(
        MoquiWidgetFactory.build(node, _stubContext()),
      ));

      expect(find.text('Open Dialog'), findsNothing);
    });

    testWidgets('shows button when condition is true', (tester) async {
      const node = WidgetNode(
        type: 'container-dialog',
        attributes: {
          '_type': 'container-dialog',
          'buttonText': 'Open Dialog',
          'condition': 'true',
        },
        children: [
          WidgetNode(type: 'label', attributes: {'text': 'Dialog Content'}),
        ],
      );

      await tester.pumpWidget(_testHarness(
        MoquiWidgetFactory.build(node, _stubContext()),
      ));

      expect(find.text('Open Dialog'), findsOneWidget);
    });

    testWidgets('opens dialog on button tap', (tester) async {
      const node = WidgetNode(
        type: 'container-dialog',
        attributes: {
          '_type': 'container-dialog',
          'buttonText': 'Click Me',
          'dialogTitle': 'My Dialog',
        },
        children: [
          WidgetNode(type: 'label', attributes: {'text': 'Inside the dialog'}),
        ],
      );

      await tester.pumpWidget(_testHarness(
        MoquiWidgetFactory.build(node, _stubContext()),
      ));

      // Tap button
      await tester.tap(find.text('Click Me'));
      await tester.pumpAndSettle();

      // Dialog should appear
      expect(find.text('My Dialog'), findsOneWidget);
      expect(find.text('Inside the dialog'), findsOneWidget);
      expect(find.text('Close'), findsOneWidget);
    });
  });

  // ===========================================================================
  // PHASE 1: Section-Iterate
  // ===========================================================================
  group('Section-Iterate Widget', () {
    testWidgets('renders pre-expanded children from server', (tester) async {
      const node = WidgetNode(
        type: 'section-iterate',
        attributes: {'_type': 'section-iterate'},
        children: [
          WidgetNode(type: 'label', attributes: {'text': 'Item 1'}),
          WidgetNode(type: 'label', attributes: {'text': 'Item 2'}),
          WidgetNode(type: 'label', attributes: {'text': 'Item 3'}),
        ],
      );

      await tester.pumpWidget(_testHarness(
        MoquiWidgetFactory.build(node, _stubContext()),
      ));

      expect(find.text('Item 1'), findsOneWidget);
      expect(find.text('Item 2'), findsOneWidget);
      expect(find.text('Item 3'), findsOneWidget);
    });

    testWidgets('client-side iteration over listData', (tester) async {
      const node = WidgetNode(
        type: 'section-iterate',
        attributes: {
          '_type': 'section-iterate',
          'list': 'itemList',
          'entry': 'item',
          'listData': [
            {'name': 'Apple'},
            {'name': 'Banana'},
            {'name': 'Cherry'},
          ],
          'widgetTemplate': [
            {'_type': 'label', 'text': 'Fruit'},
          ],
        },
      );

      await tester.pumpWidget(_testHarness(
        MoquiWidgetFactory.build(node, _stubContext()),
      ));

      // Should render 3 times (template repeated for each item)
      expect(find.text('Fruit'), findsNWidgets(3));
    });
  });

  // ===========================================================================
  // PHASE 1: Container-Box with Header/Body/Toolbar
  // ===========================================================================
  group('Container-Box Widget - Sections', () {
    testWidgets('renders header and body', (tester) async {
      const node = WidgetNode(
        type: 'container-box',
        attributes: {
          '_type': 'container-box',
          'header': [
            {'_type': 'label', 'text': 'Box Title'},
          ],
          'body': [
            {'_type': 'label', 'text': 'Box Content'},
          ],
        },
      );

      await tester.pumpWidget(_testHarness(
        MoquiWidgetFactory.build(node, _stubContext()),
      ));

      expect(find.text('Box Title'), findsOneWidget);
      expect(find.text('Box Content'), findsOneWidget);
      expect(find.byType(Card), findsOneWidget);
    });

    testWidgets('renders toolbar alongside header', (tester) async {
      const node = WidgetNode(
        type: 'container-box',
        attributes: {
          '_type': 'container-box',
          'header': [
            {'_type': 'label', 'text': 'Settings'},
          ],
          'toolbar': [
            {'_type': 'link', 'text': 'Edit', 'url': '/edit'},
          ],
          'body': [
            {'_type': 'label', 'text': 'Content here'},
          ],
        },
      );

      await tester.pumpWidget(_testHarness(
        MoquiWidgetFactory.build(node, _stubContext()),
      ));

      expect(find.text('Settings'), findsOneWidget);
      expect(find.text('Edit'), findsOneWidget);
      expect(find.text('Content here'), findsOneWidget);
    });

    testWidgets('renders bodyNoPad without padding', (tester) async {
      const node = WidgetNode(
        type: 'container-box',
        attributes: {
          '_type': 'container-box',
          'bodyNoPad': [
            {'_type': 'label', 'text': 'No padding content'},
          ],
        },
      );

      await tester.pumpWidget(_testHarness(
        MoquiWidgetFactory.build(node, _stubContext()),
      ));

      expect(find.text('No padding content'), findsOneWidget);
    });
  });

  // ===========================================================================
  // PHASE 1: Container-Row with responsive columns
  // ===========================================================================
  group('Container-Row Widget', () {
    testWidgets('renders multiple columns', (tester) async {
      const node = WidgetNode(
        type: 'container-row',
        attributes: {
          '_type': 'container-row',
          'columns': [
            {
              'lg': '4',
              'md': '6',
              'sm': '12',
              'children': [
                {'_type': 'label', 'text': 'Column A'},
              ],
            },
            {
              'lg': '4',
              'md': '6',
              'sm': '12',
              'children': [
                {'_type': 'label', 'text': 'Column B'},
              ],
            },
            {
              'lg': '4',
              'md': '6',
              'sm': '12',
              'children': [
                {'_type': 'label', 'text': 'Column C'},
              ],
            },
          ],
        },
      );

      await tester.pumpWidget(_testHarness(
        MoquiWidgetFactory.build(node, _stubContext()),
      ));

      expect(find.text('Column A'), findsOneWidget);
      expect(find.text('Column B'), findsOneWidget);
      expect(find.text('Column C'), findsOneWidget);
    });

    testWidgets('handles empty columns gracefully', (tester) async {
      const node = WidgetNode(
        type: 'container-row',
        attributes: {
          '_type': 'container-row',
          'columns': [],
        },
      );

      await tester.pumpWidget(_testHarness(
        MoquiWidgetFactory.build(node, _stubContext()),
      ));

      // Should render SizedBox.shrink without crashing
      expect(tester.takeException(), isNull);
    });
  });

  // ===========================================================================
  // PHASE 3: Field Accordion Layout
  // ===========================================================================
  group('Field Widget Factory - Reset Button', () {
    testWidgets('renders reset button with default text', (tester) async {
      final field = _makeField('resetBtn', 'reset', title: 'Reset');
      
      // Verify field model is correct
      expect(field.widgets.first.widgetType, 'reset');

      await tester.pumpWidget(_formTestHarness(
        FieldWidgetFactory.build(
          field: field,
          formData: {},
          onChanged: (name, value) {},
          ctx: _stubContext(),
        ),
      ));

      // Reset button uses widget.attr('text', 'Reset') so default is 'Reset'
      expect(find.text('Reset'), findsOneWidget);
      // Check button is rendered - use predicate for the exact type
      expect(
        find.byWidgetPredicate(
          (widget) => widget.runtimeType.toString() == '_OutlinedButtonWithIcon',
        ),
        findsOneWidget,
      );
    });

    testWidgets('renders reset button with custom text', (tester) async {
      final field = _makeField(
        'resetBtn',
        'reset',
        title: 'Reset',
        widgetAttrs: {'text': 'Clear Form'},
      );

      await tester.pumpWidget(_formTestHarness(
        FieldWidgetFactory.build(
          field: field,
          formData: {},
          onChanged: (name, value) {},
          ctx: _stubContext(),
        ),
      ));

      expect(find.text('Clear Form'), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (widget) => widget.runtimeType.toString() == '_OutlinedButtonWithIcon',
        ),
        findsOneWidget,
      );
    });
  });

  group('Field Widget Factory - Label Field', () {
    testWidgets('renders label-type field as display text', (tester) async {
      final field = _makeField(
        'infoLabel',
        'label',
        title: 'Info',
        widgetAttrs: {'text': 'This is informational text'},
      );

      await tester.pumpWidget(_formTestHarness(
        FieldWidgetFactory.build(
          field: field,
          formData: {},
          onChanged: (name, value) {},
          ctx: _stubContext(),
        ),
      ));

      expect(find.text('This is informational text'), findsOneWidget);
    });
  });

  group('Field Widget Factory - Image Field', () {
    testWidgets('renders image field', (tester) async {
      final field = _makeField(
        'productImage',
        'image',
        title: 'Product Image',
        widgetAttrs: {'url': 'https://example.com/image.png'},
      );

      await tester.pumpWidget(_formTestHarness(
        FieldWidgetFactory.build(
          field: field,
          formData: {},
          onChanged: (name, value) {},
          ctx: _stubContext(),
        ),
      ));

      expect(find.byType(Image), findsOneWidget);
    });
  });

  // ===========================================================================
  // PHASE 3: Subscreens Navigation
  // ===========================================================================
  group('Subscreens-Panel Widget', () {
    testWidgets('renders tabs for subscreens', (tester) async {
      const node = WidgetNode(
        type: 'subscreens-panel',
        attributes: {
          '_type': 'subscreens-panel',
          'type': 'tab',
          'subscreens': [
            {'name': 'tab1', 'title': 'First Tab', 'path': '/tab1'},
            {'name': 'tab2', 'title': 'Second Tab', 'path': '/tab2'},
          ],
        },
      );

      // Use a constrained height harness for TabBar/TabBarView
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 400,
            child: MoquiWidgetFactory.build(node, _stubContext()),
          ),
        ),
      ));

      expect(find.text('First Tab'), findsOneWidget);
      expect(find.text('Second Tab'), findsOneWidget);
      expect(find.byType(TabBar), findsOneWidget);
    });

    testWidgets('renders SizedBox.shrink when no subscreens', (tester) async {
      const node = WidgetNode(
        type: 'subscreens-panel',
        attributes: {
          '_type': 'subscreens-panel',
          'subscreens': [],
        },
      );

      await tester.pumpWidget(_testHarness(
        MoquiWidgetFactory.build(node, _stubContext()),
      ));

      expect(find.byType(TabBar), findsNothing);
    });
  });

  group('Subscreens-Menu Widget', () {
    testWidgets('renders popup menu button for subscreens', (tester) async {
      const node = WidgetNode(
        type: 'subscreens-menu',
        attributes: {
          '_type': 'subscreens-menu',
          'subscreens': [
            {'name': 'option1', 'title': 'Option 1', 'path': '/opt1'},
            {'name': 'option2', 'title': 'Option 2', 'path': '/opt2'},
          ],
        },
      );

      await tester.pumpWidget(_testHarness(
        MoquiWidgetFactory.build(node, _stubContext()),
      ));

      expect(find.byType(PopupMenuButton<String>), findsOneWidget);
    });
  });

  // ===========================================================================
  // Edge Cases and Error Handling
  // ===========================================================================
  group('Edge Cases', () {
    testWidgets('handles null attributes gracefully', (tester) async {
      const node = WidgetNode(
        type: 'label',
        attributes: {},
      );

      await tester.pumpWidget(_testHarness(
        MoquiWidgetFactory.build(node, _stubContext()),
      ));

      // Should not crash
      expect(tester.takeException(), isNull);
    });

    testWidgets('handles unknown widget type', (tester) async {
      const node = WidgetNode(
        type: 'completely-unknown-widget-type',
        attributes: {'_type': 'completely-unknown-widget-type'},
      );

      await tester.pumpWidget(_testHarness(
        MoquiWidgetFactory.build(node, _stubContext()),
      ));

      // Should not crash, renders generic fallback
      expect(tester.takeException(), isNull);
    });

    testWidgets('handles deeply nested widgets', (tester) async {
      const node = WidgetNode(
        type: 'container',
        attributes: {'_type': 'container'},
        children: [
          WidgetNode(
            type: 'container',
            attributes: {'_type': 'container'},
            children: [
              WidgetNode(
                type: 'container',
                attributes: {'_type': 'container'},
                children: [
                  WidgetNode(type: 'label', attributes: {'text': 'Deep Nested'}),
                ],
              ),
            ],
          ),
        ],
      );

      await tester.pumpWidget(_testHarness(
        MoquiWidgetFactory.build(node, _stubContext()),
      ));

      expect(find.text('Deep Nested'), findsOneWidget);
    });

    testWidgets('navigation callback receives correct path', (tester) async {
      String? receivedPath;
      const node = WidgetNode(
        type: 'link',
        attributes: {
          '_type': 'link',
          'text': 'Navigate',
          'url': '/fapps/tools/Entity/DataEdit',
        },
      );

      await tester.pumpWidget(_testHarness(
        MoquiWidgetFactory.build(node, _stubContext(
          navigate: (path, {params}) {
            receivedPath = path;
          },
        )),
      ));

      await tester.tap(find.text('Navigate'));
      await tester.pumpAndSettle();

      expect(receivedPath, '/fapps/tools/Entity/DataEdit');
    });
  });

  // ===========================================================================
  // Form Single with Field Layout
  // ===========================================================================
  group('Form Single with Field Layout', () {
    testWidgets('renders form with field-row layout', (tester) async {
      const form = FormDefinition(
        formType: 'form-single',
        formName: 'TestForm',
        transition: 'submit',
        fields: [
          FieldDefinition(
            name: 'firstName',
            title: 'First Name',
            widgets: [FieldWidget(widgetType: 'text-line', attributes: {})],
          ),
          FieldDefinition(
            name: 'lastName',
            title: 'Last Name',
            widgets: [FieldWidget(widgetType: 'text-line', attributes: {})],
          ),
        ],
        fieldLayout: FieldLayout(rows: [
          FieldLayoutRow(
            type: 'field-row',
            fields: [
              {'name': 'firstName'},
              {'name': 'lastName'},
            ],
          ),
        ]),
      );

      final node = WidgetNode(
        type: 'form-single',
        attributes: form.toJson(),
      );

      await tester.pumpWidget(_testHarness(
        MoquiWidgetFactory.build(node, _stubContext()),
      ));

      expect(find.text('First Name'), findsOneWidget);
      expect(find.text('Last Name'), findsOneWidget);
    });
  });
}

// Extension to convert FormDefinition to JSON for testing
extension FormDefinitionToJson on FormDefinition {
  Map<String, dynamic> toJson() => {
        '_type': formType,
        'formName': formName,
        'transition': transition,
        'fields': fields.map((f) => {
          'name': f.name,
          'title': f.title,
          'widgets': f.widgets.map((w) => {
            'widgetType': w.widgetType,
            ...w.attributes,
          }).toList(),
        }).toList(),
        'fieldLayout': fieldLayout != null
            ? {
                'rows': fieldLayout!.rows.map((r) => {
                  '_type': r.type,
                  'name': r.name,
                  'title': r.title,
                  'fields': r.fields,
                  'children': r.children.map((c) => {
                    '_type': c.type,
                    'name': c.name,
                  }).toList(),
                }).toList(),
              }
            : null,
      };
}
