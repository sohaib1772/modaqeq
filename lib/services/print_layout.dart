import 'package:html/dom.dart';

class PreparedPrintDocument {
  final String html;
  final bool landscape;
  const PreparedPrintDocument(this.html, {required this.landscape});
}

class PrintLayout {
  static void extractInvoicePages(Document doc) {
    final prepared = doc.querySelector('#printPages');
    final pages =
        (prepared != null
                ? prepared.querySelectorAll('.a4-paper')
                : doc.querySelectorAll('.a4-paper:not(.design-mode)'))
            .toList();
    if (prepared != null && pages.isEmpty) {
      throw const FormatException(
        'لم تُجهّز صفحات الفاتورة. أعد فتح المعاينة ثم حاول مجدداً.',
      );
    }
    if (pages.isEmpty) return;
    // Keep the already painted invoice, not the dialog/editor that hosts it.
    // A dialog is intentionally removed by the general sanitizer below.
    for (final style
        in doc.querySelectorAll('style,link[rel="stylesheet"]').toList()) {
      if (style.parent != doc.head) doc.head!.append(style);
    }
    final container = Element.tag('div')..id = 'printPages';
    for (final page in pages) {
      container.append(page);
    }
    doc.body!.nodes.clear();
    doc.body!.append(container);
    doc.documentElement!.classes.add('portal-pdf-invoice');
    doc.head!.append(
      Element.tag('style')
        ..text = '''
html.portal-pdf-invoice,html.portal-pdf-invoice body {
  margin:0!important;padding:0!important;background:white!important;
  min-height:0!important;height:auto!important;overflow:visible!important;
  -webkit-print-color-adjust:exact;print-color-adjust:exact;
}
html.portal-pdf-invoice body > #printPages {
  display:block!important;position:static!important;visibility:visible!important;
  margin:0!important;padding:0!important;overflow:visible!important;
  width:auto!important;max-width:none!important;max-height:none!important;
  transform:none!important;
}
html.portal-pdf-invoice #printPages > .a4-paper {
  display:block!important;visibility:visible!important;position:relative!important;
  margin:0!important;box-shadow:none!important;transform:none!important;
  break-after:page;page-break-after:always;
}
html.portal-pdf-invoice #printPages > .a4-paper:last-child {
  break-after:auto;page-break-after:auto;
}
''',
    );
  }

  static void removeInterface(Document doc) {
    doc
        .querySelectorAll(
          '.app-chrome,.app-header,.design-side,nav,.readonly-badge,.report-filters,.export-options,'
          'dialog,aside[role="alert"],aside[role="status"],.session-warning,.session-notice,.ledger-hint',
        )
        .forEach((e) => e.remove());
    // Remove operational notices only. Financial notes and table content stay.
    for (final node in doc.querySelectorAll(
      '.note,.alert,.warning,aside,footer,[role="alert"]',
    )) {
      var inTable = false;
      for (
        Element? ancestor = node;
        ancestor != null;
        ancestor = ancestor.parent
      ) {
        if (ancestor.localName == 'table') {
          inTable = true;
          break;
        }
      }
      if (inTable || node.querySelector('table') != null) continue;
      final text = node.text.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (RegExp(
        r'الجلسة.*(?:ساعة|الدخول|انته)|تنتهي الجلسة|انتهت جلسة|تسجيل الدخول|اتصال\s+HTTP|شبكة موثوقة|HTTP غير مشف',
        caseSensitive: false,
      ).hasMatch(text)) {
        node.remove();
      }
    }
  }

  static bool landscape(Document doc) {
    final styles = doc.querySelectorAll('style').map((e) => e.text).join('\n');
    // Honor the last explicit document page size (including invoice designer).
    bool? explicit;
    for (final page in RegExp(
      r'@page\s*[^{}]*\{([^}]*)\}',
      caseSensitive: false,
    ).allMatches(styles)) {
      for (final size in RegExp(
        r'(?:^|;)\s*size\s*:\s*([^;}]+)',
        caseSensitive: false,
      ).allMatches(page[1]!)) {
        final value = size[1]!.toLowerCase();
        if (value.contains('landscape')) {
          explicit = true;
        } else if (value.contains('portrait') ||
            RegExp(r'^a4\s*(?:!important)?$').hasMatch(value.trim())) {
          explicit = false;
        } else {
          final dimensions = RegExp(
            r'([\d.]+)\s*mm',
          ).allMatches(value).toList();
          if (dimensions.length == 2) {
            explicit =
                double.parse(dimensions[0][1]!) >
                double.parse(dimensions[1][1]!);
          }
        }
      }
    }
    if (explicit != null) return explicit;
    for (final row in doc.querySelectorAll('table tr')) {
      var columns = 0;
      for (final cell in row.children.where(
        (e) => ['td', 'th'].contains(e.localName),
      )) {
        columns += int.tryParse(cell.attributes['colspan'] ?? '1') ?? 1;
      }
      if (columns >= 8) return true;
    }
    return false;
  }

  static void apply(Document doc, {required bool landscape}) {
    // The invoice designer already has a paginated A4 composition: preserve it.
    if (doc.querySelector('.a4-paper') != null) return;
    doc.documentElement!.classes.add('portal-pdf-report');
    for (final table in doc.querySelectorAll('table')) {
      Element? parent = table.parent;
      while (parent != null && parent.localName != 'html') {
        if (![
          'td',
          'th',
          'tr',
          'tbody',
          'thead',
          'tfoot',
          'table',
        ].contains(parent.localName)) {
          parent.classes.add('portal-print-expand');
        }
        parent = parent.parent;
      }
    }
    doc.head!.append(
      Element.tag('style')
        ..text =
            '''
@page { size: A4 ${landscape ? 'landscape' : 'portrait'}; margin: 10mm; }
html.portal-pdf-report,html.portal-pdf-report body {
  width:auto!important;min-width:0!important;max-width:none!important;
  height:auto!important;min-height:0!important;overflow:visible!important;
  margin:0!important;padding:0!important;background:#fff!important;
  -webkit-print-color-adjust:exact;print-color-adjust:exact;
}
html.portal-pdf-report body .portal-print-expand {
  display:block!important;position:static!important;overflow:visible!important;
  width:auto!important;min-width:0!important;max-width:100%!important;
  height:auto!important;max-height:none!important;min-height:0!important;
}
html.portal-pdf-report body .panel {padding:0!important;border:0!important;box-shadow:none!important;}
html.portal-pdf-report body table {
  table-layout:fixed!important;width:100%!important;min-width:0!important;
  max-width:100%!important;white-space:normal!important;border-collapse:collapse!important;
}
html.portal-pdf-report body :is(th,td,col) {
  width:auto!important;min-width:0!important;max-width:none!important;
  white-space:normal!important;overflow-wrap:anywhere!important;word-break:normal!important;
}
html.portal-pdf-report body :is(th,td) {
  font-size:${landscape ? '9' : '10'}px!important;padding:5px 4px!important;
  line-height:1.5!important;position:static!important;overflow:visible!important;
}
html.portal-pdf-report body thead {display:table-header-group!important;}
html.portal-pdf-report body tfoot {display:table-footer-group!important;}
html.portal-pdf-report body tr {break-inside:avoid;page-break-inside:avoid;}
html.portal-pdf-report body .account-summary {display:grid!important;grid-template-columns:repeat(3,minmax(0,1fr))!important;gap:10px!important;}
html.portal-pdf-report body .balance-card {min-width:0!important;break-inside:avoid;}
html.portal-pdf-report body .balance-card .amount {font-size:20px!important;}
html.portal-pdf-report body [hidden] {display:none!important;}
html.portal-pdf-report body button {display:none!important;}
''',
    );
  }
}
