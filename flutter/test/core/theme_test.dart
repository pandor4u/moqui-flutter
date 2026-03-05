import 'package:flutter_test/flutter_test.dart';
import 'package:moqui_flutter/core/theme.dart';
import 'package:flutter/material.dart';

void main() {
  group('MoquiTheme', () {
    test('light theme uses Material 3', () {
      final theme = MoquiTheme.light();
      expect(theme.useMaterial3, isTrue);
    });

    test('dark theme uses Material 3', () {
      final theme = MoquiTheme.dark();
      expect(theme.useMaterial3, isTrue);
    });

    test('light theme has light brightness', () {
      final theme = MoquiTheme.light();
      expect(theme.colorScheme.brightness, Brightness.light);
    });

    test('dark theme has dark brightness', () {
      final theme = MoquiTheme.dark();
      expect(theme.colorScheme.brightness, Brightness.dark);
    });

    test('light theme has AppBar configuration', () {
      final theme = MoquiTheme.light();
      expect(theme.appBarTheme.centerTitle, isFalse);
      expect(theme.appBarTheme.elevation, 0);
    });

    test('dark theme has AppBar configuration', () {
      final theme = MoquiTheme.dark();
      expect(theme.appBarTheme.centerTitle, isFalse);
      expect(theme.appBarTheme.elevation, 0);
    });

    test('themes have input decoration config', () {
      for (final theme in [MoquiTheme.light(), MoquiTheme.dark()]) {
        expect(theme.inputDecorationTheme.filled, isTrue);
        expect(theme.inputDecorationTheme.border, isA<OutlineInputBorder>());
      }
    });

    test('themes have card theme config', () {
      for (final theme in [MoquiTheme.light(), MoquiTheme.dark()]) {
        expect(theme.cardTheme.elevation, 0);
        expect(theme.cardTheme.shape, isA<RoundedRectangleBorder>());
      }
    });

    test('themes have navigation rail config', () {
      for (final theme in [MoquiTheme.light(), MoquiTheme.dark()]) {
        expect(theme.navigationRailTheme.backgroundColor, isNotNull);
      }
    });

    test('themes have snackbar config', () {
      for (final theme in [MoquiTheme.light(), MoquiTheme.dark()]) {
        expect(theme.snackBarTheme.behavior, SnackBarBehavior.floating);
      }
    });

    test('themes have data table config', () {
      for (final theme in [MoquiTheme.light(), MoquiTheme.dark()]) {
        expect(theme.dataTableTheme.dataRowMinHeight, 48);
        expect(theme.dataTableTheme.dataRowMaxHeight, 56);
      }
    });
  });
}
