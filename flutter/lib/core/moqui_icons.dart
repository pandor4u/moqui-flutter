import 'package:flutter/material.dart';

/// Consolidated icon resolver for Moqui FontAwesome icon names.
///
/// Accepts both `fa-plus` (widget_factory convention) and `plus` (menu/stripped
/// convention) formats, normalising to a single lookup key. Falls back to
/// [Icons.circle] when no mapping exists.
///
/// Used by both [MoquiWidgetFactory] and [AppShell] to eliminate the
/// previous two-map fragmentation.
class MoquiIcons {
  MoquiIcons._();

  /// Resolve a Moqui/FontAwesome icon name to a Material [IconData].
  ///
  /// Input can be:
  ///  - Full FA class string `"fa fa-trash"` or `"fa fa-pencil"`
  ///  - Prefixed shorthand `"fa-trash"`
  ///  - Stripped name `"trash"`, `"pencil"`
  ///  - Material name `"search"`, `"done"`, `"edit_location"`
  static IconData resolve(String? name) {
    if (name == null || name.isEmpty) return Icons.circle_outlined;

    // Normalise: strip leading "fa " prefix (from `fa fa-trash` → `fa-trash`),
    // then strip `fa-` or `icon-` prefix to get the bare name.
    String key = name.trim();
    if (key.startsWith('fa ')) key = key.substring(3).trim();
    final bare = key.replaceFirst(RegExp(r'^fa-|^icon-'), '');

    // 1. Try the fa-prefixed map first (covers widget_factory icon strings)
    if (_faMap.containsKey(key)) return _faMap[key]!;

    // 2. Try by bare name (covers menu icon strings)
    if (_bareMap.containsKey(bare)) return _bareMap[bare]!;

    // 3. Try a few Material-native names that Moqui sometimes uses directly
    if (_materialNameMap.containsKey(bare)) return _materialNameMap[bare]!;

    return Icons.circle;
  }

  // ---------------------------------------------------------------------------
  // FA-prefixed map — keys have `fa-` prefix
  // ---------------------------------------------------------------------------
  static const Map<String, IconData> _faMap = {
    // --- Actions ---
    'fa-plus': Icons.add,
    'fa-edit': Icons.edit,
    'fa-pencil': Icons.edit,
    'fa-pencil-square-o': Icons.edit_note,
    'fa-trash': Icons.delete,
    'fa-remove': Icons.close,
    'fa-save': Icons.save,
    'fa-check': Icons.check,
    'fa-check-circle': Icons.check_circle,
    'fa-times': Icons.close,
    'fa-search': Icons.search,
    'fa-download': Icons.download,
    'fa-upload': Icons.upload,
    'fa-print': Icons.print,
    'fa-refresh': Icons.refresh,
    'fa-sync': Icons.sync,
    'fa-crosshairs': Icons.gps_fixed,

    // --- Navigation ---
    'fa-arrow-left': Icons.arrow_back,
    'fa-arrow-right': Icons.arrow_forward,
    'fa-arrow-up': Icons.arrow_upward,
    'fa-arrow-down': Icons.arrow_downward,
    'fa-caret-up': Icons.arrow_drop_up,
    'fa-caret-down': Icons.arrow_drop_down,
    'fa-sort': Icons.sort,
    'fa-filter': Icons.filter_list,
    'fa-external-link': Icons.open_in_new,
    'fa-sign-out': Icons.logout,
    'fa-sign-in': Icons.login,

    // --- Objects ---
    'fa-file': Icons.insert_drive_file,
    'fa-folder': Icons.folder,
    'fa-home': Icons.home,
    'fa-user': Icons.person,
    'fa-user-plus': Icons.person_add,
    'fa-users': Icons.people,
    'fa-cog': Icons.settings,
    'fa-cogs': Icons.settings,
    'fa-wrench': Icons.build,
    'fa-database': Icons.storage,
    'fa-globe': Icons.public,
    'fa-envelope': Icons.email,
    'fa-phone': Icons.phone,
    'fa-calendar': Icons.calendar_today,
    'fa-clock-o': Icons.access_time,
    'fa-clock': Icons.access_time,
    'fa-industry': Icons.factory,
    'fa-building': Icons.business,

    // --- ERP / Commerce ---
    'fa-shopping-cart': Icons.shopping_cart,
    'fa-dollar-sign': Icons.attach_money,
    'fa-money': Icons.attach_money,
    'fa-tags': Icons.local_offer,
    'fa-tag': Icons.label_outline,
    'fa-tasks': Icons.checklist,
    'fa-truck': Icons.local_shipping,
    'fa-box': Icons.inventory_2,
    'fa-barcode': Icons.qr_code,
    'fa-cubes': Icons.view_in_ar,

    // --- Visualization ---
    'fa-chart-bar': Icons.bar_chart,
    'fa-bar-chart': Icons.bar_chart,
    'fa-chart-line': Icons.show_chart,
    'fa-dashboard': Icons.dashboard,
    'fa-list': Icons.list,
    'fa-th': Icons.grid_view,
    'fa-th-list': Icons.view_list,
    'fa-table': Icons.table_chart,

    // --- Status / Info ---
    'fa-info-circle': Icons.info,
    'fa-exclamation-triangle': Icons.warning,
    'fa-exclamation-circle': Icons.error,
    'fa-question-circle': Icons.help,
    'fa-ban': Icons.block,

    // --- Misc ---
    'fa-eye': Icons.visibility,
    'fa-eye-slash': Icons.visibility_off,
    'fa-lock': Icons.lock,
    'fa-unlock': Icons.lock_open,
    'fa-paperclip': Icons.attach_file,
    'fa-link': Icons.link,
    'fa-star': Icons.star,
    'fa-star-o': Icons.star_border,
    'fa-heart': Icons.favorite,
    'fa-comment': Icons.comment,
    'fa-comments': Icons.forum,
    'fa-bell': Icons.notifications,
    'fa-clipboard': Icons.content_paste,
    'fa-copy': Icons.content_copy,
  };

  // ---------------------------------------------------------------------------
  // Bare-name map — keys have NO `fa-` prefix  (for menu icons)
  // ---------------------------------------------------------------------------
  static const Map<String, IconData> _bareMap = {
    'plus': Icons.add,
    'edit': Icons.edit,
    'pencil': Icons.edit,
    'pencil-square-o': Icons.edit_note,
    'trash': Icons.delete,
    'remove': Icons.close,
    'save': Icons.save,
    'check': Icons.check,
    'check-circle': Icons.check_circle,
    'times': Icons.close,
    'search': Icons.search,
    'download': Icons.download,
    'upload': Icons.upload,
    'print': Icons.print,
    'refresh': Icons.refresh,
    'sync': Icons.sync,
    'crosshairs': Icons.gps_fixed,

    'arrow-left': Icons.arrow_back,
    'arrow-right': Icons.arrow_forward,
    'arrow-up': Icons.arrow_upward,
    'arrow-down': Icons.arrow_downward,
    'caret-up': Icons.arrow_drop_up,
    'caret-down': Icons.arrow_drop_down,
    'sort': Icons.sort,
    'filter': Icons.filter_list,
    'external-link': Icons.open_in_new,
    'sign-out': Icons.logout,
    'sign-in': Icons.login,

    'file': Icons.insert_drive_file_outlined,
    'folder': Icons.folder_outlined,
    'home': Icons.home_outlined,
    'user': Icons.person_outlined,
    'user-plus': Icons.person_add,
    'users': Icons.people_outlined,
    'cog': Icons.settings_outlined,
    'cogs': Icons.settings_outlined,
    'gear': Icons.settings_outlined,
    'wrench': Icons.build_outlined,
    'database': Icons.storage,
    'globe': Icons.public,
    'envelope': Icons.email_outlined,
    'phone': Icons.phone,
    'calendar': Icons.calendar_today_outlined,
    'clock-o': Icons.access_time,
    'clock': Icons.access_time,
    'industry': Icons.factory_outlined,
    'building': Icons.business_outlined,

    'shopping-cart': Icons.shopping_cart_outlined,
    'dollar-sign': Icons.attach_money,
    'dollar': Icons.attach_money,
    'money': Icons.attach_money,
    'tags': Icons.local_offer_outlined,
    'tag': Icons.label_outline,
    'tasks': Icons.checklist,
    'truck': Icons.local_shipping_outlined,
    'box': Icons.inventory_2_outlined,
    'barcode': Icons.qr_code,
    'cubes': Icons.view_in_ar,

    'chart-bar': Icons.bar_chart,
    'bar-chart': Icons.bar_chart,
    'chart-line': Icons.show_chart,
    'chart': Icons.show_chart,
    'dashboard': Icons.dashboard_outlined,
    'list': Icons.list,
    'th': Icons.grid_view,
    'th-list': Icons.view_list_outlined,
    'table': Icons.table_chart_outlined,

    'info-circle': Icons.info,
    'exclamation-triangle': Icons.warning,
    'exclamation-circle': Icons.error,
    'question-circle': Icons.help,
    'ban': Icons.block,

    'eye': Icons.visibility,
    'eye-slash': Icons.visibility_off,
    'lock': Icons.lock,
    'unlock': Icons.lock_open,
    'paperclip': Icons.attach_file,
    'link': Icons.link,
    'star': Icons.star,
    'star-o': Icons.star_border,
    'heart': Icons.favorite,
    'comment': Icons.comment,
    'comments': Icons.forum,
    'bell': Icons.notifications,
    'clipboard': Icons.content_paste,
    'copy': Icons.content_copy,
  };

  // ---------------------------------------------------------------------------
  // Material names — used when Moqui emits Material Design icon names directly
  // (e.g., icon="search", icon="done", icon="edit_location")
  // ---------------------------------------------------------------------------
  static const Map<String, IconData> _materialNameMap = {
    'search': Icons.search,
    'done': Icons.done,
    'message': Icons.message,
    'info': Icons.info,
    'edit_location': Icons.edit_location,
    'calendar_today': Icons.calendar_today,
  };
}
