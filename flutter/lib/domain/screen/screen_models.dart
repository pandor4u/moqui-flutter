/// Domain models for Moqui screen JSON metadata.
///
/// These models deserialize the JSON output of ScreenWidgetRenderJson
/// into typed Dart objects that the widget factory uses to build Flutter widgets.
library;

import 'package:equatable/equatable.dart';
import '../../core/template_utils.dart' as tpl;

// ============================================================================
// Screen Node — The root of a rendered screen
// ============================================================================

class ScreenNode extends Equatable {
  final String type; // '_type' from JSON
  final String renderMode;
  final String screenName;
  final String menuTitle;
  final List<WidgetNode> widgets;
  /// The actual screen path after following server-side redirects (e.g. HTTP 302).
  /// Populated by [MoquiApiClient.fetchScreen] when the browser follows a redirect.
  /// Used to resolve relative URLs in the rendered screen correctly.
  final String resolvedScreenPath;

  const ScreenNode({
    this.type = 'screen',
    this.renderMode = 'fjson',
    this.screenName = '',
    this.menuTitle = '',
    this.widgets = const [],
    this.resolvedScreenPath = '',
  });

  factory ScreenNode.fromJson(Map<String, dynamic> json) {
    return ScreenNode(
      type: json['_type']?.toString() ?? 'screen',
      renderMode: json['renderMode']?.toString() ?? 'fjson',
      screenName: json['screenName']?.toString() ?? '',
      menuTitle: json['menuTitle']?.toString() ?? '',
      widgets: _parseWidgetList(json['widgets']),
      resolvedScreenPath: json['_resolvedScreenPath']?.toString() ?? '',
    );
  }

  @override
  List<Object?> get props => [type, renderMode, screenName, menuTitle, widgets, resolvedScreenPath];
}

// ============================================================================
// Widget Node — Generic widget in the tree
// ============================================================================

class WidgetNode extends Equatable {
  final String type; // '_type': form-single, container, label, link, etc.
  final Map<String, dynamic> attributes;
  final List<WidgetNode> children;

  const WidgetNode({
    required this.type,
    this.attributes = const {},
    this.children = const [],
  });

  factory WidgetNode.fromJson(Map<String, dynamic> json) {
    final type = json['_type']?.toString() ?? 'unknown';
    final children = <WidgetNode>[];

    // Parse children from various child keys
    for (final key in ['children', 'widgets', 'widgetTemplate']) {
      if (json[key] is List) {
        children.addAll(_parseWidgetList(json[key]));
      }
    }

    return WidgetNode(type: type, attributes: json, children: children);
  }

  /// Get a typed attribute value.
  String attr(String key, [String defaultValue = '']) =>
      attributes[key]?.toString() ?? defaultValue;

  /// Get a boolean attribute.
  bool boolAttr(String key, [bool defaultValue = false]) {
    final val = attributes[key]?.toString().toLowerCase();
    if (val == null) return defaultValue;
    return val == 'true' || val == '1';
  }

  /// Get an integer attribute.
  int intAttr(String key, [int defaultValue = 0]) =>
      int.tryParse(attributes[key]?.toString() ?? '') ?? defaultValue;

  /// Check if this is a specific widget type.
  bool isType(String widgetType) => type == widgetType;

  @override
  List<Object?> get props => [type, attributes, children];
}

// ============================================================================
// Form Definition — Metadata for form-single and form-list
// ============================================================================

class FormDefinition extends Equatable {
  final String formType; // 'form-single' or 'form-list'
  final String formName;
  final String transition;
  final List<FieldDefinition> fields;
  final List<FieldDefinition> headerFields; // form-list filter fields
  final FieldLayout? fieldLayout;
  final List<FormColumn>? columns;
  final bool paginate;
  final String listName;
  final bool hasRowSelection;
  final String rowSelectionIdField; // field for row-selection id
  final String rowSelectionParameter; // parameter name for selected rows
  final bool skipForm; // when true, form-list has no inline form submission
  final bool headerDialog; // show header fields in a popup dialog
  final bool showCsvButton;
  final bool showXlsxButton;
  final bool showPageSize;
  final List<Map<String, dynamic>> listData; // form-list row data
  final Map<String, dynamic> paginateInfo; // pagination metadata
  /// Optional override for the edit-row link URL (relative or absolute).
  /// Defaults to empty string, in which case the AutoScreen convention
  /// '../AutoEdit/AutoEditMaster' is used.  Set by the server via 'editUrl'.
  final String editUrl;

  // --- Phase 3 additions ---
  /// Saved finds for this form-list (from formSavedFindsList).
  final List<Map<String, dynamic>> savedFinds;
  /// All column definitions with visibility state (from allColumns).
  final List<Map<String, dynamic>> allColumns;
  /// Base URL for export downloads (CSV, XLSX, etc.)
  final String exportBaseUrl;

  const FormDefinition({
    required this.formType,
    this.formName = '',
    this.transition = '',
    this.fields = const [],
    this.headerFields = const [],
    this.fieldLayout,
    this.columns,
    this.paginate = true,
    this.listName = '',
    this.hasRowSelection = false,
    this.rowSelectionIdField = '',
    this.rowSelectionParameter = '',
    this.skipForm = false,
    this.headerDialog = false,
    this.showCsvButton = false,
    this.showXlsxButton = false,
    this.showPageSize = false,
    this.listData = const [],
    this.paginateInfo = const {},
    this.editUrl = '',
    this.savedFinds = const [],
    this.allColumns = const [],
    this.exportBaseUrl = '',
  });

  factory FormDefinition.fromJson(Map<String, dynamic> json) {
    final rowSelection = json['rowSelection'] as Map<String, dynamic>?;
    return FormDefinition(
      formType: json['_type']?.toString() ?? 'form-single',
      formName: json['formName']?.toString() ?? '',
      transition: json['transition']?.toString() ?? '',
      fields: _parseFieldList(json['fields']),
      headerFields: _parseFieldList(json['headerFields']),
      fieldLayout: json['fieldLayout'] != null
          ? FieldLayout.fromJson(json['fieldLayout'] as Map<String, dynamic>)
          : null,
      columns: json['columns'] != null
          ? (json['columns'] as List)
              .map((c) => FormColumn.fromJson(c as Map<String, dynamic>))
              .toList()
          : null,
      paginate: json['paginate']?.toString() != 'false',
      listName: json['list']?.toString() ?? '',
      hasRowSelection: rowSelection != null,
      rowSelectionIdField: rowSelection?['idField']?.toString() ?? '',
      rowSelectionParameter: rowSelection?['parameter']?.toString() ?? '',
      skipForm: json['skipForm']?.toString() == 'true',
      headerDialog: json['headerDialog']?.toString() == 'true',
      showCsvButton: json['showCsvButton']?.toString() == 'true',
      showXlsxButton: json['showXlsxButton']?.toString() == 'true',
      showPageSize: json['showPageSize']?.toString() == 'true',
      listData: (json['listData'] as List?)
              ?.map((e) => Map<String, dynamic>.from(e as Map))
              .toList() ??
          const [],
      paginateInfo: json['paginateInfo'] != null
          ? Map<String, dynamic>.from(json['paginateInfo'] as Map)
          : const {},
      editUrl: json['editUrl']?.toString() ?? '',
      savedFinds: (json['formSavedFindsList'] as List?)
              ?.map((e) => Map<String, dynamic>.from(e as Map))
              .toList() ??
          const [],
      allColumns: (json['allColumns'] as List?)
              ?.map((e) => Map<String, dynamic>.from(e as Map))
              .toList() ??
          const [],
      exportBaseUrl: json['exportBaseUrl']?.toString() ?? '',
    );
  }

  bool get isSingle => formType == 'form-single';
  bool get isList => formType == 'form-list';

  @override
  List<Object?> get props => [
        formType, formName, transition, fields, listData, editUrl,
        headerFields, fieldLayout, columns, paginate, listName,
        hasRowSelection, paginateInfo,
      ];
}

// ============================================================================
// Field Definition
// ============================================================================

class FieldDefinition extends Equatable {
  final String name;
  final String title;
  final String tooltip;
  final String from;
  final String hide;
  final String align;
  final String? currentValue;
  final List<FieldWidget> widgets;
  final List<ConditionalField> conditionalFields; // conditional-field list
  /// Multi-row fields (first-row-field, second-row-field, last-row-field).
  /// Each entry has 'rowType', 'title', and 'widgets'.
  final List<RowFieldGroup> rowFields;

  const FieldDefinition({
    required this.name,
    this.title = '',
    this.tooltip = '',
    this.from = '',
    this.hide = '',
    this.align = '',
    this.currentValue,
    this.widgets = const [],
    this.conditionalFields = const [],
    this.rowFields = const [],
  });

  factory FieldDefinition.fromJson(Map<String, dynamic> json) {
    return FieldDefinition(
      name: json['name']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      tooltip: json['tooltip']?.toString() ?? '',
      from: json['from']?.toString() ?? '',
      hide: json['hide']?.toString() ?? '',
      align: json['align']?.toString() ?? '',
      currentValue: json['currentValue']?.toString(),
      widgets: json['widgets'] != null
          ? (json['widgets'] as List)
              .map((w) => FieldWidget.fromJson(w as Map<String, dynamic>))
              .toList()
          : [],
      conditionalFields: json['conditionalFields'] != null
          ? (json['conditionalFields'] as List)
              .map((c) => ConditionalField.fromJson(c as Map<String, dynamic>))
              .toList()
          : [],
      rowFields: json['rowFields'] != null
          ? (json['rowFields'] as List)
              .map((r) => RowFieldGroup.fromJson(r as Map<String, dynamic>))
              .toList()
          : [],
    );
  }

  /// The primary widget type for this field (first widget).
  String get primaryWidgetType =>
      widgets.isNotEmpty ? widgets.first.widgetType : 'display';

  /// Whether this is a hidden field.
  bool get isHidden => primaryWidgetType == 'hidden' || primaryWidgetType == 'ignored';

  /// Human-readable display title.
  ///
  /// If the server sent a raw camelCase field name as the title (e.g.
  /// `orderName`, `grandTotal`), this converts it to a proper label
  /// (`Order Name`, `Grand Total`).  Otherwise the original title is returned.
  String get displayTitle => tpl.prettifyFieldTitle(title, name);

  /// Resolve the effective widgets for this field given a row of data.
  /// If conditionalFields are present, evaluate their conditions server-side
  /// (condition value in the row data) and return matching widgets.
  List<FieldWidget> resolveWidgets(Map<String, dynamic> rowData) {
    if (conditionalFields.isEmpty) return widgets;
    
    for (final cf in conditionalFields) {
      // Server evaluates conditions and passes conditionResult=true/false,
      // OR we check if the field mentioned in condition has a value in row data
      if (cf.conditionResult == true) {
        return cf.widgets;
      }
      // Client-side fallback: check if the condition field has a non-null value 
      // e.g. condition="entityValue != null" => check if 'entityValue' exists
      if (cf.conditionField.isNotEmpty && rowData[cf.conditionField] != null) {
        return cf.widgets;
      }
    }
    return widgets; // default-field widgets
  }

  @override
  List<Object?> get props => [name, title, tooltip, hide, currentValue, widgets, conditionalFields, rowFields];
}

// ============================================================================
// Conditional Field — conditional widget rendering based on row data
// ============================================================================

class ConditionalField extends Equatable {
  final String condition; // condition expression (server-evaluated)
  final String conditionField; // extracted field name from condition for client fallback
  final bool? conditionResult; // server-evaluated condition result
  final String title;
  final List<FieldWidget> widgets;

  const ConditionalField({
    this.condition = '',
    this.conditionField = '',
    this.conditionResult,
    this.title = '',
    this.widgets = const [],
  });

  factory ConditionalField.fromJson(Map<String, dynamic> json) {
    final condition = json['condition']?.toString() ?? '';
    // Extract field name from simple conditions like 'entityValue != null'
    String conditionField = '';
    final match = RegExp(r'^(\w+)\s*!=\s*null').firstMatch(condition);
    if (match != null) {
      conditionField = match.group(1) ?? '';
    }
    
    return ConditionalField(
      condition: condition,
      conditionField: conditionField,
      conditionResult: json['conditionResult'] == true ? true :
          json['conditionResult'] == false ? false : null,
      title: json['title']?.toString() ?? '',
      widgets: json['widgets'] != null
          ? (json['widgets'] as List)
              .map((w) => FieldWidget.fromJson(w as Map<String, dynamic>))
              .toList()
          : [],
    );
  }

  @override
  List<Object?> get props => [condition, widgets];
}

// ============================================================================
// Row Field Group — multi-row rendering (first-row-field, second-row-field, etc.)
// ============================================================================

class RowFieldGroup extends Equatable {
  final String rowType; // 'first-row-field', 'second-row-field', 'last-row-field'
  final String title;
  final List<FieldWidget> widgets;

  const RowFieldGroup({
    required this.rowType,
    this.title = '',
    this.widgets = const [],
  });

  factory RowFieldGroup.fromJson(Map<String, dynamic> json) {
    return RowFieldGroup(
      rowType: json['rowType']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      widgets: json['widgets'] != null
          ? (json['widgets'] as List)
              .map((w) => FieldWidget.fromJson(w as Map<String, dynamic>))
              .toList()
          : [],
    );
  }

  @override
  List<Object?> get props => [rowType, title, widgets];
}

// ============================================================================
// Field Widget — The actual input/display widget inside a field
// ============================================================================

class FieldWidget extends Equatable {
  final String widgetType; // text-line, drop-down, date-time, display, hidden, etc.
  final Map<String, dynamic> attributes;
  final List<FieldOption> options;
  final DynamicOptionsConfig? dynamicOptions;
  final AutocompleteConfig? autocomplete;
  final List<DependsOn> dependsOn;

  const FieldWidget({
    required this.widgetType,
    this.attributes = const {},
    this.options = const [],
    this.dynamicOptions,
    this.autocomplete,
    this.dependsOn = const [],
  });

  factory FieldWidget.fromJson(Map<String, dynamic> json) {
    return FieldWidget(
      widgetType: json['_type']?.toString() ?? 'display',
      attributes: json,
      options: json['options'] != null
          ? (json['options'] as List)
              .map((o) => FieldOption.fromJson(o as Map<String, dynamic>))
              .toList()
          : [],
      dynamicOptions: json['dynamicOptions'] != null
          ? DynamicOptionsConfig.fromJson(
              json['dynamicOptions'] as Map<String, dynamic>)
          : null,
      autocomplete: json['autocomplete'] != null
          ? AutocompleteConfig.fromJson(
              json['autocomplete'] as Map<String, dynamic>)
          : null,
      dependsOn: json['dependsOnList'] != null
          ? (json['dependsOnList'] as List)
              .map((d) => DependsOn.fromJson(d as Map<String, dynamic>))
              .toList()
          : json['dependsOnField'] != null
              ? [DependsOn(field: json['dependsOnField'].toString())]
              : [],
    );
  }

  /// Get attribute value.
  String attr(String key, [String defaultValue = '']) =>
      attributes[key]?.toString() ?? defaultValue;

  bool boolAttr(String key, [bool defaultValue = false]) {
    final val = attributes[key]?.toString().toLowerCase();
    if (val == null) return defaultValue;
    return val == 'true' || val == '1';
  }

  @override
  List<Object?> get props => [widgetType, attributes];
}

// ============================================================================
// Supporting Types
// ============================================================================

class FieldOption extends Equatable {
  final String key;
  final String text;

  const FieldOption({required this.key, required this.text});

  factory FieldOption.fromJson(Map<String, dynamic> json) {
    return FieldOption(
      key: json['key']?.toString() ?? '',
      text: json['text']?.toString() ?? '',
    );
  }

  @override
  List<Object?> get props => [key, text];
}

class DynamicOptionsConfig extends Equatable {
  final String transition;
  final bool serverSearch;
  final int minLength;
  final List<DependsOn> dependsOn;

  const DynamicOptionsConfig({
    required this.transition,
    this.serverSearch = false,
    this.minLength = 1,
    this.dependsOn = const [],
  });

  factory DynamicOptionsConfig.fromJson(Map<String, dynamic> json) {
    return DynamicOptionsConfig(
      transition: json['transition']?.toString() ?? '',
      serverSearch: json['serverSearch']?.toString() == 'true',
      minLength: int.tryParse(json['minLength']?.toString() ?? '') ?? 1,
      dependsOn: json['dependsOnList'] != null
          ? (json['dependsOnList'] as List)
              .map((d) => DependsOn.fromJson(d as Map<String, dynamic>))
              .toList()
          : [],
    );
  }

  @override
  List<Object?> get props => [transition, serverSearch];
}

class AutocompleteConfig extends Equatable {
  final String transition;
  final int delay;
  final int minLength;
  final bool showValue;
  final bool useActual;

  const AutocompleteConfig({
    required this.transition,
    this.delay = 300,
    this.minLength = 1,
    this.showValue = false,
    this.useActual = false,
  });

  factory AutocompleteConfig.fromJson(Map<String, dynamic> json) {
    return AutocompleteConfig(
      transition: json['transition']?.toString() ?? '',
      delay: int.tryParse(json['delay']?.toString() ?? '') ?? 300,
      minLength: int.tryParse(json['minLength']?.toString() ?? '') ?? 1,
      showValue: json['showValue']?.toString() == 'true',
      useActual: json['useActual']?.toString() == 'true',
    );
  }

  @override
  List<Object?> get props => [transition, delay, minLength];
}

class DependsOn extends Equatable {
  final String field;
  final String parameter;

  const DependsOn({required this.field, this.parameter = ''});

  factory DependsOn.fromJson(Map<String, dynamic> json) {
    return DependsOn(
      field: json['field']?.toString() ?? '',
      parameter: json['parameter']?.toString() ?? '',
    );
  }

  @override
  List<Object?> get props => [field, parameter];
}

class FieldLayout extends Equatable {
  final List<FieldLayoutRow> rows;

  const FieldLayout({this.rows = const []});

  factory FieldLayout.fromJson(Map<String, dynamic> json) {
    final rows = <FieldLayoutRow>[];
    if (json['rows'] is List) {
      for (final row in json['rows'] as List) {
        rows.add(FieldLayoutRow.fromJson(row as Map<String, dynamic>));
      }
    }
    return FieldLayout(rows: rows);
  }

  @override
  List<Object?> get props => [rows];
}

class FieldLayoutRow extends Equatable {
  final String type; // 'field-ref', 'field-row', 'field-group'
  final String name; // for field-ref
  final String title; // for field-group
  final List<FieldLayoutRow> children;
  final List<Map<String, String>> fields; // for field-row

  const FieldLayoutRow({
    this.type = '',
    this.name = '',
    this.title = '',
    this.children = const [],
    this.fields = const [],
  });

  factory FieldLayoutRow.fromJson(Map<String, dynamic> json) {
    return FieldLayoutRow(
      type: json['_type']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      children: json['children'] != null
          ? (json['children'] as List)
              .map((c) => FieldLayoutRow.fromJson(c as Map<String, dynamic>))
              .toList()
          : [],
      fields: json['fields'] != null
          ? (json['fields'] as List)
              .map((f) => Map<String, String>.from(f as Map))
              .toList()
          : [],
    );
  }

  @override
  List<Object?> get props => [type, name, title];
}

class FormColumn extends Equatable {
  final String style;
  final List<String> fieldRefs;

  const FormColumn({this.style = '', this.fieldRefs = const []});

  factory FormColumn.fromJson(Map<String, dynamic> json) {
    return FormColumn(
      style: json['style']?.toString() ?? '',
      fieldRefs: json['fieldRefs'] != null
          ? (json['fieldRefs'] as List).map((e) => e.toString()).toList()
          : [],
    );
  }

  @override
  List<Object?> get props => [style, fieldRefs];
}

// ============================================================================
// Menu / Navigation Models
// ============================================================================

class MenuNode extends Equatable {
  final String name;
  final String title;
  final String path;
  final String pathWithParams;
  final String image;
  final String imageType; // 'icon', 'url-screen', 'url-plain'
  final bool hasTabMenu;
  final List<MenuSubscreenItem> subscreens;

  const MenuNode({
    this.name = '',
    this.title = '',
    this.path = '',
    this.pathWithParams = '',
    this.image = '',
    this.imageType = '',
    this.hasTabMenu = false,
    this.subscreens = const [],
  });

  factory MenuNode.fromJson(Map<String, dynamic> json) {
    return MenuNode(
      name: json['name']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      path: json['path']?.toString() ?? '',
      pathWithParams: json['pathWithParams']?.toString() ?? '',
      image: json['image']?.toString() ?? '',
      imageType: json['imageType']?.toString() ?? '',
      hasTabMenu: json['hasTabMenu'] == true,
      subscreens: json['subscreens'] != null
          ? (json['subscreens'] as List)
              .map((s) =>
                  MenuSubscreenItem.fromJson(s as Map<String, dynamic>))
              .toList()
          : [],
    );
  }

  @override
  List<Object?> get props => [name, path, subscreens];
}

class MenuSubscreenItem extends Equatable {
  final String name;
  final String title;
  final String path;
  final String pathWithParams;
  final String image;
  final String imageType;
  final bool menuInclude;
  final bool active;
  final bool disableLink;

  const MenuSubscreenItem({
    this.name = '',
    this.title = '',
    this.path = '',
    this.pathWithParams = '',
    this.image = '',
    this.imageType = '',
    this.menuInclude = true,
    this.active = false,
    this.disableLink = false,
  });

  factory MenuSubscreenItem.fromJson(Map<String, dynamic> json) {
    return MenuSubscreenItem(
      name: json['name']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      path: json['path']?.toString() ?? '',
      pathWithParams: json['pathWithParams']?.toString() ?? '',
      image: json['image']?.toString() ?? '',
      imageType: json['imageType']?.toString() ?? '',
      menuInclude: json['menuInclude'] != false,
      active: json['active'] == true,
      disableLink: json['disableLink'] == true,
    );
  }

  @override
  List<Object?> get props => [name, path, active];
}

// ============================================================================
// Helpers
// ============================================================================

List<WidgetNode> _parseWidgetList(dynamic list) {
  if (list is! List) return [];
  return list
      .whereType<Map<String, dynamic>>()
      .map((w) => WidgetNode.fromJson(w))
      .toList();
}

List<FieldDefinition> _parseFieldList(dynamic list) {
  if (list is! List) return [];
  return list
      .whereType<Map<String, dynamic>>()
      .map((f) => FieldDefinition.fromJson(f))
      .toList();
}
