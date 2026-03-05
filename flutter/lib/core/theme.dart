import 'package:flutter/material.dart';

/// Material 3 theme for the Moqui Flutter app.
class MoquiTheme {
  MoquiTheme._();

  static const Color _seedColor = Color(0xFF1565C0); // Moqui blue

  static ThemeData light() {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: _seedColor,
      brightness: Brightness.light,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 1,
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        filled: true,
        fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: colorScheme.primary,
          foregroundColor: colorScheme.onPrimary,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: colorScheme.outlineVariant),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: colorScheme.surface,
        indicatorColor: colorScheme.secondaryContainer,
        selectedIconTheme: IconThemeData(color: colorScheme.onSecondaryContainer),
        unselectedIconTheme: IconThemeData(color: colorScheme.onSurfaceVariant),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: colorScheme.surface,
        indicatorColor: colorScheme.secondaryContainer,
      ),
      dataTableTheme: DataTableThemeData(
        headingRowColor: WidgetStatePropertyAll(
          colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        ),
        dataRowMinHeight: 48,
        dataRowMaxHeight: 56,
      ),
      dividerTheme: DividerThemeData(
        color: colorScheme.outlineVariant,
        thickness: 1,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  static ThemeData dark() {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: _seedColor,
      brightness: Brightness.dark,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 1,
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        filled: true,
        fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: colorScheme.primary,
          foregroundColor: colorScheme.onPrimary,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: colorScheme.outlineVariant),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: colorScheme.surface,
        indicatorColor: colorScheme.secondaryContainer,
        selectedIconTheme: IconThemeData(color: colorScheme.onSecondaryContainer),
        unselectedIconTheme: IconThemeData(color: colorScheme.onSurfaceVariant),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: colorScheme.surface,
        indicatorColor: colorScheme.secondaryContainer,
      ),
      dataTableTheme: DataTableThemeData(
        headingRowColor: WidgetStatePropertyAll(
          colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        ),
        dataRowMinHeight: 48,
        dataRowMaxHeight: 56,
      ),
      dividerTheme: DividerThemeData(
        color: colorScheme.outlineVariant,
        thickness: 1,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }
}

// ─── Semantic color helpers for dynamic widgets ───────────────────────
/// Extension on [BuildContext] providing theme-aware semantic colors that
/// adapt correctly between light and dark modes.
///
/// Usage: `context.moquiColors.mutedText` instead of `Colors.grey.shade600`.
extension MoquiColorExtension on BuildContext {
  _MoquiSemanticColors get moquiColors =>
      _MoquiSemanticColors(Theme.of(this));
}

class _MoquiSemanticColors {
  final ThemeData _theme;
  const _MoquiSemanticColors(this._theme);

  ColorScheme get _cs => _theme.colorScheme;
  bool get _isDark => _theme.brightness == Brightness.dark;

  // ── Text colors ──
  /// Muted/secondary text (breadcrumbs, placeholders, hints).
  Color get mutedText => _cs.onSurfaceVariant;

  /// Disabled or subtle text.
  Color get disabledText => _cs.onSurface.withValues(alpha: 0.38);

  // ── Surface / fill colors ──
  /// Read-only field fill, header-row background.
  Color get surfaceFill => _isDark
      ? _cs.surfaceContainerHighest
      : _cs.surfaceContainerHighest.withValues(alpha: 0.5);

  /// Border color for sections, dropdowns, dividers.
  Color get borderColor => _cs.outlineVariant;

  // ── Status colors (intentional — remain constant across themes) ──
  Color get danger => Colors.red;
  Color get success => Colors.green.shade700;
  Color get warning => Colors.orange.shade800;
  Color get info => Colors.blue;

  /// Lightened status backgrounds for row-type tinting.
  Color get dangerSurface =>
      _isDark ? Colors.red.shade900.withValues(alpha: 0.3) : Colors.red.shade50;
  Color get successSurface =>
      _isDark ? Colors.green.shade900.withValues(alpha: 0.3) : Colors.green.shade50;
  Color get warningSurface =>
      _isDark ? Colors.orange.shade900.withValues(alpha: 0.3) : Colors.orange.shade50;
  Color get infoSurface =>
      _isDark ? Colors.blue.shade900.withValues(alpha: 0.3) : Colors.blue.shade50;

  // ── Error widget colors ──
  Color get errorBorder =>
      _isDark ? Colors.red.shade700 : Colors.red.shade200;
  Color get errorSurface =>
      _isDark ? Colors.red.shade900.withValues(alpha: 0.3) : Colors.red.shade50;
  Color get errorIcon =>
      _isDark ? Colors.red.shade300 : Colors.red.shade600;
  Color get errorText =>
      _isDark ? Colors.red.shade200 : Colors.red.shade700;

  // ── Overlay / shadow ──
  Color get scrim => _cs.scrim.withValues(alpha: 0.12);
  Color get shadow => _cs.shadow.withValues(alpha: 0.1);

  // ── On-colored surface (text/icons on colored chip backgrounds) ──
  Color get onColored => Colors.white;
}
