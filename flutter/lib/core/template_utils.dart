/// Utilities for detecting and cleaning unresolved server-side template
/// expressions (`${...}`, FreeMarker `<#...>` / `<@...>`) and HTML entities
/// that the Moqui server failed to expand before sending JSON to the client.
///
/// The Moqui server's `ec.resource.expand()` silently returns the raw template
/// string when variables are not in scope (e.g. inside `section-iterate` where
/// the iteration variable doesn't exist at JSON-render time).  This utility
/// provides a client-side safety net so those raw expressions never reach the
/// user's eyes.
library;

/// Regex that matches a Groovy/Moqui `${...}` expression, including nested
/// braces (one level deep) and multi-line content.
final RegExp _groovyExprRe = RegExp(r'\$\{[^}]*(?:\{[^}]*\}[^}]*)?\}');

/// Regex for FreeMarker directives `<#...>` and macros `<@...>`.
final RegExp _freemarkerRe = RegExp(r'<[#@/][^>]*>');

/// Matches common HTML character-entity references.
final RegExp _htmlEntityRe = RegExp(r'&(?:#\d+|#x[\da-fA-F]+|[a-zA-Z]+);');

/// Named HTML entities we decode on the client side.
const Map<String, String> _htmlEntities = {
  '&nbsp;': '\u00A0',   // non-breaking space
  '&amp;': '&',
  '&lt;': '<',
  '&gt;': '>',
  '&quot;': '"',
  '&#39;': "'",
  '&apos;': "'",
  '&ndash;': '\u2013',
  '&mdash;': '\u2014',
  '&laquo;': '\u00AB',
  '&raquo;': '\u00BB',
  '&bull;': '\u2022',
  '&hellip;': '\u2026',
  '&copy;': '\u00A9',
  '&reg;': '\u00AE',
  '&trade;': '\u2122',
};

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/// Returns `true` when [text] contains at least one unresolved `${…}` or
/// FreeMarker expression.
bool hasUnresolvedTemplate(String text) {
  return _groovyExprRe.hasMatch(text) || _freemarkerRe.hasMatch(text);
}

/// Returns `true` when [text] contains HTML character-entity references
/// (e.g. `&nbsp;`, `&#160;`).
bool hasHtmlEntities(String text) => _htmlEntityRe.hasMatch(text);

/// Clean a **display text** value (label, button text, link text, etc.).
///
/// 1. Strips all `${…}` placeholders, keeping surrounding literal text.
/// 2. Strips FreeMarker directives.
/// 3. Decodes HTML entities.
/// 4. Collapses redundant whitespace.
///
/// Example:
/// ```
/// cleanDisplayText('Edit Part \${orderPart.orderPartSeqId}')
///   => 'Edit Part'
/// cleanDisplayText('\${orderPartInfo.isVendorInternalOrg ? "Sales" : "Purchase"} Order Part \${orderPart.orderPartSeqId}')
///   => 'Order Part'
/// ```
///
/// If the result would be entirely empty after stripping, [fallback] is
/// returned instead (defaults to empty string).
String cleanDisplayText(String text, {String fallback = ''}) {
  if (text.isEmpty) return text;
  var result = text;

  // 1. Strip ${…} expressions
  result = result.replaceAll(_groovyExprRe, '');

  // 2. Strip FreeMarker directives
  result = result.replaceAll(_freemarkerRe, '');

  // 3. Decode HTML entities
  result = decodeHtmlEntities(result);

  // 4. Strip standalone "null" from server-resolved Groovy expressions
  //    e.g. "Order null" → "Order", "null - null" → "-" → ""
  result = result.replaceAll(RegExp(r'\bnull\b'), '');

  // 5. Collapse regular whitespace (preserve non-breaking spaces) and trim
  result = result.replaceAll(RegExp(r'[ \t\r\n]+'), ' ').trim();

  // 6. Trim trailing/leading separators left over after null stripping
  result = result.replaceAll(RegExp(r'^[:\-,\s]+|[:\-,\s]+$'), '').trim();

  return result.isEmpty ? fallback : result;
}

/// Clean a **style / CSS-class** attribute value.
///
/// When the style string contains an unresolved `${…}` expression the entire
/// value is unreliable, so we return [fallback] (empty string by default).
/// Otherwise the original value is returned unchanged.
String cleanStyleAttr(String style, {String fallback = ''}) {
  if (style.isEmpty) return style;
  if (hasUnresolvedTemplate(style)) return fallback;
  return style;
}

/// Clean a **btnType** attribute value.
///
/// When the btnType string contains an unresolved `${…}` expression we
/// return [fallback] (`'primary'` by default) so buttons keep a sensible
/// default colour.
String cleanBtnType(String btnType, {String fallback = 'primary'}) {
  if (btnType.isEmpty) return btnType;
  if (hasUnresolvedTemplate(btnType)) return fallback;
  return btnType;
}

/// Decode HTML character-entity references in [text].
///
/// Supports common named entities and numeric (`&#123;` / `&#x7B;`) forms.
String decodeHtmlEntities(String text) {
  if (!_htmlEntityRe.hasMatch(text)) return text;

  return text.replaceAllMapped(_htmlEntityRe, (match) {
    final entity = match.group(0)!;

    // Named entity lookup
    final decoded = _htmlEntities[entity.toLowerCase()];
    if (decoded != null) return decoded;

    // Numeric entity: &#123; or &#x7B;
    if (entity.startsWith('&#')) {
      final code = entity.startsWith('&#x') || entity.startsWith('&#X')
          ? int.tryParse(entity.substring(3, entity.length - 1), radix: 16)
          : int.tryParse(entity.substring(2, entity.length - 1));
      if (code != null) return String.fromCharCode(code);
    }

    // Unknown entity – return as-is
    return entity;
  });
}

/// Returns `true` when [text] appears to contain HTML markup **or** HTML
/// entities. This is a superset of the original `_looksLikeHtml` check.
bool looksLikeHtml(String text) {
  // Existing tag check
  if (text.contains('<') &&
      text.contains('>') &&
      RegExp(r'<[a-zA-Z/][^>]*>').hasMatch(text)) {
    return true;
  }
  // Also count HTML entities as "looks like HTML"
  return hasHtmlEntities(text);
}

// ---------------------------------------------------------------------------
// Field title prettification
// ---------------------------------------------------------------------------

/// Regex that detects a camelCase or PascalCase identifier — at least two
/// words joined without spaces.  E.g. `orderName`, `salesChannelEnumId`.
final RegExp _camelCaseRe = RegExp(r'^[a-z][a-zA-Z0-9]*[A-Z][a-zA-Z0-9]*$');

/// Known suffixes that should be stripped from field names before display,
/// because the Moqui Vue UI never shows them.
final RegExp _technicalSuffix = RegExp(r'(Enum)?Id$', caseSensitive: true);

/// Convert a camelCase/PascalCase identifier into a space-separated title.
///
/// ```
/// _splitCamelCase('orderName')       => 'order Name'
/// _splitCamelCase('salesChannelEnumId') => 'sales Channel Enum Id'
/// ```
String _splitCamelCase(String s) {
  return s.replaceAllMapped(
    RegExp(r'([a-z0-9])([A-Z])'),
    (m) => '${m[1]} ${m[2]}',
  );
}

/// Prettify a field title that the server sent as a raw field name.
///
/// The Moqui Vue UI displays human-readable labels even when the server
/// sends the field name as the title.  This function replicates that logic:
///
/// 1. If [title] is empty, derives a label from [fieldName].
/// 2. If [title] looks like a camelCase identifier (matches [fieldName] or
///    is itself camelCase), convert it to Title Case with spaces.
/// 3. Strips technical suffixes like `EnumId`, `Id`.
///
/// ```
/// prettifyFieldTitle('orderName', 'orderName')   => 'Order Name'
/// prettifyFieldTitle('Placed', 'placedDate')      => 'Placed'    // already good
/// prettifyFieldTitle('grandTotal', 'grandTotal')  => 'Grand Total'
/// prettifyFieldTitle('', 'shipBeforeDate')         => 'Ship Before Date'
/// ```
String prettifyFieldTitle(String title, String fieldName) {
  // Already a nice human label — has spaces, not camelCase
  if (title.isNotEmpty && !_camelCaseRe.hasMatch(title)) {
    return title;
  }

  // Use field name as source when title is empty or matches the field name
  final source = (title.isEmpty || title == fieldName) ? fieldName : title;

  // Strip technical suffixes (EnumId, Id)
  var clean = source.replaceAll(_technicalSuffix, '');
  if (clean.isEmpty) clean = source; // safety: don't produce empty string

  // Split camelCase into words
  clean = _splitCamelCase(clean);

  // Title-case each word
  return clean
      .split(' ')
      .where((w) => w.isNotEmpty)
      .map((w) => w[0].toUpperCase() + w.substring(1))
      .join(' ');
}

/// Prettify a form-list name for display.
///
/// Splits PascalCase names into words and strips common suffixes
/// like "List", "Form", "Dynamic".
///
/// ```
/// prettifyFormListName('EmailMessageList')  => 'Email Messages'
/// prettifyFormListName('ChildOrderList')    => 'Child Orders'
/// prettifyFormListName('OrderItemList')     => 'Order Items'
/// ```
String prettifyFormListName(String name) {
  if (name.isEmpty) return name;

  // Split PascalCase / camelCase into words
  var words = _splitCamelCase(name);

  // Remove trailing List/Form/Dynamic suffix
  words = words
      .replaceAll(RegExp(r'\s+(List|Form|Dynamic)$', caseSensitive: false), '')
      .trim();

  if (words.isEmpty) return name;

  // Simple pluralisation of the last word when it was a "List" suffix
  if (name.endsWith('List')) {
    final parts = words.split(' ');
    final last = parts.last;
    if (!last.endsWith('s')) {
      if (last.endsWith('y') && last.length > 1 && !'aeiou'.contains(last[last.length - 2])) {
        parts[parts.length - 1] = '${last.substring(0, last.length - 1)}ies';
      } else {
        parts[parts.length - 1] = '${last}s';
      }
    }
    words = parts.join(' ');
  }

  // Title-case each word
  return words
      .split(' ')
      .where((w) => w.isNotEmpty)
      .map((w) => w[0].toUpperCase() + w.substring(1))
      .join(' ');
}
