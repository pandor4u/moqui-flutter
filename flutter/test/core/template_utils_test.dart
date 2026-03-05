import 'package:flutter_test/flutter_test.dart';
import 'package:moqui_flutter/core/template_utils.dart';

void main() {
  // ==========================================================================
  // hasUnresolvedTemplate
  // ==========================================================================
  group('hasUnresolvedTemplate', () {
    test('detects simple Groovy expression', () {
      expect(hasUnresolvedTemplate(r'Hello ${name}'), isTrue);
    });

    test('detects nested braces', () {
      expect(
          hasUnresolvedTemplate(
              r'${orderPartInfo.isVendorInternalOrg ? "Sales" : "Purchase"}'),
          isTrue);
    });

    test('detects FreeMarker directive', () {
      expect(hasUnresolvedTemplate('<#if foo>bar</#if>'), isTrue);
    });

    test('detects FreeMarker macro', () {
      expect(hasUnresolvedTemplate('<@spring.formInput "name"/>'), isTrue);
    });

    test('returns false for plain text', () {
      expect(hasUnresolvedTemplate('Hello World'), isFalse);
    });

    test('returns false for empty string', () {
      expect(hasUnresolvedTemplate(''), isFalse);
    });

    test('returns false for dollar sign without braces', () {
      expect(hasUnresolvedTemplate(r'Price is $10'), isFalse);
    });
  });

  // ==========================================================================
  // hasHtmlEntities
  // ==========================================================================
  group('hasHtmlEntities', () {
    test('detects &nbsp;', () {
      expect(hasHtmlEntities('Hello&nbsp;World'), isTrue);
    });

    test('detects numeric entity', () {
      expect(hasHtmlEntities('Hello&#160;World'), isTrue);
    });

    test('detects hex entity', () {
      expect(hasHtmlEntities('Hello&#xA0;World'), isTrue);
    });

    test('returns false for plain text', () {
      expect(hasHtmlEntities('Hello World'), isFalse);
    });

    test('returns false for bare ampersand', () {
      expect(hasHtmlEntities('A & B'), isFalse);
    });
  });

  // ==========================================================================
  // cleanDisplayText
  // ==========================================================================
  group('cleanDisplayText', () {
    test('strips simple expression', () {
      expect(cleanDisplayText(r'Hello ${name}'), equals('Hello'));
    });

    test('strips expression preserving surrounding text', () {
      expect(
          cleanDisplayText(
              r'Edit Part ${orderPart.orderPartSeqId}'),
          equals('Edit Part'));
    });

    test('strips ternary expression preserving literal text', () {
      expect(
          cleanDisplayText(
              r'${orderPartInfo.isVendorInternalOrg ? "Sales" : "Purchase"} Order Part ${orderPart.orderPartSeqId}'),
          equals('Order Part'));
    });

    test('decodes HTML entities', () {
      expect(cleanDisplayText('Hello&nbsp;World'), equals('Hello\u00A0World'));
    });

    test('strips both template and decodes entities', () {
      // After stripping ${name}, result is "\u00A0Suffix"; Dart trim() strips NBSP
      expect(
          cleanDisplayText(r'${name}&nbsp;Suffix'),
          equals('Suffix'));
    });

    test('strips FreeMarker directives', () {
      expect(cleanDisplayText('<#if x>Show This</#if>'), equals('Show This'));
    });

    test('returns fallback when entirely template', () {
      expect(
          cleanDisplayText(r'${something}', fallback: 'Default'),
          equals('Default'));
    });

    test('returns empty when entirely template and no fallback', () {
      expect(
          cleanDisplayText(r'${something}'),
          equals(''));
    });

    test('passes through plain text unchanged', () {
      expect(cleanDisplayText('Hello World'), equals('Hello World'));
    });

    test('passes through empty string', () {
      expect(cleanDisplayText(''), equals(''));
    });

    test('collapses excessive whitespace', () {
      expect(
          cleanDisplayText(r'A  ${x}  B'),
          equals('A B'));
    });

    test('handles complex Java method call template', () {
      expect(
          cleanDisplayText(
              r'${org.moqui.util.StringUtilities.camelCaseToPretty(fieldName)}'),
          equals(''));
    });

    test('handles multiple expressions in one string', () {
      expect(
          cleanDisplayText(r'${a} and ${b} plus ${c}'),
          equals('and plus'));
    });
  });

  // ==========================================================================
  // cleanStyleAttr
  // ==========================================================================
  group('cleanStyleAttr', () {
    test('returns style unchanged when no template', () {
      expect(cleanStyleAttr('text-danger'), equals('text-danger'));
    });

    test('returns fallback when template present', () {
      expect(
          cleanStyleAttr(
              r'${orderPart.statusId == "OrderPlaced" ? "text-success" : "text-danger"}'),
          equals(''));
    });

    test('returns custom fallback when template present', () {
      expect(
          cleanStyleAttr(r'${x}', fallback: 'text-muted'),
          equals('text-muted'));
    });

    test('returns empty for empty string', () {
      expect(cleanStyleAttr(''), equals(''));
    });
  });

  // ==========================================================================
  // cleanBtnType
  // ==========================================================================
  group('cleanBtnType', () {
    test('returns btnType unchanged when no template', () {
      expect(cleanBtnType('danger'), equals('danger'));
    });

    test('returns "primary" by default when template present', () {
      expect(
          cleanBtnType(
              r'${orderPartInfo.isVendorInternalOrg ? "success" : "primary"}'),
          equals('primary'));
    });

    test('returns custom fallback when template present', () {
      expect(
          cleanBtnType(r'${x}', fallback: 'secondary'),
          equals('secondary'));
    });

    test('returns empty for empty string', () {
      expect(cleanBtnType(''), equals(''));
    });
  });

  // ==========================================================================
  // decodeHtmlEntities
  // ==========================================================================
  group('decodeHtmlEntities', () {
    test('decodes &nbsp;', () {
      expect(decodeHtmlEntities('Hello&nbsp;World'), equals('Hello\u00A0World'));
    });

    test('decodes &amp;', () {
      expect(decodeHtmlEntities('A&amp;B'), equals('A&B'));
    });

    test('decodes &lt; and &gt;', () {
      expect(decodeHtmlEntities('&lt;div&gt;'), equals('<div>'));
    });

    test('decodes &quot;', () {
      expect(decodeHtmlEntities('&quot;hello&quot;'), equals('"hello"'));
    });

    test('decodes numeric entity &#160;', () {
      expect(decodeHtmlEntities('A&#160;B'), equals('A\u00A0B'));
    });

    test('decodes hex entity &#xA0;', () {
      expect(decodeHtmlEntities('A&#xA0;B'), equals('A\u00A0B'));
    });

    test('leaves plain text unchanged', () {
      expect(decodeHtmlEntities('plain text'), equals('plain text'));
    });

    test('leaves unknown entities unchanged', () {
      expect(decodeHtmlEntities('&foobar;'), equals('&foobar;'));
    });

    test('decodes multiple entities in string', () {
      expect(
          decodeHtmlEntities('&lt;b&gt;Bold&lt;/b&gt;&amp;More'),
          equals('<b>Bold</b>&More'));
    });

    test('decodes &ndash; and &mdash;', () {
      expect(decodeHtmlEntities('a&ndash;b&mdash;c'),
          equals('a\u2013b\u2014c'));
    });

    test('decodes &#39; (apostrophe)', () {
      expect(decodeHtmlEntities('it&#39;s'), equals("it's"));
    });
  });

  // ==========================================================================
  // looksLikeHtml
  // ==========================================================================
  group('looksLikeHtml', () {
    test('detects HTML tags', () {
      expect(looksLikeHtml('<b>bold</b>'), isTrue);
    });

    test('detects self-closing tags', () {
      expect(looksLikeHtml('<br/>'), isTrue);
    });

    test('detects HTML entities as HTML-like', () {
      expect(looksLikeHtml('Hello&nbsp;World'), isTrue);
    });

    test('returns false for plain text', () {
      expect(looksLikeHtml('Hello World'), isFalse);
    });

    test('returns false for less-than in math', () {
      expect(looksLikeHtml('a < b and c > d'), isFalse);
    });

    test('detects closing tags', () {
      expect(looksLikeHtml('</div>'), isTrue);
    });
  });

  // ==========================================================================
  // Edge cases and real-world Moqui templates
  // ==========================================================================
  group('real-world Moqui templates', () {
    test('OrderDetail Edit Part button text', () {
      expect(
          cleanDisplayText(r'Edit Part ${orderPart.orderPartSeqId}'),
          equals('Edit Part'));
    });

    test('OrderDetail sales/purchase ternary label', () {
      expect(
          cleanDisplayText(
              r'${orderPartInfo.isVendorInternalOrg ? "Sales" : "Purchase"} Order Part ${orderPart.orderPartSeqId}'),
          equals('Order Part'));
    });

    test('OrderDetail status style', () {
      expect(
          cleanStyleAttr(
              r"${orderPart.statusId == 'OrderPlaced' ? 'text-success' : (orderPart.statusId == 'OrderApproved' ? 'text-info' : '')}"),
          equals(''));
    });

    test('OrderDetail btnType ternary', () {
      expect(
          cleanBtnType(
              r'${orderPartInfo.isVendorInternalOrg ? "success" : "primary"}'),
          equals('primary'));
    });

    test('StringUtilities.camelCaseToPretty call', () {
      expect(
          cleanDisplayText(
              r'${org.moqui.util.StringUtilities.camelCaseToPretty(fieldName)}'),
          equals(''));
    });

    test('ec.entity.formatFieldString call', () {
      expect(
          cleanDisplayText(
              r'${ec.entity.formatFieldString("orderPart", "statusId", orderPart.statusId)}'),
          equals(''));
    });

    test('Mixed text with HTML entity &nbsp;', () {
      expect(
          cleanDisplayText('Order&nbsp;Details'),
          equals('Order\u00A0Details'));
    });

    test('Dashboard <strong> tag detected as HTML', () {
      expect(looksLikeHtml('<strong>Welcome</strong>'), isTrue);
    });
  });

  group('prettifyFormListName', () {
    test('splits PascalCase and strips List suffix', () {
      expect(prettifyFormListName('EmailMessageList'), equals('Email Messages'));
    });

    test('pluralises last word ending in consonant+y', () {
      expect(prettifyFormListName('OrderSummaryList'), equals('Order Summaries'));
    });

    test('pluralises regular noun', () {
      expect(prettifyFormListName('ChildOrderList'), equals('Child Orders'));
    });

    test('strips List from single-word name', () {
      expect(prettifyFormListName('ItemList'), equals('Items'));
    });

    test('returns name without List suffix unchanged (no plural)', () {
      expect(prettifyFormListName('OrderDetail'), equals('Order Detail'));
    });

    test('empty string returns empty', () {
      expect(prettifyFormListName(''), equals(''));
    });

    test('already has spaces — still title-cased', () {
      // If someone passes an already-split name it still works
      expect(prettifyFormListName('orderItems'), equals('Order Items'));
    });
  });
}
