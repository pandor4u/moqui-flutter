import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moqui_flutter/domain/tools/tool_models.dart';
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
  // 1. CACHE INFO MODEL
  // ===========================================================================

  group('CacheInfo Model', () {
    test('fromJson parses all fields', () {
      final json = {
        'name': 'entity.cache.TestEntity',
        'type': 'local',
        'size': 42,
        'maxEntries': 1000,
        'hitCount': 500,
        'missCount': 50,
        'removeCount': 10,
        'expireTimeIdle': 3600,
        'expireTimeLive': 7200,
      };

      final cache = CacheInfo.fromJson(json);

      expect(cache.name, 'entity.cache.TestEntity');
      expect(cache.type, 'local');
      expect(cache.size, 42);
      expect(cache.maxEntries, 1000);
      expect(cache.hitCount, 500);
      expect(cache.missCount, 50);
      expect(cache.removeCount, 10);
      expect(cache.expireTimeIdle, 3600);
      expect(cache.expireTimeLive, 7200);
    });

    test('fromJson handles string numeric values', () {
      final json = {
        'name': 'test.cache',
        'size': '100',
        'hitCount': '250',
        'missCount': '25',
      };

      final cache = CacheInfo.fromJson(json);
      expect(cache.size, 100);
      expect(cache.hitCount, 250);
      expect(cache.missCount, 25);
    });

    test('fromJson defaults for missing fields', () {
      final cache = CacheInfo.fromJson(const {'name': 'empty.cache'});
      expect(cache.name, 'empty.cache');
      expect(cache.type, 'local');
      expect(cache.size, 0);
      expect(cache.maxEntries, 0);
      expect(cache.hitCount, 0);
      expect(cache.missCount, 0);
    });

    test('hitRate calculated correctly', () {
      const cache = CacheInfo(
        name: 'rate.test',
        hitCount: 90,
        missCount: 10,
      );
      expect(cache.hitRate, closeTo(0.9, 0.001));
    });

    test('hitRate is 0 when no hits or misses', () {
      const cache = CacheInfo(name: 'zero.test');
      expect(cache.hitRate, 0.0);
    });

    test('hitRate with all hits', () {
      const cache = CacheInfo(name: 'perfect', hitCount: 100, missCount: 0);
      expect(cache.hitRate, 1.0);
    });

    test('hitRate with all misses', () {
      const cache = CacheInfo(name: 'miss', hitCount: 0, missCount: 50);
      expect(cache.hitRate, 0.0);
    });

    test('equatable works on name, type, size', () {
      const a = CacheInfo(name: 'x', type: 'local', size: 10, hitCount: 1);
      const b = CacheInfo(name: 'x', type: 'local', size: 10, hitCount: 99);
      expect(a, equals(b));
    });
  });

  // ===========================================================================
  // 2. LOG ENTRY MODEL
  // ===========================================================================

  group('LogEntry Model', () {
    test('fromJson parses all fields', () {
      final json = {
        'timestamp': '2024-01-15T10:30:45.123',
        'level': 'ERROR',
        'loggerName': 'org.moqui.impl.context.ArtifactExecutionFacadeImpl',
        'message': 'Error in service call',
        'throwable': 'java.lang.NullPointerException\n\tat Some.class(line:42)',
      };

      final entry = LogEntry.fromJson(json);

      expect(entry.level, 'ERROR');
      expect(entry.loggerName,
          'org.moqui.impl.context.ArtifactExecutionFacadeImpl');
      expect(entry.message, 'Error in service call');
      expect(entry.throwable, contains('NullPointerException'));
      expect(entry.timestamp.year, 2024);
      expect(entry.timestamp.month, 1);
      expect(entry.timestamp.day, 15);
    });

    test('fromJson handles epoch millis timestamp', () {
      final ts = DateTime(2024, 6, 15, 12, 0, 0);
      final json = {
        'timestamp': ts.millisecondsSinceEpoch,
        'level': 'INFO',
        'loggerName': 'test',
        'message': 'test message',
      };

      final entry = LogEntry.fromJson(json);
      expect(entry.timestamp.year, 2024);
      expect(entry.timestamp.month, 6);
    });

    test('fromJson defaults for missing fields', () {
      final entry = LogEntry.fromJson(const {});
      expect(entry.level, 'INFO');
      expect(entry.loggerName, '');
      expect(entry.message, '');
      expect(entry.throwable, isNull);
    });

    test('fromLogLine parses standard format', () {
      final entry = LogEntry.fromLogLine(
          '2024-01-15 10:30:45.123 ERROR [org.moqui.Test] Something failed');

      expect(entry.level, 'ERROR');
      expect(entry.loggerName, 'org.moqui.Test');
      expect(entry.message, 'Something failed');
      expect(entry.timestamp.year, 2024);
    });

    test('fromLogLine parses ISO timestamp format', () {
      final entry = LogEntry.fromLogLine(
          '2024-01-15T10:30:45.123 WARN [myLogger] Some warning');

      expect(entry.level, 'WARN');
      expect(entry.loggerName, 'myLogger');
      expect(entry.message, 'Some warning');
    });

    test('fromLogLine falls back for unparseable lines', () {
      final entry = LogEntry.fromLogLine('Just a plain text line');
      expect(entry.message, 'Just a plain text line');
      expect(entry.level, 'INFO');
      expect(entry.loggerName, '');
    });

    test('severityIndex ordering', () {
      final levels = [
        ('TRACE', 1),
        ('ALL', 1),
        ('DEBUG', 2),
        ('INFO', 3),
        ('WARN', 4),
        ('WARNING', 4),
        ('ERROR', 5),
        ('FATAL', 6),
      ];

      for (final (level, expected) in levels) {
        final entry = LogEntry(
          timestamp: DateTime.now(),
          level: level,
          loggerName: '',
          message: '',
        );
        expect(entry.severityIndex, expected,
            reason: '$level should have severity $expected');
      }
    });

    test('severityIndex unknown level returns 0', () {
      final entry = LogEntry(
        timestamp: DateTime.now(),
        level: 'CUSTOM',
        loggerName: '',
        message: '',
      );
      expect(entry.severityIndex, 0);
    });
  });

  // ===========================================================================
  // 3. LOG FILTER MODEL
  // ===========================================================================

  group('LogFilter Model', () {
    test('toParams includes only non-null fields', () {
      const filter = LogFilter(level: 'ERROR', loggerName: 'org.moqui');
      final params = filter.toParams();
      expect(params, containsPair('level', 'ERROR'));
      expect(params, containsPair('loggerName', 'org.moqui'));
      expect(params.containsKey('timeFrom'), false);
      expect(params.containsKey('timeTo'), false);
      expect(params.containsKey('messagePattern'), false);
    });

    test('toParams includes time range when set', () {
      final from = DateTime(2024, 1, 1);
      final to = DateTime(2024, 12, 31);
      final filter = LogFilter(timeFrom: from, timeTo: to);
      final params = filter.toParams();
      expect(params['timeFrom'], from.toIso8601String());
      expect(params['timeTo'], to.toIso8601String());
    });

    test('toParams excludes empty strings', () {
      const filter = LogFilter(loggerName: '', messagePattern: '');
      final params = filter.toParams();
      expect(params.containsKey('loggerName'), false);
      expect(params.containsKey('messagePattern'), false);
    });

    test('isActive returns false when no criteria set', () {
      const filter = LogFilter();
      expect(filter.isActive, false);
    });

    test('isActive returns true when any criteria set', () {
      expect(const LogFilter(level: 'ERROR').isActive, true);
      expect(const LogFilter(loggerName: 'test').isActive, true);
      expect(const LogFilter(messagePattern: 'error').isActive, true);
      expect(LogFilter(timeFrom: DateTime.now()).isActive, true);
    });

    test('isActive ignores empty strings', () {
      const filter = LogFilter(loggerName: '', messagePattern: '');
      expect(filter.isActive, false);
    });

    test('matches filters by level severity', () {
      const filter = LogFilter(level: 'WARN');
      final info = LogEntry(
        timestamp: DateTime.now(),
        level: 'INFO',
        loggerName: '',
        message: '',
      );
      final warn = LogEntry(
        timestamp: DateTime.now(),
        level: 'WARN',
        loggerName: '',
        message: '',
      );
      final error = LogEntry(
        timestamp: DateTime.now(),
        level: 'ERROR',
        loggerName: '',
        message: '',
      );

      expect(filter.matches(info), false); // INFO < WARN
      expect(filter.matches(warn), true); // WARN == WARN
      expect(filter.matches(error), true); // ERROR > WARN
    });

    test('matches filters by logger name (case-insensitive substring)', () {
      const filter = LogFilter(loggerName: 'moqui');

      final match = LogEntry(
        timestamp: DateTime.now(),
        level: 'INFO',
        loggerName: 'org.Moqui.impl.Test',
        message: '',
      );
      final noMatch = LogEntry(
        timestamp: DateTime.now(),
        level: 'INFO',
        loggerName: 'com.example.Other',
        message: '',
      );

      expect(filter.matches(match), true);
      expect(filter.matches(noMatch), false);
    });

    test('matches filters by message pattern (case-insensitive)', () {
      const filter = LogFilter(messagePattern: 'error');

      final match = LogEntry(
        timestamp: DateTime.now(),
        level: 'INFO',
        loggerName: '',
        message: 'An Error occurred in processing',
      );
      final noMatch = LogEntry(
        timestamp: DateTime.now(),
        level: 'INFO',
        loggerName: '',
        message: 'All good',
      );

      expect(filter.matches(match), true);
      expect(filter.matches(noMatch), false);
    });

    test('matches filters by time range', () {
      final from = DateTime(2024, 6, 1);
      final to = DateTime(2024, 6, 30);
      final filter = LogFilter(timeFrom: from, timeTo: to);

      final inRange = LogEntry(
        timestamp: DateTime(2024, 6, 15),
        level: 'INFO',
        loggerName: '',
        message: '',
      );
      final beforeRange = LogEntry(
        timestamp: DateTime(2024, 5, 15),
        level: 'INFO',
        loggerName: '',
        message: '',
      );
      final afterRange = LogEntry(
        timestamp: DateTime(2024, 7, 15),
        level: 'INFO',
        loggerName: '',
        message: '',
      );

      expect(filter.matches(inRange), true);
      expect(filter.matches(beforeRange), false);
      expect(filter.matches(afterRange), false);
    });

    test('matches combines multiple criteria (AND logic)', () {
      const filter = LogFilter(
        level: 'WARN',
        loggerName: 'moqui',
        messagePattern: 'cache',
      );

      // Matches all criteria
      final match = LogEntry(
        timestamp: DateTime.now(),
        level: 'ERROR',
        loggerName: 'org.moqui.CacheService',
        message: 'Cache expired',
      );
      expect(filter.matches(match), true);

      // Wrong level
      final wrongLevel = LogEntry(
        timestamp: DateTime.now(),
        level: 'DEBUG',
        loggerName: 'org.moqui.CacheService',
        message: 'Cache miss',
      );
      expect(filter.matches(wrongLevel), false);

      // Wrong logger
      final wrongLogger = LogEntry(
        timestamp: DateTime.now(),
        level: 'ERROR',
        loggerName: 'com.example.Other',
        message: 'Cache error',
      );
      expect(filter.matches(wrongLogger), false);

      // Wrong message
      final wrongMsg = LogEntry(
        timestamp: DateTime.now(),
        level: 'ERROR',
        loggerName: 'org.moqui.Test',
        message: 'Some error',
      );
      expect(filter.matches(wrongMsg), false);
    });

    test('no-filter matches everything', () {
      const filter = LogFilter();
      final entry = LogEntry(
        timestamp: DateTime.now(),
        level: 'TRACE',
        loggerName: 'anything',
        message: 'anything',
      );
      expect(filter.matches(entry), true);
    });
  });

  // ===========================================================================
  // 4. CACHE LIST SCREEN — rendered as form-list widget
  // ===========================================================================

  group('Cache List Screen - Form-List Pattern', () {
    testWidgets('renders cache data as form-list table', (tester) async {
      final node = WidgetNode.fromJson(const {
        '_type': 'form-list',
        'formName': 'CacheList',
        'listName': 'cacheList',
        'fields': [
          {
            'name': 'cacheName',
            'title': 'Cache Name',
            'widgets': [{'_type': 'display'}],
          },
          {
            'name': 'cacheType',
            'title': 'Type',
            'widgets': [{'_type': 'display'}],
          },
          {
            'name': 'cacheSize',
            'title': 'Size',
            'widgets': [{'_type': 'display'}],
          },
        ],
        'listData': [
          {
            'cacheName': 'entity.TestEntity',
            'cacheType': 'local',
            'cacheSize': '42',
          },
          {
            'cacheName': 'l10n.content',
            'cacheType': 'distributed',
            'cacheSize': '100',
          },
        ],
      });

      await tester.pumpWidget(_testHarness(
        MoquiWidgetFactory.build(node, _stubContext()),
      ));

      // Header cells
      expect(find.text('Cache Name'), findsOneWidget);
      expect(find.text('Type'), findsOneWidget);
      expect(find.text('Size'), findsOneWidget);

      // Data cells
      expect(find.text('entity.TestEntity'), findsOneWidget);
      expect(find.text('l10n.content'), findsOneWidget);
      expect(find.text('local'), findsOneWidget);
      expect(find.text('distributed'), findsOneWidget);
      expect(find.text('42'), findsOneWidget);
      expect(find.text('100'), findsOneWidget);
    });

    testWidgets('cache list with hit/miss statistics', (tester) async {
      final node = WidgetNode.fromJson(const {
        '_type': 'form-list',
        'formName': 'CacheList',
        'listName': 'cacheList',
        'fields': [
          {
            'name': 'cacheName',
            'title': 'Cache Name',
            'widgets': [{'_type': 'display'}],
          },
          {
            'name': 'hitCount',
            'title': 'Hits',
            'widgets': [{'_type': 'display'}],
          },
          {
            'name': 'missCount',
            'title': 'Misses',
            'widgets': [{'_type': 'display'}],
          },
          {
            'name': 'hitPercent',
            'title': 'Hit %',
            'widgets': [{'_type': 'display'}],
          },
        ],
        'listData': [
          {
            'cacheName': 'entity.definition',
            'hitCount': '9500',
            'missCount': '500',
            'hitPercent': '95.0%',
          },
          {
            'cacheName': 'conf.resource',
            'hitCount': '100',
            'missCount': '100',
            'hitPercent': '50.0%',
          },
        ],
      });

      await tester.pumpWidget(_testHarness(
        MoquiWidgetFactory.build(node, _stubContext()),
      ));

      expect(find.text('Hits'), findsOneWidget);
      expect(find.text('Misses'), findsOneWidget);
      expect(find.text('Hit %'), findsOneWidget);
      expect(find.text('9500'), findsOneWidget);
      expect(find.text('500'), findsOneWidget);
      expect(find.text('95.0%'), findsOneWidget);
    });

    testWidgets('cache clear button transition', (tester) async {
      final ctx = _stubContext(
        submitForm: (url, data) async {
          return TransitionResponse(messages: ['Cache cleared']);
        },
      );

      // In form-list, submit fields in rows fall through to default cell
      // rendering. A realistic cache clear uses a link widget instead.
      final node = WidgetNode.fromJson(const {
        '_type': 'form-list',
        'formName': 'CacheList',
        'listName': 'cacheList',
        'transition': '/tools/CacheList/clearCache',
        'fields': [
          {
            'name': 'cacheName',
            'title': 'Cache Name',
            'widgets': [{'_type': 'display'}],
          },
          {
            'name': 'clearBtn',
            'title': 'Action',
            'widgets': [
              {
                '_type': 'link',
                'text': 'Clear',
                'url': '/tools/CacheList/clearCache',
                'urlType': 'transition',
              }
            ],
          },
        ],
        'listData': [
          {'cacheName': 'entity.TestCache'},
        ],
      });

      await tester.pumpWidget(_testHarness(
        MoquiWidgetFactory.build(node, ctx),
      ));

      expect(find.text('entity.TestCache'), findsOneWidget);
      // Link type renders as clickable text in a cell
      expect(find.text('Clear'), findsOneWidget);
    });

    testWidgets('empty cache list renders empty state', (tester) async {
      final node = WidgetNode.fromJson(const {
        '_type': 'form-list',
        'formName': 'CacheList',
        'listName': 'cacheList',
        'fields': [
          {
            'name': 'cacheName',
            'title': 'Cache Name',
            'widgets': [{'_type': 'display'}],
          },
        ],
        'listData': [],
      });

      await tester.pumpWidget(_testHarness(
        MoquiWidgetFactory.build(node, _stubContext()),
      ));

      // With empty data, should show header row only
      expect(find.text('Cache Name'), findsOneWidget);
    });
  });

  // ===========================================================================
  // 5. CACHE FILTER — text-find field pattern for search
  // ===========================================================================

  group('Cache Search Filter', () {
    testWidgets('text-find field for cache name search', (tester) async {
      final field = _makeField(
        'cacheName',
        'text-find',
        title: 'Cache Name',
        widgetAttrs: {
          'defaultOperator': 'contains',
        },
      );

      await tester.pumpWidget(_formTestHarness(
        FieldWidgetFactory.build(
          field: field,
          formData: {},
          onChanged: (_, __) {},
          ctx: _stubContext(),
        ),
      ));

      // text-find renders a text field
      expect(find.byType(TextFormField), findsWidgets);
    });

    testWidgets('cache type drop-down filter', (tester) async {
      final field = _makeField(
        'cacheType',
        'drop-down',
        title: 'Cache Type',
        options: [
          const FieldOption(key: 'all', text: 'All'),
          const FieldOption(key: 'local', text: 'Local'),
          const FieldOption(key: 'distributed', text: 'Distributed'),
        ],
      );

      await tester.pumpWidget(_formTestHarness(
        FieldWidgetFactory.build(
          field: field,
          formData: {},
          onChanged: (_, __) {},
          ctx: _stubContext(),
        ),
      ));

      expect(find.byType(DropdownButtonFormField<String>), findsOneWidget);
    });
  });

  // ===========================================================================
  // 6. LOG VIEWER — form-list rendering patterns
  // ===========================================================================

  group('Log Viewer Screen - Form-List Pattern', () {
    testWidgets('log entries form-list with level and message', (tester) async {
      final node = WidgetNode.fromJson(const {
        '_type': 'form-list',
        'formName': 'LogEntries',
        'listName': 'logEntries',
        'fields': [
          {
            'name': 'timestamp',
            'title': 'Time',
            'widgets': [{'_type': 'display'}],
          },
          {
            'name': 'level',
            'title': 'Level',
            'widgets': [{'_type': 'display'}],
          },
          {
            'name': 'loggerName',
            'title': 'Logger',
            'widgets': [{'_type': 'display'}],
          },
          {
            'name': 'message',
            'title': 'Message',
            'widgets': [{'_type': 'display'}],
          },
        ],
        'listData': [
          {
            'timestamp': '2024-01-15 10:30:45',
            'level': 'ERROR',
            'loggerName': 'org.moqui.impl.context',
            'message': 'Service call failed',
          },
          {
            'timestamp': '2024-01-15 10:30:44',
            'level': 'INFO',
            'loggerName': 'org.moqui.impl.screen',
            'message': 'Rendering screen /tools/LogViewer',
          },
        ],
      });

      await tester.pumpWidget(_testHarness(
        MoquiWidgetFactory.build(node, _stubContext()),
      ));

      expect(find.text('Level'), findsOneWidget);
      expect(find.text('Logger'), findsOneWidget);
      expect(find.text('Message'), findsOneWidget);
      expect(find.text('ERROR'), findsOneWidget);
      expect(find.text('INFO'), findsOneWidget);
      expect(find.text('Service call failed'), findsOneWidget);
    });

    testWidgets('log level filter drop-down', (tester) async {
      final field = _makeField(
        'logLevel',
        'drop-down',
        title: 'Log Level',
        currentValue: 'INFO',
        options: [
          const FieldOption(key: 'ALL', text: 'All'),
          const FieldOption(key: 'TRACE', text: 'Trace'),
          const FieldOption(key: 'DEBUG', text: 'Debug'),
          const FieldOption(key: 'INFO', text: 'Info'),
          const FieldOption(key: 'WARN', text: 'Warn'),
          const FieldOption(key: 'ERROR', text: 'Error'),
        ],
      );

      await tester.pumpWidget(_formTestHarness(
        FieldWidgetFactory.build(
          field: field,
          formData: {'logLevel': 'INFO'},
          onChanged: (_, __) {},
          ctx: _stubContext(),
        ),
      ));

      expect(find.byType(DropdownButtonFormField<String>), findsOneWidget);
    });

    testWidgets('log message search field', (tester) async {
      final field = _makeField(
        'messageSearch',
        'text-find',
        title: 'Search Messages',
        widgetAttrs: {
          'defaultOperator': 'contains',
        },
      );

      await tester.pumpWidget(_formTestHarness(
        FieldWidgetFactory.build(
          field: field,
          formData: {},
          onChanged: (_, __) {},
          ctx: _stubContext(),
        ),
      ));

      expect(find.byType(TextFormField), findsWidgets);
    });

    testWidgets('log viewer with throwable/stack trace display',
        (tester) async {
      final node = WidgetNode.fromJson(const {
        '_type': 'form-list',
        'formName': 'LogEntries',
        'listName': 'logEntries',
        'fields': [
          {
            'name': 'level',
            'title': 'Level',
            'widgets': [{'_type': 'display'}],
          },
          {
            'name': 'message',
            'title': 'Message',
            'widgets': [{'_type': 'display'}],
          },
          {
            'name': 'throwable',
            'title': 'Stack Trace',
            'widgets': [{'_type': 'display'}],
          },
        ],
        'listData': [
          {
            'level': 'ERROR',
            'message': 'NullPointerException in service',
            'throwable': 'java.lang.NullPointerException\n\tat org.Test(42)',
          },
        ],
      });

      await tester.pumpWidget(_testHarness(
        MoquiWidgetFactory.build(node, _stubContext()),
      ));

      expect(find.text('ERROR'), findsOneWidget);
      expect(find.text('NullPointerException in service'), findsOneWidget);
    });
  });

  // ===========================================================================
  // 7. LOG VIEWER DATE FILTERS
  // ===========================================================================

  group('Log Viewer Date Filters', () {
    testWidgets('date-find for log time range', (tester) async {
      final field = _makeField(
        'timestamp',
        'date-find',
        title: 'Time Range',
      );

      await tester.pumpWidget(_formTestHarness(
        FieldWidgetFactory.build(
          field: field,
          formData: {},
          onChanged: (_, __) {},
          ctx: _stubContext(),
        ),
      ));

      // date-find renders input fields for date range
      expect(find.byType(TextFormField), findsWidgets);
    });

    testWidgets('date-period for log time period filter', (tester) async {
      final field = _makeField(
        'logPeriod',
        'date-period',
        title: 'Period',
        widgetAttrs: {
          'allowEmpty': 'true',
        },
      );

      await tester.pumpWidget(_formTestHarness(
        FieldWidgetFactory.build(
          field: field,
          formData: {},
          onChanged: (_, __) {},
          ctx: _stubContext(),
        ),
      ));

      // date-period renders period selection
      expect(find.byType(DropdownButtonFormField<String>), findsWidgets);
    });
  });

  // ===========================================================================
  // 8. CACHE MANAGEMENT CONTAINER LAYOUTS
  // ===========================================================================

  group('Cache Management Layout', () {
    testWidgets('renders cache screen container with toolbar + list',
        (tester) async {
      final node = WidgetNode.fromJson(const {
        '_type': 'container',
        'children': [
          {
            '_type': 'container-row',
            'columns': [
              {
                'lg': '8',
                'sm': '12',
                'children': [
                  {
                    '_type': 'label',
                    'text': 'Cache Management',
                    'labelType': 'h4'
                  },
                ],
              },
              {
                'lg': '4',
                'sm': '12',
                'children': [
                  {
                    '_type': 'label',
                    'text': '42 caches',
                    'labelType': 'span'
                  },
                ],
              },
            ],
          },
          {
            '_type': 'form-list',
            'formName': 'CacheList',
            'listName': 'cacheList',
            'fields': [
              {
                'name': 'cacheName',
                'title': 'Name',
                'widgets': [{'_type': 'display'}],
              },
            ],
            'listData': [
              {'cacheName': 'test.cache.one'},
            ],
          },
        ],
      });

      await tester.pumpWidget(_testHarness(
        MoquiWidgetFactory.build(node, _stubContext()),
      ));

      expect(find.text('Cache Management'), findsOneWidget);
      expect(find.text('42 caches'), findsOneWidget);
      expect(find.text('test.cache.one'), findsOneWidget);
    });

    testWidgets('clear all caches button in toolbar', (tester) async {
      final ctx = _stubContext(
        submitForm: (url, data) async {
          return TransitionResponse(messages: ['All caches cleared']);
        },
      );

      final node = WidgetNode.fromJson(const {
        '_type': 'container',
        'children': [
          {
            '_type': 'form-single',
            'formName': 'ClearAllForm',
            'transition': '/tools/CacheList/clearAll',
            'fields': [
              {
                'name': 'clearAll',
                'title': '',
                'widgets': [
                  {'_type': 'submit', 'text': 'Clear All Caches'}
                ],
              },
            ],
          },
        ],
      });

      await tester.pumpWidget(_testHarness(
        MoquiWidgetFactory.build(node, ctx),
      ));

      expect(_findButtonWithText('Clear All Caches'), findsOneWidget);
    });
  });

  // ===========================================================================
  // 9. LOG LEVEL MANAGEMENT
  // ===========================================================================

  group('Log Level Management', () {
    testWidgets('log level selector drop-down with current value',
        (tester) async {
      final field = _makeField(
        'rootLogLevel',
        'drop-down',
        title: 'Root Log Level',
        currentValue: 'INFO',
        options: [
          const FieldOption(key: 'TRACE', text: 'TRACE'),
          const FieldOption(key: 'DEBUG', text: 'DEBUG'),
          const FieldOption(key: 'INFO', text: 'INFO'),
          const FieldOption(key: 'WARN', text: 'WARN'),
          const FieldOption(key: 'ERROR', text: 'ERROR'),
          const FieldOption(key: 'FATAL', text: 'FATAL'),
        ],
      );

      await tester.pumpWidget(_formTestHarness(
        FieldWidgetFactory.build(
          field: field,
          formData: {'rootLogLevel': 'INFO'},
          onChanged: (_, __) {},
          ctx: _stubContext(),
        ),
      ));

      expect(find.byType(DropdownButtonFormField<String>), findsOneWidget);
      // Current value should be displayed
      expect(find.text('INFO'), findsOneWidget);
    });

    testWidgets('set log level form with submit', (tester) async {
      final ctx = _stubContext();
      final node = WidgetNode.fromJson(const {
        '_type': 'form-single',
        'formName': 'SetLogLevel',
        'transition': '/tools/LogViewer/setLogLevel',
        'fields': [
          {
            'name': 'logLevel',
            'title': 'Log Level',
            'widgets': [
              {
                '_type': 'drop-down',
                'options': [
                  {'key': 'DEBUG', 'text': 'DEBUG'},
                  {'key': 'INFO', 'text': 'INFO'},
                  {'key': 'WARN', 'text': 'WARN'},
                  {'key': 'ERROR', 'text': 'ERROR'},
                ],
              }
            ],
          },
          {
            'name': 'submit',
            'title': '',
            'widgets': [
              {'_type': 'submit', 'text': 'Set Level'}
            ],
          },
        ],
      });

      await tester.pumpWidget(_testHarness(
        MoquiWidgetFactory.build(node, ctx),
      ));

      expect(find.byType(DropdownButtonFormField<String>), findsOneWidget);
      expect(_findButtonWithText('Set Level'), findsOneWidget);
    });
  });

  // ===========================================================================
  // 10. LOG VIEWER CONTAINER LAYOUT
  // ===========================================================================

  group('Log Viewer Layout', () {
    testWidgets('log viewer full screen layout with filters + log list',
        (tester) async {
      final node = WidgetNode.fromJson(const {
        '_type': 'container',
        'children': [
          {
            '_type': 'container-row',
            'columns': [
              {
                'lg': '12',
                'children': [
                  {
                    '_type': 'label',
                    'text': 'Server Log Viewer',
                    'labelType': 'h4'
                  },
                ],
              },
            ],
          },
          {
            '_type': 'form-single',
            'formName': 'LogFilter',
            'transition': '/tools/LogViewer/getLogEntries',
            'fields': [
              {
                'name': 'level',
                'title': 'Level',
                'widgets': [
                  {
                    '_type': 'drop-down',
                    'options': [
                      {'key': 'ALL', 'text': 'All'},
                      {'key': 'INFO', 'text': 'Info'},
                      {'key': 'WARN', 'text': 'Warn'},
                      {'key': 'ERROR', 'text': 'Error'},
                    ],
                  }
                ],
              },
              {
                'name': 'submit',
                'title': '',
                'widgets': [
                  {'_type': 'submit', 'text': 'Filter'}
                ],
              },
            ],
          },
          {
            '_type': 'form-list',
            'formName': 'LogEntries',
            'listName': 'logEntries',
            'fields': [
              {
                'name': 'timestamp',
                'title': 'Time',
                'widgets': [{'_type': 'display'}],
              },
              {
                'name': 'level',
                'title': 'Level',
                'widgets': [{'_type': 'display'}],
              },
              {
                'name': 'message',
                'title': 'Message',
                'widgets': [{'_type': 'display'}],
              },
            ],
            'listData': [
              {
                'timestamp': '10:30:45',
                'level': 'WARN',
                'message': 'Cache miss for entity.Test',
              },
            ],
          },
        ],
      });

      await tester.pumpWidget(_testHarness(
        MoquiWidgetFactory.build(node, _stubContext()),
      ));

      expect(find.text('Server Log Viewer'), findsOneWidget);
      expect(find.text('Level'), findsWidgets); // in filter + table header
      expect(_findButtonWithText('Filter'), findsOneWidget);
      expect(find.text('WARN'), findsWidgets);
      expect(find.text('Cache miss for entity.Test'), findsOneWidget);
    });
  });

  // ===========================================================================
  // 11. CACHE INFO BATCH PARSING
  // ===========================================================================

  group('CacheInfo Batch Parsing', () {
    test('parses list of cache info from JSON array', () {
      final jsonList = [
        {
          'name': 'cache.one',
          'type': 'local',
          'size': 10,
          'hitCount': 100,
          'missCount': 5,
        },
        {
          'name': 'cache.two',
          'type': 'distributed',
          'size': 200,
          'hitCount': 50,
          'missCount': 50,
        },
        {
          'name': 'cache.three',
          'size': 0,
        },
      ];

      final caches =
          jsonList.map((j) => CacheInfo.fromJson(j)).toList();

      expect(caches.length, 3);
      expect(caches[0].name, 'cache.one');
      expect(caches[0].hitRate, closeTo(0.952, 0.01));
      expect(caches[1].name, 'cache.two');
      expect(caches[1].hitRate, closeTo(0.5, 0.01));
      expect(caches[2].name, 'cache.three');
      expect(caches[2].hitRate, 0.0);
    });

    test('handles malformed JSON gracefully', () {
      final cache = CacheInfo.fromJson(const {
        'name': null,
        'size': 'not-a-number',
        'hitCount': true,
      });

      expect(cache.name, '');
      expect(cache.size, 0);
      expect(cache.hitCount, 0);
    });
  });

  // ===========================================================================
  // 12. LOG ENTRY BATCH PARSING
  // ===========================================================================

  group('LogEntry Batch Parsing', () {
    test('parses list of log entries from JSON array', () {
      final jsonList = [
        {
          'timestamp': '2024-01-15T10:30:45.000',
          'level': 'INFO',
          'loggerName': 'org.moqui',
          'message': 'Startup complete',
        },
        {
          'timestamp': '2024-01-15T10:31:00.000',
          'level': 'WARN',
          'loggerName': 'org.moqui.cache',
          'message': 'Cache near capacity',
        },
      ];

      final entries =
          jsonList.map((j) => LogEntry.fromJson(j)).toList();

      expect(entries.length, 2);
      expect(entries[0].level, 'INFO');
      expect(entries[0].message, 'Startup complete');
      expect(entries[1].level, 'WARN');
    });

    test('parses multiple log lines', () {
      final lines = [
        '2024-01-15 10:30:45.123 INFO  [org.moqui.impl] Server started',
        '2024-01-15 10:30:46.456 ERROR [org.moqui.service] Service failed',
        'Plain message without format',
      ];

      final entries =
          lines.map((l) => LogEntry.fromLogLine(l)).toList();

      expect(entries.length, 3);
      expect(entries[0].level, 'INFO');
      expect(entries[0].loggerName, 'org.moqui.impl');
      expect(entries[1].level, 'ERROR');
      expect(entries[2].level, 'INFO'); // fallback
      expect(entries[2].message, 'Plain message without format');
    });
  });

  // ===========================================================================
  // 13. DISPLAY-ENTITY FIELD IN CACHE/LOG CONTEXT
  // ===========================================================================

  group('Display-Entity in Tool Screens', () {
    testWidgets('display-entity resolves for cache entity references',
        (tester) async {
      final field = _makeField(
        'entityName',
        'display-entity',
        title: 'Entity',
        widgetAttrs: {
          'entityName': 'moqui.basic.Enumeration',
          'keyFieldName': 'enumId',
          'displayFieldName': 'description',
        },
        currentValue: 'CACHE_LOCAL',
      );

      await tester.pumpWidget(_formTestHarness(
        FieldWidgetFactory.build(
          field: field,
          formData: {'entityName': 'CACHE_LOCAL'},
          onChanged: (_, __) {},
          ctx: _stubContext(),
        ),
      ));

      // display-entity renders the value text
      expect(find.text('CACHE_LOCAL'), findsOneWidget);
    });
  });

  // ===========================================================================
  // 14. EDGE CASES & ROBUSTNESS
  // ===========================================================================

  group('Edge Cases', () {
    test('CacheInfo fromJson with empty map', () {
      final cache = CacheInfo.fromJson(const {});
      expect(cache.name, '');
      expect(cache.type, 'local');
      expect(cache.size, 0);
    });

    test('LogEntry fromJson with empty map', () {
      final entry = LogEntry.fromJson(const {});
      expect(entry.level, 'INFO');
      expect(entry.message, '');
      expect(entry.throwable, isNull);
    });

    test('LogEntry fromLogLine with empty string', () {
      final entry = LogEntry.fromLogLine('');
      expect(entry.message, '');
    });

    test('LogFilter with all fields set', () {
      final now = DateTime.now();
      final filter = LogFilter(
        level: 'ERROR',
        loggerName: 'org.moqui',
        timeFrom: now.subtract(const Duration(hours: 1)),
        timeTo: now,
        messagePattern: 'exception',
      );
      expect(filter.isActive, true);
      final params = filter.toParams();
      expect(params.length, 5);
    });

    test('CacheInfo with very large values', () {
      final cache = CacheInfo.fromJson(const {
        'name': 'big.cache',
        'size': 999999999,
        'hitCount': 2147483647,
        'missCount': 1,
      });
      expect(cache.size, 999999999);
      expect(cache.hitRate, closeTo(1.0, 0.001));
    });

    test('LogFilter matches with null filter values', () {
      const filter = LogFilter();
      final entry = LogEntry(
        timestamp: DateTime.now(),
        level: 'DEBUG',
        loggerName: 'test',
        message: 'hello',
      );
      expect(filter.matches(entry), true);
    });

    testWidgets('form-list handles cache data with many columns',
        (tester) async {
      final node = WidgetNode.fromJson(const {
        '_type': 'form-list',
        'formName': 'DetailedCacheList',
        'listName': 'cacheList',
        'fields': [
          {
            'name': 'name',
            'title': 'Name',
            'widgets': [{'_type': 'display'}],
          },
          {
            'name': 'type',
            'title': 'Type',
            'widgets': [{'_type': 'display'}],
          },
          {
            'name': 'size',
            'title': 'Size',
            'widgets': [{'_type': 'display'}],
          },
          {
            'name': 'maxEntries',
            'title': 'Max',
            'widgets': [{'_type': 'display'}],
          },
          {
            'name': 'hits',
            'title': 'Hits',
            'widgets': [{'_type': 'display'}],
          },
          {
            'name': 'misses',
            'title': 'Misses',
            'widgets': [{'_type': 'display'}],
          },
          {
            'name': 'evictions',
            'title': 'Evictions',
            'widgets': [{'_type': 'display'}],
          },
        ],
        'listData': [
          {
            'name': 'entity.definition',
            'type': 'local',
            'size': '150',
            'maxEntries': '500',
            'hits': '10000',
            'misses': '100',
            'evictions': '50',
          },
        ],
      });

      await tester.pumpWidget(_testHarness(
        MoquiWidgetFactory.build(node, _stubContext()),
      ));

      // All columns rendered
      expect(find.text('Name'), findsOneWidget);
      expect(find.text('Type'), findsOneWidget);
      expect(find.text('Max'), findsOneWidget);
      expect(find.text('entity.definition'), findsOneWidget);
      expect(find.text('10000'), findsOneWidget);
    });
  });

  // ===========================================================================
  // 15. TRANSITION RESPONSES FOR CACHE/LOG OPERATIONS
  // ===========================================================================

  group('Cache/Log Transition Responses', () {
    test('TransitionResponse with cache clear success', () {
      final response = TransitionResponse.fromJson({
        'screenPathList': ['tools', 'CacheList'],
        'screenUrl': '/fapps/tools/CacheList',
        'messages': ['Cache "entity.TestEntity" cleared successfully'],
        'errors': [],
      });

      expect(response.hasErrors, false);
      expect(response.hasMessages, true);
      expect(response.messages.first, contains('cleared successfully'));
    });

    test('TransitionResponse with log level change', () {
      final response = TransitionResponse.fromJson({
        'screenPathList': ['tools', 'LogViewer'],
        'screenUrl': '/fapps/tools/LogViewer',
        'messages': ['Log level set to DEBUG'],
        'errors': [],
      });

      expect(response.hasErrors, false);
      expect(response.messages.first, contains('DEBUG'));
    });

    test('TransitionResponse with error', () {
      final response = TransitionResponse.fromJson({
        'errors': ['Permission denied: cannot clear system caches'],
      });

      expect(response.hasErrors, true);
      expect(response.errors.first, contains('Permission denied'));
    });
  });

  // ===========================================================================
  // 16. LOG ENTRY COMPARISON AND SORTING
  // ===========================================================================

  group('LogEntry Sorting', () {
    test('sort by severity', () {
      final entries = [
        LogEntry(
            timestamp: DateTime.now(),
            level: 'INFO',
            loggerName: '',
            message: ''),
        LogEntry(
            timestamp: DateTime.now(),
            level: 'ERROR',
            loggerName: '',
            message: ''),
        LogEntry(
            timestamp: DateTime.now(),
            level: 'DEBUG',
            loggerName: '',
            message: ''),
        LogEntry(
            timestamp: DateTime.now(),
            level: 'WARN',
            loggerName: '',
            message: ''),
      ];

      entries.sort((a, b) => a.severityIndex.compareTo(b.severityIndex));

      expect(entries[0].level, 'DEBUG');
      expect(entries[1].level, 'INFO');
      expect(entries[2].level, 'WARN');
      expect(entries[3].level, 'ERROR');
    });

    test('sort by timestamp', () {
      final base = DateTime(2024, 1, 15, 10, 0, 0);
      final entries = [
        LogEntry(
            timestamp: base.add(const Duration(minutes: 2)),
            level: 'INFO',
            loggerName: '',
            message: 'third'),
        LogEntry(
            timestamp: base,
            level: 'INFO',
            loggerName: '',
            message: 'first'),
        LogEntry(
            timestamp: base.add(const Duration(minutes: 1)),
            level: 'INFO',
            loggerName: '',
            message: 'second'),
      ];

      entries.sort((a, b) => a.timestamp.compareTo(b.timestamp));

      expect(entries[0].message, 'first');
      expect(entries[1].message, 'second');
      expect(entries[2].message, 'third');
    });
  });
}
