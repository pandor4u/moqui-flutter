import 'package:flutter/material.dart';
import '../../../domain/screen/screen_models.dart';

/// Toolbar composable with _MoquiFormList.
///
/// Contains: filter toggle, saved finds dropdown, select columns button,
/// export button group, page-size selector, "Save Changes" button, and
/// "Show all" link.
class FormListToolbar extends StatelessWidget {
  /// The owning form definition (provides metadata flags).
  final FormDefinition form;

  /// Whether filter panel is currently visible.
  final bool showFilters;

  /// Callback when user toggles filter visibility.
  final VoidCallback onToggleFilters;

  /// Number of rows currently edited (>0 shows "Save Changes" button).
  final int editedRowCount;

  /// Whether a save submission is in progress.
  final bool submittingEdits;

  /// Callback to submit edited rows.
  final VoidCallback? onSaveEdits;

  /// Current page size.
  final int pageSize;

  /// Callback when user picks a new page size.
  final ValueChanged<int> onPageSizeChanged;

  /// Callback for "Show all" (send pageNoLimit=true).
  final VoidCallback? onShowAll;

  /// Callback when CSV export is requested.
  final VoidCallback? onExportCsv;

  /// Callback when XLSX export is requested.
  final VoidCallback? onExportXlsx;

  /// Optional saved finds list from server JSON.
  final List<Map<String, dynamic>> savedFinds;

  /// Callback when user selects a saved find.
  final void Function(Map<String, dynamic>)? onLoadSavedFind;

  /// Callback when user requests saving the current find.
  final VoidCallback? onSaveCurrentFind;

  /// Callback when user requests select-columns dialog.
  final VoidCallback? onSelectColumns;

  const FormListToolbar({
    super.key,
    required this.form,
    required this.showFilters,
    required this.onToggleFilters,
    this.editedRowCount = 0,
    this.submittingEdits = false,
    this.onSaveEdits,
    this.pageSize = 20,
    required this.onPageSizeChanged,
    this.onShowAll,
    this.onExportCsv,
    this.onExportXlsx,
    this.savedFinds = const [],
    this.onLoadSavedFind,
    this.onSaveCurrentFind,
    this.onSelectColumns,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Wrap(
        spacing: 4,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          // ── Filter toggle ──
          if (form.headerFields.isNotEmpty) _buildFilterToggle(),

          // ── Saved Finds dropdown (when server provides data) ──
          if (savedFinds.isNotEmpty || onSaveCurrentFind != null)
            _buildSavedFindsDropdown(context),

          // ── Select Columns button ──
          if (onSelectColumns != null)
            IconButton(
              icon: const Icon(Icons.view_column, size: 20),
              tooltip: 'Select Columns',
              onPressed: onSelectColumns,
            ),

          // ── Export buttons ──
          if (form.showCsvButton && onExportCsv != null)
            IconButton(
              icon: const Icon(Icons.download, size: 20),
              tooltip: 'Export CSV',
              onPressed: onExportCsv,
            ),
          if (form.showXlsxButton && onExportXlsx != null)
            IconButton(
              icon: const Icon(Icons.table_chart_outlined, size: 20),
              tooltip: 'Export Excel',
              onPressed: onExportXlsx,
            ),

          // ── Save Changes button (inline-edit) ──
          if (editedRowCount > 0) _buildSaveChangesButton(),

          // Spacer — push right-aligned items
          const SizedBox(width: 0), // Wrap doesn't support Spacer

          // ── Page-size selector ──
          if (form.paginateInfo.isNotEmpty) _buildPageSizeSelector(),

          // ── "Show all" link ──
          if (form.paginate && form.paginateInfo.isNotEmpty && onShowAll != null)
            _buildShowAllLink(context),

          // Form name omitted from toolbar — label comes from the
          // surrounding screen / container-box structure instead.
        ],
      ),
    );
  }

  // ── Filter toggle button ──
  Widget _buildFilterToggle() {
    if (form.headerDialog) {
      return ElevatedButton(
        onPressed: onToggleFilters,
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search, size: 18),
            SizedBox(width: 8),
            Text('Find'),
          ],
        ),
      );
    }
    return IconButton(
      icon: Icon(showFilters ? Icons.filter_list_off : Icons.filter_list),
      tooltip: 'Toggle filters',
      onPressed: onToggleFilters,
    );
  }

  // ── Saved Finds dropdown ──
  Widget _buildSavedFindsDropdown(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Saved Finds',
      icon: const Icon(Icons.bookmark_border, size: 20),
      onSelected: (value) {
        if (value == '__save__') {
          onSaveCurrentFind?.call();
        } else {
          final find = savedFinds.firstWhere(
            (f) => f['id']?.toString() == value,
            orElse: () => <String, dynamic>{},
          );
          if (find.isNotEmpty) onLoadSavedFind?.call(find);
        }
      },
      itemBuilder: (ctx) => [
        if (onSaveCurrentFind != null)
          const PopupMenuItem(
            value: '__save__',
            child: Row(
              children: [
                Icon(Icons.save, size: 18),
                SizedBox(width: 8),
                Text('Save Current Find'),
              ],
            ),
          ),
        if (savedFinds.isNotEmpty && onSaveCurrentFind != null)
          const PopupMenuDivider(),
        ...savedFinds.map((f) => PopupMenuItem(
              value: f['id']?.toString() ?? '',
              child: Text(f['description']?.toString() ?? 'Unnamed'),
            )),
      ],
    );
  }

  // ── Save Changes button (inline edits) ──
  Widget _buildSaveChangesButton() {
    if (submittingEdits) {
      return const Padding(
        padding: EdgeInsets.only(left: 8),
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: ElevatedButton(
        onPressed: onSaveEdits,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.save, size: 18),
            const SizedBox(width: 8),
            Text('Save Changes ($editedRowCount)'),
          ],
        ),
      ),
    );
  }

  // ── Page-size selector (10, 20, 50, 100, 200) ──
  Widget _buildPageSizeSelector() {
    return DropdownButton<int>(
      value: _pageSizeOptions.contains(pageSize) ? pageSize : null,
      hint: Text('$pageSize rows'),
      underline: const SizedBox.shrink(),
      isDense: true,
      items: _pageSizeOptions.map((size) {
        return DropdownMenuItem(value: size, child: Text('$size rows'));
      }).toList(),
      onChanged: (size) {
        if (size != null) onPageSizeChanged(size);
      },
    );
  }

  static const _pageSizeOptions = [10, 20, 50, 100, 200];

  // ── "Show all" link ──
  Widget _buildShowAllLink(BuildContext context) {
    final count = (form.paginateInfo['count'] as num?)?.toInt();
    final label = count != null ? 'Show all $count' : 'Show all';
    return TextButton(
      onPressed: onShowAll,
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        minimumSize: const Size(0, 32),
      ),
      child: Text(label, style: const TextStyle(fontSize: 12)),
    );
  }
}
