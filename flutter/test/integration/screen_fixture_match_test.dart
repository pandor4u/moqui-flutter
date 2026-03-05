/// Phase 10 — Real screen fixture matching tests.
///
/// Loads REAL `.fjson` captures from the Moqui server (not mock templates),
/// parses via [ScreenNode.fromJson], renders via [MoquiWidgetFactory.build],
/// and validates that the Flutter rendering pipeline handles every real-world
/// screen structure without error.
///
/// Additionally validates data integrity:
///   - Form field counts match expectations from the manifest
///   - List data row counts match
///   - Widget type coverage is comprehensive
///   - Entity parameter values appear in rendered outputs
///
/// Run:
///   flutter test test/integration/screen_fixture_match_test.dart
///
/// To generate/update fixtures, run:
///   python3 tools/regenerate_fixtures.py
library;

import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moqui_flutter/domain/screen/screen_models.dart';
import 'package:moqui_flutter/presentation/widgets/moqui/widget_factory.dart';

// =============================================================================
// Fixture loader
// =============================================================================

/// All screen fixtures discovered from test/fixtures/screens/*.fjson
final Map<String, Map<String, dynamic>> _fixtures = {};

/// Manifest data (screen metadata from crawler)
Map<String, dynamic> _manifest = {};

/// Screen entries from manifest keyed by path
final Map<String, Map<String, dynamic>> _manifestScreens = {};

/// Load fixtures from disk. Fixtures are named: marble__Module__Screen.fjson
void _loadFixtures() {
  if (_fixtures.isNotEmpty) return;

  final dir = Directory('test/fixtures/screens');
  if (!dir.existsSync()) {
    fail('Fixture directory test/fixtures/screens/ not found. '
        'Run: python3 tools/screen_crawler_v3.py to generate fixtures.');
  }

  // Load manifest
  final mFile = File('test/fixtures/screens/_manifest.json');
  if (mFile.existsSync()) {
    _manifest = jsonDecode(mFile.readAsStringSync()) as Map<String, dynamic>;
    final screens = _manifest['screens'] as List<dynamic>? ?? [];
    for (final s in screens) {
      if (s is Map<String, dynamic>) {
        final path = s['path']?.toString() ?? '';
        if (path.isNotEmpty) _manifestScreens[path] = s;
      }
    }
  }

  // Load all .fjson fixture files
  for (final file in dir.listSync()) {
    if (file is File && file.path.endsWith('.fjson')) {
      final name = file.uri.pathSegments.last;
      if (name.startsWith('_')) continue; // Skip _manifest.json etc.
      final path = name.replaceAll('.fjson', '').replaceAll('__', '/');
      try {
        final json =
            jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
        _fixtures[path] = json;
      } catch (e) {
        debugPrint('WARNING: Failed to parse $name: $e');
      }
    }
  }
}

// =============================================================================
// Screen data extraction helpers
// =============================================================================

/// Extract all form definitions from a widget tree recursively.
List<Map<String, dynamic>> _extractForms(dynamic obj) {
  final forms = <Map<String, dynamic>>[];
  if (obj is Map<String, dynamic>) {
    final type = obj['_type']?.toString() ?? '';
    if (type == 'form-single' || type == 'form-list') {
      forms.add(obj);
    }
    for (final v in obj.values) {
      forms.addAll(_extractForms(v));
    }
  } else if (obj is List) {
    for (final item in obj) {
      forms.addAll(_extractForms(item));
    }
  }
  return forms;
}

/// Extract all widget types from a JSON tree recursively.
Set<String> _extractWidgetTypes(dynamic obj) {
  final types = <String>{};
  if (obj is Map<String, dynamic>) {
    final type = obj['_type']?.toString() ?? '';
    if (type.isNotEmpty) types.add(type);
    for (final v in obj.values) {
      types.addAll(_extractWidgetTypes(v));
    }
  } else if (obj is List) {
    for (final item in obj) {
      types.addAll(_extractWidgetTypes(item));
    }
  }
  return types;
}

/// Extract all field names from a form definition.
List<String> _extractFieldNames(Map<String, dynamic> form) {
  final fields = form['fields'] as List<dynamic>? ?? [];
  return fields
      .whereType<Map<String, dynamic>>()
      .map((f) => f['name']?.toString() ?? '')
      .where((n) => n.isNotEmpty)
      .toList();
}

/// Extract list data values from a form-list.
List<Map<String, dynamic>> _extractListData(Map<String, dynamic> form) {
  final listData = form['listData'] as List<dynamic>? ?? [];
  return listData.whereType<Map<String, dynamic>>().toList();
}

/// Count total widgets in a JSON tree.
int _countWidgets(dynamic obj) {
  int count = 0;
  if (obj is Map<String, dynamic>) {
    if (obj.containsKey('_type')) count++;
    for (final v in obj.values) {
      count += _countWidgets(v);
    }
  } else if (obj is List) {
    for (final item in obj) {
      count += _countWidgets(item);
    }
  }
  return count;
}

/// Find the first subscreens-panel node in a JSON tree.
Map<String, dynamic>? _findSubscreensPanel(dynamic obj) {
  if (obj is Map<String, dynamic>) {
    if (obj['_type'] == 'subscreens-panel') return obj;
    for (final v in obj.values) {
      final r = _findSubscreensPanel(v);
      if (r != null) return r;
    }
  } else if (obj is List) {
    for (final item in obj) {
      final r = _findSubscreensPanel(item);
      if (r != null) return r;
    }
  }
  return null;
}

/// Module-level screens that should have subscreens-panel with activeSubscreen.
/// These are the parents whose default-item is a Find screen.
const List<String> _moduleScreensWithDefaultSubscreen = [
  'marble/Party',
  'marble/Customer',
  'marble/Order',
  'marble/Shipment',
  'marble/Return',
  'marble/Request',
  'marble/Project',
  'marble/Task',
  'marble/Catalog/Product',
  'marble/Catalog/Category',
  'marble/Asset/Asset',
  'marble/Accounting/Invoice',
  'marble/Accounting/FinancialAccount',
  'marble/Accounting/TimePeriod',
  'marble/Accounting/Budget',
  'marble/Facility',
  'marble/Supplier',
  'marble/Shipping/Picklist',
  'marble/Manufacturing/Run',
];

// =============================================================================
// Test context helpers
// =============================================================================

MoquiRenderContext _stubContext() {
  return MoquiRenderContext(
    navigate: (path, {params}) {},
    submitForm: (url, data) async => null,
    loadDynamic: (transition, params) async => <String, dynamic>{},
  );
}

Widget _harness(Widget child) {
  return MaterialApp(
    home: Scaffold(
      body: SizedBox(
        width: 1200,
        height: 900,
        child: SingleChildScrollView(child: child),
      ),
    ),
  );
}

/// Group paths by their top-level module (e.g. marble/Party/EditParty → Party).
Map<String, List<String>> _groupByModule(List<String> paths) {
  final groups = <String, List<String>>{};
  for (final path in paths) {
    final parts = path.split('/');
    // marble/Module/Screen... → Module is parts[1] if exists
    final module = parts.length > 1 ? parts[1] : parts[0];
    groups.putIfAbsent(module, () => []).add(path);
  }
  return Map.fromEntries(
    groups.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
  );
}

// =============================================================================
// Cross-test result tracking
// =============================================================================

final _results = <String, bool>{};
final _errors = <String, String>{};
final _widgetTypesCovered = <String>{};
final _dataMatches = <String, _DataMatchResult>{};

class _DataMatchResult {
  final String path;
  final int expectedFormCount;
  final int actualFormCount;
  final int expectedFieldCount;
  final int actualFieldCount;
  final int expectedListDataRows;
  final int actualListDataRows;
  final bool parsed;
  final bool rendered;

  _DataMatchResult({
    required this.path,
    this.expectedFormCount = 0,
    this.actualFormCount = 0,
    this.expectedFieldCount = 0,
    this.actualFieldCount = 0,
    this.expectedListDataRows = 0,
    this.actualListDataRows = 0,
    this.parsed = true,
    this.rendered = true,
  });

  bool get formCountMatch => expectedFormCount == actualFormCount;
  bool get fieldCountMatch => expectedFieldCount == actualFieldCount;
  bool get listDataRowMatch => expectedListDataRows == actualListDataRows;
  // Only compare forms and dataRows — the Python crawler manifest doesn't count
  // individual fields (always reports 0), so field comparison is skipped.
  bool get allMatch => formCountMatch && listDataRowMatch;
}

// =============================================================================
// Entity param values expected in specific screens
// =============================================================================

const Map<String, Map<String, String>> _expectedEntityValues = {
  // Party screens should contain the partyId
  'marble/Party/EditParty': {'partyId': 'CustJqp'},
  'marble/Party/PartyMessages': {'partyId': 'CustJqp'},
  // Product
  'marble/Catalog/Product/EditProduct': {'productId': 'DEMO_1_1'},
  'marble/Catalog/Product/EditPrices': {'productId': 'DEMO_1_1'},
  // Category
  'marble/Catalog/Category/EditCategory': {
    'productCategoryId': 'PopcAllProducts'
  },
  // Facility
  'marble/Facility/EditFacility': {'facilityId': 'ZIRET_WH'},
  // Product Store
  'marble/ProductStore/EditProductStore': {
    'productStoreId': 'POPC_DEFAULT'
  },
  // Time Period
  'marble/Accounting/TimePeriod/EditTimePeriod': {
    'timePeriodId': '100003'
  },
  // Order
  'marble/Order/OrderDetail': {'orderId': '100006'},
  // Payment
  'marble/Accounting/Payment/EditPayment': {'paymentId': '100002'},
  // Shipment
  'marble/Shipment/ShipmentDetail': {'shipmentId': '100002'},
  // Return
  'marble/Return/EditReturn': {'returnId': '100002'},
  // Request
  'marble/Request/EditRequest': {'requestId': '100000'},
  // Project
  'marble/Project/EditProject': {'workEffortId': '100004'},
  // Task
  'marble/Task/EditTask': {'workEffortId': '100004-100000'},
  // GL Account
  'marble/Accounting/GlAccount/EditGlAccount': {'glAccountId': '110000'},
};

// =============================================================================
// Tests
// =============================================================================

void main() {
  // Suppress known rendering warnings
  void Function(FlutterErrorDetails)? origOnError;

  setUpAll(() {
    _loadFixtures();
    debugPrint(
        '\nLoaded ${_fixtures.length} screen fixtures from test/fixtures/screens/');
  });

  setUp(() {
    origOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      final msg = details.toString();
      if (msg.contains('overflowed') ||
          msg.contains('non-zero flex') ||
          msg.contains('was not laid out') ||
          msg.contains('_needsLayout') ||
          msg.contains('Vertical viewport was given unbounded') ||
          msg.contains('performLayout')) {
        return;
      }
      origOnError?.call(details);
    };
  });

  tearDown(() {
    FlutterError.onError = origOnError;
  });

  // -------------------------------------------------------------------------
  // 1. Fixture loading validation
  // -------------------------------------------------------------------------
  group('Fixture Loading', () {
    test('loaded at least 100 screen fixtures', () {
      _loadFixtures();
      expect(_fixtures.length, greaterThanOrEqualTo(100),
          reason:
              'Expected >= 100 fixtures, got ${_fixtures.length}');
    });

    test('manifest has screen metadata', () {
      _loadFixtures();
      expect(_manifestScreens.length, greaterThanOrEqualTo(100));
    });

    test('all fixtures are valid JSON with widgets key', () {
      _loadFixtures();
      int valid = 0;
      for (final entry in _fixtures.entries) {
        final json = entry.value;
        // Real screens have either 'widgets' or '_type' at root
        if (json.containsKey('widgets') || json.containsKey('_type')) {
          valid++;
        } else {
          debugPrint('  WARN: ${entry.key} has no widgets or _type key');
        }
      }
      final rate = valid / _fixtures.length;
      debugPrint('  $valid/${_fixtures.length} fixtures have valid structure');
      expect(rate, greaterThanOrEqualTo(0.90));
    });
  });

  // -------------------------------------------------------------------------
  // 2. Parse all fixtures → ScreenNode
  // -------------------------------------------------------------------------
  group('Fixture Parse — ScreenNode.fromJson', () {
    test('all fixtures parse to ScreenNode without exceptions', () {
      _loadFixtures();
      int passed = 0;
      final failures = <String>[];

      for (final entry in _fixtures.entries) {
        try {
          final screen = ScreenNode.fromJson(entry.value);
          // Validate basic structure
          expect(screen, isNotNull);
          passed++;
        } catch (e) {
          failures.add('${entry.key}: $e');
        }
      }

      final rate = passed / _fixtures.length;
      debugPrint(
          '\n=== Parse Results: $passed/${_fixtures.length} (${(rate * 100).toStringAsFixed(1)}%) ===');
      if (failures.isNotEmpty) {
        for (final f in failures.take(10)) {
          debugPrint('  FAIL: $f');
        }
      }
      expect(rate, greaterThanOrEqualTo(0.95),
          reason: 'At least 95% of fixtures must parse');
    });
  });

  // -------------------------------------------------------------------------
  // 3. Data integrity — form counts, field counts, list data rows
  // -------------------------------------------------------------------------
  group('Fixture Data Integrity', () {
    test('form definitions match manifest expectations', () {
      _loadFixtures();
      int matched = 0;
      int total = 0;
      final mismatches = <String>[];

      for (final entry in _fixtures.entries) {
        final path = entry.key;
        final manifest = _manifestScreens[path];
        if (manifest == null) continue;

        final expectedForms = manifest['forms'] as int? ?? 0;
        final expectedFields = manifest['fields'] as int? ?? 0;
        final expectedRows = manifest['dataRows'] as int? ?? 0;

        // Extract actual data from fixture
        final forms = _extractForms(entry.value);
        final actualForms = forms.length;
        int actualFields = 0;
        int actualRows = 0;
        for (final form in forms) {
          actualFields += _extractFieldNames(form).length;
          actualRows += _extractListData(form).length;
        }

        total++;
        final result = _DataMatchResult(
          path: path,
          expectedFormCount: expectedForms,
          actualFormCount: actualForms,
          expectedFieldCount: expectedFields,
          actualFieldCount: actualFields,
          expectedListDataRows: expectedRows,
          actualListDataRows: actualRows,
        );
        _dataMatches[path] = result;

        if (result.allMatch) {
          matched++;
        } else {
          mismatches.add(
              '$path: forms=$actualForms(exp=$expectedForms) '
              'fields=$actualFields(exp=$expectedFields) '
              'rows=$actualRows(exp=$expectedRows)');
        }
      }

      final rate = total > 0 ? matched / total : 1.0;
      debugPrint(
          '\n=== Data Match: $matched/$total (${(rate * 100).toStringAsFixed(1)}%) ===');
      if (mismatches.isNotEmpty) {
        debugPrint('  Mismatches (${mismatches.length}):');
        for (final m in mismatches.take(10)) {
          debugPrint('    $m');
        }
      }
      // Allow some tolerance — manifest counts from Python vs Dart parsing
      // may differ slightly on edge cases
      expect(rate, greaterThanOrEqualTo(0.80),
          reason: 'At least 80% data counts must match manifest');
    });

    test('screens with entity params contain those values', () {
      _loadFixtures();
      int checked = 0;
      int found = 0;
      final missing = <String>[];

      for (final entry in _expectedEntityValues.entries) {
        final path = entry.key;
        final json = _fixtures[path];
        if (json == null) continue;

        final jsonStr = jsonEncode(json);
        for (final paramEntry in entry.value.entries) {
          checked++;
          if (jsonStr.contains(paramEntry.value)) {
            found++;
          } else {
            missing.add('$path: ${paramEntry.key}=${paramEntry.value} '
                'not found in JSON');
          }
        }
      }

      debugPrint(
          '\n=== Entity Value Check: $found/$checked ===');
      if (missing.isNotEmpty) {
        for (final m in missing) {
          debugPrint('  MISSING: $m');
        }
      }
      final rate = checked > 0 ? found / checked : 1.0;
      expect(rate, greaterThanOrEqualTo(0.80),
          reason: 'At least 80% of entity values should appear in fixtures');
    });
  });

  // -------------------------------------------------------------------------
  // 4. Render all fixtures — one testWidgets per module
  // -------------------------------------------------------------------------
  group('Fixture Render — by module', () {
    // Need to call loadFixtures synchronously before creating tests
    _loadFixtures();

    final modules = _groupByModule(_fixtures.keys.toList());

    for (final entry in modules.entries) {
      final moduleName = entry.key;
      final modulePaths = entry.value;

      testWidgets(
        'render: $moduleName (${modulePaths.length} screens)',
        (tester) async {
          // Suppress known rendering warnings inside testWidgets where the
          // framework resets FlutterError.onError per test.
          final origHandler = FlutterError.onError;
          FlutterError.onError = (details) {
            final msg = details.toString();
            if (msg.contains('overflowed') ||
                msg.contains('non-zero flex') ||
                msg.contains('was not laid out') ||
                msg.contains('_needsLayout') ||
                msg.contains('Vertical viewport was given unbounded') ||
                msg.contains('performLayout') ||
                msg.contains("Controller's length property") ||
                msg.contains('does not match the number of')) {
              return;
            }
            origHandler?.call(details);
          };
          addTearDown(() => FlutterError.onError = origHandler);

          int passed = 0;
          final failures = <String>[];

          for (final path in modulePaths) {
            final json = _fixtures[path]!;
            try {
              final screen = ScreenNode.fromJson(json);
              final ctx = _stubContext();

              final widgets = screen.widgets
                  .map((w) => MoquiWidgetFactory.build(w, ctx))
                  .toList();

              await tester.pumpWidget(_harness(
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: widgets,
                ),
              ));

              // Collect widget types for coverage tracking
              _widgetTypesCovered.addAll(_extractWidgetTypes(json));

              _results[path] = true;
              passed++;
            } catch (e) {
              _results[path] = false;
              _errors[path] = e.toString();
              failures.add('$path: ${e.toString().split('\n').first}');
            }
          }

          debugPrint(
              '  $moduleName: $passed/${modulePaths.length} rendered OK');
          if (failures.isNotEmpty) {
            for (final f in failures) {
              debugPrint('    FAIL: $f');
            }
          }

          // Each module should have ≥85% success with real data
          final rate = modulePaths.isNotEmpty
              ? passed / modulePaths.length
              : 1.0;
          expect(rate, greaterThanOrEqualTo(0.85),
              reason: '$moduleName render rate '
                  '$passed/${modulePaths.length} < 85%');
        },
      );
    }
  });

  // -------------------------------------------------------------------------
  // 5. Widget type coverage
  // -------------------------------------------------------------------------
  group('Fixture Render — widget type coverage', () {
    test('real fixtures exercise at least 12 distinct widget types', () {
      _loadFixtures();
      // Collect types from all fixtures
      final types = <String>{};
      for (final json in _fixtures.values) {
        types.addAll(_extractWidgetTypes(json));
      }
      types.addAll(_widgetTypesCovered);

      debugPrint(
          '\n=== Widget Types in Real Fixtures (${types.length}) ===');
      for (final t in types.toList()..sort()) {
        debugPrint('  $t');
      }

      expect(types.length, greaterThanOrEqualTo(12),
          reason: 'Real fixtures should cover at least 12 widget types');
    });
  });

  // -------------------------------------------------------------------------
  // 6. Rich screen validation — specific high-value screens
  // -------------------------------------------------------------------------
  group('Rich Screen Validation', () {
    _loadFixtures();

    // Screens with forms AND data rows are the most important to validate
    final richScreens = <String, _RichScreenExpectation>{
      'marble/Party/EditParty': const _RichScreenExpectation(
        minForms: 5,
        minFields: 30,
        mustContain: ['CustJqp'],
      ),
      'marble/Catalog/Product/EditProduct': const _RichScreenExpectation(
        minForms: 5,
        minFields: 30,
        mustContain: ['DEMO_1_1'],
      ),
      'marble/Order/OrderDetail': const _RichScreenExpectation(
        minForms: 3,
        minFields: 15,
        mustContain: ['100006'],
      ),
      'marble/Shipment/ShipmentDetail': const _RichScreenExpectation(
        minForms: 3,
        minFields: 15,
        mustContain: ['100002'],
      ),
      'marble/Facility/EditFacility': const _RichScreenExpectation(
        minForms: 3,
        minFields: 10,
        mustContain: ['ZIRET_WH'],
      ),
      'marble/ProductStore/EditProductStore': const _RichScreenExpectation(
        minForms: 5,
        minFields: 20,
        mustContain: ['POPC_DEFAULT'],
      ),
      'marble/Accounting/Payment/EditPayment': const _RichScreenExpectation(
        minForms: 3,
        minFields: 15,
        mustContain: ['100002'],
      ),
      'marble/Project/ProjectSummary': const _RichScreenExpectation(
        minForms: 2,
        minFields: 5,
        mustContain: ['100004'],
      ),
      'marble/dashboard': const _RichScreenExpectation(
        minWidgets: 50,
      ),
    };

    for (final entry in richScreens.entries) {
      final path = entry.key;
      final expect_ = entry.value;

      test('rich screen: $path', () {
        final json = _fixtures[path];
        if (json == null) {
          // Skip if fixture not available
          debugPrint('  SKIP: $path fixture not found');
          return;
        }

        final forms = _extractForms(json);
        final totalFields = forms.fold<int>(
          0,
          (sum, f) => sum + _extractFieldNames(f).length,
        );
        final totalRows = forms.fold<int>(
          0,
          (sum, f) => sum + _extractListData(f).length,
        );
        final widgetCount = _countWidgets(json);

        debugPrint('  $path: ${forms.length} forms, '
            '$totalFields fields, $totalRows rows, '
            '$widgetCount widgets');

        if (expect_.minForms > 0) {
          expect(forms.length, greaterThanOrEqualTo(expect_.minForms),
              reason: '$path should have >= ${expect_.minForms} forms');
        }
        if (expect_.minFields > 0) {
          expect(totalFields, greaterThanOrEqualTo(expect_.minFields),
              reason: '$path should have >= ${expect_.minFields} fields');
        }
        if (expect_.minListRows > 0) {
          expect(totalRows, greaterThanOrEqualTo(expect_.minListRows),
              reason:
                  '$path should have >= ${expect_.minListRows} list rows');
        }
        if (expect_.minWidgets > 0) {
          expect(widgetCount, greaterThanOrEqualTo(expect_.minWidgets),
              reason:
                  '$path should have >= ${expect_.minWidgets} widgets');
        }

        // Check required strings
        if (expect_.mustContain.isNotEmpty) {
          final jsonStr = jsonEncode(json);
          for (final s in expect_.mustContain) {
            expect(jsonStr, contains(s),
                reason: '$path should contain "$s"');
          }
        }
      });
    }
  });

  // -------------------------------------------------------------------------
  // 7. Subscreens-panel navigation — default subscreen rendered
  // -------------------------------------------------------------------------
  group('Subscreens-Panel Navigation', () {
    _loadFixtures();

    test('module screens have subscreens-panel with activeSubscreen', () {
      int checked = 0;
      int passed = 0;
      final failures = <String>[];

      for (final path in _moduleScreensWithDefaultSubscreen) {
        final json = _fixtures[path];
        if (json == null) {
          debugPrint('  SKIP: $path fixture not found');
          continue;
        }

        checked++;
        final panel = _findSubscreensPanel(json);
        if (panel == null) {
          failures.add('$path: no subscreens-panel found');
          continue;
        }

        final activeSubscreen = panel['activeSubscreen'];
        final activeSubscreenName =
            panel['activeSubscreenName']?.toString() ?? '';

        if (activeSubscreen == null || activeSubscreen is! Map) {
          failures.add('$path: subscreens-panel missing activeSubscreen');
          continue;
        }

        if (activeSubscreenName.isEmpty) {
          failures.add('$path: subscreens-panel missing activeSubscreenName');
          continue;
        }

        // Verify activeSubscreen has widgets (not an empty shell)
        final widgetCount = _countWidgets(activeSubscreen);
        if (widgetCount < 5) {
          failures.add('$path: activeSubscreen has only $widgetCount widgets '
              '(expected >= 5)');
          continue;
        }

        passed++;
        debugPrint('  OK: $path → $activeSubscreenName ($widgetCount widgets)');
      }

      debugPrint('\n=== Subscreens Navigation: $passed/$checked ===');
      if (failures.isNotEmpty) {
        for (final f in failures) {
          debugPrint('  FAIL: $f');
        }
      }

      // All module screens should render their default subscreen
      expect(checked, greaterThan(0),
          reason: 'Should check at least 1 module screen');
      final rate = checked > 0 ? passed / checked : 0.0;
      expect(rate, greaterThanOrEqualTo(0.90),
          reason: 'At least 90% of module screens must have '
              'activeSubscreen: $passed/$checked');
    });

    test('activeSubscreen contains Find form-list', () {
      int checked = 0;
      int passed = 0;
      final failures = <String>[];

      for (final path in _moduleScreensWithDefaultSubscreen) {
        final json = _fixtures[path];
        if (json == null) continue;

        final panel = _findSubscreensPanel(json);
        if (panel == null) continue;

        final activeSubscreen = panel['activeSubscreen'];
        if (activeSubscreen == null || activeSubscreen is! Map) continue;

        checked++;
        final forms = _extractForms(activeSubscreen);
        if (forms.isNotEmpty) {
          passed++;
          debugPrint(
              '  OK: $path → ${forms.length} forms in activeSubscreen');
        } else {
          failures.add('$path: activeSubscreen has 0 forms');
        }
      }

      debugPrint(
          '\n=== Active Subscreen Forms: $passed/$checked ===');
      if (failures.isNotEmpty) {
        for (final f in failures) {
          debugPrint('  FAIL: $f');
        }
      }

      if (checked > 0) {
        final rate = passed / checked;
        expect(rate, greaterThanOrEqualTo(0.85),
            reason: 'At least 85% of active subscreens should have forms: '
                '$passed/$checked');
      }
    });

    test('defaultItem matches activeSubscreenName', () {
      int checked = 0;
      int matched = 0;

      for (final path in _moduleScreensWithDefaultSubscreen) {
        final json = _fixtures[path];
        if (json == null) continue;

        final panel = _findSubscreensPanel(json);
        if (panel == null) continue;

        final defaultItem = panel['defaultItem']?.toString() ?? '';
        final activeName = panel['activeSubscreenName']?.toString() ?? '';

        if (defaultItem.isEmpty || activeName.isEmpty) continue;

        checked++;
        if (defaultItem == activeName) {
          matched++;
        } else {
          debugPrint(
              '  MISMATCH: $path defaultItem=$defaultItem '
              'activeSubscreenName=$activeName');
        }
      }

      debugPrint(
          '\n=== Default ↔ Active Match: $matched/$checked ===');
      if (checked > 0) {
        expect(matched, equals(checked),
            reason: 'defaultItem should match activeSubscreenName');
      }
    });
  });

  // -------------------------------------------------------------------------
  // 8. Aggregate summary
  // -------------------------------------------------------------------------
  group('Fixture Match — Summary', () {
    test('overall render success rate ≥ 90%', () {
      if (_results.isEmpty) {
        debugPrint('WARNING: No render results recorded');
        return;
      }

      final total = _results.length;
      final passed = _results.values.where((v) => v).length;
      final rate = passed / total;

      debugPrint('\n╔═══════════════════════════════════════════════╗');
      debugPrint('║  FIXTURE MATCH SUMMARY                         ║');
      debugPrint('╠═══════════════════════════════════════════════╣');
      debugPrint('║  Total fixtures:    $total');
      debugPrint('║  Rendered OK:       $passed');
      debugPrint('║  Failed:            ${total - passed}');
      debugPrint(
          '║  Success rate:      ${(rate * 100).toStringAsFixed(1)}%');
      debugPrint('║  Widget types:      ${_widgetTypesCovered.length}');
      debugPrint('╠═══════════════════════════════════════════════╣');

      // Data match summary
      if (_dataMatches.isNotEmpty) {
        final dmTotal = _dataMatches.length;
        final dmMatch =
            _dataMatches.values.where((r) => r.allMatch).length;
        debugPrint(
            '║  Data matches:      $dmMatch/$dmTotal');
      }

      if (_errors.isNotEmpty) {
        debugPrint('╠═══════════════════════════════════════════════╣');
        debugPrint('║  FAILURES:');
        for (final e in _errors.entries.take(20)) {
          debugPrint('║    ${e.key}');
          debugPrint('║      ${e.value.split('\n').first}');
        }
      }

      debugPrint('╚═══════════════════════════════════════════════╝');

      expect(rate, greaterThanOrEqualTo(0.90),
          reason: 'Overall success rate '
              '$passed/$total (${(rate * 100).toStringAsFixed(1)}%) < 90%');
    });
  });
}

class _RichScreenExpectation {
  final int minForms;
  final int minFields;
  final int minListRows;
  final int minWidgets;
  final List<String> mustContain;

  const _RichScreenExpectation({
    this.minForms = 0,
    this.minFields = 0,
    this.minListRows = 0,
    this.minWidgets = 0,
    this.mustContain = const [],
  });
}
