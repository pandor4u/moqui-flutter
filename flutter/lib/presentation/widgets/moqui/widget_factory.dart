import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import '../../../core/moqui_icons.dart';
import '../../../core/keyboard_shortcuts.dart';
import '../../../core/template_utils.dart' as tpl;
import '../../../core/theme.dart';
import '../../../domain/screen/screen_models.dart';
import '../../../data/api/moqui_api_client.dart';
import '../fields/field_widget_factory.dart';
import 'form_list_toolbar.dart';

/// Callback for navigating to a screen path.
typedef ScreenNavigator = void Function(String path, {Map<String, dynamic>? params});

/// Callback for submitting a form. Returns a TransitionResponse with
/// messages, errors, and optional redirect URL.
typedef FormSubmitter = Future<TransitionResponse?> Function(
    String transitionUrl, Map<String, dynamic> formData);

/// Callback for loading a dynamic dialog/container (GET).
typedef DynamicLoader = Future<Map<String, dynamic>> Function(
    String transition, Map<String, dynamic> params);

/// Callback for POST-based transition calls (dynamic options, server search).
typedef DynamicPoster = Future<Map<String, dynamic>> Function(
    String transition, Map<String, dynamic> params);

/// Context passed to widget builders.
/// Callback to launch an export URL (CSV, XLSX download).
typedef ExportLauncher = void Function(String url);

class MoquiRenderContext {
  final ScreenNavigator navigate;
  final FormSubmitter submitForm;
  final DynamicLoader loadDynamic;
  final DynamicPoster? postDynamic;
  final Map<String, dynamic> contextData;
  final String? currentScreenPath;
  final ExportLauncher? launchExportUrl;

  const MoquiRenderContext({
    required this.navigate,
    required this.submitForm,
    required this.loadDynamic,
    this.postDynamic,
    this.contextData = const {},
    this.currentScreenPath,
    this.launchExportUrl,
  });
}

/// Registry that maps Moqui widget type strings to Flutter widget builders.
///
/// Each Moqui JSON widget node has a `_type` field.  This factory dispatches
/// to the appropriate builder, producing a Flutter widget that matches the
/// Moqui XML screen's intent.
class MoquiWidgetFactory {
  const MoquiWidgetFactory._();

  /// Build a Flutter widget from a [WidgetNode].
  ///
  /// Any exception thrown by a sub-builder is caught here and replaced by an
  /// error card so one broken widget doesn't blank the entire screen.
  static Widget build(WidgetNode node, MoquiRenderContext ctx) {
    try {
      return _buildUnsafe(node, ctx);
    } catch (e, stack) {
      // Log briefly and render a non-crashing error indicator
      assert(() { debugPrint('MoquiWidgetFactory error for type=${node.type}: $e\n$stack'); return true; }());
      return _buildErrorCard(node.type, e);
    }
  }

  static Widget _buildErrorCard(String widgetType, Object error) {
    return Builder(builder: (context) {
      final mc = context.moquiColors;
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          border: Border.all(color: mc.errorBorder),
          borderRadius: BorderRadius.circular(4),
          color: mc.errorSurface,
        ),
        child: Row(
          children: [
            Icon(Icons.warning_amber_outlined, size: 16, color: mc.errorIcon),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'Widget error [$widgetType]: $error',
                style: TextStyle(fontSize: 12, color: mc.errorText),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      );
    });
  }

  static Widget _buildUnsafe(WidgetNode node, MoquiRenderContext ctx) {
    switch (node.type) {
      case 'form-single':
        return _buildFormSingle(node, ctx);
      case 'form-list':
        return _buildFormList(node, ctx);
      case 'section':
        return _buildSection(node, ctx);
      case 'section-iterate':
        return _buildSectionIterate(node, ctx);
      case 'container':
        return _buildContainer(node, ctx);
      case 'container-box':
        return _buildContainerBox(node, ctx);
      case 'container-row':
        return _buildContainerRow(node, ctx);
      case 'container-panel':
        return _buildContainerPanel(node, ctx);
      case 'container-dialog':
        return _buildContainerDialog(node, ctx);
      case 'subscreens-panel':
        return _buildSubscreensPanel(node, ctx);
      case 'subscreens-menu':
        return _buildSubscreensMenu(node, ctx);
      case 'subscreens-active':
        return _buildSubscreensActive(node, ctx);
      case 'link':
        return _buildLink(node, ctx);
      case 'label':
        return _buildLabel(node, ctx);
      case 'image':
        return _buildImage(node, ctx);
      case 'dynamic-dialog':
        return _buildDynamicDialog(node, ctx);
      case 'dynamic-container':
        return _buildDynamicContainer(node, ctx);
      case 'button-menu':
        return _buildButtonMenu(node, ctx);
      case 'tree':
        return _buildTree(node, ctx);
      case 'text':
        return _buildText(node, ctx);
      case 'include-screen':
        return _buildIncludeScreen(node, ctx);
      case 'section-include':
        return _buildSectionInclude(node, ctx);
      case 'widgets':
        // The server wraps top-level screen content in a _type:"widgets" node.
        // Use inline grouping so consecutive action buttons (container-dialog,
        // link, dynamic-dialog) render in a horizontal Wrap row — matching the
        // Moqui Vue UI layout — while block-level widgets stack vertically.
        if (node.children.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: _buildWithInlineGrouping(node.children, ctx),
        );
      default:
        return _buildGeneric(node, ctx);
    }
  }

  /// Build a list of widgets from child WidgetNodes.
  static List<Widget> buildChildren(WidgetNode node, MoquiRenderContext ctx) {
    return node.children.map((child) => build(child, ctx)).toList();
  }

  /// Build widgets from a list of WidgetNodes.
  static List<Widget> buildList(
      List<WidgetNode> nodes, MoquiRenderContext ctx) {
    return nodes.map((node) => build(node, ctx)).toList();
  }

  // =========================================================================
  // Inline-action grouping
  // =========================================================================

  /// Widget types that Moqui Vue renders inline (horizontally) when they appear
  /// consecutively at the same level in a section or column.
  static bool _isInlineWidget(WidgetNode node) {
    switch (node.type) {
      case 'link':
      case 'container-dialog':
      case 'dynamic-dialog':
        return true;
      case 'section':
        // Sections whose only children are inline widgets should also be inline.
        // This handles patterns like: section(cond) { link, dialog }
        final ws = node.attributes['widgets'] as List?;
        if (ws == null || ws.isEmpty) return true; // empty or failed section
        return ws.whereType<Map<String, dynamic>>().every((w) {
          final t = w['_type']?.toString() ?? '';
          return t == 'link' || t == 'container-dialog' || t == 'dynamic-dialog';
        });
      default:
        return false;
    }
  }

  /// Build children from a list of [WidgetNode]s, grouping consecutive
  /// inline-action widgets (links, dialogs) into horizontal [Wrap] rows.
  ///
  /// This replicates how the Moqui Vue UI renders action buttons in a
  /// horizontal flow while block-level widgets (forms, containers, labels)
  /// stack vertically.
  static List<Widget> _buildWithInlineGrouping(
      List<WidgetNode> nodes, MoquiRenderContext ctx) {
    final result = <Widget>[];
    final inlineBatch = <WidgetNode>[];

    void flushInline() {
      if (inlineBatch.isEmpty) return;
      result.add(Wrap(
        spacing: 4,
        runSpacing: 4,
        children: inlineBatch.map((n) => build(n, ctx)).toList(),
      ));
      inlineBatch.clear();
    }

    for (final node in nodes) {
      if (_isInlineWidget(node)) {
        inlineBatch.add(node);
      } else {
        flushInline();
        result.add(build(node, ctx));
      }
    }
    flushInline();
    return result;
  }

  // =========================================================================
  // Form Single
  // =========================================================================

  static Widget _buildFormSingle(WidgetNode node, MoquiRenderContext ctx) {
    final form = FormDefinition.fromJson(node.attributes);
    return _MoquiFormSingle(form: form, ctx: ctx);
  }

  // =========================================================================
  // Form List
  // =========================================================================

  static Widget _buildFormList(WidgetNode node, MoquiRenderContext ctx) {
    final form = FormDefinition.fromJson(node.attributes);
    return _MoquiFormList(form: form, ctx: ctx);
  }

  // =========================================================================
  // Sections
  // =========================================================================

  static Widget _buildSection(WidgetNode node, MoquiRenderContext ctx) {
    final widgetsList = node.attributes['widgets'] as List?;
    final failWidgetsList = node.attributes['failWidgets'] as List?;

    // The server already evaluates the condition — if widgets are present,
    // the condition passed. If failWidgets are present and widgets empty,
    // the condition failed.
    if (widgetsList != null && widgetsList.isNotEmpty) {
      final children = widgetsList
          .whereType<Map<String, dynamic>>()
          .map((w) => WidgetNode.fromJson(w))
          .toList();
      if (children.isEmpty) return const SizedBox.shrink();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: _buildWithInlineGrouping(children, ctx),
      );
    }

    if (failWidgetsList != null && failWidgetsList.isNotEmpty) {
      final children = failWidgetsList
          .whereType<Map<String, dynamic>>()
          .map((w) => WidgetNode.fromJson(w))
          .toList();
      if (children.isEmpty) return const SizedBox.shrink();
      // Phase 5.3: fail-widgets get distinct error styling
      return _buildFailWidgetsContainer(children, ctx);
    }

    // Fallback: render children directly
    if (node.children.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: node.children.map((c) => build(c, ctx)).toList(),
    );
  }

  // Phase 5.2: section-include — server inlines the referenced section
  static Widget _buildSectionInclude(WidgetNode node, MoquiRenderContext ctx) {
    final widgetsList = node.attributes['widgets'] as List?;
    final failWidgetsList = node.attributes['failWidgets'] as List?;

    if (widgetsList != null && widgetsList.isNotEmpty) {
      final children = widgetsList
          .whereType<Map<String, dynamic>>()
          .map((w) => WidgetNode.fromJson(w))
          .toList();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children.map((c) => build(c, ctx)).toList(),
      );
    }

    if (failWidgetsList != null && failWidgetsList.isNotEmpty) {
      final children = failWidgetsList
          .whereType<Map<String, dynamic>>()
          .map((w) => WidgetNode.fromJson(w))
          .toList();
      // Phase 5.3: fail-widgets get distinct error styling
      return _buildFailWidgetsContainer(children, ctx);
    }

    return const SizedBox.shrink();
  }

  // Phase 5.3: Distinct fail-widgets rendering with error tint
  static Widget _buildFailWidgetsContainer(
      List<WidgetNode> children, MoquiRenderContext ctx) {
    return Builder(builder: (context) {
      final mc = context.moquiColors;
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: mc.errorSurface,
          border: Border(
            left: BorderSide(color: mc.errorBorder, width: 3),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
        children: children.map((c) => build(c, ctx)).toList(),
      ),
    );
    });
  }

  static Widget _buildSectionIterate(WidgetNode node, MoquiRenderContext ctx) {
    // Section-iterate renders a template for each item in a list.
    // The server may send pre-expanded iterations (each iteration is a list of widget JSON).

    // Check for server-expanded iterations array
    final iterations = node.attributes['iterations'] as List?;
    if (iterations != null && iterations.isNotEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: iterations.expand<Widget>((iteration) {
          if (iteration is List) {
            final nodes = iteration
                .whereType<Map<String, dynamic>>()
                .map((w) => WidgetNode.fromJson(w))
                .toList();
            return _buildWithInlineGrouping(nodes, ctx);
          }
          return <Widget>[];
        }).toList(),
      );
    }

    // If children were already expanded server-side
    if (node.children.isNotEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: node.children.map((c) => build(c, ctx)).toList(),
      );
    }

    // Client-side iteration over listData
    final listName = node.attr('list');
    final entry = node.attr('entry', listName.replaceAll(RegExp(r'List$'), ''));
    final widgetTemplates = node.attributes['widgetTemplate'] as List?;
    
    // Get the list from context data
    final listData = ctx.contextData[listName] as List? ?? 
        node.attributes['listData'] as List? ?? [];

    if (listData.isEmpty || widgetTemplates == null) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: listData.asMap().entries.map((listEntry) {
        final index = listEntry.key;
        final item = listEntry.value as Map<String, dynamic>? ?? {};
        
        // Create a new context with the entry data merged in
        final entryContext = MoquiRenderContext(
          navigate: ctx.navigate,
          submitForm: ctx.submitForm,
          loadDynamic: ctx.loadDynamic,
          postDynamic: ctx.postDynamic,
          launchExportUrl: ctx.launchExportUrl,
          contextData: {
            ...ctx.contextData,
            entry: item,
            '${entry}_index': index,
            ...item, // Merge item fields directly into context
          },
        );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: widgetTemplates
              .whereType<Map<String, dynamic>>()
              .map((w) => build(WidgetNode.fromJson(w), entryContext))
              .toList(),
        );
      }).toList(),
    );
  }

  // =========================================================================
  // Containers
  // =========================================================================

  static Widget _buildContainer(WidgetNode node, MoquiRenderContext ctx) {
    final condition = node.attr('condition');
    if (condition == 'false') return const SizedBox.shrink();

    final containerType = node.attr('containerType', 'div');
    final style = node.attr('style');
    final children = buildChildren(node, ctx);

    if (children.isEmpty) return const SizedBox.shrink();

    // Map HTML-like container types to Flutter layouts
    switch (containerType) {
      case 'row':
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children.map((c) => Flexible(child: c)).toList(),
        );
      case 'dl':
        // Definition list: pair up dt (term) and dd (definition) children.
        // Build a compact two-column table of key-value pairs.
        return _buildDefinitionList(node, ctx);
      case 'dt':
        // Definition term — render bold
        return DefaultTextStyle.merge(
          style: const TextStyle(fontWeight: FontWeight.bold),
          child: children.length == 1
              ? children.first
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: children,
                ),
        );
      case 'dd':
        // Definition description — render with left padding
        return Padding(
          padding: const EdgeInsets.only(left: 8),
          child: children.length == 1
              ? children.first
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: children,
                ),
        );
      case 'hr':
        return const Divider(height: 24, thickness: 1);
      case 'ul':
      case 'ol':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children
              .map((c) => Padding(
                    padding: const EdgeInsets.only(left: 16, bottom: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(containerType == 'ul' ? '• ' : '${children.indexOf(c) + 1}. '),
                        Expanded(child: c),
                      ],
                    ),
                  ))
              .toList(),
        );
      default: // div, span, etc.
        return Padding(
          padding: style.contains('q-pa') ? const EdgeInsets.all(16) : EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: children,
          ),
        );
    }
  }

  /// Build an HTML-style definition list (`<dl>`) from child `dt`/`dd` nodes.
  ///
  /// Pairs consecutive `dt` (term) and `dd` (definition) children into rows.
  /// Each row shows the term on the left and the definition on the right,
  /// mimicking the Moqui Vue UI's definition-list styling.
  static Widget _buildDefinitionList(WidgetNode node, MoquiRenderContext ctx) {
    final childNodes = node.children;
    final rows = <Widget>[];
    int i = 0;
    while (i < childNodes.length) {
      final child = childNodes[i];
      final childType = child.attr('containerType', child.attr('labelType', child.type));

      if (childType == 'dt') {
        // Look ahead for the matching dd
        final dtWidget = build(child, ctx);
        Widget ddWidget = const SizedBox.shrink();
        if (i + 1 < childNodes.length) {
          final next = childNodes[i + 1];
          final nextType = next.attr('containerType', next.attr('labelType', next.type));
          if (nextType == 'dd') {
            ddWidget = build(next, ctx);
            i += 2;
          } else {
            i += 1;
          }
        } else {
          i += 1;
        }
        rows.add(Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 160,
                child: DefaultTextStyle.merge(
                  style: const TextStyle(fontWeight: FontWeight.w600),
                  child: dtWidget,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(child: ddWidget),
            ],
          ),
        ));
      } else {
        // Not a dt — render standalone (e.g. a section or other widget inside dl)
        rows.add(build(child, ctx));
        i += 1;
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: rows,
    );
  }

  static Widget _buildContainerBox(WidgetNode node, MoquiRenderContext ctx) {
    final headerWidgets = node.attributes['header'] as List?;
    final toolbarWidgets = node.attributes['toolbar'] as List?;
    final bodyWidgets = node.attributes['body'] as List?;
    final bodyNoPadWidgets = node.attributes['bodyNoPad'] as List?;
    final boxTitle = node.attributes['boxTitle'] as String?;

    // Determine if we have actual header child widgets (not just an empty list)
    final hasHeaderChildren = headerWidgets != null &&
        headerWidgets.whereType<Map<String, dynamic>>().isNotEmpty;
    final hasToolbar = toolbarWidgets != null &&
        toolbarWidgets.whereType<Map<String, dynamic>>().isNotEmpty;

    return Builder(builder: (context) {
    return Card(
      margin: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header + Toolbar
          if (hasHeaderChildren || hasToolbar || (boxTitle != null && boxTitle.isNotEmpty))
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: context.moquiColors.borderColor),
                ),
              ),
              child: Row(
                children: [
                  if (hasHeaderChildren)
                    Expanded(
                      child: Wrap(
                        children: headerWidgets
                            .whereType<Map<String, dynamic>>()
                            .map((w) => build(WidgetNode.fromJson(w), ctx))
                            .toList(),
                      ),
                    )
                  else if (boxTitle != null && boxTitle.isNotEmpty)
                    Expanded(
                      child: Text(
                        tpl.cleanDisplayText(boxTitle, fallback: boxTitle),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  if (hasToolbar)
                    Wrap(
                      children: toolbarWidgets
                          .whereType<Map<String, dynamic>>()
                          .map((w) => build(WidgetNode.fromJson(w), ctx))
                          .toList(),
                    ),
                ],
              ),
            ),
          // Body
          if (bodyWidgets != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: bodyWidgets
                    .whereType<Map<String, dynamic>>()
                    .map((w) => build(WidgetNode.fromJson(w), ctx))
                    .toList(),
              ),
            ),
          // Body no pad
          if (bodyNoPadWidgets != null)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: bodyNoPadWidgets
                  .whereType<Map<String, dynamic>>()
                  .map((w) => build(WidgetNode.fromJson(w), ctx))
                  .toList(),
            ),
        ],
      ),
    );
    });
  }

  static Widget _buildContainerRow(WidgetNode node, MoquiRenderContext ctx) {
    final columns = node.attributes['columns'] as List?;
    if (columns == null || columns.isEmpty) return const SizedBox.shrink();
    final rowStyle = tpl.cleanStyleAttr(node.attr('style'));

    return LayoutBuilder(builder: (context, constraints) {
      final w = constraints.maxWidth;

      // Bootstrap-compatible breakpoints: xs <576, sm 576-767, md 768-991, lg ≥992
      final String breakpoint;
      if (w >= 992) {
        breakpoint = 'lg';
      } else if (w >= 768) {
        breakpoint = 'md';
      } else if (w >= 576) {
        breakpoint = 'sm';
      } else {
        breakpoint = 'xs';
      }

      final colData = columns.whereType<Map<String, dynamic>>().toList();

      // Helper: parse column children and apply inline-action grouping
      List<Widget> buildColChildren(List childList) {
        final nodes = childList
            .whereType<Map<String, dynamic>>()
            .map((cw) => WidgetNode.fromJson(cw))
            .toList();
        return _buildWithInlineGrouping(nodes, ctx);
      }

      // At xs breakpoint, always stack vertically regardless of column sizes
      if (breakpoint == 'xs') {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: colData.map((col) {
            final childList = col['children'] as List? ?? [];
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: buildColChildren(childList),
              ),
            );
          }).toList(),
        );
      }

      // For sm, md, lg — resolve the best matching flex value per column.
      // Cascade: try exact breakpoint, then fall back to the next smaller one.
      final colWidgets = colData.map((col) {
        final childList = col['children'] as List? ?? [];
        final flex = _resolveColFlex(col, breakpoint);

        return Expanded(
          flex: flex,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: buildColChildren(childList),
            ),
          ),
        );
      }).toList();

      // Check if any column has flex == 12 (full-width); if so, stack vertically
      final anyFullWidth = colData.any((col) => _resolveColFlex(col, breakpoint) >= 12);
      if (anyFullWidth) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: colData.map((col) {
            final childList = col['children'] as List? ?? [];
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: buildColChildren(childList),
              ),
            );
          }).toList(),
        );
      }

      Widget rowWidget = Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: colWidgets,
      );

      // Apply shaded-area style (light grey background, common in Moqui)
      if (rowStyle.contains('shaded-area')) {
        rowWidget = Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(4),
          ),
          child: rowWidget,
        );
      }

      return rowWidget;
    });
  }

  /// Resolve the Bootstrap grid flex value for a column at a given breakpoint.
  /// Falls back through sm → md → lg if the exact breakpoint isn't specified.
  static int _resolveColFlex(Map<String, dynamic> col, String breakpoint) {
    const order = ['lg', 'md', 'sm'];
    final startIdx = order.indexOf(breakpoint);
    for (var i = startIdx; i < order.length; i++) {
      final val = int.tryParse(col[order[i]]?.toString() ?? '');
      if (val != null) return val;
    }
    // Ultimate fallback: try lg, then default to 1
    return int.tryParse(col['lg']?.toString() ?? '') ?? 1;
  }

  static Widget _buildContainerPanel(WidgetNode node, MoquiRenderContext ctx) {
    final collapsible = node.boolAttr('collapsible');
    final initiallyCollapsed = node.boolAttr('initiallyCollapsed');

    if (collapsible) {
      return _CollapsiblePanel(node: node, ctx: ctx, initiallyCollapsed: initiallyCollapsed);
    }

    return _buildContainerPanelBody(node, ctx);
  }

  static Widget _buildContainerPanelBody(WidgetNode node, MoquiRenderContext ctx) {
    final headerWidgets = node.attributes['header'] as List?;
    final leftData = node.attributes['left'] as Map<String, dynamic>?;
    final centerWidgets = node.attributes['center'] as List?;
    final rightData = node.attributes['right'] as Map<String, dynamic>?;
    final footerWidgets = node.attributes['footer'] as List?;

    return LayoutBuilder(builder: (context, constraints) {
      final bodyRow = Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (leftData != null)
            SizedBox(
              width: double.tryParse(leftData['size']?.toString() ?? '180') ?? 180,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: (leftData['children'] as List? ?? [])
                    .whereType<Map<String, dynamic>>()
                    .map((w) => build(WidgetNode.fromJson(w), ctx))
                    .toList(),
              ),
            ),
          if (centerWidgets != null)
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: centerWidgets
                    .whereType<Map<String, dynamic>>()
                    .map((w) => build(WidgetNode.fromJson(w), ctx))
                    .toList(),
              ),
            ),
          if (rightData != null)
            SizedBox(
              width: double.tryParse(rightData['size']?.toString() ?? '180') ?? 180,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: (rightData['children'] as List? ?? [])
                    .whereType<Map<String, dynamic>>()
                    .map((w) => build(WidgetNode.fromJson(w), ctx))
                    .toList(),
              ),
            ),
        ],
      );

      return Column(
        children: [
          // Header
          if (headerWidgets != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              child: Wrap(
                children: headerWidgets
                    .whereType<Map<String, dynamic>>()
                    .map((w) => build(WidgetNode.fromJson(w), ctx))
                    .toList(),
              ),
            ),
          // Body: Left | Center | Right
          // Use Flexible only when height is bounded; otherwise just use the Row directly
          if (constraints.maxHeight.isFinite)
            Flexible(child: bodyRow)
          else
            bodyRow,
          // Footer
          if (footerWidgets != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              child: Wrap(
                children: footerWidgets
                    .whereType<Map<String, dynamic>>()
                    .map((w) => build(WidgetNode.fromJson(w), ctx))
                    .toList(),
              ),
            ),
        ],
      );
    });
  }

  static Widget _buildContainerDialog(WidgetNode node, MoquiRenderContext ctx) {
    final buttonText = tpl.cleanDisplayText(node.attr('buttonText', 'Open'), fallback: 'Open');
    final dialogTitle = tpl.cleanDisplayText(node.attr('dialogTitle', ''));
    final icon = node.attr('icon');
    final dialogWidth = double.tryParse(node.attr('dialogWidth', '')) ?? 500;
    final btnType = tpl.cleanBtnType(node.attr('btnType'));
    final condition = node.attr('condition');
    final openDialog = node.boolAttr('openDialog'); // auto-open on load

    // Condition handling: if server provided condition=false, hide button
    if (condition == 'false') {
      return const SizedBox.shrink();
    }

    void showContainerDialog(BuildContext context) {
      showDialog(
        context: context,
        builder: (dialogContext) => AlertDialog(
          // Phase 5.5: Title bar with close button
          title: dialogTitle.isNotEmpty
              ? Row(
                  children: [
                    Expanded(child: Text(dialogTitle)),
                    IconButton(
                      icon: const Icon(Icons.close, size: 20),
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      tooltip: 'Close',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    ),
                  ],
                )
              : null,
          content: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: dialogWidth.clamp(300.0, 900.0),
              maxHeight: MediaQuery.of(context).size.height * 0.8,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: buildChildren(node, ctx),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    }

    return _ContainerDialogButton(
      buttonText: buttonText,
      icon: icon,
      btnType: btnType,
      openDialog: openDialog,
      showContainerDialog: showContainerDialog,
    );
  }

  // =========================================================================
  // Subscreens
  // =========================================================================

  static Widget _buildSubscreensPanel(WidgetNode node, MoquiRenderContext ctx) {
    // Extract subscreens from server-provided data or context
    final subscreensData = node.attributes['subscreens'] as List?;
    final type = node.attr('type', 'tab'); // tab, popup, stack, wizard
    final noSubBanner = node.boolAttr('noSubBanner');
    final defaultItem = node.attributes['defaultItem']?.toString() ?? '';

    // Get the active subscreen content if server pre-rendered it
    final activeSubscreenData =
        node.attributes['activeSubscreen'] as Map<String, dynamic>?;

    // Normalize subscreens list from server or context
    List<Map<String, dynamic>> normalizedSubscreens = [];

    final rawList = subscreensData ??
        ctx.contextData['subscreens'] as List? ??
        [];

    for (final item in rawList) {
      if (item is! Map<String, dynamic>) continue;
      final normalized = Map<String, dynamic>.from(item);
      // Map 'menuTitle' to 'title' for consistency with what _SubscreensPanelWidget expects
      normalized['title'] ??=
          normalized['menuTitle'] ?? normalized['name'] ?? '';
      // Build a path for lazy loading if not already present
      // loadDynamic prepends the current screen path, so just use the name
      normalized['path'] ??= normalized['name'] ?? '';
      // Mark the default item as active
      if (defaultItem.isNotEmpty && normalized['name'] == defaultItem) {
        normalized['active'] = true;
      }
      normalizedSubscreens.add(normalized);
    }

    // If server provided active subscreen content but no subscreens list,
    // render the subscreen content directly
    if (normalizedSubscreens.isEmpty && activeSubscreenData != null) {
      final screenNode = ScreenNode.fromJson(activeSubscreenData);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: screenNode.widgets
            .map((w) => MoquiWidgetFactory.build(w, ctx))
            .toList(),
      );
    }

    if (normalizedSubscreens.isEmpty) {
      // Last fallback: if there's an activeSubscreen in children, render it
      for (final child in node.children) {
        if (child.type == 'subscreens-active') {
          final childActiveData =
              child.attributes['activeSubscreen'] as Map<String, dynamic>?;
          if (childActiveData != null) {
            final screenNode = ScreenNode.fromJson(childActiveData);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: screenNode.widgets
                  .map((w) => MoquiWidgetFactory.build(w, ctx))
                  .toList(),
            );
          }
        }
      }
      return const SizedBox.shrink();
    }

    return _SubscreensPanelWidget(
      subscreens: normalizedSubscreens,
      type: type,
      noSubBanner: noSubBanner,
      ctx: ctx,
      preloadedActiveSubscreen: activeSubscreenData,
      defaultItem: defaultItem,
    );
  }

  static Widget _buildSubscreensMenu(WidgetNode node, MoquiRenderContext ctx) {
    // subscreens-menu renders a dropdown menu of subscreens
    final subscreensData = node.attributes['subscreens'] as List? ??
        ctx.contextData['subscreens'] as List? ?? [];

    if (subscreensData.isEmpty) return const SizedBox.shrink();

    final items = subscreensData
        .whereType<Map<String, dynamic>>()
        .where((s) => s['menuInclude'] != false)
        .toList();

    if (items.isEmpty) return const SizedBox.shrink();

    return Builder(builder: (context) {
      return PopupMenuButton<String>(
        tooltip: 'Subscreens',
        icon: const Icon(Icons.menu),
        itemBuilder: (_) => items.map((item) {
          return PopupMenuItem<String>(
            value: item['path']?.toString() ?? '',
            child: Row(
              children: [
                if (item['image'] != null && item['image'].toString().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Icon(_mapIcon(item['image'].toString()), size: 18),
                  ),
                Text(item['title']?.toString() ?? item['name']?.toString() ?? ''),
              ],
            ),
          );
        }).toList(),
        onSelected: (path) {
          if (path.isNotEmpty) ctx.navigate(path);
        },
      );
    });
  }

  static Widget _buildSubscreensActive(WidgetNode node, MoquiRenderContext ctx) {
    // subscreens-active renders the currently active subscreen's content
    // This is typically used within a parent screen to embed subscreen content
    final activeScreen = node.attributes['activeSubscreen'] as Map<String, dynamic>?;
    
    if (activeScreen == null) {
      // The active content should be loaded dynamically
      // First check extraPath from context, then fall back to defaultItem from server
      String loadPath = ctx.contextData['extraPath']?.toString() ?? '';
      if (loadPath.isEmpty) {
        loadPath = node.attr('defaultItem', '');
      }
      if (loadPath.isEmpty) {
        return const SizedBox.shrink();
      }
      
      // Load the active subscreen via a StatefulWidget that caches the future
      return _AsyncLoadWidget(
        loadKey: '${ctx.currentScreenPath}/$loadPath',
        loader: () => ctx.loadDynamic(loadPath, {}),
        builder: (data) {
          final screen = ScreenNode.fromJson(data);
          
          // Create child context with updated path for the loaded subscreen
          final childCtx = MoquiRenderContext(
            contextData: ctx.contextData,
            navigate: (path, {Map<String, dynamic>? params}) {
              // For relative paths, prepend loadPath before delegating to parent
              if (!path.startsWith('/') && !path.startsWith('http')) {
                final resolvedPath = loadPath.isNotEmpty ? '$loadPath/$path' : path;
                ctx.navigate(resolvedPath, params: params);
              } else {
                ctx.navigate(path, params: params);
              }
            },
            submitForm: ctx.submitForm,
            loadDynamic: (transition, params) async {
              return ctx.loadDynamic(
                loadPath.isNotEmpty ? '$loadPath/$transition' : transition,
                params,
              );
            },
            postDynamic: ctx.postDynamic != null
                ? (transition, params) async {
                    return ctx.postDynamic!(
                      loadPath.isNotEmpty ? '$loadPath/$transition' : transition,
                      params,
                    );
                  }
                : null,
            launchExportUrl: ctx.launchExportUrl,
            currentScreenPath: loadPath.isNotEmpty 
                ? '${ctx.currentScreenPath}/$loadPath'
                : ctx.currentScreenPath,
          );
          
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: screen.widgets.map((w) => build(w, childCtx)).toList(),
          );
        },
      );
    }

    // If activeScreen is embedded in the response, render it
    // Note: When server embeds activeSubscreen, we don't know the subscreen name/path,
    // so we can't create a proper child context. The parent context will be used.
    final screen = ScreenNode.fromJson(activeScreen);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: screen.widgets.map((w) => build(w, ctx)).toList(),
    );
  }

  // =========================================================================
  // Standalone Widgets
  // =========================================================================

  static Widget _buildLink(WidgetNode node, MoquiRenderContext ctx) {
    final text = tpl.cleanDisplayText(node.attr('resolvedText', node.attr('text', 'Link')), fallback: 'Link');
    final url = node.attr('url');
    final icon = node.attr('icon');
    final linkType = node.attr('linkType', 'auto');
    final confirmation = node.attr('confirmation');
    final btnType = tpl.cleanBtnType(node.attr('btnType'));
    final condition = node.attr('condition');
    final targetWindow = node.attr('targetWindow');
    final badgeText = node.attr('badge');
    final tooltip = node.attr('tooltip');
    final urlType = node.attr('urlType', 'transition'); // Phase 5.4

    // Build parameterMap from attributes.
    // Prefer the server-resolved 'parameterMap' (already evaluated against context)
    // over the raw 'parameters' list whose 'from' references can't be resolved client-side.
    Map<String, dynamic>? parameterMap;
    if (node.attributes['parameterMap'] is Map) {
      parameterMap = Map<String, dynamic>.from(node.attributes['parameterMap'] as Map);
    }
    // Process parameters list as a fallback — only fill keys not already present
    // in the resolved parameterMap (avoids overwriting correct server values with empty strings).
    if (node.attributes['parameters'] is List) {
      parameterMap ??= {};
      for (final p in (node.attributes['parameters'] as List).whereType<Map<String, dynamic>>()) {
        final name = p['name']?.toString() ?? '';
        final from = p['from']?.toString();
        final value = p['value']?.toString();
        if (name.isEmpty) continue;
        // Don't overwrite a key that's already present from the server-resolved map
        if (parameterMap.containsKey(name)) continue;
        if (from != null && from.isNotEmpty) {
          parameterMap[name] = ctx.contextData[from]?.toString() ?? value ?? '';
        } else {
          parameterMap[name] = value ?? '';
        }
      }
    }

    // Condition handling: if server provided condition=false, hide link
    if (condition == 'false') {
      return const SizedBox.shrink();
    }

    // Determine if this link is a form-submission transition (non-anchor) or
    // a plain navigation link (anchor). The server sets 'isAnchorLink'.
    final isAnchorLink = node.attributes['isAnchorLink'] != false;

    void onPressed() {
      if (url.isEmpty) return;

      // Phase 5.4: Handle urlType variants — download/external links
      if (urlType == 'content' || urlType == 'plain') {
        if (ctx.launchExportUrl != null) {
          String fullUrl = url;
          if (parameterMap != null && parameterMap.isNotEmpty) {
            final query = parameterMap.entries
                .map((e) => '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value.toString())}')
                .join('&');
            fullUrl += (fullUrl.contains('?') ? '&' : '?') + query;
          }
          ctx.launchExportUrl!(fullUrl);
        }
        return;
      }

      // Round 2.1: targetWindow="_blank" → open in browser tab
      if (targetWindow == '_blank' && ctx.launchExportUrl != null) {
        String fullUrl = url;
        if (parameterMap != null && parameterMap.isNotEmpty) {
          final query = parameterMap.entries
              .map((e) => '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value.toString())}')
              .join('&');
          fullUrl += (fullUrl.contains('?') ? '&' : '?') + query;
        }
        ctx.launchExportUrl!(fullUrl);
        return;
      }

      // Round 2.2: Confirmed links always POST (destructive actions like delete).
      // Unconfirmed links navigate via GET.
      if (confirmation.isNotEmpty) {
        ctx.submitForm(url, parameterMap ?? {});
      } else {
        ctx.navigate(url, params: parameterMap);
      }
    }

    // Wrap in Builder to get context for confirmation dialog
    return Builder(builder: (context) {
      VoidCallback effectiveOnPressed = onPressed;
      
      if (confirmation.isNotEmpty) {
        final inner = onPressed;
        effectiveOnPressed = () {
          // Show confirmation dialog before executing action
          showDialog(
            context: context,
            builder: (dialogContext) => AlertDialog(
              title: const Text('Confirm Action'),
              content: Text(confirmation),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () {
                    Navigator.of(dialogContext).pop();
                    inner();
                  },
                  child: const Text('Confirm'),
                ),
              ],
            ),
          );
        };
      }

      Widget linkWidget;

      // Build the button content (icon + text)
      Widget buttonContent = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Icon(_mapIcon(icon), size: 18),
            ),
          Flexible(
            child: tpl.looksLikeHtml(text)
                ? HtmlWidget(text, textStyle: const TextStyle())
                : Text(text, overflow: TextOverflow.ellipsis),
          ),
        ],
      );

      // Determine button color from btnType
      Color? btnColor;
      if (btnType.contains('danger')) {
        btnColor = Colors.red;
      } else if (btnType.contains('success')) {
        btnColor = Colors.green.shade700;
      } else if (btnType.contains('warning')) {
        btnColor = Colors.orange.shade800;
      }

      // Choose button style based on link-type and btn-type
      if (linkType == 'hidden-form-link' || btnType.contains('primary')) {
        linkWidget = Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
          child: ElevatedButton(
            onPressed: effectiveOnPressed,
            style: btnColor != null
                ? ElevatedButton.styleFrom(
                    backgroundColor: btnColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    minimumSize: Size.zero,
                  )
                : ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    minimumSize: Size.zero,
                  ),
            child: buttonContent,
          ),
        );
      } else if (linkType == 'hidden-form') {
        // hidden-form links render as compact outlined buttons in Moqui Vue
        linkWidget = Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
          child: OutlinedButton(
            onPressed: effectiveOnPressed,
            style: OutlinedButton.styleFrom(
              foregroundColor: btnColor ?? Theme.of(context).colorScheme.primary,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              minimumSize: Size.zero,
              textStyle: const TextStyle(fontSize: 13),
            ),
            child: buttonContent,
          ),
        );
      } else {
        linkWidget = Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
          child: TextButton(
            onPressed: effectiveOnPressed,
            style: btnColor != null
                ? TextButton.styleFrom(
                    foregroundColor: btnColor,
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    minimumSize: Size.zero,
                  )
                : TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    minimumSize: Size.zero,
                  ),
            child: buttonContent,
          ),
        );
      }

      // Attach badge if present (rendered as a small colored pill like Moqui's UI)
      if (badgeText.isNotEmpty && !badgeText.contains('\${')) {
        linkWidget = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            linkWidget,
            const SizedBox(width: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                badgeText,
                style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        );
      }

      // Wrap with tooltip if specified
      if (tooltip.isNotEmpty) {
        return Tooltip(message: tooltip, child: linkWidget);
      }

      return linkWidget;
    });
  }

  static Widget _buildLabel(WidgetNode node, MoquiRenderContext ctx) {
    final condition = node.attr('condition');
    // Condition handling: server may include a label with a condition attribute.
    // If the condition is 'false' or if the resolved text contains ": null" or
    // equals "null" when there's a condition, hide the label.
    if (condition == 'false') return const SizedBox.shrink();

    final rawText = node.attr('resolvedText', node.attr('text', ''));

    // Hide unresolved Moqui template names (e.g. "PartyNameTemplate",
    // "OrderPartHeaderTemplate"). These are L10n/resource expand keys that
    // the server couldn't resolve without entity context.
    if (RegExp(r'^[A-Z][a-zA-Z0-9]*Template$').hasMatch(rawText.trim())) {
      return const SizedBox.shrink();
    }

    final text = tpl.cleanDisplayText(rawText);
    final labelType = node.attr('labelType', 'span');
    final style = tpl.cleanStyleAttr(node.attr('style'));

    if (text.isEmpty) return const SizedBox.shrink();

    // If there's a condition and the resolved text is just "null" or ends with
    // ": null" or "null: ", the server data was empty — hide the label.
    if (condition.isNotEmpty) {
      final trimmed = text.trim();
      if (trimmed == 'null' ||
          trimmed.endsWith(': null') ||
          trimmed.endsWith('null: ') ||
          trimmed.startsWith('null:') ||
          trimmed == 'null:') {
        return const SizedBox.shrink();
      }
    }

    return Builder(builder: (context) {
      TextStyle textStyle;
      switch (labelType) {
        case 'h1':
          textStyle = Theme.of(context).textTheme.headlineLarge!;
          break;
        case 'h2':
          textStyle = Theme.of(context).textTheme.headlineMedium!;
          break;
        case 'h3':
          textStyle = Theme.of(context).textTheme.headlineSmall!;
          break;
        case 'h4':
          textStyle = Theme.of(context).textTheme.titleLarge!;
          break;
        case 'h5':
          textStyle = Theme.of(context).textTheme.titleMedium!;
          break;
        case 'h6':
          textStyle = Theme.of(context).textTheme.titleSmall!;
          break;
        case 'strong':
        case 'b':
          textStyle = Theme.of(context)
              .textTheme
              .bodyMedium!
              .copyWith(fontWeight: FontWeight.bold);
          break;
        case 'em':
        case 'i':
          textStyle = Theme.of(context)
              .textTheme
              .bodyMedium!
              .copyWith(fontStyle: FontStyle.italic);
          break;
        case 'small':
          textStyle = Theme.of(context).textTheme.bodySmall!;
          break;
        case 'code':
        case 'pre':
          textStyle = Theme.of(context)
              .textTheme
              .bodyMedium!
              .copyWith(fontFamily: 'monospace');
          break;
        default:
          textStyle = Theme.of(context).textTheme.bodyMedium!;
      }

      if (style.contains('text-danger') || style.contains('text-red')) {
        textStyle = textStyle.copyWith(color: Colors.red);
      } else if (style.contains('text-success') || style.contains('text-green')) {
        textStyle = textStyle.copyWith(color: Colors.green.shade700);
      } else if (style.contains('text-warning') || style.contains('text-orange')) {
        textStyle = textStyle.copyWith(color: Colors.orange.shade800);
      } else if (style.contains('text-muted') || style.contains('text-grey')) {
        textStyle = textStyle.copyWith(color: context.moquiColors.mutedText);
      }

      final child = tpl.looksLikeHtml(text)
          ? HtmlWidget(text, textStyle: textStyle)
          : Text(text, style: textStyle);

      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: child,
      );
    });
  }

  /// Returns `true` when [text] appears to contain HTML markup or entities.
  static bool _looksLikeHtml(String text) => tpl.looksLikeHtml(text);

  static Widget _buildImage(WidgetNode node, MoquiRenderContext ctx) {
    final url = node.attr('url');
    final alt = node.attr('alt');
    final width = double.tryParse(node.attr('width'));
    final height = double.tryParse(node.attr('height'));

    if (url.isEmpty) return const SizedBox.shrink();

    return Image.network(
      url.startsWith('http') ? url : '${ctx.contextData['baseUrl'] ?? ''}$url',
      width: width,
      height: height,
      semanticLabel: alt.isNotEmpty ? alt : 'Image',
      errorBuilder: (_, __, ___) =>
          Tooltip(message: alt, child: const Icon(Icons.broken_image)),
    );
  }

  static Widget _buildDynamicDialog(WidgetNode node, MoquiRenderContext ctx) {
    final buttonText = tpl.cleanDisplayText(node.attr('buttonText', 'Open'), fallback: 'Open');
    final transition = node.attr('transition');
    final dialogTitle = tpl.cleanDisplayText(node.attr('dialogTitle'));
    final dialogWidth = double.tryParse(node.attr('dialogWidth', '')) ?? 500;
    final icon = node.attr('icon');
    final btnType = tpl.cleanBtnType(node.attr('btnType'));
    final condition = node.attr('condition');

    // Condition handling: if server provided condition=false, hide button
    if (condition == 'false') {
      return const SizedBox.shrink();
    }

    // Button style based on btnType
    ButtonStyle? buttonStyle;
    if (btnType.contains('danger')) {
      buttonStyle = OutlinedButton.styleFrom(
        foregroundColor: Colors.red,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        minimumSize: Size.zero,
      );
    } else if (btnType.contains('success')) {
      buttonStyle = OutlinedButton.styleFrom(
        foregroundColor: Colors.green.shade700,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        minimumSize: Size.zero,
      );
    } else if (btnType.contains('secondary') || btnType.contains('link')) {
      buttonStyle = TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        minimumSize: Size.zero,
      );
    }

    return Builder(builder: (context) {
      final buttonChild = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Icon(_mapIcon(icon), size: 16),
            ),
          Flexible(child: Text(buttonText, overflow: TextOverflow.ellipsis)),
        ],
      );

      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
        child: btnType.contains('link')
            ? TextButton(
                style: buttonStyle,
                onPressed: () => _showDynamicDialogContent(
                  context, transition, dialogTitle, dialogWidth, node, ctx,
                ),
                child: buttonChild,
              )
            : OutlinedButton(
                style: buttonStyle ?? OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  minimumSize: Size.zero,
                  textStyle: const TextStyle(fontSize: 13),
                ),
                onPressed: () => _showDynamicDialogContent(
                  context, transition, dialogTitle, dialogWidth, node, ctx,
                ),
                child: buttonChild,
              ),
      );
    });
  }

  static void _showDynamicDialogContent(
    BuildContext context,
    String transition,
    String dialogTitle,
    double dialogWidth,
    WidgetNode node,
    MoquiRenderContext ctx,
  ) {
    if (transition.isEmpty) return;

    // Build parameters from attributes and context
    final params = <String, dynamic>{};
    final paramList = node.attributes['parameters'] as List?;
    if (paramList != null) {
      for (final p in paramList.whereType<Map<String, dynamic>>()) {
        final name = p['name']?.toString() ?? '';
        final from = p['from']?.toString();
        final value = p['value']?.toString();
        
        if (name.isEmpty) continue;
        
        // Try to resolve value from context if 'from' is specified
        if (from != null && from.isNotEmpty) {
          params[name] = ctx.contextData[from]?.toString() ?? value ?? '';
        } else {
          params[name] = value ?? '';
        }
      }
    }

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: dialogTitle.isNotEmpty ? Text(dialogTitle) : null,
        content: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: dialogWidth,
            maxHeight: MediaQuery.of(context).size.height * 0.8,
          ),
          child: FutureBuilder<Map<String, dynamic>>(
            future: ctx.loadDynamic(transition, params),
            builder: (_, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const SizedBox(
                  width: 100,
                  height: 100,
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              if (snapshot.hasError) {
                return Text('Error: ${snapshot.error}');
              }
              final screen = ScreenNode.fromJson(snapshot.data ?? {});
              return SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: screen.widgets.map((w) => build(w, ctx)).toList(),
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  static Widget _buildDynamicContainer(WidgetNode node, MoquiRenderContext ctx) {
    final transition = node.attr('transition');
    if (transition.isEmpty) return const SizedBox.shrink();

    return _AsyncLoadWidget(
      loadKey: transition,
      loader: () => ctx.loadDynamic(transition, {}),
      builder: (data) {
        final screen = ScreenNode.fromJson(data);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: screen.widgets.map((w) => build(w, ctx)).toList(),
        );
      },
    );
  }

  static Widget _buildButtonMenu(WidgetNode node, MoquiRenderContext ctx) {
    final text = tpl.cleanDisplayText(node.attr('text', 'Menu'), fallback: 'Menu');
    final icon = node.attr('icon');
    final image = node.attr('image');
    final btnType = tpl.cleanBtnType(node.attr('btnType'));

    // Phase 5.6: Resolve icon from image attr via MoquiIcons 
    IconData? resolvedIcon;
    if (icon.isNotEmpty) {
      resolvedIcon = _mapIcon(icon);
    } else if (image.isNotEmpty) {
      resolvedIcon = MoquiIcons.resolve(image);
    }

    // Phase 5.6: Determine chip color from btnType
    Color? chipColor;
    if (btnType.contains('primary')) {
      chipColor = Colors.blue;
    } else if (btnType.contains('danger')) {
      chipColor = Colors.red;
    } else if (btnType.contains('success')) {
      chipColor = Colors.green;
    } else if (btnType.contains('warning')) {
      chipColor = Colors.orange;
    }

    return Builder(builder: (context) {
      return PopupMenuButton<int>(
        child: Chip(
          avatar: resolvedIcon != null
              ? Icon(resolvedIcon, size: 18,
                  color: chipColor != null ? Colors.white : null)
              : null,
          label: Text(text,
              style: chipColor != null
                  ? const TextStyle(color: Colors.white)
                  : null),
          backgroundColor: chipColor?.withOpacity(0.85),
        ),
        itemBuilder: (_) {
          final items = <PopupMenuEntry<int>>[];
          for (var i = 0; i < node.children.length; i++) {
            final child = node.children[i];
            items.add(PopupMenuItem<int>(
              value: i,
              child: build(child, ctx),
            ));
          }
          return items;
        },
      );
    });
  }

  static Widget _buildTree(WidgetNode node, MoquiRenderContext ctx) {
    final treeName = node.attr('treeName');
    final items = node.attributes['items'] as List?;
    final treeError = node.attr('treeError');

    // Fallback to old treeNodes-only format
    if (items == null || items.isEmpty) {
      if (treeError.isNotEmpty) {
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Text('Tree "$treeName": $treeError',
              style: const TextStyle(color: Colors.orange)),
        );
      }
      final treeNodes = node.attributes['treeNodes'] as List?;
      if (treeNodes == null || treeNodes.isEmpty) return const SizedBox.shrink();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: treeNodes.whereType<Map<String, dynamic>>().map((tn) {
          final link = tn['link'] as Map<String, dynamic>?;
          final text = link?['text']?.toString() ?? tn['name']?.toString() ?? '';
          return ListTile(
            leading: const Icon(Icons.folder_outlined, size: 20),
            title: Text(tpl.cleanDisplayText(text)),
            dense: true,
            visualDensity: VisualDensity.compact,
          );
        }).toList(),
      );
    }

    // Render evaluated tree items with expand/collapse
    return _TreeWidget(items: items, ctx: ctx, treeName: treeName);
  }

  static Widget _buildText(WidgetNode node, MoquiRenderContext ctx) {
    final rawContent = node.attr('content');
    if (rawContent.isEmpty) return const SizedBox.shrink();

    // Clean any unresolved template expressions and HTML entities.
    final content = tpl.cleanDisplayText(rawContent);
    if (content.isEmpty) return const SizedBox.shrink();

    // Render HTML content via HtmlWidget when marked as html or when
    // the content looks like it contains markup.
    final textType = node.attr('textType');
    if (textType == 'html' || _looksLikeHtml(content)) {
      return HtmlWidget(content);
    }

    return Text(content);
  }

  static Widget _buildIncludeScreen(WidgetNode node, MoquiRenderContext ctx) {
    final location = node.attr('location');
    if (location.isEmpty) return const SizedBox.shrink();

    return _AsyncLoadWidget(
      loadKey: location,
      loader: () => ctx.loadDynamic(location, {}),
      builder: (data) {
        final screen = ScreenNode.fromJson(data);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: screen.widgets.map((w) => build(w, ctx)).toList(),
        );
      },
    );
  }

  static Widget _buildGeneric(WidgetNode node, MoquiRenderContext ctx) {
    if (node.children.isEmpty) {
      final text = tpl.cleanDisplayText(node.attr('text'));
      if (text.isNotEmpty) return Text(text);
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: buildChildren(node, ctx),
    );
  }

  // =========================================================================
  // Icon mapping — delegates to the consolidated MoquiIcons utility
  // =========================================================================

  static IconData _mapIcon(String faIcon) {
    return MoquiIcons.resolve(faIcon);
  }
}

// ============================================================================
// Async Load Widget (StatefulWidget that caches futures to prevent HTTP storms)
// ============================================================================

class _AsyncLoadWidget extends StatefulWidget {
  final String loadKey;
  final Future<Map<String, dynamic>> Function() loader;
  final Widget Function(Map<String, dynamic> data) builder;

  const _AsyncLoadWidget({
    required this.loadKey,
    required this.loader,
    required this.builder,
  });

  @override
  State<_AsyncLoadWidget> createState() => _AsyncLoadWidgetState();
}

class _AsyncLoadWidgetState extends State<_AsyncLoadWidget> {
  late Future<Map<String, dynamic>> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.loader();
  }

  @override
  void didUpdateWidget(covariant _AsyncLoadWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.loadKey != oldWidget.loadKey) {
      _future = widget.loader();
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _future,
      builder: (_, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }
        return widget.builder(snapshot.data ?? {});
      },
    );
  }
}

// ============================================================================
// Container Dialog Button (StatefulWidget to prevent infinite dialog loop)
// ============================================================================

class _ContainerDialogButton extends StatefulWidget {
  final String buttonText;
  final String icon;
  final String btnType;
  final bool openDialog;
  final void Function(BuildContext) showContainerDialog;

  const _ContainerDialogButton({
    required this.buttonText,
    required this.icon,
    required this.btnType,
    required this.openDialog,
    required this.showContainerDialog,
  });

  @override
  State<_ContainerDialogButton> createState() => _ContainerDialogButtonState();
}

class _ContainerDialogButtonState extends State<_ContainerDialogButton> {
  bool _hasAutoOpened = false;

  @override
  Widget build(BuildContext context) {
    ButtonStyle? buttonStyle;
    if (widget.btnType.contains('danger')) {
      buttonStyle = OutlinedButton.styleFrom(
        foregroundColor: Theme.of(context).colorScheme.error,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        minimumSize: Size.zero,
      );
    } else if (widget.btnType.contains('success')) {
      buttonStyle = OutlinedButton.styleFrom(
        foregroundColor: Colors.green.shade700,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        minimumSize: Size.zero,
      );
    } else if (widget.btnType.contains('warning')) {
      buttonStyle = OutlinedButton.styleFrom(
        foregroundColor: Colors.orange.shade800,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        minimumSize: Size.zero,
      );
    } else if (widget.btnType.contains('secondary')) {
      buttonStyle = OutlinedButton.styleFrom(
        foregroundColor: Theme.of(context).colorScheme.onSurfaceVariant,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        minimumSize: Size.zero,
      );
    }

    // Auto-open dialog only once on first build
    if (widget.openDialog && !_hasAutoOpened) {
      _hasAutoOpened = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.showContainerDialog(context);
      });
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
      child: OutlinedButton(
        style: buttonStyle ?? OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          minimumSize: Size.zero,
          textStyle: const TextStyle(fontSize: 13),
        ),
        onPressed: () => widget.showContainerDialog(context),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.icon.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Icon(MoquiWidgetFactory._mapIcon(widget.icon), size: 16),
              ),
            Flexible(child: Text(widget.buttonText, overflow: TextOverflow.ellipsis)),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// Tree Widget (StatefulWidget for expand/collapse state)
// ============================================================================

class _TreeWidget extends StatefulWidget {
  final List items;
  final MoquiRenderContext ctx;
  final String treeName;

  const _TreeWidget({required this.items, required this.ctx, required this.treeName});

  @override
  State<_TreeWidget> createState() => _TreeWidgetState();
}

class _TreeWidgetState extends State<_TreeWidget> {
  final Set<String> _expanded = {};

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final item in widget.items.whereType<Map<String, dynamic>>())
          _buildTreeItem(item, 0),
      ],
    );
  }

  Widget _buildTreeItem(Map<String, dynamic> item, int depth) {
    final text = tpl.cleanDisplayText(
      item['text']?.toString() ?? item['nodeType']?.toString() ?? '',
    );
    final url = item['url']?.toString() ?? '';
    final hasChildren = item['hasChildren'] == true;
    final children = item['children'] as List?;
    final itemKey = '${item['nodeType']}_${item['data']?.toString().hashCode ?? text.hashCode}';
    final isExpanded = _expanded.contains(itemKey);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(left: depth * 24.0),
          child: Semantics(
            button: true,
            expanded: hasChildren ? isExpanded : null,
            label: hasChildren
                ? '$text ${isExpanded ? "expanded" : "collapsed"} folder'
                : text,
            child: InkWell(
            onTap: () {
              if (hasChildren) {
                setState(() {
                  if (isExpanded) {
                    _expanded.remove(itemKey);
                  } else {
                    _expanded.add(itemKey);
                  }
                });
              } else if (url.isNotEmpty) {
                widget.ctx.navigate(url);
              }
            },
            borderRadius: BorderRadius.circular(4),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (hasChildren)
                    Icon(
                      isExpanded ? Icons.expand_more : Icons.chevron_right,
                      size: 20,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    )
                  else
                    const SizedBox(width: 20),
                  const SizedBox(width: 4),
                  Icon(
                    hasChildren
                        ? (isExpanded ? Icons.folder_open : Icons.folder)
                        : Icons.article_outlined,
                    size: 18,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: url.isNotEmpty
                        ? Text(text,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.primary,
                              decoration: TextDecoration.underline,
                            ),
                            overflow: TextOverflow.ellipsis)
                        : Text(text, overflow: TextOverflow.ellipsis),
                  ),
                ],
              ),
            ),
          ),
          ),
        ),
        if (isExpanded && children != null)
          for (final child in children.whereType<Map<String, dynamic>>())
            _buildTreeItem(child, depth + 1),
      ],
    );
  }
}

// ============================================================================
// Form Single Widget (StatefulWidget for form state management)
// ============================================================================

class _MoquiFormSingle extends StatefulWidget {
  final FormDefinition form;
  final MoquiRenderContext ctx;

  const _MoquiFormSingle({required this.form, required this.ctx});

  @override
  State<_MoquiFormSingle> createState() => _MoquiFormSingleState();
}

class _MoquiFormSingleState extends State<_MoquiFormSingle> {
  final _formKey = GlobalKey<FormState>();
  final Map<String, dynamic> _formData = {};
  bool _submitting = false;
  KeyboardIntentNotifier? _keyNotifier;
  int _lastHandledCounter = -1;

  @override
  void initState() {
    super.initState();
    // Populate initial values from field definitions
    for (final field in widget.form.fields) {
      if (field.currentValue != null && field.currentValue!.isNotEmpty) {
        _formData[field.name] = field.currentValue;
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Listen to keyboard shortcut broadcasts (Ctrl+S → submit)
    final notifier = KeyboardShortcutScope.read(context);
    if (notifier != _keyNotifier) {
      _keyNotifier?.removeListener(_onKeyboardIntent);
      _keyNotifier = notifier;
      _keyNotifier?.addListener(_onKeyboardIntent);
    }
  }

  @override
  void dispose() {
    _keyNotifier?.removeListener(_onKeyboardIntent);
    super.dispose();
  }

  void _onKeyboardIntent() {
    final n = _keyNotifier;
    if (n == null || n.counter == _lastHandledCounter) return;
    _lastHandledCounter = n.counter;
    if (n.lastIntent is SubmitFormIntent && !_submitting) {
      _submit();
    }
  }

  @override
  Widget build(BuildContext context) {
    final visibleFields =
        widget.form.fields.where((f) => !f.isHidden).toList();
    final hiddenFields =
        widget.form.fields.where((f) => f.isHidden).toList();

    // Collect hidden field values
    for (final hf in hiddenFields) {
      if (hf.currentValue != null) _formData[hf.name] = hf.currentValue;
    }

    return Form(
      key: _formKey,
      child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Render according to field layout or sequentially
              if (widget.form.fieldLayout != null)
                _buildFieldLayout(widget.form.fieldLayout!, visibleFields)
              else
                ...visibleFields.map((field) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: FieldWidgetFactory.build(
                        field: field,
                        formData: _formData,
                        onChanged: _handleFieldChanged,
                        ctx: widget.ctx,
                      ),
                    )),
            ],
          ),
          if (_submitting)
            Positioned.fill(
              child: Container(
                color: context.moquiColors.scrim,
                child: const Center(child: CircularProgressIndicator()),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFieldLayout(
      FieldLayout layout, List<FieldDefinition> fields) {
    final fieldMap = {for (final f in fields) f.name: f};

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: layout.rows.map((row) => _buildLayoutRow(row, fieldMap)).toList(),
    );
  }

  Widget _buildLayoutRow(FieldLayoutRow row, Map<String, FieldDefinition> fieldMap) {
    switch (row.type) {
      case 'field-ref':
        final field = fieldMap[row.name];
        if (field == null) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: FieldWidgetFactory.build(
            field: field,
            formData: _formData,
            onChanged: _handleFieldChanged,
            ctx: widget.ctx,
          ),
        );

      case 'field-row':
      case 'field-row-big':
        // Determine which fields to render in this row.
        // If the layout row has explicit field-refs, use them; otherwise
        // Moqui convention is to place ALL remaining (unassigned) visible
        // fields into the row.  This commonly appears in search forms where
        // <field-row-big/> has no children in the JSON.
        var rowFields = row.fields;
        if (rowFields.isEmpty) {
          // Infer: place every visible field from the form into this row
          rowFields = fieldMap.keys
              .map((name) => <String, String>{'name': name})
              .toList();
        }
        // Check if a field contains a submit widget (should not stretch).
        bool isSubmitField(FieldDefinition f) =>
            f.widgets.isNotEmpty && f.widgets.first.widgetType == 'submit';

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: rowFields.map((r) {
              final field = fieldMap[r['name']];
              if (field == null) return const Expanded(child: SizedBox.shrink());
              final child = Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: FieldWidgetFactory.build(
                  field: field,
                  formData: _formData,
                  onChanged: _handleFieldChanged,
                  ctx: widget.ctx,
                ),
              );
              // Submit buttons should stay compact, not stretch to fill.
              if (isSubmitField(field)) return child;
              return Expanded(child: child);
            }).toList(),
          ),
        );

      case 'field-group':
        return Card(
          margin: const EdgeInsets.symmetric(vertical: 8),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (row.title.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(row.title,
                        style: Theme.of(context).textTheme.titleMedium),
                  ),
                ...row.children.map((child) => _buildLayoutRow(child, fieldMap)),
              ],
            ),
          ),
        );

      case 'field-accordion':
        return Card(
          margin: const EdgeInsets.symmetric(vertical: 8),
          child: Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionPanelList.radio(
              expansionCallback: (index, isExpanded) {},
              children: row.children.asMap().entries.map((entry) {
                final group = entry.value;
                return ExpansionPanelRadio(
                  value: entry.key,
                  headerBuilder: (context, isExpanded) => ListTile(
                    title: Text(
                      group.title.isNotEmpty ? group.title : 'Section ${entry.key + 1}',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  body: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: group.children.map((child) => _buildLayoutRow(child, fieldMap)).toList(),
                    ),
                  ),
                  canTapOnHeader: true,
                );
              }).toList(),
            ),
          ),
        );

      case 'field-col-row':
        // Column-based row layout with responsive columns
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: row.children.map((col) {
              // Each child is a field-col with flex/md/lg attributes
              final flex = int.tryParse(col.fields.firstOrNull?['md'] ?? '1') ?? 1;
              return Expanded(
                flex: flex,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: col.children.map((child) => _buildLayoutRow(child, fieldMap)).toList(),
                  ),
                ),
              );
            }).toList(),
          ),
        );

      default:
        return const SizedBox.shrink();
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (widget.form.transition.isEmpty) return;

    setState(() => _submitting = true);
    try {
      // Check if any field contains file data (PlatformFile) — if so, flag
      // the formData so the submission layer can handle multipart upload.
      final hasFiles = _formData.values.any((v) =>
          v is PlatformFile || (v is List && v.any((e) => e is PlatformFile)));
      final submitData = Map<String, dynamic>.from(_formData);
      if (hasFiles) {
        submitData['_hasFileUploads'] = true;
      }

      final response = await widget.ctx.submitForm(widget.form.transition, submitData);
      if (!mounted) return;

      if (response != null) {
        // Show error messages
        if (response.hasErrors) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(response.errors.join('\n')),
              backgroundColor: Colors.red,
            ),
          );
          return;
        }

        // Show success messages
        if (response.hasMessages) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(response.messages.join('\n'))),
          );
        }

        // Navigate to redirect URL if present
        if (response.screenUrl.isNotEmpty) {
          widget.ctx.navigate(response.screenUrl,
              params: response.screenParameters.isNotEmpty
                  ? response.screenParameters
                  : null);
        }

        // If we're inside a dialog, close it since submission succeeded
        if (ModalRoute.of(context) is PopupRoute) {
          Navigator.of(context).pop();
        }
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _handleFieldChanged(String name, dynamic value) {
    if (name == '__submit__') {
      _submit();
      return;
    }
    setState(() => _formData[name] = value);
  }
}

// ============================================================================
// Form List Widget
// ============================================================================

class _MoquiFormList extends StatefulWidget {
  final FormDefinition form;
  final MoquiRenderContext ctx;

  const _MoquiFormList({required this.form, required this.ctx});

  @override
  State<_MoquiFormList> createState() => _MoquiFormListState();
}

class _MoquiFormListState extends State<_MoquiFormList> {
  bool _showFilters = false;
  final Map<String, dynamic> _filterData = {};
  final Set<int> _selectedRows = {};
  final Set<int> _editedRows = {};
  bool _submittingEdits = false;
  String? _sortColumn;
  bool _sortAscending = true;
  KeyboardIntentNotifier? _keyNotifier;
  int _lastHandledCounter = -1;

  /// Row count above which we switch from DataTable to virtual-scroll table.
  static const int _virtualScrollThreshold = 100;

  /// Row height for virtual scroll calculations.
  static const double _virtualRowHeight = 48.0;

  /// Maximum height for the virtual scroll viewport.
  static const double _maxVirtualTableHeight = 600.0;

  @override
  void initState() {
    super.initState();
    // Initialize sort state from paginateInfo if provided
    final orderBy = widget.form.paginateInfo['orderByField']?.toString();
    if (orderBy != null && orderBy.isNotEmpty) {
      if (orderBy.startsWith('-')) {
        _sortColumn = orderBy.substring(1);
        _sortAscending = false;
      } else {
        _sortColumn = orderBy;
        _sortAscending = true;
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Listen to keyboard shortcut broadcasts (Ctrl+F → open filters)
    final notifier = KeyboardShortcutScope.read(context);
    if (notifier != _keyNotifier) {
      _keyNotifier?.removeListener(_onKeyboardIntent);
      _keyNotifier = notifier;
      _keyNotifier?.addListener(_onKeyboardIntent);
    }
  }

  @override
  void dispose() {
    _keyNotifier?.removeListener(_onKeyboardIntent);
    super.dispose();
  }

  void _onKeyboardIntent() {
    final n = _keyNotifier;
    if (n == null || n.counter == _lastHandledCounter) return;
    _lastHandledCounter = n.counter;
    if (n.lastIntent is SearchFocusIntent) {
      if (!_showFilters && widget.form.headerFields.isNotEmpty) {
        setState(() => _showFilters = true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final visibleFields =
        widget.form.fields.where((f) => !f.isHidden).toList();

    // Determine column ordering from form columns if specified
    final orderedFields = _getOrderedFields(visibleFields);

    final currentPageSize =
        (widget.form.paginateInfo['pageSize'] as num?)?.toInt() ?? 20;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Toolbar: filter toggle, export, saved finds, page-size, show-all
        FormListToolbar(
          form: widget.form,
          showFilters: _showFilters,
          onToggleFilters: () => setState(() => _showFilters = !_showFilters),
          editedRowCount: _editedRows.length,
          submittingEdits: _submittingEdits,
          onSaveEdits: _editedRows.isNotEmpty ? _submitEdits : null,
          pageSize: currentPageSize,
          onPageSizeChanged: (size) {
            widget.ctx.loadDynamic('', {
              'pageSize': size.toString(),
              'pageIndex': '0',
            });
          },
          onShowAll: () {
            widget.ctx.loadDynamic('', {'pageNoLimit': 'true'});
          },
          savedFinds: widget.form.savedFinds,
          onLoadSavedFind: _loadSavedFind,
          onSaveCurrentFind: widget.form.headerFields.isNotEmpty
              ? () => _showSaveCurrentFindDialog(context)
              : null,
          onSelectColumns: widget.form.allColumns.isNotEmpty
              ? () => _showSelectColumnsDialog(context)
              : null,
          onExportCsv: widget.form.showCsvButton
              ? () => _exportData('csv')
              : null,
          onExportXlsx: widget.form.showXlsxButton
              ? () => _exportData('xlsx')
              : null,
        ),

        // Filter row (header-fields) — inline or dialog
        if (_showFilters && widget.form.headerFields.isNotEmpty)
          _buildFilterPanel(),

        // Data table with widget-rendered cells
        if (orderedFields.isEmpty)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text('No visible fields',
                style: TextStyle(color: context.moquiColors.mutedText)),
          )
        else if (widget.form.listData.length > _virtualScrollThreshold)
          _buildVirtualScrollTable(context, orderedFields)
        else
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            showCheckboxColumn: widget.form.hasRowSelection,
            sortColumnIndex: _sortColumn != null
                ? (() {
                    final idx = orderedFields.indexWhere((f) => f.name == _sortColumn);
                    return idx >= 0 ? idx : null;
                  })()
                : null,
            sortAscending: _sortAscending,
            columns: [
              // Row selection column handled by DataTable showCheckboxColumn
              ...orderedFields.asMap().entries.map((entry) {
                final colIndex = entry.key;
                final f = entry.value;
                return DataColumn(
                  label: Text(f.displayTitle),
                  onSort: (columnIndex, ascending) {
                    _onSort(f.name, ascending);
                  },
                );
              }),
            ],
            rows: widget.form.listData.isEmpty
                ? [
                    DataRow(
                      cells: orderedFields.asMap().entries.map((entry) {
                        if (entry.key == 0) {
                          return DataCell(Row(children: [
                            Icon(Icons.inbox_outlined, size: 18,
                                color: context.moquiColors.mutedText),
                            const SizedBox(width: 8),
                            Text(
                              'No records found',
                              style: TextStyle(
                                color: context.moquiColors.mutedText,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ]));
                        }
                        return const DataCell(SizedBox.shrink());
                      }).toList(),
                    ),
                  ]
                : widget.form.listData.asMap().entries.map((entry) {
              final rowIndex = entry.key;
              final row = entry.value;

              // Row-type coloring (3.7): _rowType field from server
              final rowType = row['_rowType']?.toString() ?? '';
              final rowColor = _rowTypeColor(rowType);

              return DataRow(
                color: rowColor != null
                    ? WidgetStateProperty.all(rowColor)
                    : null,
                selected: widget.form.hasRowSelection && _selectedRows.contains(rowIndex),
                onSelectChanged: widget.form.hasRowSelection
                    ? (selected) {
                        setState(() {
                          if (selected == true) {
                            _selectedRows.add(rowIndex);
                          } else {
                            _selectedRows.remove(rowIndex);
                          }
                        });
                      }
                    : null,
                cells: orderedFields.map((f) {
                  final cellWidget = _buildCellWidget(f, row);
                  final canTap = _rowNavigationEnabled &&
                      !_cellHasInteraction(f, row);
                  return DataCell(
                    cellWidget,
                    onTap: canTap ? () => _navigateToRowDetail(row) : null,
                  );
                }).toList(),
              );
            }).toList(),
          ),
        ),

        // Aggregate footer row (Phase 3.6)
        if (_hasAggregateFooter(orderedFields))
          _buildAggregateFooter(orderedFields),

        // Row selection action bar
        if (widget.form.hasRowSelection && _selectedRows.isNotEmpty)
          _buildSelectionActionBar(),

        // Pagination controls
        if (widget.form.paginate && widget.form.paginateInfo.isNotEmpty)
          _buildPaginationBar(),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Phase 8.7: Virtual-scroll table for large lists (>100 rows).
  // Uses a sticky header + ListView.builder to lazily build only visible rows,
  // avoiding the O(n) widget tree that DataTable creates.
  // ---------------------------------------------------------------------------
  Widget _buildVirtualScrollTable(
      BuildContext context, List<FieldDefinition> orderedFields) {
    final rows = widget.form.listData;
    final cs = Theme.of(context).colorScheme;
    final mc = context.moquiColors;

    // Calculate column width based on field count, ensuring minimum 120px each.
    const double colWidth = 160;
    final double checkboxColWidth = widget.form.hasRowSelection ? 56 : 0;
    final double totalWidth =
        checkboxColWidth + orderedFields.length * colWidth;

    // Viewport height: cap at max, or use actual rows height if smaller.
    final double viewportHeight =
        (rows.length * _virtualRowHeight).clamp(0, _maxVirtualTableHeight)
            .toDouble();

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SizedBox(
        width: totalWidth,
        child: Column(
          children: [
            // ── Sticky column header ──
            Container(
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                border: Border(
                  bottom: BorderSide(color: mc.borderColor, width: 1),
                ),
              ),
              height: _virtualRowHeight,
              child: Row(
                children: [
                  if (widget.form.hasRowSelection)
                    SizedBox(
                      width: checkboxColWidth,
                      child: Checkbox(
                        value: _selectedRows.length == rows.length &&
                            rows.isNotEmpty,
                        tristate: true,
                        onChanged: (val) {
                          setState(() {
                            if (val == true) {
                              _selectedRows.addAll(
                                  List.generate(rows.length, (i) => i));
                            } else {
                              _selectedRows.clear();
                            }
                          });
                        },
                      ),
                    ),
                  ...orderedFields.map((f) {
                    final isSorted = _sortColumn == f.name;
                    return InkWell(
                      onTap: () => _onSort(f.name, isSorted ? !_sortAscending : true),
                      child: SizedBox(
                        width: colWidth,
                        height: _virtualRowHeight,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  f.displayTitle,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (isSorted)
                                Icon(
                                  _sortAscending
                                      ? Icons.arrow_upward
                                      : Icons.arrow_downward,
                                  size: 14,
                                ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ),

            // ── Virtual-scroll body ──
            SizedBox(
              height: viewportHeight,
              child: ListView.builder(
                itemCount: rows.length,
                itemExtent: _virtualRowHeight,
                itemBuilder: (context, index) {
                  final row = rows[index];
                  final rowType = row['_rowType']?.toString() ?? '';
                  final rowColor = _rowTypeColor(rowType);
                  final isSelected = widget.form.hasRowSelection &&
                      _selectedRows.contains(index);

                  return InkWell(
                    onTap: _rowNavigationEnabled
                        ? () => _navigateToRowDetail(row)
                        : null,
                    mouseCursor: _rowNavigationEnabled
                        ? SystemMouseCursors.click
                        : SystemMouseCursors.basic,
                    child: Container(
                    height: _virtualRowHeight,
                    decoration: BoxDecoration(
                      color: rowColor ??
                          (isSelected
                              ? cs.primaryContainer.withValues(alpha: 0.3)
                              : (index.isOdd
                                  ? cs.surfaceContainerLowest
                                  : null)),
                      border: Border(
                        bottom: BorderSide(
                          color: mc.borderColor.withValues(alpha: 0.5),
                          width: 0.5,
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        if (widget.form.hasRowSelection)
                          SizedBox(
                            width: checkboxColWidth,
                            child: Checkbox(
                              value: isSelected,
                              onChanged: (selected) {
                                setState(() {
                                  if (selected == true) {
                                    _selectedRows.add(index);
                                  } else {
                                    _selectedRows.remove(index);
                                  }
                                });
                              },
                            ),
                          ),
                        ...orderedFields.map((f) {
                          return SizedBox(
                            width: colWidth,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              child: _buildCellWidget(f, row),
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Build the cell widget for a field in a form-list row.
  /// Instead of just displaying text, render the field's actual widget type.
  Widget _buildCellWidget(FieldDefinition field, Map<String, dynamic> row) {
    // Resolve widgets (handles conditional-field)
    final effectiveWidgets = field.resolveWidgets(row);

    // Special handling for "edit" and "delete" fields in AutoFind-style form-lists.
    // The Moqui fjson renderer only serializes the default-field (display ' ') for
    // conditional-field links. We detect the empty display and render proper icons.
    final isEmptyDisplay = effectiveWidgets.length == 1 &&
        effectiveWidgets.first.widgetType == 'display' &&
        (effectiveWidgets.first.attr('resolvedText').trim().isEmpty ||
            effectiveWidgets.first.attr('text').trim().isEmpty);
    if (isEmptyDisplay) {
      final hasData =
          row.values.any((v) => v != null && v.toString().isNotEmpty);
      if (hasData) {
        if (field.name == 'edit') return _buildAutoEditCell(row);
        if (field.name == 'delete') return _buildAutoDeleteCell(row);
      }
    }

    // Build the primary (default-field) widget
    Widget primaryWidget;
    if (effectiveWidgets.isEmpty) {
      final value = row['${field.name}_display'] ?? row[field.name];
      primaryWidget = Text(value?.toString() ?? '');
    } else {
      primaryWidget = _buildCellWidgetFromFieldWidget(field, effectiveWidgets.first, row);
    }

    // Multi-row cells: stack first-row-field, second-row-field, last-row-field
    if (field.rowFields.isEmpty) return primaryWidget;

    final children = <Widget>[primaryWidget];
    for (final rfg in field.rowFields) {
      if (rfg.widgets.isEmpty) continue;
      children.add(
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: _buildCellWidgetFromFieldWidget(field, rfg.widgets.first, row),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: children,
    );
  }

  /// Build a single cell widget from a FieldWidget (used by both default-field and row-fields).
  Widget _buildCellWidgetFromFieldWidget(
      FieldDefinition field, FieldWidget fieldWidget, Map<String, dynamic> row) {
    switch (fieldWidget.widgetType) {
      case 'link':
        return _buildCellLink(fieldWidget, row, field.name);
      case 'display':
        return _buildCellDisplay(field, fieldWidget, row);
      case 'hidden':
      case 'ignored':
        return const SizedBox.shrink();
      case 'text-line':
      case 'text-area':
      case 'drop-down':
      case 'check':
      case 'date-time':
      case 'editable':
        if (!widget.form.skipForm) {
          return _buildEditableCell(field, fieldWidget, row);
        }
        final value = row['${field.name}_display'] ?? row[field.name];
        return Text(value?.toString() ?? '');
      default:
        final value = row['${field.name}_display'] ?? row[field.name];
        return Text(value?.toString() ?? '');
    }
  }

  /// Build an inline-editable cell widget for form-list rows.
  Widget _buildEditableCell(
      FieldDefinition field, FieldWidget fw, Map<String, dynamic> row) {
    // Create a FieldDefinition with the current row value as currentValue
    final cellField = FieldDefinition(
      name: field.name,
      title: '', // No label in cell
      tooltip: field.tooltip,
      currentValue: row[field.name]?.toString(),
      widgets: [fw],
    );

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 200),
      child: FieldWidgetFactory.build(
        field: cellField,
        formData: row,
        onChanged: (name, value) {
          // Track the edit in the row
          row[name] = value;
          // Notify that this row has been edited
          _onCellEdited(row);
        },
        ctx: widget.ctx,
      ),
    );
  }

  void _onCellEdited(Map<String, dynamic> row) {
    // Find the row index and mark it as edited
    final rowIndex = widget.form.listData.indexOf(row);
    if (rowIndex >= 0) {
      setState(() => _editedRows.add(rowIndex));
    }
  }

  /// Submit all edited rows using Moqui form-list parameter naming convention
  /// (fieldName_rowIndex).
  Future<void> _submitEdits() async {
    if (_editedRows.isEmpty || widget.form.transition.isEmpty) return;

    setState(() => _submittingEdits = true);
    try {
      final submitData = <String, dynamic>{};
      // Build indexed parameter map: fieldName_rowIndex = value
      for (final rowIndex in _editedRows) {
        if (rowIndex >= widget.form.listData.length) continue;
        final row = widget.form.listData[rowIndex];
        for (final field in widget.form.fields) {
          final value = row[field.name];
          if (value != null) {
            submitData['${field.name}_$rowIndex'] = value.toString();
          }
        }
      }
      submitData['_isMulti'] = 'true';
      submitData['_rowCount'] = widget.form.listData.length.toString();

      final response = await widget.ctx.submitForm(
        widget.form.transition, submitData);
      if (!mounted) return;

      if (response != null) {
        // Show error messages
        if (response.hasErrors) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(response.errors.join('\n')),
              backgroundColor: Colors.red,
            ),
          );
          return;
        }

        // Show success messages
        if (response.hasMessages) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(response.messages.join('\n'))),
          );
        }

        // Navigate to redirect URL if present
        if (response.screenUrl.isNotEmpty) {
          widget.ctx.navigate(response.screenUrl,
              params: response.screenParameters.isNotEmpty
                  ? response.screenParameters
                  : null);
        }

        // Clear edited rows after successful submission
        setState(() => _editedRows.clear());

        // Placed in a dialog or other modal? Close it.
        if (ModalRoute.of(context) is PopupRoute) {
          Navigator.of(context).pop();
        }
      }
    } finally {
      if (mounted) setState(() => _submittingEdits = false);
    }
  }

  // ---------------------------------------------------------------------------
  // Phase 6.4: Auto-edit cell path — tapping a form-list row navigates to
  // the detail/edit screen.  Only enabled for display-only lists (skipForm).
  // ---------------------------------------------------------------------------

  /// Whether tapping a row should navigate to the detail/edit screen.
  bool get _rowNavigationEnabled => widget.form.skipForm;

  /// Navigate to the detail/edit screen for a row.
  void _navigateToRowDetail(Map<String, dynamic> row) {
    final target = widget.form.editUrl.isNotEmpty
        ? widget.form.editUrl
        : '../AutoEdit/AutoEditMaster';
    final params = <String, dynamic>{};
    for (final k in row.keys) {
      if (!k.startsWith('_') && !k.endsWith('_display')) {
        final v = row[k];
        if (v != null && v.toString().isNotEmpty) params[k] = v;
      }
    }
    widget.ctx.navigate(target, params: params);
  }

  /// Returns true when the cell already has its own tap handler (link, editable
  /// field, edit/delete icon) so the row-level navigation should NOT attach.
  bool _cellHasInteraction(FieldDefinition field, Map<String, dynamic> row) {
    if (field.name == 'edit' || field.name == 'delete') return true;
    final widgets = field.resolveWidgets(row);
    if (widgets.isEmpty) return false;
    final wt = widgets.first.widgetType;
    if (wt == 'link') return true;
    if (!widget.form.skipForm &&
        const {'text-line', 'text-area', 'drop-down', 'check', 'date-time', 'editable'}
            .contains(wt)) {
      return true;
    }
    return false;
  }

  /// Build an edit icon button for a form-list row.
  /// Uses the form's `editUrl` if provided by the server, otherwise falls back
  /// to the AutoScreen convention '../AutoEdit/AutoEditMaster'.
  Widget _buildAutoEditCell(Map<String, dynamic> row) {
    final target = widget.form.editUrl.isNotEmpty
        ? widget.form.editUrl
        : '../AutoEdit/AutoEditMaster';
    return IconButton(
      icon: const Icon(Icons.edit, size: 16),
      tooltip: 'Edit',
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      onPressed: () {
        // Build params: include aen and all non-_display fields
        final params = <String, dynamic>{};
        for (final k in row.keys) {
          if (!k.endsWith('_display')) {
            final v = row[k];
            if (v != null && v.toString().isNotEmpty) params[k] = v;
          }
        }
        widget.ctx.navigate(target, params: params);
      },
    );
  }

  /// Build a delete icon button for a form-list row using the AutoFind convention.
  /// Shows a confirmation dialog then POSTs to the deleteRecord transition.
  Widget _buildAutoDeleteCell(Map<String, dynamic> row) {
    return Builder(builder: (buildContext) {
      return IconButton(
        icon: Icon(Icons.delete, size: 16, color: Colors.red.shade400),
        tooltip: 'Delete',
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
        onPressed: () {
          showDialog(
            context: buildContext,
            builder: (dialogContext) => AlertDialog(
              title: const Text('Confirm Delete'),
              content: const Text('Are you sure?'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                  onPressed: () {
                    Navigator.of(dialogContext).pop();
                    // Build params: include aen and all non-_display fields
                    final params = <String, dynamic>{};
                    for (final k in row.keys) {
                      if (!k.endsWith('_display')) {
                        final v = row[k];
                        if (v != null && v.toString().isNotEmpty) params[k] = v;
                      }
                    }
                    widget.ctx.submitForm('deleteRecord', params);
                  },
                  child: const Text('Delete'),
                ),
              ],
            ),
          );
        },
      );
    });
  }

  Widget _buildCellLink(FieldWidget fw, Map<String, dynamic> row, [String fieldName = '']) {
    // Use per-row resolved link text from server if available (key: "fieldName_linkText")
    // Falls back to the template text from the field definition
    final text = tpl.cleanDisplayText(
        (fieldName.isNotEmpty ? row['${fieldName}_linkText']?.toString() : null) ??
        fw.attr('resolvedText', fw.attr('text')));
    final url = fw.attr('url');
    final icon = fw.attr('icon');
    final confirmation = fw.attr('confirmation');
    final linkType = fw.attr('linkType');

    // Build parameter map from the field widget's parameterMap,
    // resolving values from the row data
    Map<String, dynamic>? parameterMap;
    if (fw.attributes['parameterMap'] is Map) {
      parameterMap = {};
      for (final entry in (fw.attributes['parameterMap'] as Map).entries) {
        final key = entry.key.toString();
        final val = entry.value?.toString() ?? '';
        // If value references a row field, resolve it
        parameterMap[key] = row[val]?.toString() ?? row[key]?.toString() ?? val;
      }
    }
    // Also resolve parameters list
    if (fw.attributes['parameters'] is List) {
      parameterMap ??= {};
      for (final p in (fw.attributes['parameters'] as List).whereType<Map<String, dynamic>>()) {
        final name = p['name']?.toString() ?? '';
        final from = p['from']?.toString();
        final value = p['value']?.toString();
        if (name.isEmpty) continue;
        // Check server-provided per-row resolved param value first
        final serverResolved = fieldName.isNotEmpty
            ? row['${fieldName}_param_$name']?.toString()
            : null;
        if (serverResolved != null && serverResolved.isNotEmpty) {
          parameterMap[name] = serverResolved;
        } else if (from != null && from.isNotEmpty) {
          parameterMap[name] = row[from]?.toString() ?? value ?? '';
        } else {
          parameterMap[name] = value ?? '';
        }
      }
    }
    // Resolve parameterFromFields: server-provided mapping of param name → source row field name.
    // Used for parameter-map="[selectedEntity:fullEntityName]" where fullEntityName is per-row.
    // The server adds the raw field value (e.g. fullEntityName) to each row so we can look it up.
    if (fw.attributes['parameterFromFields'] is Map) {
      parameterMap ??= {};
      for (final entry in (fw.attributes['parameterFromFields'] as Map).entries) {
        final paramName = entry.key.toString();
        final fromField = entry.value?.toString() ?? '';
        // Only fill in if not already resolved to a non-empty value
        if (parameterMap.containsKey(paramName) &&
            (parameterMap[paramName] as String?)?.isNotEmpty == true) {
          continue;
        }
        // Try exact field name first, then with _display suffix
        final val = row[fromField]?.toString() ??
            row['${fromField}_display']?.toString() ?? '';
        if (val.isNotEmpty) parameterMap[paramName] = val;
      }
    }

    // If text is empty but icon is set, render icon-only button
    final hasText = text.isNotEmpty;
    final hasIcon = icon.isNotEmpty;

    // Use isAnchorLink from server to decide navigate vs submit
    final isAnchorLink = fw.attributes['isAnchorLink'] != false;

    void onTap() {
      if (url.isEmpty) return;
      // Navigation links (isAnchorLink) and subscreen-style hidden-form links
      // (no confirmation) use GET navigation. The fetchScreen method handles
      // transition redirects (screenUrl) automatically.
      // Only confirmed destructive links (delete, etc.) use POST submitForm.
      if (isAnchorLink || confirmation.isEmpty) {
        widget.ctx.navigate(url, params: parameterMap);
      } else {
        // Confirmed transition (e.g. delete) — submit as a form POST
        widget.ctx.submitForm(url, parameterMap ?? {});
      }
    }

    return Builder(builder: (context) {
      VoidCallback effectiveOnTap = onTap;

      if (confirmation.isNotEmpty) {
        final inner = onTap;
        effectiveOnTap = () {
          showDialog(
            context: context,
            builder: (dialogContext) => AlertDialog(
              title: const Text('Confirm Action'),
              content: Text(confirmation),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () {
                    Navigator.of(dialogContext).pop();
                    inner();
                  },
                  child: const Text('Confirm'),
                ),
              ],
            ),
          );
        };
      }

      if (!hasText && hasIcon) {
        // Icon-only button (e.g., edit/delete icons)
        return IconButton(
          icon: Icon(MoquiWidgetFactory._mapIcon(icon), size: 18),
          onPressed: effectiveOnTap,
          tooltip: fw.attr('tooltip', text),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
        );
      }

      if (linkType == 'anchor') {
        return Semantics(
          button: true,
          label: text.isNotEmpty ? text : 'Link',
          child: InkWell(
            onTap: effectiveOnTap,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (hasIcon)
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Icon(MoquiWidgetFactory._mapIcon(icon), size: 16),
                  ),
                Text(
                  text,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ],
            ),
          ),
        );
      }

      return TextButton(
        onPressed: effectiveOnTap,
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          minimumSize: const Size(0, 32),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (hasIcon)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Icon(MoquiWidgetFactory._mapIcon(icon), size: 16),
              ),
            Text(text),
          ],
        ),
      );
    });
  }

  /// Build a display widget inside a DataTable cell with format support.
  Widget _buildCellDisplay(FieldDefinition field, FieldWidget fw, Map<String, dynamic> row) {
    // The server's getFormListRowValues() puts display-formatted values under
    // "${fieldName}_display" and raw values under "${fieldName}"
    final displayValue = row['${field.name}_display'];
    final value = displayValue ?? row[field.name];
    final format = fw.attr('format');
    final style = tpl.cleanStyleAttr(fw.attr('style'));
    
    String displayText;
    if (format.isNotEmpty && value != null) {
      displayText = tpl.cleanDisplayText(_formatValue(value, format));
    } else {
      displayText = tpl.cleanDisplayText(value?.toString() ?? '');
    }

    TextStyle? textStyle;
    if (style.contains('text-strong') || style.contains('text-bold')) {
      textStyle = const TextStyle(fontWeight: FontWeight.bold);
    } else if (style.contains('text-danger') || style.contains('text-red')) {
      textStyle = const TextStyle(color: Colors.red);
    } else if (style.contains('text-success') || style.contains('text-green')) {
      textStyle = const TextStyle(color: Colors.green);
    } else if (style.contains('text-warning') || style.contains('text-orange')) {
      textStyle = const TextStyle(color: Colors.orange);
    } else if (style.contains('text-muted')) {
      textStyle = TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant);
    }

    return Text(displayText, style: textStyle);
  }

  /// Format a value using a date/number format pattern.
  String _formatValue(dynamic value, String format) {
    try {
      // Try date formatting first
      if (format.contains('yyyy') || format.contains('MM') || format.contains('dd')) {
        final date = DateTime.tryParse(value.toString());
        if (date != null) {
          return _simpleDateFormat(date, format);
        }
      }
      // Try number formatting
      final num? numVal = num.tryParse(value.toString());
      if (numVal != null && format.contains('#')) {
        return numVal.toStringAsFixed(format.split('.').length > 1 ? 
            format.split('.').last.length : 0);
      }
    } catch (_) {
      // Fallback to raw value
    }
    return value.toString();
  }

  /// Simple date formatter matching common Moqui patterns.
  String _simpleDateFormat(DateTime date, String format) {
    var result = format;
    result = result.replaceAll('yyyy', date.year.toString().padLeft(4, '0'));
    result = result.replaceAll('MM', date.month.toString().padLeft(2, '0'));
    result = result.replaceAll('dd', date.day.toString().padLeft(2, '0'));
    result = result.replaceAll('HH', date.hour.toString().padLeft(2, '0'));
    result = result.replaceAll('mm', date.minute.toString().padLeft(2, '0'));
    result = result.replaceAll('ss', date.second.toString().padLeft(2, '0'));
    result = result.replaceAll('SSS', date.millisecond.toString().padLeft(3, '0'));
    return result;
  }

  /// Get fields in the order specified by form columns, or default order.
  /// Also adds auto-generated display columns derived from listData keys for
  /// fields that are not defined in the form's fields array (e.g., entity fields
  /// from auto-fields-entity that the server doesn't include in the fields list).
  List<FieldDefinition> _getOrderedFields(List<FieldDefinition> visibleFields) {
    // Build a map for quick lookup
    final fieldMap = {for (final f in visibleFields) f.name: f};
    final orderedFields = <FieldDefinition>[];

    if (widget.form.columns != null && widget.form.columns!.isNotEmpty) {
      for (final col in widget.form.columns!) {
        for (final ref in col.fieldRefs) {
          final field = fieldMap[ref];
          if (field != null && !field.isHidden) {
            orderedFields.add(field);
          }
        }
      }
    } else {
      orderedFields.addAll(visibleFields);
    }

    // Add any explicitly-defined fields not referenced in columns at the end
    for (final f in visibleFields) {
      if (!orderedFields.contains(f)) {
        orderedFields.add(f);
      }
    }

    // Auto-generate display columns from listData keys that are not already
    // covered by the form's fields array. Moqui's auto-fields-entity directive
    // adds entity fields to listData but the fjson renderer only includes
    // explicitly-defined fields in the fields array.
    if (widget.form.listData.isNotEmpty) {
      final firstRow = widget.form.listData.first;
      final alreadyIncluded = {...visibleFields.map((f) => f.name), ...orderedFields.map((f) => f.name)};

      final autoFields = firstRow.keys
          .where((k) =>
              !k.startsWith('_') && // skip all internal/metadata keys
              !k.endsWith('_display') && // skip _display variants
              !k.endsWith('_linkText') && // skip per-row link text
              !k.contains('_param_') && // skip per-row link params
              !alreadyIncluded.contains(k) && // skip already-included fields
              k != 'aen') // skip entity name metadata
          .map((k) => FieldDefinition(
                name: k,
                title: tpl.prettifyFieldTitle(k, k),
                widgets: const [FieldWidget(widgetType: 'display')],
              ))
          .toList();

      if (autoFields.isNotEmpty) {
        // Insert auto-columns before lastUpdatedStamp (if present) so it stays last
        final lastUpdatedIdx =
            orderedFields.indexWhere((f) => f.name == 'lastUpdatedStamp');
        if (lastUpdatedIdx >= 0) {
          orderedFields.insertAll(lastUpdatedIdx, autoFields);
        } else {
          orderedFields.addAll(autoFields);
        }
      }
    }

    return orderedFields;
  }

  // _fieldNameToTitle removed — use tpl.prettifyFieldTitle() instead.

  Widget _buildFilterPanel() {
    return Card(
      margin: const EdgeInsets.all(8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.form.headerDialog)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text('Search Filters',
                    style: Theme.of(context).textTheme.titleSmall),
              ),
            Wrap(
              spacing: 16,
              runSpacing: 8,
              children: widget.form.headerFields
                  .where((f) => !f.isHidden)
                  .map((field) => SizedBox(
                        width: 200,
                        child: FieldWidgetFactory.build(
                          field: field,
                          formData: _filterData,
                          onChanged: (name, value) =>
                              setState(() => _filterData[name] = value),
                          ctx: widget.ctx,
                        ),
                      ))
                  .toList(),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => setState(() {
                    _filterData.clear();
                    _showFilters = false;
                  }),
                  child: const Text('Clear'),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () {
                    // Submit filter
                    widget.ctx.submitForm(widget.form.transition, _filterData);
                  },
                  child: const Text('Find'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── Phase 3: Saved Finds ──

  /// Load a saved find: inject its filter params and re-fetch the screen.
  void _loadSavedFind(Map<String, dynamic> find) {
    final filterParams = find['filterParams'];
    if (filterParams is Map) {
      widget.ctx.loadDynamic('', Map<String, dynamic>.from(filterParams));
    } else if (filterParams is String && filterParams.isNotEmpty) {
      // Attempt to parse a JSON string of filter params
      try {
        final parsed = Map<String, dynamic>.from(
            _jsonDecode(filterParams) as Map);
        widget.ctx.loadDynamic('', parsed);
      } catch (_) {
        // Fallback: just reload with empty params
        widget.ctx.loadDynamic('', {});
      }
    }
  }

  static dynamic _jsonDecode(String s) {
    return jsonDecode(s);
  }

  /// Show a dialog to save the current find.
  void _showSaveCurrentFindDialog(BuildContext context) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Save Current Find'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Description',
            hintText: 'Enter a name for this saved find',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final desc = controller.text.trim();
              if (desc.isEmpty) return;
              Navigator.of(ctx).pop();
              // Submit save-find request: uses formListFindId convention
              widget.ctx.submitForm(widget.form.transition, {
                'formListFindId': '',
                'description': desc,
                '_findFormList_save': 'true',
              });
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  // ── Phase 3: Select Columns ──

  /// Show a dialog with checkboxes for column visibility.
  void _showSelectColumnsDialog(BuildContext context) {
    // Work on a mutable copy
    final columnsCopy = widget.form.allColumns
        .map((c) => Map<String, dynamic>.from(c))
        .toList();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Select Columns'),
          content: SizedBox(
            width: double.maxFinite,
            child: ReorderableListView(
              shrinkWrap: true,
              onReorder: (oldIndex, newIndex) {
                setDialogState(() {
                  if (newIndex > oldIndex) newIndex--;
                  final item = columnsCopy.removeAt(oldIndex);
                  columnsCopy.insert(newIndex, item);
                });
              },
              children: [
                for (int i = 0; i < columnsCopy.length; i++)
                  CheckboxListTile(
                    key: ValueKey(columnsCopy[i]['name']?.toString() ?? '$i'),
                    value: columnsCopy[i]['visible'] == true ||
                        columnsCopy[i]['visible']?.toString() == 'true',
                    title: Text(
                      columnsCopy[i]['title']?.toString() ??
                          columnsCopy[i]['name']?.toString() ??
                          'Column $i',
                    ),
                    secondary: const Icon(Icons.drag_handle),
                    onChanged: (val) {
                      setDialogState(() {
                        columnsCopy[i]['visible'] = val ?? true;
                      });
                    },
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                _applyColumnSelection(columnsCopy);
              },
              child: const Text('Apply'),
            ),
          ],
        ),
      ),
    );
  }

  /// Apply selected column order/visibility to the server.
  void _applyColumnSelection(List<Map<String, dynamic>> columns) {
    final params = <String, dynamic>{
      '_uiType': 'formListColumnConfig',
      'formListFindId': '', // empty = default
    };
    for (int i = 0; i < columns.length; i++) {
      final col = columns[i];
      final name = col['name']?.toString() ?? '';
      params['columnOrder_$name'] = '$i';
      params['columnVisible_$name'] =
          (col['visible'] == true || col['visible']?.toString() == 'true')
              ? 'true'
              : 'false';
    }
    // Use the form transition to POST column config
    widget.ctx.submitForm(widget.form.transition, params);
  }

  // ── Phase 3: Export ──

  /// Trigger export download for CSV or XLSX.
  void _exportData(String format) {
    final baseUrl = widget.form.exportBaseUrl;
    if (baseUrl.isEmpty) return;

    final separator = baseUrl.contains('?') ? '&' : '?';
    final url = '$baseUrl${separator}renderMode=$format';

    // Use the context to launch an export download
    final launcher = widget.ctx.launchExportUrl;
    if (launcher != null) {
      launcher(url);
    } else {
      debugPrint('Export URL: $url (no launcher configured)');
    }
  }

  // ── Phase 3.6: Aggregate Footer ──

  /// Check if any visible field has aggregate flags (showTotal, showCount, etc.)
  bool _hasAggregateFooter(List<FieldDefinition> orderedFields) {
    if (widget.form.listData.isEmpty) return false;
    for (final f in orderedFields) {
      final w = f.resolveWidgets(widget.form.listData.first).firstOrNull;
      if (w == null) continue;
      if (w.boolAttr('showTotal') ||
          w.boolAttr('showCount') ||
          w.boolAttr('showMin') ||
          w.boolAttr('showMax') ||
          w.boolAttr('showAvg')) {
        return true;
      }
    }
    return false;
  }

  /// Build a styled footer row with aggregate values computed from listData.
  Widget _buildAggregateFooter(List<FieldDefinition> orderedFields) {
    final rows = widget.form.listData;
    if (rows.isEmpty) return const SizedBox.shrink();

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Container(
        color: context.moquiColors.surfaceFill,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: orderedFields.map((f) {
            final w = f.resolveWidgets(rows.first).firstOrNull;
            if (w == null) {
              return const SizedBox(width: 100);
            }

            final parts = <String>[];
            final values = rows
                .map((r) => num.tryParse(
                    (r['${f.name}_display'] ?? r[f.name])?.toString() ?? ''))
                .where((v) => v != null)
                .cast<num>()
                .toList();

            if (w.boolAttr('showTotal') && values.isNotEmpty) {
              final total = values.fold<num>(0, (a, b) => a + b);
              parts.add('Total: ${_formatNum(total)}');
            }
            if (w.boolAttr('showCount')) {
              parts.add('Count: ${values.length}');
            }
            if (w.boolAttr('showAvg') && values.isNotEmpty) {
              final avg = values.fold<num>(0, (a, b) => a + b) / values.length;
              parts.add('Avg: ${_formatNum(avg)}');
            }
            if (w.boolAttr('showMin') && values.isNotEmpty) {
              final min = values.reduce((a, b) => a < b ? a : b);
              parts.add('Min: ${_formatNum(min)}');
            }
            if (w.boolAttr('showMax') && values.isNotEmpty) {
              final max = values.reduce((a, b) => a > b ? a : b);
              parts.add('Max: ${_formatNum(max)}');
            }

            if (parts.isEmpty) return const SizedBox(width: 100);

            return SizedBox(
              width: 140,
              child: Text(
                parts.join('\n'),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: context.moquiColors.mutedText,
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  static String _formatNum(num value) {
    if (value is int || value == value.roundToDouble()) {
      return value.toInt().toString();
    }
    return value.toStringAsFixed(2);
  }

  Widget _buildSelectionActionBar() {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Row(
        children: [
          Text('${_selectedRows.length} selected',
              style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(width: 16),
          ElevatedButton(
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.check, size: 18),
                SizedBox(width: 8),
                Text('Apply to Selected'),
              ],
            ),
            onPressed: () {
              // Collect selected row IDs
              final selectedIds = _selectedRows.map((i) {
                if (i < widget.form.listData.length) {
                  final idField = widget.form.rowSelectionIdField;
                  return idField.isNotEmpty
                      ? widget.form.listData[i][idField]?.toString() ?? '$i'
                      : '$i';
                }
                return '$i';
              }).toList();
              
              widget.ctx.submitForm(widget.form.transition, {
                widget.form.rowSelectionParameter.isNotEmpty
                    ? widget.form.rowSelectionParameter
                    : 'selectedRows': selectedIds,
              });
            },
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: () => setState(() => _selectedRows.clear()),
            child: const Text('Clear Selection'),
          ),
        ],
      ),
    );
  }

  /// Map row-type string (from server `_rowType` field) to a background color.
  Color? _rowTypeColor(String rowType) {
    final mc = context.moquiColors;
    switch (rowType) {
      case 'success':
        return mc.successSurface;
      case 'warning':
        return mc.warningSurface;
      case 'danger':
        return mc.dangerSurface;
      case 'info':
        return mc.infoSurface;
      default:
        return null;
    }
  }

  Widget _buildPaginationBar() {
    final info = widget.form.paginateInfo;
    final pageIndex = (info['pageIndex'] as num?)?.toInt() ?? 0;
    final pageMaxIndex = (info['pageMaxIndex'] as num?)?.toInt() ?? 0;
    final count = (info['count'] as num?)?.toInt() ?? 0;
    final rangeLow = (info['pageRangeLow'] as num?)?.toInt() ?? 0;
    final rangeHigh = (info['pageRangeHigh'] as num?)?.toInt() ?? 0;

    return Padding(
      padding: const EdgeInsets.all(8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            icon: const Icon(Icons.first_page),
            tooltip: 'First page',
            onPressed: pageIndex > 0 ? () => _goToPage(0) : null,
          ),
          IconButton(
            icon: const Icon(Icons.chevron_left),
            tooltip: 'Previous page',
            onPressed: pageIndex > 0 ? () => _goToPage(pageIndex - 1) : null,
          ),
          Text('$rangeLow-$rangeHigh of $count'),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            tooltip: 'Next page',
            onPressed: pageIndex < pageMaxIndex ? () => _goToPage(pageIndex + 1) : null,
          ),
          IconButton(
            icon: const Icon(Icons.last_page),
            tooltip: 'Last page',
            onPressed: pageIndex < pageMaxIndex ? () => _goToPage(pageMaxIndex) : null,
          ),
        ],
      ),
    );
  }

  void _onSort(String fieldName, bool ascending) {
    setState(() {
      _sortColumn = fieldName;
      _sortAscending = ascending;
    });
    final orderBy = ascending ? fieldName : '-$fieldName';
    widget.ctx.loadDynamic('', {'orderByField': orderBy, 'pageIndex': '0'});
  }

  void _goToPage(int pageIndex) {
    // Re-fetch the screen with the new page index parameter
    widget.ctx.loadDynamic('', {'pageIndex': pageIndex.toString()});
  }
}

// ============================================================================
// Subscreens Panel Widget — Tab-based or popup navigation
// ============================================================================

class _SubscreensPanelWidget extends StatefulWidget {
  final List<Map<String, dynamic>> subscreens;
  final String type; // tab, popup, stack, wizard
  final bool noSubBanner;
  final MoquiRenderContext ctx;
  final Map<String, dynamic>? preloadedActiveSubscreen;
  final String defaultItem;

  const _SubscreensPanelWidget({
    required this.subscreens,
    required this.type,
    required this.noSubBanner,
    required this.ctx,
    this.preloadedActiveSubscreen,
    this.defaultItem = '',
  });

  @override
  State<_SubscreensPanelWidget> createState() => _SubscreensPanelWidgetState();
}

class _SubscreensPanelWidgetState extends State<_SubscreensPanelWidget>
    with TickerProviderStateMixin {
  late TabController _tabController;
  int _activeIndex = 0;
  final Map<int, ScreenNode?> _loadedScreens = {};
  final Map<int, bool> _loading = {};

  /// Phase 6.5: Track the current resolved sub-path per tab so that in-panel
  /// navigations can reload content without a full-page GoRouter push.
  final Map<int, String> _tabSubPaths = {};

  @override
  void initState() {
    super.initState();
    final menuItems = _getMenuItems();
    _tabController = TabController(length: menuItems.length, vsync: this);
    _tabController.addListener(_onTabChanged);
    // Find initially active tab
    _activeIndex = menuItems.indexWhere((s) => s['active'] == true);
    if (_activeIndex < 0) _activeIndex = 0;
    if (_activeIndex < menuItems.length) {
      _tabController.index = _activeIndex;
      // If server pre-rendered the active subscreen, use it directly
      if (widget.preloadedActiveSubscreen != null) {
        _loadedScreens[_activeIndex] =
            ScreenNode.fromJson(widget.preloadedActiveSubscreen!);
      } else {
        _loadScreen(_activeIndex);
      }
    }
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _SubscreensPanelWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // When the parent screen's effective path changes (i.e. a redirect resolved
    // and _effectiveScreenPath was updated via setState in DynamicScreenPage),
    // invalidate cached child screens so they reload with the correct base path.
    final newMenuItems = _getMenuItems();
    final pathChanged = widget.ctx.currentScreenPath != oldWidget.ctx.currentScreenPath;
    final tabCountChanged = newMenuItems.length != _tabController.length;

    if (tabCountChanged) {
      // Recreate TabController when subscreens list changes to avoid assert failure
      _tabController.removeListener(_onTabChanged);
      _tabController.dispose();
      _tabController = TabController(length: newMenuItems.length, vsync: this);
      _tabController.addListener(_onTabChanged);
      _activeIndex = _activeIndex.clamp(0, newMenuItems.isEmpty ? 0 : newMenuItems.length - 1);
      if (newMenuItems.isNotEmpty) _tabController.index = _activeIndex;
      setState(() {
        _loadedScreens.clear();
        _loading.clear();
      });
      if (newMenuItems.isNotEmpty) _loadScreen(_activeIndex);
    } else if (pathChanged) {
      setState(() {
        _loadedScreens.clear();
        _loading.clear();
      });
      _loadScreen(_activeIndex);
    }
  }

  List<Map<String, dynamic>> _getMenuItems() {
    return widget.subscreens
        .where((s) => s['menuInclude'] != false && s['disableLink'] != true)
        .toList();
  }

  void _onTabChanged() {
    if (_tabController.indexIsChanging) return;
    setState(() {
      _activeIndex = _tabController.index;
    });
    _loadScreen(_activeIndex);
  }

  Future<void> _loadScreen(int index) async {
    if (_loadedScreens.containsKey(index)) return;
    if (_loading[index] == true) return;

    final menuItems = _getMenuItems();
    if (index >= menuItems.length) return;

    final item = menuItems[index];
    final path = item['pathWithParams']?.toString() ?? item['path']?.toString();
    if (path == null || path.isEmpty) return;

    setState(() => _loading[index] = true);

    try {
      final data = await widget.ctx.loadDynamic(path, {});
      if (mounted) {
        setState(() {
          _loadedScreens[index] = ScreenNode.fromJson(data);
          _loading[index] = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading[index] = false);
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Phase 6.5: Nested subscreen panel push — navigate within a panel/tab
  // without triggering a full-page GoRouter push.
  // ---------------------------------------------------------------------------

  /// Navigate within the panel.  If [path] resolves to another tab's subscreen,
  /// switch to that tab.  If it goes deeper into the current tab, reload the
  /// tab content in-place.  Otherwise, fall back to the parent's navigate
  /// (full-page GoRouter push).
  void _navigateWithinPanel(
    int tabIndex,
    String subscreenPath,
    String path, {
    Map<String, dynamic>? params,
  }) {
    // Absolute paths or external URLs → always full-page navigation.
    if (path.startsWith('/') || path.startsWith('http')) {
      widget.ctx.navigate(path, params: params);
      return;
    }

    // Resolve the relative path (resolve '..' segments).
    final resolvedPath =
        subscreenPath.isNotEmpty ? '$subscreenPath/$path' : path;
    final segments =
        resolvedPath.split('/').where((s) => s.isNotEmpty).toList();
    final resolved = <String>[];
    for (final seg in segments) {
      if (seg == '..') {
        if (resolved.isNotEmpty) resolved.removeLast();
      } else if (seg != '.') {
        resolved.add(seg);
      }
    }
    final normalizedPath = resolved.join('/');

    // If the resolved path escapes above the panel root (too many '..' segments
    // making it empty or pointing above), delegate to parent.
    if (normalizedPath.isEmpty) {
      widget.ctx.navigate(path, params: params);
      return;
    }

    // Check if the path maps to another tab.
    final menuItems = _getMenuItems();
    for (int i = 0; i < menuItems.length; i++) {
      final tabPath = menuItems[i]['path']?.toString() ?? '';
      if (tabPath.isNotEmpty && normalizedPath == tabPath) {
        // Switch to that tab (invalidate cache so it reloads).
        setState(() {
          _activeIndex = i;
          _tabController.animateTo(i);
          _loadedScreens.remove(i);
          _tabSubPaths.remove(i);
        });
        _loadScreen(i);
        return;
      }
    }

    // Otherwise, reload the current tab's content in-place.
    _reloadTabContent(tabIndex, normalizedPath, params: params);
  }

  /// Reload the content of [tabIndex] with [path] without a full-page push.
  Future<void> _reloadTabContent(
    int tabIndex,
    String path, {
    Map<String, dynamic>? params,
  }) async {
    setState(() => _loading[tabIndex] = true);
    try {
      final data = await widget.ctx.loadDynamic(path, params ?? {});
      if (mounted) {
        setState(() {
          _loadedScreens[tabIndex] = ScreenNode.fromJson(data);
          _tabSubPaths[tabIndex] = path;
          _loading[tabIndex] = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading[tabIndex] = false);
      }
      // If in-panel load fails, fall back to full-page navigation.
      widget.ctx.navigate(path, params: params);
    }
  }

  @override
  Widget build(BuildContext context) {
    final menuItems = _getMenuItems();
    if (menuItems.isEmpty) return const SizedBox.shrink();

    // For popup type, use a different layout
    if (widget.type == 'popup') {
      return _buildPopupPanel(menuItems);
    }

    // Default: Tab layout
    // Use LayoutBuilder to handle both bounded and unbounded height contexts.
    // When inside a scrollable (unbounded height), use a fixed height for the
    // TabBarView instead of Expanded to avoid the "non-zero flex but incoming
    // height constraints are unbounded" error.
    final tabBar = widget.noSubBanner
        ? null
        : TabBar(
            controller: _tabController,
            isScrollable: menuItems.length > 4,
            tabs: menuItems.map((item) {
              final icon = item['image']?.toString() ?? '';
              final title = item['title']?.toString() ??
                  item['name']?.toString() ?? '';
              return Tab(
                icon: icon.isNotEmpty ? Icon(MoquiWidgetFactory._mapIcon(icon)) : null,
                text: title,
              );
            }).toList(),
          );

    Widget buildTabContent() {
      return TabBarView(
        controller: _tabController,
        children: List.generate(menuItems.length, (index) {
          if (_loading[index] == true) {
            return const Center(child: CircularProgressIndicator());
          }
          final screen = _loadedScreens[index];
          if (screen == null) {
            return Center(
              child: TextButton(
                onPressed: () => _loadScreen(index),
                child: const Text('Load content'),
              ),
            );
          }
          // Create child context with updated screen path for this subscreen
          final subscreenPath = _tabSubPaths[index] ??
              (menuItems[index]['path']?.toString() ?? '');
          final childScreenPath = subscreenPath.isNotEmpty 
              ? '${widget.ctx.currentScreenPath}/$subscreenPath'
              : widget.ctx.currentScreenPath;
          final childCtx = MoquiRenderContext(
            contextData: widget.ctx.contextData,
            navigate: (path, {Map<String, dynamic>? params}) {
              // Phase 6.5: In-panel navigation — reload tab content instead
              // of full-page GoRouter push for relative paths.
              _navigateWithinPanel(index, subscreenPath, path,
                  params: params);
            },
            submitForm: widget.ctx.submitForm,
            loadDynamic: (transition, params) async {
              return widget.ctx.loadDynamic(
                subscreenPath.isNotEmpty ? '$subscreenPath/$transition' : transition,
                params,
              );
            },
            postDynamic: widget.ctx.postDynamic != null
                ? (transition, params) async {
                    return widget.ctx.postDynamic!(
                      subscreenPath.isNotEmpty ? '$subscreenPath/$transition' : transition,
                      params,
                    );
                  }
                : null,
            launchExportUrl: widget.ctx.launchExportUrl,
            currentScreenPath: childScreenPath,
          );
          
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: screen.widgets
                  .map((w) => MoquiWidgetFactory.build(w, childCtx))
                  .toList(),
            ),
          );
        }),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final hasBoundedHeight = constraints.maxHeight != double.infinity;
        if (hasBoundedHeight) {
          return Column(
            children: [
              if (tabBar != null) tabBar,
              Expanded(child: buildTabContent()),
            ],
          );
        }
        // Unbounded height (inside a scrollable) — use fixed height
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (tabBar != null) tabBar,
            SizedBox(height: 500, child: buildTabContent()),
          ],
        );
      },
    );
  }

  Widget _buildPopupPanel(List<Map<String, dynamic>> menuItems) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Sidebar with popup buttons
        SizedBox(
          width: 200,
          child: Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: menuItems.asMap().entries.map((entry) {
                final index = entry.key;
                final item = entry.value;
                final isActive = index == _activeIndex;
                return ListTile(
                  leading: item['image'] != null
                      ? Icon(MoquiWidgetFactory._mapIcon(item['image'].toString()))
                      : null,
                  title: Text(
                    item['title']?.toString() ?? item['name']?.toString() ?? '',
                  ),
                  selected: isActive,
                  onTap: () {
                    setState(() => _activeIndex = index);
                    _loadScreen(index);
                  },
                );
              }).toList(),
            ),
          ),
        ),
        // Main content area
        Expanded(
          child: Card(
            margin: const EdgeInsets.only(left: 8),
            child: _loading[_activeIndex] == true
                ? const Center(child: CircularProgressIndicator())
                : _loadedScreens[_activeIndex] == null
                    ? const Center(child: Text('Select a subscreen'))
                    : Builder(builder: (context) {
                        // Create child context with updated screen path for this subscreen
                        final subscreenPath = _tabSubPaths[_activeIndex] ??
                            (menuItems[_activeIndex]['path']?.toString() ?? '');
                        final childScreenPath = subscreenPath.isNotEmpty 
                            ? '${widget.ctx.currentScreenPath}/$subscreenPath'
                            : widget.ctx.currentScreenPath;
                        final childCtx = MoquiRenderContext(
                          contextData: widget.ctx.contextData,
                          navigate: (path, {Map<String, dynamic>? params}) {
                            // Phase 6.5: In-panel navigation for popup panels.
                            _navigateWithinPanel(_activeIndex, subscreenPath,
                                path, params: params);
                          },
                          submitForm: widget.ctx.submitForm,
                          loadDynamic: (transition, params) async {
                            return widget.ctx.loadDynamic(
                              subscreenPath.isNotEmpty ? '$subscreenPath/$transition' : transition,
                              params,
                            );
                          },
                          postDynamic: widget.ctx.postDynamic != null
                              ? (transition, params) async {
                                  return widget.ctx.postDynamic!(
                                    subscreenPath.isNotEmpty ? '$subscreenPath/$transition' : transition,
                                    params,
                                  );
                                }
                              : null,
                          launchExportUrl: widget.ctx.launchExportUrl,
                          currentScreenPath: childScreenPath,
                        );
                        
                        return SingleChildScrollView(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: _loadedScreens[_activeIndex]!
                                .widgets
                                .map((w) => MoquiWidgetFactory.build(w, childCtx))
                                .toList(),
                          ),
                        );
                      }),
          ),
        ),
      ],
    );
  }
}

// =============================================================================
// Phase 5.1: CollapsiblePanel — container-panel with collapse toggle
// =============================================================================

class _CollapsiblePanel extends StatefulWidget {
  final WidgetNode node;
  final MoquiRenderContext ctx;
  final bool initiallyCollapsed;

  const _CollapsiblePanel({
    required this.node,
    required this.ctx,
    this.initiallyCollapsed = false,
  });

  @override
  State<_CollapsiblePanel> createState() => _CollapsiblePanelState();
}

class _CollapsiblePanelState extends State<_CollapsiblePanel> {
  late bool _isCollapsed;

  @override
  void initState() {
    super.initState();
    _isCollapsed = widget.initiallyCollapsed;
  }

  @override
  Widget build(BuildContext context) {
    final headerWidgets = widget.node.attributes['header'] as List?;
    final panelTitle = widget.node.attr('title');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Clickable header row with collapse indicator
        Semantics(
          button: true,
          label: '${_isCollapsed ? "Expand" : "Collapse"} ${panelTitle ?? "panel"}',
          child: InkWell(
            onTap: () => setState(() => _isCollapsed = !_isCollapsed),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                border: Border(
                  bottom: BorderSide(
                    color: Theme.of(context).dividerColor,
                  ),
                ),
              ),
              child: Row(
                children: [
                  AnimatedRotation(
                    duration: const Duration(milliseconds: 200),
                    turns: _isCollapsed ? -0.25 : 0,
                    child: const Icon(Icons.expand_more, size: 20),
                  ),
                  const SizedBox(width: 8),
                  if (panelTitle.isNotEmpty)
                    Expanded(
                      child: Text(
                        panelTitle,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                    )
                  else if (headerWidgets != null)
                    Expanded(
                      child: Wrap(
                        children: headerWidgets
                            .whereType<Map<String, dynamic>>()
                            .map((w) => MoquiWidgetFactory.build(
                                WidgetNode.fromJson(w), widget.ctx))
                            .toList(),
                      ),
                    )
                  else
                    const Expanded(child: SizedBox.shrink()),
                ],
              ),
            ),
          ),
        ),
        // Animated body
        AnimatedCrossFade(
          duration: const Duration(milliseconds: 250),
          crossFadeState: _isCollapsed
              ? CrossFadeState.showSecond
              : CrossFadeState.showFirst,
          firstChild: MoquiWidgetFactory._buildContainerPanelBody(
            widget.node,
            widget.ctx,
          ),
          secondChild: const SizedBox(width: double.infinity, height: 0),
        ),
      ],
    );
  }
}
