import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import '../../../core/template_utils.dart' as tpl;
import '../../../core/theme.dart';
import '../../../domain/screen/screen_models.dart';
import '../moqui/widget_factory.dart';

/// Callback when a field value changes.
typedef FieldChangedCallback = void Function(String fieldName, dynamic value);

/// Factory that maps Moqui field widget type strings to Flutter form field widgets.
///
/// Each field sub-type (text-line, drop-down, date-time, etc.) from the Moqui XML
/// form schema is mapped to an appropriate Material Design form field.
class FieldWidgetFactory {
  const FieldWidgetFactory._();

  /// Build a Flutter form field from a [FieldDefinition].
  static Widget build({
    required FieldDefinition field,
    required Map<String, dynamic> formData,
    required FieldChangedCallback onChanged,
    required MoquiRenderContext ctx,
  }) {
    if (field.widgets.isEmpty) return const SizedBox.shrink();

    // Use the first (primary) widget definition
    final widget = field.widgets.first;

    switch (widget.widgetType) {
      case 'text-line':
        // If the server emitted autocomplete config (ac-transition), route to
        // the autocomplete builder instead of the plain text-line builder.
        final acConfig = widget.attributes['autocomplete'];
        if (acConfig is Map &&
            (acConfig['transition']?.toString().isNotEmpty ?? false)) {
          return _buildAutocomplete(field, widget, formData, onChanged, ctx);
        }
        return _buildTextLine(field, widget, formData, onChanged, ctx);
      case 'text-area':
        return _buildTextArea(field, widget, formData, onChanged);
      case 'text-find':
        return _buildTextFind(field, widget, formData, onChanged);
      case 'text-find-autocomplete':
        return _buildAutocomplete(field, widget, formData, onChanged, ctx);
      case 'drop-down':
        return _buildDropDown(field, widget, formData, onChanged, ctx);
      case 'date-time':
        return _buildDateTime(field, widget, formData, onChanged);
      case 'date-find':
        return _buildDateFind(field, widget, formData, onChanged);
      case 'date-period':
        return _buildDatePeriod(field, widget, formData, onChanged);
      case 'display':
        return _buildDisplay(field, widget, formData, ctx);
      case 'display-entity':
        return _buildDisplayEntity(field, widget, formData);
      case 'hidden':
        return const SizedBox.shrink();
      case 'ignored':
        return const SizedBox.shrink();
      case 'check':
        return _buildCheck(field, widget, formData, onChanged);
      case 'radio':
        return _buildRadio(field, widget, formData, onChanged);
      case 'file':
        return _buildFile(field, widget, formData, onChanged);
      case 'password':
        return _buildPassword(field, widget, formData, onChanged);
      case 'range-find':
        return _buildRangeFind(field, widget, formData, onChanged);
      case 'submit':
        return _buildSubmit(field, widget, ctx, formData, onChanged);
      case 'reset':
        return _buildReset(field, widget, ctx, formData, onChanged);
      case 'label':
        return _buildLabelField(field, widget, formData);
      case 'image':
        return _buildImageField(field, widget, formData, ctx);
      case 'editable':
        return _buildEditable(field, widget, formData, onChanged, ctx);
      case 'link':
        return MoquiWidgetFactory.build(
          WidgetNode(type: 'link', attributes: widget.attributes),
          ctx,
        );
      default:
        return _buildDefault(field, widget, formData, onChanged);
    }
  }

  // ===========================================================================
  // Text Line — Standard text input
  // ===========================================================================

  /// Build a validator function for a field based on its widget attributes.
  /// Checks: required, regex-pattern, minlength/maxlength.
  static String? Function(String?)? _buildValidator(
      FieldDefinition field, FieldWidget widget) {
    final isRequired =
        widget.boolAttr('required') || field.widgets.first == widget && widget.attr('validate') == 'required';
    final regexPattern = widget.attr('regexp');
    final minLength = int.tryParse(widget.attr('minlength'));
    final maxLength = int.tryParse(widget.attr('maxlength'));

    // Only build a validator if there are constraints
    if (!isRequired && regexPattern.isEmpty && minLength == null && maxLength == null) {
      return null;
    }

    return (String? value) {
      final v = value?.trim() ?? '';
      if (isRequired && v.isEmpty) {
        return '${field.displayTitle.isNotEmpty ? field.displayTitle : field.name} is required';
      }
      if (v.isEmpty) return null; // Skip other validations if empty and not required
      if (minLength != null && v.length < minLength) {
        return 'Minimum $minLength characters';
      }
      if (maxLength != null && v.length > maxLength) {
        return 'Maximum $maxLength characters';
      }
      if (regexPattern.isNotEmpty) {
        final re = RegExp(regexPattern);
        if (!re.hasMatch(v)) {
          return 'Invalid format';
        }
      }
      return null;
    };
  }

  static Widget _buildTextLine(
    FieldDefinition field,
    FieldWidget widget,
    Map<String, dynamic> formData,
    FieldChangedCallback onChanged,
    MoquiRenderContext ctx,
  ) {
    // Phase 4.3: If default-transition exists, use a StatefulWidget that fires on mount
    final defaultTransition = widget.attributes['defaultTransition'];
    if (defaultTransition is Map && defaultTransition['transition'] != null) {
      return _DefaultTransitionTextLine(
        field: field,
        widget: widget,
        formData: formData,
        onChanged: onChanged,
        ctx: ctx,
      );
    }

    final inputType = widget.attr('inputType', 'text');
    final maxLength = int.tryParse(widget.attr('maxlength'));
    final prefix = widget.attr('prefix');
    final mask = widget.attr('mask');
    final disabled = widget.boolAttr('disabled');

    TextInputType keyboardType;
    switch (inputType) {
      case 'number':
        keyboardType = TextInputType.number;
        break;
      case 'email':
        keyboardType = TextInputType.emailAddress;
        break;
      case 'tel':
        keyboardType = TextInputType.phone;
        break;
      case 'url':
        keyboardType = TextInputType.url;
        break;
      default:
        keyboardType = TextInputType.text;
    }

    return TextFormField(
      initialValue: formData[field.name]?.toString() ?? field.currentValue ?? '',
      decoration: InputDecoration(
        labelText: field.displayTitle,
        hintText: field.tooltip.isNotEmpty ? field.tooltip : null,
        prefixText: prefix.isNotEmpty ? prefix : null,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
      keyboardType: keyboardType,
      maxLength: maxLength,
      enabled: !disabled,
      validator: _buildValidator(field, widget),
      inputFormatters: [
        if (mask.isNotEmpty) FilteringTextInputFormatter.allow(RegExp(mask)),
      ],
      onChanged: (value) => onChanged(field.name, value),
    );
  }

  // ===========================================================================
  // Text Area — Multi-line text input
  // ===========================================================================

  static Widget _buildTextArea(
    FieldDefinition field,
    FieldWidget widget,
    Map<String, dynamic> formData,
    FieldChangedCallback onChanged,
  ) {
    final rows = int.tryParse(widget.attr('rows', '3')) ?? 3;
    final maxLength = int.tryParse(widget.attr('maxlength'));
    final readOnly = widget.boolAttr('readOnly');

    return TextFormField(
      initialValue: formData[field.name]?.toString() ?? field.currentValue ?? '',
      decoration: InputDecoration(
        labelText: field.displayTitle,
        hintText: field.tooltip.isNotEmpty ? field.tooltip : null,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
      maxLines: rows,
      maxLength: maxLength,
      readOnly: readOnly,
      validator: _buildValidator(field, widget),
      onChanged: (value) => onChanged(field.name, value),
    );
  }

  // ===========================================================================
  // Text Find — Search input with operator options
  // ===========================================================================

  static Widget _buildTextFind(
    FieldDefinition field,
    FieldWidget widget,
    Map<String, dynamic> formData,
    FieldChangedCallback onChanged,
  ) {
    final defaultOp = widget.attr('defaultOperator', 'contains');
    final hideOptions = widget.boolAttr('hideOptions');

    return _TextFindField(
      field: field,
      defaultOp: defaultOp,
      hideOptions: hideOptions,
      formData: formData,
      onChanged: onChanged,
    );
  }

  // ===========================================================================
  // Text Find Autocomplete — Search input with server-side suggestions
  // ===========================================================================

  static Widget _buildAutocomplete(
    FieldDefinition field,
    FieldWidget widget,
    Map<String, dynamic> formData,
    FieldChangedCallback onChanged,
    MoquiRenderContext ctx,
  ) {
    return _AutocompleteField(
      field: field,
      widget: widget,
      formData: formData,
      onChanged: onChanged,
      ctx: ctx,
    );
  }

  // ===========================================================================
  // Drop Down — Select or multi-select, with dynamic options & depends-on
  // ===========================================================================

  static Widget _buildDropDown(
    FieldDefinition field,
    FieldWidget widget,
    Map<String, dynamic> formData,
    FieldChangedCallback onChanged,
    MoquiRenderContext ctx,
  ) {
    // Delegate to StatefulWidget when dynamic options or depends-on is configured
    final hasDynamicOptions = widget.dynamicOptions != null &&
        widget.dynamicOptions!.transition.isNotEmpty;
    final hasDependsOn = widget.dependsOn.isNotEmpty;

    if (hasDynamicOptions || hasDependsOn) {
      return _DynamicDropDown(
        field: field,
        widget: widget,
        formData: formData,
        onChanged: onChanged,
        ctx: ctx,
      );
    }

    return _buildStaticDropDown(field, widget, formData, onChanged);
  }

  /// Static drop-down with pre-loaded options (no server interaction).
  static Widget _buildStaticDropDown(
    FieldDefinition field,
    FieldWidget widget,
    Map<String, dynamic> formData,
    FieldChangedCallback onChanged,
  ) {
    final allowEmpty = widget.boolAttr('allowEmpty', true);
    final allowMultiple = widget.boolAttr('allowMultiple');
    final options = widget.options;

    if (allowMultiple) {
      // Multi-select as filter chips
      final selectedValues = formData[field.name] is List
          ? formData[field.name] as List
          : (formData[field.name]?.toString().isNotEmpty == true
              ? [formData[field.name].toString()]
              : []);

      return InputDecorator(
        decoration: InputDecoration(
          labelText: field.displayTitle,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
        child: Wrap(
          spacing: 8,
          children: options.map((opt) {
            final isSelected = selectedValues.contains(opt.key);
            return FilterChip(
              label: Text(opt.text.isEmpty ? opt.key : opt.text),
              selected: isSelected,
              onSelected: (selected) {
                final newValues = List<String>.from(selectedValues);
                if (selected) {
                  newValues.add(opt.key);
                } else {
                  newValues.remove(opt.key);
                }
                onChanged(field.name, newValues);
              },
            );
          }).toList(),
        ),
      );
    }

    // Single select dropdown
    final items = <DropdownMenuItem<String>>[];
    if (allowEmpty) {
      items.add(const DropdownMenuItem(value: '', child: Text('')));
    }
    for (final opt in options) {
      items.add(DropdownMenuItem(
        value: opt.key,
        child: Text(opt.text.isEmpty ? opt.key : opt.text),
      ));
    }

    // Ensure initialValue is valid — must match an item value,
    // otherwise DropdownButtonFormField throws an assertion error.
    final rawValue =
        formData[field.name]?.toString() ?? field.currentValue ?? '';
    final validValues = items.map((i) => i.value).toSet();
    final initialValue = validValues.contains(rawValue)
        ? rawValue
        : (allowEmpty ? '' : null);

    return DropdownButtonFormField<String>(
      initialValue: initialValue,
      decoration: InputDecoration(
        labelText: field.displayTitle,
        hintText: field.tooltip.isNotEmpty ? field.tooltip : null,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
      items: items,
      onChanged: (value) => onChanged(field.name, value),
      validator: widget.boolAttr('required')
          ? (value) => (value == null || value.isEmpty)
              ? '${field.displayTitle.isNotEmpty ? field.displayTitle : field.name} is required'
              : null
          : null,
      isExpanded: true,
    );
  }

  // ===========================================================================
  // Date Time — Date and/or time picker (Phase 4.6: proper controller lifecycle)
  // ===========================================================================

  static Widget _buildDateTime(
    FieldDefinition field,
    FieldWidget widget,
    Map<String, dynamic> formData,
    FieldChangedCallback onChanged,
  ) {
    final dateType = widget.attr('dateType', 'timestamp');
    return _DateTimeField(
      field: field,
      dateType: dateType,
      formData: formData,
      onChanged: onChanged,
    );
  }

  static Future<void> _pickDateTime(
    BuildContext context,
    FieldDefinition field,
    String dateType,
    Map<String, dynamic> formData,
    FieldChangedCallback onChanged,
  ) async {
    DateTime? date;
    TimeOfDay? time;

    if (dateType != 'time') {
      date = await showDatePicker(
        context: context,
        initialDate: DateTime.now(),
        firstDate: DateTime(1900),
        lastDate: DateTime(2100),
      );
      if (date == null) return;
    }

    if (dateType != 'date') {
      time = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.now(),
      );
    }

    String formatted;
    if (dateType == 'date') {
      formatted = DateFormat('yyyy-MM-dd').format(date!);
    } else if (dateType == 'time') {
      formatted = time != null
          ? '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}'
          : '';
    } else {
      // timestamp
      final dt = DateTime(
        date!.year,
        date.month,
        date.day,
        time?.hour ?? 0,
        time?.minute ?? 0,
      );
      formatted = DateFormat('yyyy-MM-dd HH:mm').format(dt);
    }

    onChanged(field.name, formatted);
  }

  // ===========================================================================
  // Date Find — From/thru date range (Phase 4.4 + 4.6: dateType + controller lifecycle)
  // ===========================================================================

  static Widget _buildDateFind(
    FieldDefinition field,
    FieldWidget widget,
    Map<String, dynamic> formData,
    FieldChangedCallback onChanged,
  ) {
    final dateType = widget.attr('dateType', 'timestamp');
    return _DateFindField(
      field: field,
      dateType: dateType,
      formData: formData,
      onChanged: onChanged,
    );
  }

  // ===========================================================================
  // Date Period — Period selector
  // ===========================================================================

  static Widget _buildDatePeriod(
    FieldDefinition field,
    FieldWidget widget,
    Map<String, dynamic> formData,
    FieldChangedCallback onChanged,
  ) {
    return Row(
      children: [
        Expanded(
          child: DropdownButtonFormField<String>(
            initialValue: formData['${field.name}_period']?.toString() ?? '',
            decoration: InputDecoration(
              labelText: field.displayTitle,
              border: const OutlineInputBorder(),
              isDense: true,
            ),
            items: const [
              DropdownMenuItem(value: '', child: Text('Any')),
              DropdownMenuItem(value: 'day', child: Text('Day')),
              DropdownMenuItem(value: 'week', child: Text('Week')),
              DropdownMenuItem(value: 'month', child: Text('Month')),
              DropdownMenuItem(value: 'quarter', child: Text('Quarter')),
              DropdownMenuItem(value: 'year', child: Text('Year')),
            ],
            onChanged: (value) => onChanged('${field.name}_period', value),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: TextFormField(
            initialValue: formData['${field.name}_poffset']?.toString() ?? '0',
            decoration: const InputDecoration(
              labelText: 'Offset',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            keyboardType: TextInputType.number,
            onChanged: (value) => onChanged('${field.name}_poffset', value),
          ),
        ),
      ],
    );
  }

  // ===========================================================================
  // Display — Read-only text (Phase 4.2: dynamic-transition support)
  // ===========================================================================

  static Widget _buildDisplay(
    FieldDefinition field,
    FieldWidget widget,
    Map<String, dynamic> formData,
    MoquiRenderContext ctx,
  ) {
    // Phase 4.2: If dynamic-transition is present, use a StatefulWidget
    final dynamicUrl = widget.attr('dynamic-url');
    if (dynamicUrl.isNotEmpty) {
      return _DynamicDisplay(
        field: field,
        widget: widget,
        formData: formData,
        ctx: ctx,
      );
    }

    final text = tpl.cleanDisplayText(widget.attr('resolvedText',
        formData[field.name]?.toString() ?? field.currentValue ?? ''));

    final textChild = _looksLikeHtml(text)
        ? HtmlWidget(text, textStyle: const TextStyle(fontSize: 14))
        : Text(text, style: const TextStyle(fontSize: 14));

    return Builder(builder: (context) {
    return InputDecorator(
      decoration: InputDecoration(
        labelText: field.displayTitle,
        border: const OutlineInputBorder(),
        isDense: true,
        filled: true,
        fillColor: context.moquiColors.surfaceFill,
      ),
      child: textChild,
    );
    });
  }

  /// Returns `true` when [text] appears to contain HTML markup or entities.
  static bool _looksLikeHtml(String text) => tpl.looksLikeHtml(text);

  // ===========================================================================
  // Display Entity — Read-only text resolved from entity
  // ===========================================================================

  static Widget _buildDisplayEntity(
    FieldDefinition field,
    FieldWidget widget,
    Map<String, dynamic> formData,
  ) {
    // Values resolved server-side in JSON
    final text = tpl.cleanDisplayText(widget.attr('resolvedText',
        formData[field.name]?.toString() ?? field.currentValue ?? ''));

    final textChild = _looksLikeHtml(text)
        ? HtmlWidget(text, textStyle: const TextStyle(fontSize: 14))
        : Text(text, style: const TextStyle(fontSize: 14));

    return Builder(builder: (context) {
    return InputDecorator(
      decoration: InputDecoration(
        labelText: field.displayTitle,
        border: const OutlineInputBorder(),
        isDense: true,
        filled: true,
        fillColor: context.moquiColors.surfaceFill,
      ),
      child: textChild,
    );
    });
  }

  // ===========================================================================
  // Check — Checkbox group
  // ===========================================================================

  static Widget _buildCheck(
    FieldDefinition field,
    FieldWidget widget,
    Map<String, dynamic> formData,
    FieldChangedCallback onChanged,
  ) {
    final options = widget.options;
    final allChecked = widget.boolAttr('allChecked');
    final currentValues = formData[field.name] is List
        ? (formData[field.name] as List).map((e) => e.toString()).toSet()
        : (field.currentValue != null
            ? {field.currentValue!}
            : (allChecked
                ? options.map((o) => o.key).toSet()
                : <String>{}));

    return InputDecorator(
      decoration: InputDecoration(
        labelText: field.displayTitle,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
      child: Column(
        children: options.map((opt) {
          return CheckboxListTile(
            title: Text(opt.text.isEmpty ? opt.key : opt.text),
            value: currentValues.contains(opt.key),
            dense: true,
            contentPadding: EdgeInsets.zero,
            onChanged: (checked) {
              final newValues = Set<String>.from(currentValues);
              if (checked == true) {
                newValues.add(opt.key);
              } else {
                newValues.remove(opt.key);
              }
              onChanged(field.name, newValues.toList());
            },
          );
        }).toList(),
      ),
    );
  }

  // ===========================================================================
  // Radio — Radio button group
  // ===========================================================================

  static Widget _buildRadio(
    FieldDefinition field,
    FieldWidget widget,
    Map<String, dynamic> formData,
    FieldChangedCallback onChanged,
  ) {
    final options = widget.options;
    final currentValue =
        formData[field.name]?.toString() ?? field.currentValue ?? '';

    return InputDecorator(
      decoration: InputDecoration(
        labelText: field.displayTitle,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
      child: Column(
        children: options.map((opt) {
          return RadioListTile<String>(
            title: Text(opt.text.isEmpty ? opt.key : opt.text),
            value: opt.key,
            groupValue: currentValue,
            dense: true,
            contentPadding: EdgeInsets.zero,
            onChanged: (value) => onChanged(field.name, value),
          );
        }).toList(),
      ),
    );
  }

  // ===========================================================================
  // File — File picker
  // ===========================================================================

  static Widget _buildFile(
    FieldDefinition field,
    FieldWidget widget,
    Map<String, dynamic> formData,
    FieldChangedCallback onChanged,
  ) {
    final multiple = widget.boolAttr('multiple');
    final accept = widget.attr('accept');
    final maxSize = int.tryParse(widget.attr('maxSize', '0')) ?? 0;

    return _FilePickerField(
      field: field,
      multiple: multiple,
      accept: accept,
      maxSize: maxSize,
      formData: formData,
      onChanged: onChanged,
    );
  }

  // ===========================================================================
  // Password — Obscured text input
  // ===========================================================================

  static Widget _buildPassword(
    FieldDefinition field,
    FieldWidget widget,
    Map<String, dynamic> formData,
    FieldChangedCallback onChanged,
  ) {
    return _PasswordField(
      field: field,
      widget: widget,
      formData: formData,
      onChanged: onChanged,
    );
  }

  // ===========================================================================
  // Range Find — From/thru numeric range
  // ===========================================================================

  static Widget _buildRangeFind(
    FieldDefinition field,
    FieldWidget widget,
    Map<String, dynamic> formData,
    FieldChangedCallback onChanged,
  ) {
    return Row(
      children: [
        Expanded(
          child: TextFormField(
            initialValue: formData['${field.name}_from']?.toString() ?? '',
            decoration: InputDecoration(
              labelText: '${field.displayTitle} From',
              border: const OutlineInputBorder(),
              isDense: true,
            ),
            keyboardType: TextInputType.number,
            onChanged: (value) => onChanged('${field.name}_from', value),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: TextFormField(
            initialValue: formData['${field.name}_thru']?.toString() ?? '',
            decoration: InputDecoration(
              labelText: '${field.displayTitle} Thru',
              border: const OutlineInputBorder(),
              isDense: true,
            ),
            keyboardType: TextInputType.number,
            onChanged: (value) => onChanged('${field.name}_thru', value),
          ),
        ),
      ],
    );
  }

  // ===========================================================================
  // Submit — Form submit button
  // ===========================================================================

  static Widget _buildSubmit(
    FieldDefinition field,
    FieldWidget widget,
    MoquiRenderContext ctx,
    Map<String, dynamic> formData,
    FieldChangedCallback onChanged,
  ) {
    final rawText = widget.attr('text');
    final text = rawText.isNotEmpty
        ? rawText
        : (field.title.isNotEmpty ? field.title : 'Submit');
    final icon = widget.attr('icon');
    final confirmation = widget.attr('confirmation');
    final btnType = widget.attr('btnType');

    Color? buttonColor;
    if (btnType.contains('danger')) {
      buttonColor = Colors.red;
    } else if (btnType.contains('success')) {
      buttonColor = Colors.green;
    } else if (btnType.contains('warning')) {
      buttonColor = Colors.orange;
    }

    return Builder(builder: (context) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: ElevatedButton(
          style: buttonColor != null
              ? ElevatedButton.styleFrom(backgroundColor: buttonColor)
              : null,
          onPressed: () async {
            if (confirmation.isNotEmpty) {
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (_) => AlertDialog(
                  content: Text(confirmation),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Cancel')),
                    ElevatedButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('Confirm')),
                  ],
                ),
              );
              if (confirmed != true) return;
            }

            // Find the parent form's submit callback from context
            // Walk up the widget tree to find the form and call submit
            final formState = Form.maybeOf(context);
            if (formState?.validate() ?? true) {
              // Trigger form submission via the onChanged mechanism
              final transition = widget.attr('transition', '');
              onChanged('__submit__', transition);
            }
          },
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Icon(_mapFieldIcon(icon), size: 18),
                ),
              Text(text),
            ],
          ),
        ),
      );
    });
  }

  // ===========================================================================
  // Reset — Form reset button
  // ===========================================================================

  static Widget _buildReset(
    FieldDefinition field,
    FieldWidget widget,
    MoquiRenderContext ctx,
    Map<String, dynamic> formData,
    FieldChangedCallback onChanged,
  ) {
    final text = widget.attr('text', 'Reset');
    final icon = widget.attr('icon');

    return Builder(builder: (context) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: OutlinedButton.icon(
          icon: icon.isNotEmpty
              ? Icon(_mapFieldIcon(icon), size: 18)
              : const SizedBox.shrink(),
          label: Text(text),
          onPressed: () {
            // Reset all form fields
            final formState = Form.maybeOf(context);
            formState?.reset();
            // Also trigger callback to clear form data
            onChanged('__reset__', true);
          },
        ),
      );
    });
  }

  // ===========================================================================
  // Label — Static text within a form field
  // ===========================================================================

  static Widget _buildLabelField(
    FieldDefinition field,
    FieldWidget widget,
    Map<String, dynamic> formData,
  ) {
    final text = tpl.cleanDisplayText(widget.attr('resolvedText', widget.attr('text', '')));
    final labelType = widget.attr('labelType', 'span');
    final style = tpl.cleanStyleAttr(widget.attr('style'));

    if (text.isEmpty) return const SizedBox.shrink();

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
        case 'strong':
        case 'b':
          textStyle = Theme.of(context)
              .textTheme
              .bodyMedium!
              .copyWith(fontWeight: FontWeight.bold);
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

      final child = _looksLikeHtml(text)
          ? HtmlWidget(text, textStyle: textStyle)
          : Text(text, style: textStyle);

      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: child,
      );
    });
  }

  // ===========================================================================
  // Image — Image display within a form field
  // ===========================================================================

  static Widget _buildImageField(
    FieldDefinition field,
    FieldWidget widget,
    Map<String, dynamic> formData,
    MoquiRenderContext ctx,
  ) {
    final url = widget.attr('url', formData[field.name]?.toString() ?? '');
    final alt = widget.attr('alt', field.displayTitle);
    final width = double.tryParse(widget.attr('width'));
    final height = double.tryParse(widget.attr('height'));

    if (url.isEmpty) return const SizedBox.shrink();

    final baseUrl = ctx.contextData['baseUrl']?.toString() ?? '';
    final fullUrl = url.startsWith('http') ? url : '$baseUrl$url';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (field.displayTitle.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Builder(builder: (ctx) => Text(
              field.displayTitle,
              style: TextStyle(fontSize: 12, color: ctx.moquiColors.mutedText),
            )),
          ),
        Builder(builder: (context) => Image.network(
          fullUrl,
          width: width ?? 200,
          height: height,
          fit: BoxFit.contain,
          semanticLabel: alt.isNotEmpty ? alt : field.displayTitle,
          errorBuilder: (_, __, ___) => Tooltip(
            message: alt,
            child: Container(
              width: width ?? 200,
              height: height ?? 100,
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: const Icon(Icons.broken_image, size: 40),
            ),
          ),
        )),
      ],
    );
  }

  // ===========================================================================
  // Editable — Inline editable cell (for form-list)
  // ===========================================================================

  static Widget _buildEditable(
    FieldDefinition field,
    FieldWidget widget,
    Map<String, dynamic> formData,
    FieldChangedCallback onChanged,
    MoquiRenderContext ctx,
  ) {
    return _EditableField(
      field: field,
      widget: widget,
      formData: formData,
      onChanged: onChanged,
      ctx: ctx,
    );
  }

  // ===========================================================================
  // Default fallback
  // ===========================================================================

  static Widget _buildDefault(
    FieldDefinition field,
    FieldWidget widget,
    Map<String, dynamic> formData,
    FieldChangedCallback onChanged,
  ) {
    return TextFormField(
      initialValue: formData[field.name]?.toString() ?? field.currentValue ?? '',
      decoration: InputDecoration(
        labelText: field.displayTitle,
        hintText: '${widget.widgetType} field',
        border: const OutlineInputBorder(),
        isDense: true,
      ),
      onChanged: (value) => onChanged(field.name, value),
    );
  }

  static IconData _mapFieldIcon(String icon) {
    const map = {
      'fa-save': Icons.save,
      'fa-check': Icons.check,
      'fa-plus': Icons.add,
      'fa-edit': Icons.edit,
      'fa-trash': Icons.delete,
      'fa-times': Icons.close,
      'fa-search': Icons.search,
    };
    return map[icon] ?? Icons.circle;
  }
}

// ===========================================================================
// Password field with toggle visibility (StatefulWidget)
// ===========================================================================

class _PasswordField extends StatefulWidget {
  final FieldDefinition field;
  final FieldWidget widget;
  final Map<String, dynamic> formData;
  final FieldChangedCallback onChanged;

  const _PasswordField({
    required this.field,
    required this.widget,
    required this.formData,
    required this.onChanged,
  });

  @override
  State<_PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<_PasswordField> {
  bool _obscure = true;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      initialValue: widget.formData[widget.field.name]?.toString()
          ?? widget.field.currentValue
          ?? '',
      decoration: InputDecoration(
        labelText: widget.field.displayTitle,
        border: const OutlineInputBorder(),
        isDense: true,
        suffixIcon: IconButton(
          icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility),
          tooltip: _obscure ? 'Show password' : 'Hide password',
          onPressed: () => setState(() => _obscure = !_obscure),
        ),
      ),
      obscureText: _obscure,
      validator: FieldWidgetFactory._buildValidator(widget.field, widget.widget),
      onChanged: (value) => widget.onChanged(widget.field.name, value),
    );
  }
}

// ===========================================================================
// File picker field with progress tracking (StatefulWidget)
// ===========================================================================

class _FilePickerField extends StatefulWidget {
  final FieldDefinition field;
  final bool multiple;
  final String accept;
  final int maxSize;
  final Map<String, dynamic> formData;
  final FieldChangedCallback onChanged;

  const _FilePickerField({
    required this.field,
    required this.multiple,
    required this.accept,
    required this.maxSize,
    required this.formData,
    required this.onChanged,
  });

  @override
  State<_FilePickerField> createState() => _FilePickerFieldState();
}

class _FilePickerFieldState extends State<_FilePickerField> {
  List<PlatformFile> _selectedFiles = [];
  bool _isLoading = false;
  String? _error;

  /// Upload progress (0.0 to 1.0), null when not uploading.
  double? _uploadProgress;

  /// Threshold above which web uses readStream instead of withData.
  static const int _streamThreshold = 5 * 1024 * 1024; // 5 MB

  @override
  void initState() {
    super.initState();
    // Restore previously selected files if stored
    final existing = widget.formData[widget.field.name];
    if (existing is List<PlatformFile>) {
      _selectedFiles = existing;
    }
  }

  Future<void> _pickFiles() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // Determine file type and extensions from accept attribute
      FileType fileType = FileType.any;
      List<String>? allowedExtensions;

      if (widget.accept.isNotEmpty) {
        final acceptLower = widget.accept.toLowerCase();
        if (acceptLower.contains('image')) {
          fileType = FileType.image;
        } else if (acceptLower.contains('video')) {
          fileType = FileType.video;
        } else if (acceptLower.contains('audio')) {
          fileType = FileType.audio;
        } else {
          // Custom extensions like .xml,.json,.csv
          fileType = FileType.custom;
          allowedExtensions = widget.accept
              .split(',')
              .map((e) => e.trim().replaceAll('.', ''))
              .where((e) => e.isNotEmpty)
              .toList();
          if (allowedExtensions.isEmpty) {
            fileType = FileType.any;
            allowedExtensions = null;
          }
        }
      }

      final result = await FilePicker.platform.pickFiles(
        allowMultiple: widget.multiple,
        type: fileType,
        allowedExtensions: allowedExtensions,
        withData: !kIsWeb, // Eager bytes on mobile only
        withReadStream: kIsWeb, // Stream on web — avoids OOM for large files
      );

      if (result != null && result.files.isNotEmpty) {
        // Validate file size if maxSize is set
        if (widget.maxSize > 0) {
          for (final file in result.files) {
            if (file.size > widget.maxSize) {
              setState(() {
                _error = '${file.name} exceeds max size (${_formatBytes(widget.maxSize)})';
              });
              return;
            }
          }
        }

        setState(() {
          if (widget.multiple) {
            _selectedFiles = [..._selectedFiles, ...result.files];
          } else {
            _selectedFiles = result.files;
          }
        });

        // Store files in form data for submission
        widget.onChanged(
          widget.field.name,
          widget.multiple ? _selectedFiles : _selectedFiles.first,
        );
      }
    } catch (e) {
      setState(() {
        _error = 'Error picking file: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _removeFile(int index) {
    setState(() {
      _selectedFiles.removeAt(index);
    });
    widget.onChanged(
      widget.field.name,
      _selectedFiles.isEmpty
          ? null
          : (widget.multiple ? _selectedFiles : _selectedFiles.first),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: InputDecoration(
        labelText: widget.field.displayTitle,
        border: const OutlineInputBorder(),
        isDense: true,
        errorText: _error,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              ElevatedButton.icon(
                icon: _isLoading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.attach_file, size: 18),
                label: Text(widget.multiple ? 'Choose Files' : 'Choose File'),
                onPressed: _isLoading ? null : _pickFiles,
              ),
              if (_selectedFiles.isNotEmpty) ...[
                const SizedBox(width: 8),
                Text(
                  '${_selectedFiles.length} file${_selectedFiles.length > 1 ? 's' : ''} selected',
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ],
            ],
          ),
          if (_selectedFiles.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: _selectedFiles.asMap().entries.map((entry) {
                final index = entry.key;
                final file = entry.value;
                return Chip(
                  label: Text(
                    '${file.name} (${_formatBytes(file.size)})',
                    style: const TextStyle(fontSize: 12),
                  ),
                  onDeleted: () => _removeFile(index),
                  deleteIcon: const Icon(Icons.close, size: 16),
                );
              }).toList(),
            ),
          ],
          // Upload progress bar
          if (_uploadProgress != null) ...[
            const SizedBox(height: 8),
            LinearProgressIndicator(value: _uploadProgress),
            const SizedBox(height: 4),
            Text(
              '${(_uploadProgress! * 100).toStringAsFixed(0)}% uploaded',
              style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }
}

// ===========================================================================
// Dynamic Drop-Down — Fetches options from server, supports depends-on
// cascading and server-search (typeahead within dropdown).
// ===========================================================================

class _DynamicDropDown extends StatefulWidget {
  final FieldDefinition field;
  final FieldWidget widget;
  final Map<String, dynamic> formData;
  final FieldChangedCallback onChanged;
  final MoquiRenderContext ctx;

  const _DynamicDropDown({
    required this.field,
    required this.widget,
    required this.formData,
    required this.onChanged,
    required this.ctx,
  });

  @override
  State<_DynamicDropDown> createState() => _DynamicDropDownState();
}

class _DynamicDropDownState extends State<_DynamicDropDown> {
  List<FieldOption> _dynamicOptions = [];
  bool _isLoading = false;
  bool _hasLoadedOnce = false;
  Map<String, dynamic> _lastParentValues = {};
  String _searchTerm = '';

  // Debounce for server search
  DateTime? _lastSearch;
  static const _searchDebounceMs = 300;

  @override
  void initState() {
    super.initState();
    // Start with static options as fallback
    _dynamicOptions = List.of(widget.widget.options);
    _lastParentValues = _captureParentValues();
    _fetchOptions();
  }

  @override
  void didUpdateWidget(covariant _DynamicDropDown oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Check if any depends-on parent field value has changed
    final currentParentValues = _captureParentValues();
    if (_parentValuesChanged(currentParentValues)) {
      _lastParentValues = currentParentValues;
      // Reset the current value when parent changes
      widget.onChanged(widget.field.name, null);
      _fetchOptions();
    }
  }

  /// Capture current values of all depends-on parent fields.
  Map<String, dynamic> _captureParentValues() {
    final values = <String, dynamic>{};
    // Check depends-on from the field widget itself
    for (final dep in widget.widget.dependsOn) {
      values[dep.field] = widget.formData[dep.field];
    }
    // Check depends-on from dynamicOptions config
    final dynOpts = widget.widget.dynamicOptions;
    if (dynOpts != null) {
      for (final dep in dynOpts.dependsOn) {
        values[dep.field] = widget.formData[dep.field];
      }
    }
    return values;
  }

  bool _parentValuesChanged(Map<String, dynamic> current) {
    if (current.length != _lastParentValues.length) return true;
    for (final entry in current.entries) {
      if (_lastParentValues[entry.key]?.toString() != entry.value?.toString()) {
        return true;
      }
    }
    return false;
  }

  Future<void> _fetchOptions({String? searchTerm}) async {
    final dynOpts = widget.widget.dynamicOptions;
    if (dynOpts == null || dynOpts.transition.isEmpty) {
      // No dynamic options configured — use depends-on with loadDynamic
      if (widget.widget.dependsOn.isNotEmpty) {
        await _fetchDependsOnOptions();
      }
      return;
    }

    setState(() => _isLoading = true);
    try {
      final params = <String, dynamic>{};
      // Add depends-on parent field values as parameters
      for (final dep in widget.widget.dependsOn) {
        final paramName = dep.parameter.isNotEmpty ? dep.parameter : dep.field;
        final value = widget.formData[dep.field];
        if (value != null) params[paramName] = value.toString();
      }
      for (final dep in dynOpts.dependsOn) {
        final paramName = dep.parameter.isNotEmpty ? dep.parameter : dep.field;
        final value = widget.formData[dep.field];
        if (value != null) params[paramName] = value.toString();
      }
      // Add search term for server-search mode
      if (searchTerm != null && searchTerm.isNotEmpty) {
        params['term'] = searchTerm;
      }

      // Use POST for dynamic option fetches — Moqui rejects GET with URL params
      // on non-read-only transitions for security reasons.
      final poster = widget.ctx.postDynamic;
      final result = poster != null
          ? await poster(dynOpts.transition, params)
          : await widget.ctx.loadDynamic(dynOpts.transition, params);

      // Parse options from result
      final List<dynamic> rawOptions;
      if (result['options'] is List) {
        rawOptions = result['options'] as List;
      } else if (result['data'] is List) {
        rawOptions = result['data'] as List;
      } else {
        rawOptions = [];
      }

      if (mounted) {
        setState(() {
          _dynamicOptions = rawOptions.whereType<Map<String, dynamic>>().map((opt) {
            return FieldOption(
              key: opt['key']?.toString() ?? opt['value']?.toString() ?? '',
              text: opt['text']?.toString() ?? opt['label']?.toString() ?? '',
            );
          }).toList();
          _isLoading = false;
          _hasLoadedOnce = true;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _hasLoadedOnce = true;
        });
      }
    }
  }

  Future<void> _fetchDependsOnOptions() async {
    // When there's no dynamic transition URL, avoid re-fetching the entire
    // screen JSON.  Instead, filter from the pre-loaded static options based
    // on the parent field value.
    final dynOpts = widget.widget.dynamicOptions;
    if (dynOpts == null || dynOpts.transition.isEmpty) {
      // No server endpoint — just filter static options locally if possible
      final parentValues = _captureParentValues();
      final hasNonNullParent = parentValues.values.any(
        (v) => v != null && v.toString().isNotEmpty,
      );
      if (!hasNonNullParent) {
        // Parent cleared — restore all static options
        setState(() {
          _dynamicOptions = List.of(widget.widget.options);
          _hasLoadedOnce = true;
        });
        return;
      }
      // No transition configured — use loadDynamic as a fallback with
      // the depends-on parent values so the server can resolve options.
      setState(() => _isLoading = true);
      try {
        final params = <String, dynamic>{};
        for (final dep in widget.widget.dependsOn) {
          final paramName = dep.parameter.isNotEmpty ? dep.parameter : dep.field;
          final value = widget.formData[dep.field];
          if (value != null) params[paramName] = value.toString();
        }
        final result = await widget.ctx.loadDynamic('', params);
        final List<dynamic> rawOptions;
        if (result['options'] is List) {
          rawOptions = result['options'] as List;
        } else if (result['data'] is List) {
          rawOptions = result['data'] as List;
        } else {
          rawOptions = [];
        }
        if (mounted) {
          setState(() {
            _dynamicOptions = rawOptions.whereType<Map<String, dynamic>>().map((opt) {
              return FieldOption(
                key: opt['key']?.toString() ?? opt['value']?.toString() ?? '',
                text: opt['text']?.toString() ?? opt['label']?.toString() ?? '',
              );
            }).toList();
            _isLoading = false;
            _hasLoadedOnce = true;
          });
        }
      } catch (_) {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _hasLoadedOnce = true;
          });
        }
      }
      return;
    }

    // Has a transition URL — use it to fetch filtered options
    setState(() => _isLoading = true);
    try {
      final params = <String, dynamic>{};
      for (final dep in widget.widget.dependsOn) {
        final paramName = dep.parameter.isNotEmpty ? dep.parameter : dep.field;
        final value = widget.formData[dep.field];
        if (value != null) params[paramName] = value.toString();
      }
      params['_fieldName'] = widget.field.name;

      final result = await widget.ctx.loadDynamic(dynOpts.transition, params);

      final List<dynamic> rawOptions;
      if (result['options'] is List) {
        rawOptions = result['options'] as List;
      } else if (result['data'] is List) {
        rawOptions = result['data'] as List;
      } else {
        rawOptions = [];
      }

      if (mounted) {
        setState(() {
          _dynamicOptions = rawOptions.whereType<Map<String, dynamic>>().map((opt) {
            return FieldOption(
              key: opt['key']?.toString() ?? opt['value']?.toString() ?? '',
              text: opt['text']?.toString() ?? opt['label']?.toString() ?? '',
            );
          }).toList();
          _isLoading = false;
          _hasLoadedOnce = true;
        });
      }
    } catch (_) {
      if (mounted) setState(() { _isLoading = false; _hasLoadedOnce = true; });
    }
  }

  Future<void> _onServerSearch(String term) async {
    _searchTerm = term;
    final dynOpts = widget.widget.dynamicOptions;
    if (dynOpts == null || !dynOpts.serverSearch) return;
    if (term.length < dynOpts.minLength) {
      setState(() => _dynamicOptions = []);
      return;
    }

    final now = DateTime.now();
    _lastSearch = now;
    await Future.delayed(const Duration(milliseconds: _searchDebounceMs));
    if (_lastSearch != now) return;

    await _fetchOptions(searchTerm: term);
  }

  @override
  Widget build(BuildContext context) {
    final dynOpts = widget.widget.dynamicOptions;
    final isServerSearch = dynOpts?.serverSearch ?? false;
    final allowEmpty = widget.widget.boolAttr('allowEmpty', true);

    if (isServerSearch) {
      return _buildServerSearchDropDown(allowEmpty);
    }

    return _buildStandardDynamic(allowEmpty);
  }

  /// Standard dynamic dropdown — fetches options on mount and parent changes.
  Widget _buildStandardDynamic(bool allowEmpty) {
    // Phase 4.7: If still loading and haven't loaded once, show currentDescription
    // as a readonly placeholder so the user sees meaningful text while waiting.
    final currentDescription = widget.widget.attr('currentDescription');
    if (_isLoading && !_hasLoadedOnce && currentDescription.isNotEmpty) {
      return InputDecorator(
        decoration: InputDecoration(
          labelText: widget.field.displayTitle,
          border: const OutlineInputBorder(),
          isDense: true,
          suffixIcon: const Padding(
            padding: EdgeInsets.all(12),
            child: SizedBox(
              width: 16, height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ),
        child: Text(currentDescription, style: const TextStyle(fontSize: 14)),
      );
    }

    final items = <DropdownMenuItem<String>>[];
    if (allowEmpty) {
      items.add(const DropdownMenuItem(value: '', child: Text('')));
    }
    for (final opt in _dynamicOptions) {
      items.add(DropdownMenuItem(
        value: opt.key,
        child: Text(opt.text.isEmpty ? opt.key : opt.text),
      ));
    }

    // Determine the current value and ensure it exists in items
    final rawValue = widget.formData[widget.field.name]?.toString() ??
        widget.field.currentValue ?? '';
    final currentValue = items.any((item) => item.value == rawValue)
        ? rawValue
        : (allowEmpty ? '' : null);

    return DropdownButtonFormField<String>(
      initialValue: currentValue,
      decoration: InputDecoration(
        labelText: widget.field.displayTitle,
        hintText: widget.field.tooltip.isNotEmpty ? widget.field.tooltip : null,
        border: const OutlineInputBorder(),
        isDense: true,
        suffixIcon: _isLoading
            ? const Padding(
                padding: EdgeInsets.all(12),
                child: SizedBox(
                  width: 16, height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            : null,
      ),
      items: items,
      onChanged: (value) => widget.onChanged(widget.field.name, value),
      validator: widget.widget.boolAttr('required')
          ? (value) => (value == null || value.isEmpty)
              ? '${widget.field.displayTitle.isNotEmpty ? widget.field.displayTitle : widget.field.name} is required'
              : null
          : null,
      isExpanded: true,
    );
  }

  /// Server-search dropdown — shows a text field that filters options on server.
  Widget _buildServerSearchDropDown(bool allowEmpty) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        TextFormField(
          decoration: InputDecoration(
            labelText: widget.field.displayTitle,
            hintText: widget.field.tooltip.isNotEmpty
                ? widget.field.tooltip
                : 'Type to search...',
            border: const OutlineInputBorder(),
            isDense: true,
            prefixIcon: const Icon(Icons.search, size: 20),
            suffixIcon: _isLoading
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : null,
          ),
          onChanged: _onServerSearch,
        ),
        if (_dynamicOptions.isNotEmpty)
          Container(
            constraints: const BoxConstraints(maxHeight: 200),
            margin: const EdgeInsets.only(top: 4),
            decoration: BoxDecoration(
              border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
              borderRadius: BorderRadius.circular(4),
              color: Theme.of(context).cardColor,
            ),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: _dynamicOptions.length,
              itemBuilder: (context, index) {
                final opt = _dynamicOptions[index];
                final isSelected =
                    widget.formData[widget.field.name]?.toString() == opt.key;
                return ListTile(
                  dense: true,
                  title: Text(opt.text.isEmpty ? opt.key : opt.text),
                  selected: isSelected,
                  selectedTileColor:
                      Theme.of(context).primaryColor.withOpacity(0.1),
                  onTap: () {
                    widget.onChanged(widget.field.name, opt.key);
                  },
                );
              },
            ),
          ),
      ],
    );
  }
}

// ===========================================================================
// Autocomplete field with server-side search (StatefulWidget)
// ===========================================================================

class _AutocompleteField extends StatefulWidget {
  final FieldDefinition field;
  final FieldWidget widget;
  final Map<String, dynamic> formData;
  final FieldChangedCallback onChanged;
  final MoquiRenderContext ctx;

  const _AutocompleteField({
    required this.field,
    required this.widget,
    required this.formData,
    required this.onChanged,
    required this.ctx,
  });

  @override
  State<_AutocompleteField> createState() => _AutocompleteFieldState();
}

class _AutocompleteFieldState extends State<_AutocompleteField> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  List<_AutocompleteOption> _options = [];
  bool _isLoading = false;
  bool _showOptions = false;
  String? _selectedValue;
  String? _selectedLabel;

  // Debounce timer — values from AutocompleteConfig when available
  DateTime? _lastSearch;
  int get _debounceMs => widget.widget.autocomplete?.delay ?? 300;
  int get _minSearchLength => widget.widget.autocomplete?.minLength ?? 2;

  @override
  void initState() {
    super.initState();
    // Initialize with existing value
    final existing = widget.formData[widget.field.name];
    if (existing != null) {
      _selectedValue = existing.toString();
      // Try to get display text from options if available
      final displayField = widget.widget.attr('descriptionField', 'description');
      final existingLabel = widget.formData['${widget.field.name}_$displayField'];
      _selectedLabel = existingLabel?.toString() ?? _selectedValue;
      _controller.text = _selectedLabel ?? '';
    }
    _focusNode.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    if (!_focusNode.hasFocus) {
      setState(() => _showOptions = false);
    }
  }

  Future<void> _search(String term) async {
    if (term.length < _minSearchLength) {
      setState(() {
        _options = [];
        _showOptions = false;
      });
      return;
    }

    // Debounce
    final now = DateTime.now();
    _lastSearch = now;
    await Future.delayed(Duration(milliseconds: _debounceMs));
    if (_lastSearch != now) return; // Another search was triggered

    setState(() => _isLoading = true);

    try {
      final transition = widget.widget.autocomplete?.transition ??
          widget.widget.attr('transition');
      if (transition.isEmpty) {
        setState(() {
          _options = [];
          _showOptions = false;
          _isLoading = false;
        });
        return;
      }

      final valueField = widget.widget.attr('valueField', 'value');
      final labelField = widget.widget.attr('labelField', 'label');

      // Build the search URL
      final params = <String, dynamic>{
        'term': term,
      };

      // Add any additional parameters from the widget
      final paramList = widget.widget.attributes['parameters'] as List?;
      if (paramList != null) {
        for (final p in paramList.whereType<Map<String, dynamic>>()) {
          final name = p['name']?.toString();
          final value = p['value']?.toString();
          if (name != null && name.isNotEmpty) {
            params[name] = value ?? '';
          }
        }
      }

      final result = await widget.ctx.loadDynamic(transition, params);

      // Parse results - may be in 'options' array or directly as array
      final List<dynamic> options;
      if (result['options'] is List) {
        options = result['options'] as List;
      } else if (result['data'] is List) {
        options = result['data'] as List;
      } else {
        options = [];
      }

      setState(() {
        _options = options.whereType<Map<String, dynamic>>().map((opt) {
          return _AutocompleteOption(
            value: opt[valueField]?.toString() ?? opt['value']?.toString() ?? '',
            label: opt[labelField]?.toString() ?? opt['label']?.toString() ?? opt[valueField]?.toString() ?? '',
          );
        }).toList();
        _showOptions = _options.isNotEmpty;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _options = [];
        _showOptions = false;
        _isLoading = false;
      });
    }
  }

  void _selectOption(_AutocompleteOption option) {
    setState(() {
      _selectedValue = option.value;
      _selectedLabel = option.label;
      _controller.text = option.label;
      _showOptions = false;
    });
    widget.onChanged(widget.field.name, option.value);
    _focusNode.unfocus();
  }

  void _clearSelection() {
    setState(() {
      _selectedValue = null;
      _selectedLabel = null;
      _controller.clear();
      _options = [];
      _showOptions = false;
    });
    widget.onChanged(widget.field.name, null);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        TextFormField(
          controller: _controller,
          focusNode: _focusNode,
          decoration: InputDecoration(
            labelText: widget.field.displayTitle,
            hintText: widget.field.tooltip.isNotEmpty ? widget.field.tooltip : 'Type to search...',
            border: const OutlineInputBorder(),
            isDense: true,
            prefixIcon: const Icon(Icons.search, size: 20),
            suffixIcon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_isLoading)
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                if (_selectedValue != null && !_isLoading)
                  IconButton(
                    icon: const Icon(Icons.clear, size: 18),
                    onPressed: _clearSelection,
                    tooltip: 'Clear selection',
                  ),
              ],
            ),
          ),
          onChanged: (value) {
            if (_selectedValue != null && value != _selectedLabel) {
              // User started typing, clear selection
              _selectedValue = null;
              _selectedLabel = null;
            }
            _search(value);
          },
          onTap: () {
            if (_options.isNotEmpty) {
              setState(() => _showOptions = true);
            }
          },
        ),
        if (_showOptions && _options.isNotEmpty)
          Container(
            constraints: const BoxConstraints(maxHeight: 200),
            margin: const EdgeInsets.only(top: 4),
            decoration: BoxDecoration(
              border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
              borderRadius: BorderRadius.circular(4),
              color: Theme.of(context).cardColor,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: _options.length,
              itemBuilder: (context, index) {
                final option = _options[index];
                final isSelected = option.value == _selectedValue;
                return ListTile(
                  dense: true,
                  title: Text(option.label),
                  selected: isSelected,
                  selectedTileColor: Theme.of(context).primaryColor.withOpacity(0.1),
                  onTap: () => _selectOption(option),
                );
              },
            ),
          ),
      ],
    );
  }
}

class _AutocompleteOption {
  final String value;
  final String label;

  _AutocompleteOption({required this.value, required this.label});
}

// ===========================================================================
// Editable field - click to edit inline (StatefulWidget)
// ===========================================================================

class _EditableField extends StatefulWidget {
  final FieldDefinition field;
  final FieldWidget widget;
  final Map<String, dynamic> formData;
  final FieldChangedCallback onChanged;
  final MoquiRenderContext ctx;

  const _EditableField({
    required this.field,
    required this.widget,
    required this.formData,
    required this.onChanged,
    required this.ctx,
  });

  @override
  State<_EditableField> createState() => _EditableFieldState();
}

class _EditableFieldState extends State<_EditableField> {
  bool _isEditing = false;
  bool _isSaving = false;
  late TextEditingController _controller;
  final FocusNode _focusNode = FocusNode();
  String? _originalValue;

  @override
  void initState() {
    super.initState();
    _originalValue = widget.formData[widget.field.name]?.toString() ?? 
        widget.field.currentValue ?? '';
    _controller = TextEditingController(text: _originalValue);
    _focusNode.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    if (!_focusNode.hasFocus && _isEditing) {
      _saveAndExit();
    }
  }

  void _startEditing() {
    setState(() {
      _isEditing = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  Future<void> _saveAndExit() async {
    final newValue = _controller.text;
    if (newValue != _originalValue) {
      widget.onChanged(widget.field.name, newValue);

      // Phase 4.1: POST to server if urlValue (update URL) is specified
      final urlValue = widget.widget.attr('url');
      if (urlValue.isNotEmpty) {
        setState(() => _isSaving = true);
        try {
          final response = await widget.ctx.submitForm(
            urlValue,
            {widget.field.name: newValue},
          );
          if (mounted && response != null) {
            if (response.hasErrors) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(response.errors.join('\n')),
                  backgroundColor: Colors.red,
                ),
              );
            } else if (response.hasMessages) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(response.messages.join('\n'))),
              );
            }
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Save failed: $e'),
                backgroundColor: Colors.red,
              ),
            );
          }
        } finally {
          if (mounted) setState(() => _isSaving = false);
        }
      }

      _originalValue = newValue;
    }
    if (mounted) setState(() => _isEditing = false);
  }

  void _cancel() {
    _controller.text = _originalValue ?? '';
    setState(() => _isEditing = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_isSaving) {
      return const Padding(
        padding: EdgeInsets.all(8),
        child: SizedBox(
          width: 20, height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    if (_isEditing) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Expanded(
            child: TextFormField(
              controller: _controller,
              focusNode: _focusNode,
              decoration: InputDecoration(
                labelText: widget.field.displayTitle,
                border: const OutlineInputBorder(),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 8,
                ),
              ),
              onFieldSubmitted: (_) => _saveAndExit(),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.check, color: Colors.green, size: 18),
            onPressed: _saveAndExit,
            tooltip: 'Save',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.red, size: 18),
            onPressed: _cancel,
            tooltip: 'Cancel',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
        ],
      );
    }

    // Display mode - click to edit
    return Semantics(
      button: true,
      label: 'Edit ${widget.field.displayTitle}',
      child: InkWell(
        onTap: _startEditing,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Expanded(
              child: Text(
                _originalValue?.isNotEmpty == true ? _originalValue! : '—',
                style: TextStyle(
                  color: _originalValue?.isEmpty == true 
                      ? Theme.of(context).colorScheme.onSurfaceVariant
                      : null,
                ),
              ),
            ),
            Icon(Icons.edit, size: 14, color: Theme.of(context).colorScheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

// ===========================================================================
// Phase 4.6: DateTime — StatefulWidget with proper controller lifecycle
// ===========================================================================

class _DateTimeField extends StatefulWidget {
  final FieldDefinition field;
  final String dateType;
  final Map<String, dynamic> formData;
  final FieldChangedCallback onChanged;

  const _DateTimeField({
    required this.field,
    required this.dateType,
    required this.formData,
    required this.onChanged,
  });

  @override
  State<_DateTimeField> createState() => _DateTimeFieldState();
}

class _DateTimeFieldState extends State<_DateTimeField> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    final initial = widget.formData[widget.field.name]?.toString() ??
        widget.field.currentValue ?? '';
    _controller = TextEditingController(text: initial);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    await FieldWidgetFactory._pickDateTime(
      context,
      widget.field,
      widget.dateType,
      widget.formData,
      (fieldName, value) {
        _controller.text = value?.toString() ?? '';
        widget.onChanged(fieldName, value);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    String hint;
    switch (widget.dateType) {
      case 'date':
        hint = 'YYYY-MM-DD';
        break;
      case 'time':
        hint = 'HH:MM';
        break;
      default:
        hint = 'YYYY-MM-DD HH:MM';
    }

    return TextFormField(
      controller: _controller,
      decoration: InputDecoration(
        labelText: widget.field.displayTitle,
        hintText: hint,
        border: const OutlineInputBorder(),
        isDense: true,
        suffixIcon: IconButton(
          icon: Icon(
            widget.dateType == 'time' ? Icons.access_time : Icons.calendar_today,
            size: 20,
          ),
          tooltip: widget.dateType == 'time' ? 'Pick time' : 'Pick date',
          onPressed: _pick,
        ),
      ),
      readOnly: true,
      onTap: _pick,
    );
  }
}

// ===========================================================================
// Phase 4.4 + 4.6: DateFind — From/thru range with proper controller lifecycle
// ===========================================================================

class _DateFindField extends StatefulWidget {
  final FieldDefinition field;
  final String dateType;
  final Map<String, dynamic> formData;
  final FieldChangedCallback onChanged;

  const _DateFindField({
    required this.field,
    required this.dateType,
    required this.formData,
    required this.onChanged,
  });

  @override
  State<_DateFindField> createState() => _DateFindFieldState();
}

class _DateFindFieldState extends State<_DateFindField> {
  late TextEditingController _fromController;
  late TextEditingController _thruController;

  @override
  void initState() {
    super.initState();
    _fromController = TextEditingController(
      text: widget.formData['${widget.field.name}_from']?.toString() ?? '',
    );
    _thruController = TextEditingController(
      text: widget.formData['${widget.field.name}_thru']?.toString() ?? '',
    );
  }

  @override
  void dispose() {
    _fromController.dispose();
    _thruController.dispose();
    super.dispose();
  }

  Future<void> _pickFor(TextEditingController controller, String suffix) async {
    await FieldWidgetFactory._pickDateTime(
      context,
      widget.field,
      widget.dateType,
      widget.formData,
      (_, value) {
        controller.text = value?.toString() ?? '';
        widget.onChanged('${widget.field.name}_$suffix', value);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final iconData = widget.dateType == 'time'
        ? Icons.access_time
        : Icons.calendar_today;

    return Row(
      children: [
        Expanded(
          child: TextFormField(
            controller: _fromController,
            decoration: InputDecoration(
              labelText: '${widget.field.displayTitle} From',
              border: const OutlineInputBorder(),
              isDense: true,
              suffixIcon: IconButton(
                icon: Icon(iconData, size: 20),
                tooltip: 'Pick from date',
                onPressed: () => _pickFor(_fromController, 'from'),
              ),
            ),
            readOnly: true,
            onTap: () => _pickFor(_fromController, 'from'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: TextFormField(
            controller: _thruController,
            decoration: InputDecoration(
              labelText: '${widget.field.displayTitle} Thru',
              border: const OutlineInputBorder(),
              isDense: true,
              suffixIcon: IconButton(
                icon: Icon(iconData, size: 20),
                tooltip: 'Pick thru date',
                onPressed: () => _pickFor(_thruController, 'thru'),
              ),
            ),
            readOnly: true,
            onTap: () => _pickFor(_thruController, 'thru'),
          ),
        ),
      ],
    );
  }
}

// ===========================================================================
// Phase 4.5: TextFind — text-find with not/ignoreCase toggles + operator
// ===========================================================================

class _TextFindField extends StatefulWidget {
  final FieldDefinition field;
  final String defaultOp;
  final bool hideOptions;
  final Map<String, dynamic> formData;
  final FieldChangedCallback onChanged;

  const _TextFindField({
    required this.field,
    required this.defaultOp,
    required this.hideOptions,
    required this.formData,
    required this.onChanged,
  });

  @override
  State<_TextFindField> createState() => _TextFindFieldState();
}

class _TextFindFieldState extends State<_TextFindField> {
  late String _selectedOp;
  late bool _not;
  late bool _ignoreCase;

  static const _operators = [
    ('contains', 'Contains'),
    ('equals', 'Equals'),
    ('begins', 'Begins With'),
    ('empty', 'Is Empty'),
    ('in', 'In'),
  ];

  @override
  void initState() {
    super.initState();
    _selectedOp = widget.formData['${widget.field.name}_op']?.toString() ??
        widget.defaultOp;
    _not = widget.formData['${widget.field.name}_not']?.toString() == 'Y';
    _ignoreCase =
        widget.formData['${widget.field.name}_ic']?.toString() != 'N';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            if (!widget.hideOptions) ...[
              SizedBox(
                width: 200,
                child: DropdownButtonFormField<String>(
                  initialValue: _selectedOp,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    isDense: true,
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  ),
                  items: _operators
                      .map((op) => DropdownMenuItem(
                          value: op.$1, child: Text(op.$2, style: const TextStyle(fontSize: 13))))
                      .toList(),
                  onChanged: (val) {
                    if (val != null) {
                      setState(() => _selectedOp = val);
                      widget.onChanged('${widget.field.name}_op', val);
                    }
                  },
                ),
              ),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: TextFormField(
                initialValue:
                    widget.formData[widget.field.name]?.toString() ?? '',
                decoration: InputDecoration(
                  labelText: widget.field.displayTitle,
                  hintText: widget.field.tooltip.isNotEmpty
                      ? widget.field.tooltip
                      : null,
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: (value) =>
                    widget.onChanged(widget.field.name, value),
              ),
            ),
          ],
        ),
        if (!widget.hideOptions)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              children: [
                SizedBox(
                  height: 28,
                  child: FilterChip(
                    label: const Text('Not', style: TextStyle(fontSize: 12)),
                    selected: _not,
                    visualDensity: VisualDensity.compact,
                    onSelected: (val) {
                      setState(() => _not = val);
                      widget.onChanged(
                          '${widget.field.name}_not', val ? 'Y' : 'N');
                    },
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  height: 28,
                  child: FilterChip(
                    label: const Text('Ignore Case',
                        style: TextStyle(fontSize: 12)),
                    selected: _ignoreCase,
                    visualDensity: VisualDensity.compact,
                    onSelected: (val) {
                      setState(() => _ignoreCase = val);
                      widget.onChanged(
                          '${widget.field.name}_ic', val ? 'Y' : 'N');
                    },
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

// ===========================================================================
// Phase 4.3: DefaultTransitionTextLine — fires default-transition on mount
// ===========================================================================

class _DefaultTransitionTextLine extends StatefulWidget {
  final FieldDefinition field;
  final FieldWidget widget;
  final Map<String, dynamic> formData;
  final FieldChangedCallback onChanged;
  final MoquiRenderContext ctx;

  const _DefaultTransitionTextLine({
    required this.field,
    required this.widget,
    required this.formData,
    required this.onChanged,
    required this.ctx,
  });

  @override
  State<_DefaultTransitionTextLine> createState() =>
      _DefaultTransitionTextLineState();
}

class _DefaultTransitionTextLineState
    extends State<_DefaultTransitionTextLine> {
  late TextEditingController _controller;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    final initial = widget.formData[widget.field.name]?.toString() ??
        widget.field.currentValue ?? '';
    _controller = TextEditingController(text: initial);
    _fetchDefault();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _DefaultTransitionTextLine oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Re-fetch when depends-on parent field changes
    final dtConfig = widget.widget.attributes['defaultTransition'];
    if (dtConfig is Map) {
      final dependsOn = dtConfig['dependsOn']?.toString() ?? '';
      if (dependsOn.isNotEmpty) {
        final oldVal = oldWidget.formData[dependsOn];
        final newVal = widget.formData[dependsOn];
        if (oldVal?.toString() != newVal?.toString()) {
          _fetchDefault();
        }
      }
    }
  }

  Future<void> _fetchDefault() async {
    final dtConfig = widget.widget.attributes['defaultTransition'];
    if (dtConfig is! Map) return;

    final transition = dtConfig['transition']?.toString() ?? '';
    if (transition.isEmpty) return;

    setState(() => _isLoading = true);
    try {
      final params = <String, dynamic>{};
      final dependsOn = dtConfig['dependsOn']?.toString() ?? '';
      if (dependsOn.isNotEmpty) {
        final depValue = widget.formData[dependsOn];
        if (depValue != null) params[dependsOn] = depValue.toString();
      }

      final result = await widget.ctx.loadDynamic(transition, params);
      final defaultValue = result['defaultValue']?.toString() ??
          result['value']?.toString() ?? '';

      if (mounted && defaultValue.isNotEmpty && _controller.text.isEmpty) {
        _controller.text = defaultValue;
        widget.onChanged(widget.field.name, defaultValue);
      }
    } catch (_) {
      // Silently fail — field remains editable without default
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final inputType = widget.widget.attr('inputType', 'text');
    final maxLength = int.tryParse(widget.widget.attr('maxlength'));
    final disabled = widget.widget.boolAttr('disabled');

    TextInputType keyboardType;
    switch (inputType) {
      case 'number':
        keyboardType = TextInputType.number;
        break;
      case 'email':
        keyboardType = TextInputType.emailAddress;
        break;
      case 'tel':
        keyboardType = TextInputType.phone;
        break;
      case 'url':
        keyboardType = TextInputType.url;
        break;
      default:
        keyboardType = TextInputType.text;
    }

    return TextFormField(
      controller: _controller,
      decoration: InputDecoration(
        labelText: widget.field.displayTitle,
        hintText: widget.field.tooltip.isNotEmpty ? widget.field.tooltip : null,
        border: const OutlineInputBorder(),
        isDense: true,
        suffixIcon: _isLoading
            ? const Padding(
                padding: EdgeInsets.all(12),
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            : null,
      ),
      keyboardType: keyboardType,
      maxLength: maxLength,
      enabled: !disabled,
      validator: FieldWidgetFactory._buildValidator(widget.field, widget.widget),
      onChanged: (value) => widget.onChanged(widget.field.name, value),
    );
  }
}

// ===========================================================================
// Phase 4.2: DynamicDisplay — display field with dynamic-transition reload
// ===========================================================================

class _DynamicDisplay extends StatefulWidget {
  final FieldDefinition field;
  final FieldWidget widget;
  final Map<String, dynamic> formData;
  final MoquiRenderContext ctx;

  const _DynamicDisplay({
    required this.field,
    required this.widget,
    required this.formData,
    required this.ctx,
  });

  @override
  State<_DynamicDisplay> createState() => _DynamicDisplayState();
}

class _DynamicDisplayState extends State<_DynamicDisplay> {
  String _displayText = '';
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _displayText = tpl.cleanDisplayText(widget.widget.attr('resolvedText',
        widget.formData[widget.field.name]?.toString() ??
            widget.field.currentValue ?? ''));
    _fetchDynamic();
  }

  @override
  void didUpdateWidget(covariant _DynamicDisplay oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Re-fetch when depends-on parent field changes
    for (final dep in widget.widget.dependsOn) {
      final oldVal = oldWidget.formData[dep.field];
      final newVal = widget.formData[dep.field];
      if (oldVal?.toString() != newVal?.toString()) {
        _fetchDynamic();
        return;
      }
    }
  }

  Future<void> _fetchDynamic() async {
    final dynamicUrl = widget.widget.attr('dynamic-url');
    if (dynamicUrl.isEmpty) return;

    setState(() => _isLoading = true);
    try {
      final params = <String, dynamic>{};
      for (final dep in widget.widget.dependsOn) {
        final paramName = dep.parameter.isNotEmpty ? dep.parameter : dep.field;
        final value = widget.formData[dep.field];
        if (value != null) params[paramName] = value.toString();
      }

      final result = await widget.ctx.loadDynamic(dynamicUrl, params);
      final newText = result['value']?.toString() ??
          result['text']?.toString() ??
          result['resolvedText']?.toString() ?? '';

      if (mounted && newText.isNotEmpty) {
        setState(() => _displayText = newText);
      }
    } catch (_) {
      // Silently fail — keep existing display text
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final textChild = FieldWidgetFactory._looksLikeHtml(_displayText)
        ? HtmlWidget(_displayText, textStyle: const TextStyle(fontSize: 14))
        : Text(_displayText, style: const TextStyle(fontSize: 14));

    return InputDecorator(
      decoration: InputDecoration(
        labelText: widget.field.displayTitle,
        border: const OutlineInputBorder(),
        isDense: true,
        filled: true,
        fillColor: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        suffixIcon: _isLoading
            ? const Padding(
                padding: EdgeInsets.all(12),
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            : null,
      ),
      child: textChild,
    );
  }
}
