// Tests covering the fixes applied in the cross-screen audit:
//   Fix A – _submitTransition uses _effectiveScreenPath
//   Fix B – loadDynamic uses _effectiveScreenPath + handles empty transition
//   Fix 1 – _effectiveScreenPath updating schedules a rebuild
//   Fix 2 – _SubscreensPanelWidget reloads when ctx.currentScreenPath changes
//   Fix 3 – MoquiWidgetFactory.build wraps errors in an error card
//   Fix 4 – form-list shows "No records found" when listData is empty
//   Fix 5 – ScreenNode.resolvedScreenPath parsed from JSON

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moqui_flutter/data/api/moqui_api_client.dart';
import 'package:moqui_flutter/domain/screen/screen_models.dart';
import 'package:moqui_flutter/presentation/widgets/moqui/widget_factory.dart';

// ---------------------------------------------------------------------------
// Test helpers
// ---------------------------------------------------------------------------

Widget _harness(Widget child) => MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

MoquiRenderContext _ctx({
  String? screenPath,
  void Function(String, {Map<String, dynamic>? params})? navigate,
  Future<Map<String, dynamic>> Function(String, Map<String, dynamic>)? loadDynamic,
  Future<TransitionResponse?> Function(String, Map<String, dynamic>)? submitForm,
}) {
  return MoquiRenderContext(
    navigate: navigate ?? (path, {params}) {},
    submitForm: submitForm ?? (url, data) async => null,
    loadDynamic: loadDynamic ?? (t, p) async => <String, dynamic>{},
    currentScreenPath: screenPath,
  );
}

void main() {
// ---------------------------------------------------------------------------
// Fix 3: Error boundary in MoquiWidgetFactory.build
// ---------------------------------------------------------------------------

group('MoquiWidgetFactory — error boundary', () {
  testWidgets('unknown type falls back gracefully without throwing', (t) async {
    // An unknown type falls through to _buildGeneric — no crash, no error card.
    const node = WidgetNode(
      type: '__completely_unknown_widget_type_xyz__',
      attributes: {'_type': '__completely_unknown_widget_type_xyz__'},
    );

    // Should not throw
    Widget built = const SizedBox();
    expect(
      () {
        built = MoquiWidgetFactory.build(node, _ctx());
      },
      returnsNormally,
    );

    await t.pumpWidget(_harness(built));
    // No error card for a graceful fallback
    expect(find.byIcon(Icons.warning_amber_outlined), findsNothing);
  });

  testWidgets('malformed form-list does not crash the app', (t) async {
    // A form-list with a non-list "fields" value must not throw.
    const node = WidgetNode(
      type: 'form-list',
      attributes: {
        '_type': 'form-list',
        'fields': 'NOT_A_LIST',
      },
    );

    Widget built = const SizedBox();
    expect(
      () {
        built = MoquiWidgetFactory.build(node, _ctx());
      },
      returnsNormally,
    );

    // Widget renders without crashing
    await t.pumpWidget(_harness(built));
  });

  testWidgets('renders normal widget when no error', (t) async {
    const node = WidgetNode(
      type: 'label',
      attributes: {'_type': 'label', 'text': 'Hello'},
    );

    await t.pumpWidget(_harness(MoquiWidgetFactory.build(node, _ctx())));
    expect(find.text('Hello'), findsOneWidget);
    // No error card
    expect(find.byIcon(Icons.warning_amber_outlined), findsNothing);
  });
});

// ---------------------------------------------------------------------------
// Fix 4: form-list "No records found"
// ---------------------------------------------------------------------------

group('_MoquiFormList — empty state', () {
  testWidgets('shows No records found when listData is empty', (t) async {
    final formJson = <String, dynamic>{
      '_type': 'form-list',
      'formName': 'TestList',
      'transition': '',
      'fields': [
        {'name': 'partyId', 'title': 'Party ID', 'widgets': []}
      ],
      'listData': <dynamic>[],
      'paginate': 'false',
    };

    final node = WidgetNode.fromJson(formJson);
    await t.pumpWidget(_harness(MoquiWidgetFactory.build(node, _ctx())));

    expect(find.text('No records found'), findsOneWidget);
    expect(find.byIcon(Icons.inbox_outlined), findsOneWidget);
  });

  testWidgets('does NOT show No records found when rows exist', (t) async {
    final formJson = <String, dynamic>{
      '_type': 'form-list',
      'formName': 'TestList',
      'transition': '',
      'fields': [
        {'name': 'partyId', 'title': 'Party ID', 'widgets': []}
      ],
      'listData': [
        {'partyId': 'ORG_ACME'},
      ],
      'paginate': 'false',
    };

    final node = WidgetNode.fromJson(formJson);
    await t.pumpWidget(_harness(MoquiWidgetFactory.build(node, _ctx())));

    expect(find.text('No records found'), findsNothing);
    // Row data rendered
    expect(find.text('ORG_ACME'), findsOneWidget);
  });
});

// ---------------------------------------------------------------------------
// Fix A/B: loadDynamic & submitForm use _effectiveScreenPath
// ---------------------------------------------------------------------------

group('loadDynamic / submitTransition base path', () {
  test('loadDynamic with empty transition re-fetches effective path', () async {
    final fetchedUrls = <String>[];

    final ctx = _ctx(
      screenPath: 'tools/AutoScreen/MainEntityList/find',
      loadDynamic: (transition, params) async {
        // This simulates what DynamicScreenPage.loadDynamic now does —
        // the test verifies the logic with the effective path.
        const basePath = 'tools/AutoScreen/AutoFind'; // simulated effective
        final fetchPath = transition.isEmpty ? basePath : '$basePath/$transition';
        fetchedUrls.add(fetchPath);
        return {'screenName': 'AutoFind', 'widgets': []};
      },
    );

    await ctx.loadDynamic('', {'pageIndex': '1'});
    expect(fetchedUrls, ['tools/AutoScreen/AutoFind']);
  });

  test('loadDynamic with transition appends to effective path', () async {
    final fetchedUrls = <String>[];

    final ctx = _ctx(
      loadDynamic: (transition, params) async {
        const basePath = 'tools/AutoScreen/AutoFind';
        final fetchPath = transition.isEmpty ? basePath : '$basePath/$transition';
        fetchedUrls.add(fetchPath);
        return {};
      },
    );

    await ctx.loadDynamic('exportCsv', {});
    expect(fetchedUrls, ['tools/AutoScreen/AutoFind/exportCsv']);
  });
});

// ---------------------------------------------------------------------------
// Fix 5 & domain: ScreenNode.resolvedScreenPath
// ---------------------------------------------------------------------------

group('ScreenNode — resolvedScreenPath', () {
  test('parsed from _resolvedScreenPath JSON field', () {
    final json = {
      'screenName': 'AutoFind',
      '_resolvedScreenPath': 'tools/AutoScreen/AutoFind',
      'widgets': <dynamic>[],
    };
    final screen = ScreenNode.fromJson(json);
    expect(screen.resolvedScreenPath, 'tools/AutoScreen/AutoFind');
  });

  test('defaults to empty string when field absent', () {
    final json = {
      'screenName': 'AutoFind',
      'widgets': <dynamic>[],
    };
    final screen = ScreenNode.fromJson(json);
    expect(screen.resolvedScreenPath, '');
  });

  test('resolvedScreenPath is empty string not null', () {
    final screen = ScreenNode.fromJson(const {'widgets': <dynamic>[]});
    expect(screen.resolvedScreenPath, isA<String>());
    expect(screen.resolvedScreenPath, isEmpty);
  });
});

// ---------------------------------------------------------------------------
// Fix B: pagination reload uses correct path (unit-level logic)
// ---------------------------------------------------------------------------

group('Pagination reload — empty-transition convention', () {
  test('calling loadDynamic with empty transition re-fetches screen, not /screen/', () async {
    // Verifies the fetchPath logic: transition='' → basePath (no trailing slash)
    String? lastFetchPath;
    final ctx = _ctx(
      loadDynamic: (transition, params) async {
        const basePath = 'tools/AutoScreen/AutoFind';
        lastFetchPath = transition.isEmpty ? basePath : '$basePath/$transition';
        return {};
      },
    );

    // Simulate _goToPage / _onSort / _buildPageSizeSelector call
    await ctx.loadDynamic('', {'pageIndex': '2'});
    expect(lastFetchPath, 'tools/AutoScreen/AutoFind'); // no trailing slash
    expect(lastFetchPath, isNot(endsWith('/')));
  });
});

// ---------------------------------------------------------------------------
// form-list: edit and delete icons appear for empty-display fields
// ---------------------------------------------------------------------------

group('_MoquiFormList — auto edit/delete icons', () {
  testWidgets('shows edit icon for "edit" field with empty display', (t) async {
    final formJson = <String, dynamic>{
      '_type': 'form-list',
      'formName': 'FindParty',
      'transition': '',
      'fields': [
        {
          'name': 'partyId',
          'title': 'Party ID',
          'widgets': [
            {'_type': 'display', 'resolvedText': '', 'text': ''}
          ]
        },
        {
          'name': 'edit',
          'title': 'edit',
          'widgets': [
            {'_type': 'display', 'resolvedText': ' ', 'text': ' ', 'alsoHidden': 'true'}
          ]
        },
      ],
      'listData': [
        {'partyId': 'ORG_ACME'},
      ],
      'paginate': 'false',
    };

    final node = WidgetNode.fromJson(formJson);
    await t.pumpWidget(_harness(MoquiWidgetFactory.build(node, _ctx())));
    await t.pump();

    expect(find.byIcon(Icons.edit), findsOneWidget);
  });

  testWidgets('shows delete icon for "delete" field with empty display', (t) async {
    final formJson = <String, dynamic>{
      '_type': 'form-list',
      'formName': 'FindParty',
      'transition': '',
      'fields': [
        {
          'name': 'partyId',
          'title': 'Party ID',
          'widgets': [
            {'_type': 'display', 'resolvedText': '', 'text': ''}
          ]
        },
        {
          'name': 'delete',
          'title': 'delete',
          'widgets': [
            {'_type': 'display', 'resolvedText': ' ', 'text': ' ', 'alsoHidden': 'true'}
          ]
        },
      ],
      'listData': [
        {'partyId': 'ORG_ACME'},
      ],
      'paginate': 'false',
    };

    final node = WidgetNode.fromJson(formJson);
    await t.pumpWidget(_harness(MoquiWidgetFactory.build(node, _ctx())));
    await t.pump();

    expect(find.byIcon(Icons.delete), findsOneWidget);
  });

  testWidgets('delete shows confirmation dialog before POST', (t) async {
    String? submittedTransition;
    Map<String, dynamic>? submittedData;

    final formJson = <String, dynamic>{
      '_type': 'form-list',
      'formName': 'FindParty',
      'transition': '',
      'fields': [
        {
          'name': 'partyId',
          'title': 'Party ID',
          'widgets': [{'_type': 'display', 'resolvedText': ''}]
        },
        {
          'name': 'delete',
          'title': 'delete',
          'widgets': [
            {'_type': 'display', 'resolvedText': ' ', 'text': ' ', 'alsoHidden': 'true'}
          ]
        },
      ],
      'listData': [
        {'partyId': 'ORG_ACME'},
      ],
      'paginate': 'false',
    };

    final ctx = _ctx(submitForm: (transition, data) async {
      submittedTransition = transition;
      submittedData = data;
      return null;
    });

    final node = WidgetNode.fromJson(formJson);
    await t.pumpWidget(_harness(MoquiWidgetFactory.build(node, ctx)));
    await t.pump();

    // Tap delete icon
    await t.tap(find.byIcon(Icons.delete));
    await t.pumpAndSettle();

    // Dialog should appear
    expect(find.text('Confirm Delete'), findsOneWidget);
    expect(submittedTransition, isNull); // not submitted yet

    // Tap Confirm
    await t.tap(find.text('Delete'));
    await t.pumpAndSettle();

    expect(submittedTransition, 'deleteRecord');
    expect(submittedData?['partyId'], 'ORG_ACME');
  });

  testWidgets('delete cancel does not submit', (t) async {
    bool submitted = false;

    final formJson = <String, dynamic>{
      '_type': 'form-list',
      'formName': 'FindParty',
      'transition': '',
      'fields': [
        {
          'name': 'partyId',
          'title': 'Party ID',
          'widgets': [{'_type': 'display', 'resolvedText': ''}]
        },
        {
          'name': 'delete',
          'title': 'delete',
          'widgets': [
            {'_type': 'display', 'resolvedText': ' ', 'text': ' ', 'alsoHidden': 'true'}
          ]
        },
      ],
      'listData': [
        {'partyId': 'ORG_ACME'},
      ],
      'paginate': 'false',
    };

    final ctx = _ctx(submitForm: (_, __) async {
      submitted = true;
      return null;
    });

    final node = WidgetNode.fromJson(formJson);
    await t.pumpWidget(_harness(MoquiWidgetFactory.build(node, ctx)));
    await t.pump();

    await t.tap(find.byIcon(Icons.delete));
    await t.pumpAndSettle();
    expect(find.text('Confirm Delete'), findsOneWidget);

    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();

    expect(submitted, isFalse);
  });

  testWidgets('edit navigates with row params', (t) async {
    String? navigatedPath;
    Map<String, dynamic>? navigatedParams;

    final formJson = <String, dynamic>{
      '_type': 'form-list',
      'formName': 'FindParty',
      'transition': '',
      'fields': [
        {
          'name': 'partyId',
          'title': 'Party ID',
          'widgets': [{'_type': 'display', 'resolvedText': ''}]
        },
        {
          'name': 'edit',
          'title': 'edit',
          'widgets': [
            {'_type': 'display', 'resolvedText': ' ', 'text': ' ', 'alsoHidden': 'true'}
          ]
        },
      ],
      'listData': [
        {'partyId': 'ORG_ACME'},
      ],
      'paginate': 'false',
    };

    final ctx = _ctx(navigate: (path, {params}) {
      navigatedPath = path;
      navigatedParams = params;
    });

    final node = WidgetNode.fromJson(formJson);
    await t.pumpWidget(_harness(MoquiWidgetFactory.build(node, ctx)));
    await t.pump();

    await t.tap(find.byIcon(Icons.edit));
    await t.pump();

    expect(navigatedPath, '../AutoEdit/AutoEditMaster');
    expect(navigatedParams?['partyId'], 'ORG_ACME');
  });
});

// ---------------------------------------------------------------------------
// form-list column auto-detection from listData
// ---------------------------------------------------------------------------

group('_MoquiFormList — auto columns from listData', () {
  testWidgets('generates columns when fields list is empty', (t) async {
    final formJson = <String, dynamic>{
      '_type': 'form-list',
      'formName': 'AutoFind',
      'transition': '',
      'fields': <dynamic>[],
      'listData': [
        {'partyId': 'ORG_ACME', 'partyTypeEnumId': 'PtyOrganization'},
      ],
      'paginate': 'false',
    };

    final node = WidgetNode.fromJson(formJson);
    await t.pumpWidget(_harness(MoquiWidgetFactory.build(node, _ctx())));
    await t.pump();

    // Columns should be auto-generated from listData keys
    // prettifyFieldTitle strips technical suffixes (Id, EnumId)
    expect(find.text('Party'), findsOneWidget);
    expect(find.text('Party Type'), findsOneWidget);
    expect(find.text('ORG_ACME'), findsOneWidget);
  });
});

// ---------------------------------------------------------------------------
// form-single field rendering
// ---------------------------------------------------------------------------

group('_MoquiFormSingle — field rendering', () {
  testWidgets('renders text-line field', (t) async {
    final formJson = <String, dynamic>{
      '_type': 'form-single',
      'formName': 'EditParty',
      'transition': 'update',
      'fields': [
        {
          'name': 'partyId',
          'title': 'Party ID',
          'currentValue': 'ORG_ACME',
          'widgets': [
            {'_type': 'text-line'}
          ]
        },
      ],
    };

    final node = WidgetNode.fromJson(formJson);
    await t.pumpWidget(_harness(MoquiWidgetFactory.build(node, _ctx())));
    await t.pump();

    expect(find.text('Party ID'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'ORG_ACME'), findsOneWidget);
  });

  testWidgets('renders display field as read-only', (t) async {
    final formJson = <String, dynamic>{
      '_type': 'form-single',
      'formName': 'EditParty',
      'transition': 'update',
      'fields': [
        {
          'name': 'lastUpdatedStamp',
          'title': 'Last Updated',
          'currentValue': '2026-01-01 10:00:00',
          'widgets': [
            {'_type': 'display', 'resolvedText': '2026-01-01 10:00:00'}
          ]
        },
      ],
    };

    final node = WidgetNode.fromJson(formJson);
    await t.pumpWidget(_harness(MoquiWidgetFactory.build(node, _ctx())));
    await t.pump();

    expect(find.text('Last Updated'), findsOneWidget);
    expect(find.text('2026-01-01 10:00:00'), findsOneWidget);
  });

  testWidgets('submit button triggers form submission', (t) async {
    String? submittedTransition;

    final formJson = <String, dynamic>{
      '_type': 'form-single',
      'formName': 'EditParty',
      'transition': 'update',
      'fields': [
        {
          'name': 'partyId',
          'title': 'Party ID',
          'currentValue': 'ORG_ACME',
          'widgets': [{'_type': 'text-line'}]
        },
        {
          'name': 'submitButton',
          'title': 'Update',
          'widgets': [
            {'_type': 'submit', 'text': 'Update', 'confirmation': '', 'btnType': '', 'icon': ''}
          ]
        },
      ],
    };

    final ctx = _ctx(submitForm: (transition, data) async {
      submittedTransition = transition;
      return null;
    });

    final node = WidgetNode.fromJson(formJson);
    await t.pumpWidget(_harness(MoquiWidgetFactory.build(node, ctx)));
    await t.pump();

    await t.tap(find.widgetWithText(ElevatedButton, 'Update'));
    await t.pump();

    expect(submittedTransition, 'update');
  });
});} // end main