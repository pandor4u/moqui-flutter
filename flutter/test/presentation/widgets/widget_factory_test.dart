import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moqui_flutter/domain/screen/screen_models.dart';
import 'package:moqui_flutter/presentation/widgets/moqui/widget_factory.dart';

/// A helper that wraps a widget in MaterialApp for testing.
Widget _testHarness(Widget child) {
  return MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(child: child),
    ),
  );
}

/// Stub render context for widget tests.
MoquiRenderContext _stubContext() {
  return MoquiRenderContext(
    navigate: (path, {params}) {},
    submitForm: (url, data) async { return null; },
    loadDynamic: (transition, params) async => <String, dynamic>{},
  );
}

void main() {
  group('MoquiWidgetFactory — Label', () {
    testWidgets('renders label text widget', (tester) async {
      const node = WidgetNode(
        type: 'label',
        attributes: {
          '_type': 'label',
          'text': 'Hello World',
          'type': 'h4',
        },
      );

      await tester.pumpWidget(_testHarness(
        MoquiWidgetFactory.build(node, _stubContext()),
      ));

      expect(find.text('Hello World'), findsOneWidget);
    });

    testWidgets('renders SizedBox.shrink when text is empty', (tester) async {
      const node = WidgetNode(
        type: 'label',
        attributes: {
          '_type': 'label',
          'text': '',
          'id': 'my-label',
        },
      );

      await tester.pumpWidget(_testHarness(
        MoquiWidgetFactory.build(node, _stubContext()),
      ));

      // Label with empty text returns SizedBox.shrink
      expect(find.byType(SizedBox), findsWidgets);
    });
  });

  group('MoquiWidgetFactory — Link', () {
    testWidgets('renders link as clickable element', (tester) async {
      const node = WidgetNode(
        type: 'link',
        attributes: {
          '_type': 'link',
          'text': 'Click Me',
          'url': '/fapps/dashboard',
          'urlType': 'screen',
        },
      );

      await tester.pumpWidget(_testHarness(
        MoquiWidgetFactory.build(node, _stubContext()),
      ));

      expect(find.text('Click Me'), findsOneWidget);
    });
  });

  group('MoquiWidgetFactory — Container', () {
    testWidgets('renders container with child widgets', (tester) async {
      const node = WidgetNode(
        type: 'container',
        attributes: {
          '_type': 'container',
          'containerType': 'div',
          'style': '',
        },
        children: [
          WidgetNode(
            type: 'label',
            attributes: {'_type': 'label', 'text': 'Inside container'},
          ),
        ],
      );

      await tester.pumpWidget(_testHarness(
        MoquiWidgetFactory.build(node, _stubContext()),
      ));

      expect(find.text('Inside container'), findsOneWidget);
    });

    testWidgets('renders row container type as Row', (tester) async {
      const node = WidgetNode(
        type: 'container',
        attributes: {
          '_type': 'container',
          'containerType': 'row',
          'style': '',
        },
        children: [
          WidgetNode(
            type: 'label',
            attributes: {'_type': 'label', 'text': 'Col 1'},
          ),
          WidgetNode(
            type: 'label',
            attributes: {'_type': 'label', 'text': 'Col 2'},
          ),
        ],
      );

      await tester.pumpWidget(_testHarness(
        MoquiWidgetFactory.build(node, _stubContext()),
      ));

      expect(find.text('Col 1'), findsOneWidget);
      expect(find.text('Col 2'), findsOneWidget);
      expect(find.byType(Row), findsOneWidget);
    });
  });

  group('MoquiWidgetFactory — Section', () {
    testWidgets('renders section with widgets', (tester) async {
      const node = WidgetNode(
        type: 'section',
        attributes: {
          '_type': 'section',
          'widgets': [
            {'_type': 'label', 'text': 'Section content'},
          ],
        },
      );

      await tester.pumpWidget(_testHarness(
        MoquiWidgetFactory.build(node, _stubContext()),
      ));

      expect(find.text('Section content'), findsOneWidget);
    });

    testWidgets('renders failWidgets when widgets empty', (tester) async {
      const node = WidgetNode(
        type: 'section',
        attributes: {
          '_type': 'section',
          'widgets': [],
          'failWidgets': [
            {'_type': 'label', 'text': 'Fallback content'},
          ],
        },
      );

      await tester.pumpWidget(_testHarness(
        MoquiWidgetFactory.build(node, _stubContext()),
      ));

      expect(find.text('Fallback content'), findsOneWidget);
    });
  });

  group('MoquiWidgetFactory — Image', () {
    testWidgets('renders image widget with network url', (tester) async {
      const node = WidgetNode(
        type: 'image',
        attributes: {
          '_type': 'image',
          'url': 'https://example.com/logo.png',
          'alt': 'Logo',
          'width': '100',
        },
      );

      await tester.pumpWidget(_testHarness(
        MoquiWidgetFactory.build(node, _stubContext()),
      ));

      // Should have an Image.network widget
      expect(find.byType(Image), findsOneWidget);
    });

    testWidgets('renders SizedBox.shrink for empty url', (tester) async {
      const node = WidgetNode(
        type: 'image',
        attributes: {
          '_type': 'image',
          'url': '',
        },
      );

      await tester.pumpWidget(_testHarness(
        MoquiWidgetFactory.build(node, _stubContext()),
      ));

      expect(find.byType(Image), findsNothing);
    });
  });

  group('MoquiWidgetFactory — Text', () {
    testWidgets('renders raw text content using content attribute', (tester) async {
      const node = WidgetNode(
        type: 'text',
        attributes: {
          '_type': 'text',
          'content': 'Plain text content here',
        },
      );

      await tester.pumpWidget(_testHarness(
        MoquiWidgetFactory.build(node, _stubContext()),
      ));

      expect(find.text('Plain text content here'), findsOneWidget);
    });

    testWidgets('renders SizedBox.shrink for empty content', (tester) async {
      const node = WidgetNode(
        type: 'text',
        attributes: {
          '_type': 'text',
          'content': '',
        },
      );

      await tester.pumpWidget(_testHarness(
        MoquiWidgetFactory.build(node, _stubContext()),
      ));

      expect(find.byType(Text), findsNothing);
    });
  });

  group('MoquiWidgetFactory — Generic/Unknown', () {
    testWidgets('renders unknown type with placeholder', (tester) async {
      const node = WidgetNode(
        type: 'some-unknown-type-xyz',
        attributes: {
          '_type': 'some-unknown-type-xyz',
        },
      );

      await tester.pumpWidget(_testHarness(
        MoquiWidgetFactory.build(node, _stubContext()),
      ));

      // Should still render something without crashing
      expect(tester.takeException(), isNull);
    });
  });

  group('MoquiWidgetFactory — buildChildren', () {
    test('returns empty list for node with no children', () {
      const node = WidgetNode(type: 'container', attributes: {});
      final widgets = MoquiWidgetFactory.buildChildren(node, _stubContext());
      expect(widgets, isEmpty);
    });

    test('returns widgets for each child', () {
      const node = WidgetNode(
        type: 'container',
        attributes: {},
        children: [
          WidgetNode(type: 'label', attributes: {'text': 'A'}),
          WidgetNode(type: 'label', attributes: {'text': 'B'}),
          WidgetNode(type: 'label', attributes: {'text': 'C'}),
        ],
      );
      final widgets = MoquiWidgetFactory.buildChildren(node, _stubContext());
      expect(widgets.length, 3);
    });
  });

  group('MoquiWidgetFactory — buildList', () {
    test('returns empty list for empty input', () {
      final widgets = MoquiWidgetFactory.buildList([], _stubContext());
      expect(widgets, isEmpty);
    });

    test('builds each node in list', () {
      final nodes = [
        const WidgetNode(type: 'label', attributes: {'text': 'X'}),
        const WidgetNode(type: 'label', attributes: {'text': 'Y'}),
      ];
      final widgets = MoquiWidgetFactory.buildList(nodes, _stubContext());
      expect(widgets.length, 2);
    });
  });

  group('MoquiWidgetFactory — ContainerBox', () {
    testWidgets('renders card with body content', (tester) async {
      const node = WidgetNode(
        type: 'container-box',
        attributes: {
          '_type': 'container-box',
          'body': [
            {'_type': 'label', 'text': 'Box body'},
          ],
        },
      );

      await tester.pumpWidget(_testHarness(
        MoquiWidgetFactory.build(node, _stubContext()),
      ));

      expect(find.text('Box body'), findsOneWidget);
      expect(find.byType(Card), findsOneWidget);
    });
  });

  group('MoquiWidgetFactory — ContainerRow', () {
    testWidgets('renders columns in a row using columns attribute', (tester) async {
      const node = WidgetNode(
        type: 'container-row',
        attributes: {
          '_type': 'container-row',
          'columns': [
            {
              'lg': '6',
              'sm': '12',
              'children': [
                {'_type': 'label', 'text': 'Left'},
              ],
            },
            {
              'lg': '6',
              'sm': '12',
              'children': [
                {'_type': 'label', 'text': 'Right'},
              ],
            },
          ],
        },
      );

      await tester.pumpWidget(_testHarness(
        MoquiWidgetFactory.build(node, _stubContext()),
      ));

      expect(find.text('Left'), findsOneWidget);
      expect(find.text('Right'), findsOneWidget);
    });

    testWidgets('renders SizedBox.shrink when no columns', (tester) async {
      const node = WidgetNode(
        type: 'container-row',
        attributes: {'_type': 'container-row'},
      );

      await tester.pumpWidget(_testHarness(
        MoquiWidgetFactory.build(node, _stubContext()),
      ));

      expect(find.byType(SizedBox), findsWidgets);
    });
  });

  group('MoquiRenderContext', () {
    test('can be constructed with all required fields', () {
      final ctx = MoquiRenderContext(
        navigate: (path, {params}) {},
        submitForm: (url, data) async { return null; },
        loadDynamic: (t, p) async => {},
        contextData: {'key': 'value'},
      );
      expect(ctx.contextData['key'], 'value');
    });

    test('contextData defaults to empty map', () {
      final ctx = MoquiRenderContext(
        navigate: (path, {params}) {},
        submitForm: (url, data) async { return null; },
        loadDynamic: (t, p) async => {},
      );
      expect(ctx.contextData, isEmpty);
    });
  });
}
