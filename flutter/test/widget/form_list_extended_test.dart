import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moqui_flutter/domain/screen/screen_models.dart';
import 'package:moqui_flutter/presentation/widgets/moqui/widget_factory.dart';
import 'package:moqui_flutter/data/api/moqui_api_client.dart';

/// Phase 9.3: Extended widget tests for form-list features:
/// pagination, row selection, filter panel, toolbar (export, saved finds),
/// aggregate footer, virtual scroll threshold, row-type coloring,
/// _fieldNameToTitle helper, empty state, and pagination button states.

// ---------------------------------------------------------------------------
// Harness
// ---------------------------------------------------------------------------

Widget _testHarness(Widget child) {
  return MaterialApp(
    home: Scaffold(
      body: SizedBox(
        width: 1000,
        height: 900,
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
  void Function(String url)? launchExportUrl,
}) {
  return MoquiRenderContext(
    navigate: navigate ?? (path, {params}) {},
    submitForm: submitForm ?? (url, data) async => null,
    loadDynamic:
        loadDynamic ?? (transition, params) async => <String, dynamic>{},
    contextData: contextData ?? {},
    launchExportUrl: launchExportUrl,
  );
}

/// Build a form-list via WidgetNode.fromJson → MoquiWidgetFactory.build.
Widget _buildFormList(
  Map<String, dynamic> json,
  MoquiRenderContext ctx,
) {
  return _testHarness(
    MoquiWidgetFactory.build(WidgetNode.fromJson(json), ctx),
  );
}

/// Helper: two-column list JSON with pagination.
Map<String, dynamic> _basicListJson({
  List<Map<String, dynamic>>? listData,
  Map<String, dynamic> paginateInfo = const {},
  bool paginate = false,
  bool showCsvButton = false,
  bool showXlsxButton = false,
  bool rowSelection = false,
  String rowSelectionIdField = 'orderId',
  String transition = '',
  List<Map<String, dynamic>>? headerFields,
  List<Map<String, dynamic>>? savedFinds,
  String exportBaseUrl = '',
}) {
  return {
    '_type': 'form-list',
    'formName': 'TestList',
    'listName': 'TestListData',
    if (transition.isNotEmpty) 'transition': transition,
    if (paginate) 'paginate': 'true',
    if (rowSelection)
      'rowSelection': {'idField': rowSelectionIdField, 'parameter': 'selectedRows'},
    if (showCsvButton) 'showCsvButton': 'true',
    if (showXlsxButton) 'showXlsxButton': 'true',
    if (exportBaseUrl.isNotEmpty) 'exportBaseUrl': exportBaseUrl,
    if (paginateInfo.isNotEmpty) 'paginateInfo': paginateInfo,
    if (headerFields != null) 'headerFields': headerFields,
    if (savedFinds != null) 'formSavedFindsList': savedFinds,
    'fields': [
      {
        'name': 'orderId',
        'title': 'Order ID',
        'widgets': [
          {'_type': 'display'}
        ]
      },
      {
        'name': 'status',
        'title': 'Status',
        'widgets': [
          {'_type': 'display'}
        ]
      },
    ],
    'listData': listData ??
        [
          {'orderId': 'ORD001', 'status': 'Active'},
          {'orderId': 'ORD002', 'status': 'Pending'},
          {'orderId': 'ORD003', 'status': 'Closed'},
        ],
  };
}

void main() {
  // =========================================================================
  // Pagination Controls
  // =========================================================================
  group('Form-list pagination', () {
    testWidgets('renders pagination bar with page controls', (tester) async {
      await tester.pumpWidget(_buildFormList(
        _basicListJson(
          paginate: true,
          paginateInfo: {
            'pageIndex': 1,
            'pageMaxIndex': 5,
            'pageSize': 20,
            'pageRangeLow': 21,
            'pageRangeHigh': 40,
            'count': 100,
          },
        ),
        _stubContext(),
      ));
      await tester.pumpAndSettle();

      // All 4 nav buttons present
      expect(find.byIcon(Icons.first_page), findsOneWidget);
      expect(find.byIcon(Icons.chevron_left), findsOneWidget);
      expect(find.byIcon(Icons.chevron_right), findsOneWidget);
      expect(find.byIcon(Icons.last_page), findsOneWidget);

      // Range text
      expect(find.text('21-40 of 100'), findsOneWidget);
    });

    testWidgets('first/previous disabled on first page', (tester) async {
      await tester.pumpWidget(_buildFormList(
        _basicListJson(
          paginate: true,
          paginateInfo: {
            'pageIndex': 0,
            'pageMaxIndex': 5,
            'pageSize': 20,
            'pageRangeLow': 1,
            'pageRangeHigh': 20,
            'count': 100,
          },
        ),
        _stubContext(),
      ));
      await tester.pumpAndSettle();

      // First page and previous page buttons should be disabled
      final firstBtn = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.first_page),
      );
      expect(firstBtn.onPressed, isNull);

      final prevBtn = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.chevron_left),
      );
      expect(prevBtn.onPressed, isNull);

      // Next/last should be enabled
      final nextBtn = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.chevron_right),
      );
      expect(nextBtn.onPressed, isNotNull);
    });

    testWidgets('next/last disabled on last page', (tester) async {
      await tester.pumpWidget(_buildFormList(
        _basicListJson(
          paginate: true,
          paginateInfo: {
            'pageIndex': 5,
            'pageMaxIndex': 5,
            'pageSize': 20,
            'pageRangeLow': 81,
            'pageRangeHigh': 100,
            'count': 100,
          },
        ),
        _stubContext(),
      ));
      await tester.pumpAndSettle();

      final nextBtn = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.chevron_right),
      );
      expect(nextBtn.onPressed, isNull);

      final lastBtn = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.last_page),
      );
      expect(lastBtn.onPressed, isNull);
    });

    testWidgets('clicking next page calls loadDynamic', (tester) async {
      String? lastTransition;
      Map<String, dynamic>? lastParams;
      final ctx = _stubContext(
        loadDynamic: (transition, params) async {
          lastTransition = transition;
          lastParams = params;
          return <String, dynamic>{};
        },
      );

      await tester.pumpWidget(_buildFormList(
        _basicListJson(
          paginate: true,
          paginateInfo: {
            'pageIndex': 1,
            'pageMaxIndex': 5,
            'pageSize': 20,
            'pageRangeLow': 21,
            'pageRangeHigh': 40,
            'count': 100,
          },
        ),
        ctx,
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.chevron_right));
      await tester.pumpAndSettle();

      expect(lastParams, isNotNull);
      expect(lastParams!['pageIndex'], '2');
    });

    testWidgets('clicking first page goes to index 0', (tester) async {
      Map<String, dynamic>? lastParams;
      final ctx = _stubContext(
        loadDynamic: (transition, params) async {
          lastParams = params;
          return <String, dynamic>{};
        },
      );

      await tester.pumpWidget(_buildFormList(
        _basicListJson(
          paginate: true,
          paginateInfo: {
            'pageIndex': 3,
            'pageMaxIndex': 5,
            'pageSize': 20,
            'pageRangeLow': 61,
            'pageRangeHigh': 80,
            'count': 100,
          },
        ),
        ctx,
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.first_page));
      await tester.pumpAndSettle();

      expect(lastParams!['pageIndex'], '0');
    });

    testWidgets('no pagination bar without paginate flag', (tester) async {
      await tester.pumpWidget(_buildFormList(
        _basicListJson(paginate: false),
        _stubContext(),
      ));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.first_page), findsNothing);
      expect(find.byIcon(Icons.last_page), findsNothing);
    });
  });

  // =========================================================================
  // Row Selection
  // =========================================================================
  group('Form-list row selection', () {
    testWidgets('shows checkboxes when rowSelection enabled', (tester) async {
      await tester.pumpWidget(_buildFormList(
        _basicListJson(rowSelection: true),
        _stubContext(),
      ));
      await tester.pumpAndSettle();

      // DataTable with checkboxes
      expect(find.byType(Checkbox), findsAtLeastNWidgets(1));
    });

    testWidgets('no checkboxes when rowSelection disabled', (tester) async {
      await tester.pumpWidget(_buildFormList(
        _basicListJson(rowSelection: false),
        _stubContext(),
      ));
      await tester.pumpAndSettle();

      expect(find.byType(Checkbox), findsNothing);
    });

    testWidgets('selecting rows shows selection action bar', (tester) async {
      await tester.pumpWidget(_buildFormList(
        _basicListJson(rowSelection: true),
        _stubContext(),
      ));
      await tester.pumpAndSettle();

      // No action bar initially
      expect(find.text('Apply to Selected'), findsNothing);

      // Tap a row checkbox — DataTable renders Checkbox widgets for selectable rows
      final checkboxes = find.byType(Checkbox);
      expect(checkboxes, findsAtLeastNWidgets(2)); // header + rows
      // Tap first data row checkbox (index 1; index 0 is the header "select all")
      await tester.tap(checkboxes.at(1));
      await tester.pumpAndSettle();

      // Action bar should appear with "1 selected"
      expect(find.text('1 selected'), findsOneWidget);
      expect(find.text('Apply to Selected'), findsOneWidget);
      expect(find.text('Clear Selection'), findsOneWidget);
    });

    testWidgets('clear selection removes action bar', (tester) async {
      await tester.pumpWidget(_buildFormList(
        _basicListJson(rowSelection: true),
        _stubContext(),
      ));
      await tester.pumpAndSettle();

      // Select a row
      final checkboxes = find.byType(Checkbox);
      expect(checkboxes, findsAtLeastNWidgets(2));
      await tester.tap(checkboxes.at(1));
      await tester.pumpAndSettle();

      expect(find.text('1 selected'), findsOneWidget);

      // Clear selection
      await tester.tap(find.text('Clear Selection'));
      await tester.pumpAndSettle();

      expect(find.text('Apply to Selected'), findsNothing);
    });
  });

  // =========================================================================
  // Export Buttons
  // =========================================================================
  group('Form-list export', () {
    testWidgets('shows CSV export button when enabled', (tester) async {
      await tester.pumpWidget(_buildFormList(
        _basicListJson(
          showCsvButton: true,
          exportBaseUrl: '/api/export',
        ),
        _stubContext(),
      ));
      await tester.pumpAndSettle();

      expect(find.byTooltip('Export CSV'), findsOneWidget);
    });

    testWidgets('shows XLSX export button when enabled', (tester) async {
      await tester.pumpWidget(_buildFormList(
        _basicListJson(
          showXlsxButton: true,
          exportBaseUrl: '/api/export',
        ),
        _stubContext(),
      ));
      await tester.pumpAndSettle();

      expect(find.byTooltip('Export Excel'), findsOneWidget);
    });

    testWidgets('CSV export calls launchExportUrl', (tester) async {
      String? launchedUrl;
      final ctx = _stubContext(
        launchExportUrl: (url) => launchedUrl = url,
      );

      await tester.pumpWidget(_buildFormList(
        _basicListJson(
          showCsvButton: true,
          exportBaseUrl: '/api/export',
        ),
        ctx,
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Export CSV'));
      await tester.pumpAndSettle();

      expect(launchedUrl, contains('renderMode=csv'));
    });

    testWidgets('no export buttons when not configured', (tester) async {
      await tester.pumpWidget(_buildFormList(
        _basicListJson(),
        _stubContext(),
      ));
      await tester.pumpAndSettle();

      expect(find.byTooltip('Export CSV'), findsNothing);
      expect(find.byTooltip('Export Excel'), findsNothing);
    });
  });

  // =========================================================================
  // Filter Panel
  // =========================================================================
  group('Form-list filter panel', () {
    testWidgets('filter toggle shows filter panel', (tester) async {
      await tester.pumpWidget(_buildFormList(
        _basicListJson(
          headerFields: [
            {
              'name': 'searchField',
              'title': 'Search',
              'widgets': [
                {'_type': 'text-line'}
              ]
            }
          ],
        ),
        _stubContext(),
      ));
      await tester.pumpAndSettle();

      // Filter panel not visible initially
      expect(find.text('Find'), findsNothing);

      // Toggle filters — find the filter button (funnel icon or text)
      final filterToggle = find.byTooltip('Toggle Filters');
      if (filterToggle.evaluate().isNotEmpty) {
        await tester.tap(filterToggle);
      } else {
        // Fallback: look for filter_list icon
        await tester.tap(find.byIcon(Icons.filter_list));
      }
      await tester.pumpAndSettle();

      // Filter panel should show Clear and Find buttons
      expect(find.text('Find'), findsOneWidget);
      expect(find.text('Clear'), findsOneWidget);
    });

    testWidgets('clicking Find submits filter form', (tester) async {
      String? lastUrl;
      Map<String, dynamic>? lastData;
      final ctx = _stubContext(
        submitForm: (url, data) async {
          lastUrl = url;
          lastData = data;
          return null;
        },
      );

      await tester.pumpWidget(_buildFormList(
        _basicListJson(
          transition: 'searchOrders',
          headerFields: [
            {
              'name': 'searchField',
              'title': 'Search',
              'widgets': [
                {'_type': 'text-line'}
              ]
            }
          ],
        ),
        ctx,
      ));
      await tester.pumpAndSettle();

      // Open filters
      await tester.tap(find.byIcon(Icons.filter_list));
      await tester.pumpAndSettle();

      // Tap Find
      await tester.tap(find.text('Find'));
      await tester.pumpAndSettle();

      expect(lastUrl, 'searchOrders');
    });
  });

  // =========================================================================
  // Aggregate Footer
  // =========================================================================
  group('Form-list aggregate footer', () {
    testWidgets('shows total when showTotal attribute set', (tester) async {
      await tester.pumpWidget(_buildFormList(
        {
          '_type': 'form-list',
          'formName': 'TestAgg',
          'fields': [
            {
              'name': 'amount',
              'title': 'Amount',
              'widgets': [
                {
                  '_type': 'display',
                  'showTotal': 'true',
                  'showCount': 'true',
                }
              ]
            }
          ],
          'listData': [
            {'amount': '100'},
            {'amount': '200'},
            {'amount': '50'},
          ],
        },
        _stubContext(),
      ));
      await tester.pumpAndSettle();

      expect(find.textContaining('Total: 350'), findsOneWidget);
      expect(find.textContaining('Count: 3'), findsOneWidget);
    });

    testWidgets('shows avg/min/max when configured', (tester) async {
      await tester.pumpWidget(_buildFormList(
        {
          '_type': 'form-list',
          'formName': 'TestAgg2',
          'fields': [
            {
              'name': 'price',
              'title': 'Price',
              'widgets': [
                {
                  '_type': 'display',
                  'showAvg': 'true',
                  'showMin': 'true',
                  'showMax': 'true',
                }
              ]
            }
          ],
          'listData': [
            {'price': '10'},
            {'price': '20'},
            {'price': '30'},
          ],
        },
        _stubContext(),
      ));
      await tester.pumpAndSettle();

      expect(find.textContaining('Avg: 20'), findsOneWidget);
      expect(find.textContaining('Min: 10'), findsOneWidget);
      expect(find.textContaining('Max: 30'), findsOneWidget);
    });

    testWidgets('no aggregate footer when no flags set', (tester) async {
      await tester.pumpWidget(_buildFormList(
        _basicListJson(listData: [
          {'orderId': 'ORD001', 'status': 'Active'},
        ]),
        _stubContext(),
      ));
      await tester.pumpAndSettle();

      expect(find.textContaining('Total:'), findsNothing);
      expect(find.textContaining('Count:'), findsNothing);
    });
  });

  // =========================================================================
  // Row-type Coloring
  // =========================================================================
  group('Form-list row-type coloring', () {
    testWidgets('renders rows with _rowType field', (tester) async {
      await tester.pumpWidget(_buildFormList(
        _basicListJson(
          listData: [
            {'orderId': 'ORD001', 'status': 'Active', '_rowType': 'success'},
            {'orderId': 'ORD002', 'status': 'Overdue', '_rowType': 'danger'},
            {'orderId': 'ORD003', 'status': 'Normal'},
          ],
        ),
        _stubContext(),
      ));
      await tester.pumpAndSettle();

      // All three rows should render
      expect(find.text('ORD001'), findsOneWidget);
      expect(find.text('ORD002'), findsOneWidget);
      expect(find.text('ORD003'), findsOneWidget);
    });
  });

  // =========================================================================
  // Empty State
  // =========================================================================
  group('Form-list empty state', () {
    testWidgets('shows No records found for empty listData', (tester) async {
      await tester.pumpWidget(_buildFormList(
        _basicListJson(listData: []),
        _stubContext(),
      ));
      await tester.pumpAndSettle();

      expect(find.text('No records found'), findsOneWidget);
    });
  });

  // =========================================================================
  // Column Headers & Sorting
  // =========================================================================
  group('Form-list column headers', () {
    testWidgets('renders column headers from field titles', (tester) async {
      await tester.pumpWidget(_buildFormList(
        _basicListJson(),
        _stubContext(),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Order ID'), findsOneWidget);
      expect(find.text('Status'), findsOneWidget);
    });

    testWidgets('clicking column header triggers sort via loadDynamic',
        (tester) async {
      Map<String, dynamic>? lastParams;
      final ctx = _stubContext(
        loadDynamic: (transition, params) async {
          lastParams = params;
          return <String, dynamic>{};
        },
      );

      await tester.pumpWidget(_buildFormList(
        _basicListJson(),
        ctx,
      ));
      await tester.pumpAndSettle();

      // Tap on 'Order ID' column header to sort
      await tester.tap(find.text('Order ID'));
      await tester.pumpAndSettle();

      expect(lastParams, isNotNull);
      expect(lastParams!['orderByField'], contains('orderId'));
      expect(lastParams!['pageIndex'], '0');
    });
  });

  // =========================================================================
  // Toolbar: Page-size selector
  // =========================================================================
  group('Form-list page-size selector', () {
    testWidgets('shows page size when paginated', (tester) async {
      await tester.pumpWidget(_buildFormList(
        _basicListJson(
          paginate: true,
          paginateInfo: {
            'pageIndex': 0,
            'pageMaxIndex': 5,
            'pageSize': 20,
            'pageRangeLow': 1,
            'pageRangeHigh': 20,
            'count': 100,
          },
        ),
        _stubContext(),
      ));
      await tester.pumpAndSettle();

      // Page size selector should be visible in toolbar
      expect(find.textContaining('20'), findsAtLeastNWidgets(1));
    });
  });

  // =========================================================================
  // Data Cell Rendering
  // =========================================================================
  group('Form-list data cells', () {
    testWidgets('renders cell text from listData', (tester) async {
      await tester.pumpWidget(_buildFormList(
        _basicListJson(),
        _stubContext(),
      ));
      await tester.pumpAndSettle();

      expect(find.text('ORD001'), findsOneWidget);
      expect(find.text('Active'), findsOneWidget);
      expect(find.text('ORD002'), findsOneWidget);
      expect(find.text('Pending'), findsOneWidget);
    });

    testWidgets('renders correct number of data rows', (tester) async {
      await tester.pumpWidget(_buildFormList(
        _basicListJson(),
        _stubContext(),
      ));
      await tester.pumpAndSettle();

      // 3 data rows
      expect(find.text('ORD001'), findsOneWidget);
      expect(find.text('ORD002'), findsOneWidget);
      expect(find.text('ORD003'), findsOneWidget);
    });
  });

  // =========================================================================
  // Virtual Scroll Threshold
  // =========================================================================
  group('Form-list virtual scroll', () {
    testWidgets('uses DataTable for small lists', (tester) async {
      await tester.pumpWidget(_buildFormList(
        _basicListJson(), // 3 rows, well below 100 threshold
        _stubContext(),
      ));
      await tester.pumpAndSettle();

      expect(find.byType(DataTable), findsOneWidget);
    });

    testWidgets('uses ListView.builder for large lists (> 100 rows)',
        (tester) async {
      // Generate 110 rows
      final largeData = List.generate(
        110,
        (i) => {'orderId': 'ORD${i.toString().padLeft(3, '0')}', 'status': 'Active'},
      );

      await tester.pumpWidget(_buildFormList(
        _basicListJson(listData: largeData),
        _stubContext(),
      ));
      await tester.pumpAndSettle();

      // Should NOT use DataTable
      expect(find.byType(DataTable), findsNothing);
      // Should use ListView
      expect(find.byType(ListView), findsOneWidget);
    });
  });
}
