import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:html/dom.dart';
import 'package:html/parser.dart' as html;
import 'package:xml/xml.dart';
import 'print_layout.dart';

class XlsxDocument {
  final String title;
  final Uint8List bytes;
  final int dataRows;
  const XlsxDocument(this.title, this.bytes, this.dataRows);
}

XlsxDocument buildXlsx(String source) => XlsxExporter().convert(source);

class _Row {
  final List<String> values;
  final bool header;
  _Row(this.values, this.header);
}

/// A real OOXML workbook. No macros, external links or executable formulas.
/// Tables come from the authorized export snapshot, never from a second API.
class XlsxExporter {
  static const _sheetNs =
      'http://schemas.openxmlformats.org/spreadsheetml/2006/main';
  static const _rels =
      'http://schemas.openxmlformats.org/package/2006/relationships';
  static const mime =
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';

  XlsxDocument convert(String source) {
    if (utf8.encode(source).length > 2 * 1024 * 1024) {
      throw const FormatException('حجم التقرير كبير جداً.');
    }
    final doc = html.parse(source);
    PrintLayout.extractInvoicePages(doc);
    PrintLayout.removeInterface(doc);
    doc
        .querySelectorAll(
          'script,style,link,iframe,object,embed,form,button,input,textarea,select,svg,math',
        )
        .forEach((e) => e.remove());
    final title = _text(
      doc.querySelector('.invoice-tools h3') ??
          doc.querySelector('h1,h2,h3') ??
          doc.querySelector('title'),
    );
    final name = title.isEmpty ? 'تقرير' : title;
    final metadata = <String>[];
    final seenMetadata = <String>{};
    for (final node in doc.querySelectorAll(
      'h1,h2,h3,.balance-card,.note,.muted,.invoice-party,.invoice-totals>div,.print-element',
    )) {
      if (_hidden(node) ||
          node.querySelector('table') != null ||
          _inside(node, 'table')) {
        continue;
      }
      final value = _text(node);
      if (value.isNotEmpty && value != name && seenMetadata.add(value)) {
        metadata.add(value);
      }
    }
    final groups = <String, List<_Row>>{};
    var totalRows = 0;
    for (final table in doc.querySelectorAll('table')) {
      if (_hidden(table)) continue;
      final rows = <_Row>[];
      for (final tr in table.querySelectorAll('tr')) {
        if (_hidden(tr) ||
            _nearestTable(tr) != table ||
            tr.querySelector('table') != null) {
          continue;
        }
        final values = <String>[];
        final cells = tr.children
            .where((c) => c.localName == 'td' || c.localName == 'th')
            .toList();
        for (final cell in cells) {
          if (_hidden(cell)) continue;
          values.add(_text(cell));
          final span = int.tryParse(cell.attributes['colspan'] ?? '1') ?? 1;
          if (span < 1 || span > 64) {
            throw const FormatException('عدد أعمدة التقرير غير مدعوم.');
          }
          for (var i = 1; i < span; i++) {
            values.add('');
          }
        }
        if (values.isEmpty) continue;
        if (values.length > 64 || ++totalRows > 50000) {
          throw const FormatException('التقرير أكبر من الحجم المدعوم.');
        }
        rows.add(
          _Row(
            values,
            cells.any((c) => c.localName == 'th') || _inside(tr, 'thead'),
          ),
        );
      }
      if (rows.isEmpty) continue;
      // Statement exports may contain one products table per transaction.
      // Carry its parent transaction and exchange-rate notes with the detail
      // table so the spreadsheet never loses the relationship or financial note.
      final nested = _inside(table, 'table');
      if (nested) {
        Element? detail = table.parent;
        while (detail != null && detail.localName != 'tr') {
          detail = detail.parent;
        }
        final context =
            detail?.previousElementSibling?.children
                .where((e) => e.localName == 'td' || e.localName == 'th')
                .map(_text)
                .join(' | ') ??
            '';
        final notes =
            detail
                ?.querySelectorAll('p,strong,h3')
                .where((e) => _nearestTable(e) != table)
                .map(_text)
                .where((s) => s.isNotEmpty)
                .toSet() ??
            <String>{};
        rows.insertAll(0, [
          if (context.isNotEmpty) _Row(['تفاصيل الحركة: $context'], false),
          ...notes.map((s) => _Row([s], false)),
        ]);
      }
      final headers = rows
          .where((r) => r.header)
          .map((r) => r.values.join('\u001f'))
          .join('\u001e');
      // Join paginated invoice tables with matching headers, without removing
      // duplicate product lines or repeating each printed page's header.
      final key =
          headers.isEmpty ||
              nested ||
              !doc.documentElement!.classes.contains('portal-pdf-invoice')
          ? 'table-${groups.length}'
          : headers;
      if (groups.containsKey(key)) {
        groups[key]!.addAll(rows.where((r) => !r.header));
      } else {
        groups[key] = rows;
      }
    }
    if (groups.isEmpty) {
      throw const FormatException(
        'لا يوجد جدول جاهز للمشاركة. افتح التقرير أو معاينة الفاتورة أولاً.',
      );
    }
    final rows = <_Row>[
      _Row([name], true),
      ...metadata.map((t) => _Row([t], false)),
      _Row([], false),
    ];
    final tableStarts = <int>[];
    var dataRows = 0;
    for (final group in groups.values) {
      tableStarts.add(rows.length);
      rows.addAll(group);
      dataRows += group.where((r) => !r.header).length;
      rows.add(_Row([], false));
    }
    final width = groups.values
        .expand((g) => g)
        .map((r) => r.values.length)
        .reduce((a, b) => a > b ? a : b);
    if (rows.length * width > 300000) {
      throw const FormatException('التقرير أكبر من الحجم المدعوم.');
    }
    final builder = XmlBuilder();
    builder.processing(
      'xml',
      'version="1.0" encoding="UTF-8" standalone="yes"',
    );
    builder.element(
      'worksheet',
      namespaces: {_sheetNs: ''},
      nest: () {
        builder.element(
          'sheetPr',
          nest: () =>
              builder.element('pageSetUpPr', attributes: {'fitToPage': '1'}),
        );
        builder.element(
          'sheetViews',
          nest: () => builder.element(
            'sheetView',
            attributes: {'workbookViewId': '0', 'rightToLeft': '1'},
            nest: () {
              final frozen = tableStarts.first + 1;
              builder.element(
                'pane',
                attributes: {
                  'ySplit': '$frozen',
                  'topLeftCell': 'A${frozen + 1}',
                  'activePane': 'bottomLeft',
                  'state': 'frozen',
                },
              );
            },
          ),
        );
        builder.element(
          'sheetFormatPr',
          attributes: {'defaultRowHeight': '20'},
        );
        builder.element(
          'cols',
          nest: () {
            for (var i = 0; i < width; i++) {
              builder.element(
                'col',
                attributes: {
                  'min': '${i + 1}',
                  'max': '${i + 1}',
                  'width': i == 0 ? '24' : '20',
                  'customWidth': '1',
                },
              );
            }
          },
        );
        builder.element(
          'sheetData',
          nest: () {
            List<String> headers = [];
            for (var r = 0; r < rows.length; r++) {
              final row = rows[r];
              if (tableStarts.contains(r)) {
                headers = row.header ? row.values : [];
              }
              if (r > 0 && row.header) headers = row.values;
              builder.element(
                'row',
                attributes: {
                  'r': '${r + 1}',
                  'ht': r == 0
                      ? '36'
                      : row.header
                      ? '40'
                      : r < tableStarts.first
                      ? '${24 * ((row.values.firstOrNull?.length ?? 0) / (width * 12)).ceil().clamp(1, 16)}'
                      : '${24 * row.values.fold<int>(1, (height, text) {
                              final lines = (text.length / 18).ceil().clamp(1, 16);
                              return lines > height ? lines : height;
                            })}',
                  'customHeight': '1',
                },
                nest: () {
                  for (var c = 0; c < row.values.length; c++) {
                    final value = row.values[c];
                    if (value.length > 32767) {
                      throw const FormatException(
                        'أحد حقول التقرير طويل جداً.',
                      );
                    }
                    final number = !row.header && r >= tableStarts.first
                        ? _number(value, c < headers.length ? headers[c] : '')
                        : null;
                    final style = r == 0
                        ? 1
                        : row.header
                        ? 2
                        : number != null
                        ? 4
                        : r % 2 == 0
                        ? 5
                        : 3;
                    builder.element(
                      'c',
                      attributes: {
                        'r': '${_column(c)}${r + 1}',
                        's': '$style',
                        if (number == null) 't': 'inlineStr',
                      },
                      nest: () {
                        if (number != null) {
                          builder.element('v', nest: number);
                        } else {
                          builder.element(
                            'is',
                            nest: () => builder.element(
                              't',
                              attributes: {'xml:space': 'preserve'},
                              nest: value,
                            ),
                          );
                        }
                      },
                    );
                  }
                },
              );
            }
          },
        );
        if (groups.length == 1 && groups.values.first.first.header) {
          final start = tableStarts.first + 1,
              end = tableStarts.first + groups.values.first.length;
          builder.element(
            'autoFilter',
            attributes: {'ref': 'A$start:${_column(width - 1)}$end'},
          );
        }
        if (width > 1) {
          builder.element(
            'mergeCells',
            attributes: {'count': '${tableStarts.first - 1}'},
            nest: () {
              for (var r = 1; r < tableStarts.first; r++) {
                builder.element(
                  'mergeCell',
                  attributes: {'ref': 'A$r:${_column(width - 1)}$r'},
                );
              }
            },
          );
        }
        builder.element(
          'pageMargins',
          attributes: {
            'left': '0.3',
            'right': '0.3',
            'top': '0.4',
            'bottom': '0.4',
            'header': '0.2',
            'footer': '0.2',
          },
        );
        builder.element(
          'pageSetup',
          attributes: {
            'paperSize': '9',
            'orientation': width >= 8 ? 'landscape' : 'portrait',
            'fitToWidth': '1',
            'fitToHeight': '0',
          },
        );
      },
    );
    final archive = Archive();
    void add(String path, String content) {
      final bytes = utf8.encode(content);
      archive.addFile(ArchiveFile(path, bytes.length, bytes));
    }

    add(
      '[Content_Types].xml',
      '''<?xml version="1.0" encoding="UTF-8"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/><Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/></Types>''',
    );
    add(
      '_rels/.rels',
      '<Relationships xmlns="$_rels"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>',
    );
    add(
      'xl/workbook.xml',
      '<workbook xmlns="$_sheetNs" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="التقرير" sheetId="1" r:id="rId1"/></sheets></workbook>',
    );
    add(
      'xl/_rels/workbook.xml.rels',
      '<Relationships xmlns="$_rels"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/></Relationships>',
    );
    add('xl/styles.xml', _styles);
    add('xl/worksheets/sheet1.xml', builder.buildDocument().toXmlString());
    return XlsxDocument(
      name,
      Uint8List.fromList(ZipEncoder().encode(archive)),
      dataRows,
    );
  }

  static bool _inside(Element node, String tag) {
    for (Element? p = node.parent; p != null; p = p.parent) {
      if (p.localName == tag) return true;
    }
    return false;
  }

  static Element? _nearestTable(Element node) {
    for (Element? p = node.parent; p != null; p = p.parent) {
      if (p.localName == 'table') return p;
    }
    return null;
  }

  static bool _hidden(Element node) {
    for (Element? p = node; p != null; p = p.parent) {
      if (p.attributes.containsKey('hidden') ||
          RegExp(
            r'display\s*:\s*none|visibility\s*:\s*hidden',
            caseSensitive: false,
          ).hasMatch(p.attributes['style'] ?? '')) {
        return true;
      }
    }
    return false;
  }

  static String _text(Element? e) => (e?.text ?? '')
      .replaceAll(RegExp(r'[\u0000-\u0008\u000b\u000c\u000e-\u001f]'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  static String _column(int c) {
    var s = '';
    for (var n = c + 1; n > 0; n = (n - 1) ~/ 26) {
      s = String.fromCharCode(65 + (n - 1) % 26) + s;
    }
    return s;
  }

  static String? _number(String value, String header) {
    if (!RegExp(
          r'كمية|الكمية|رصيد|الرصيد|مدين|دائن|سعر|السعر|كلفة|مبلغ|إجمالي|اجمالي|الإجمالي|حسم|خصم|نسبة|قيمة',
        ).hasMatch(header) ||
        RegExp(r'رقم|رمز|كود|باركود|معرف|مرجع').hasMatch(header)) {
      return null;
    }
    var s = value
        .replaceAll(RegExp(r'[\u200e\u200f\u061c\u2066-\u2069]'), '')
        .trim();
    for (var i = 0; i < 10; i++) {
      s = s.replaceAll('٠١٢٣٤٥٦٧٨٩'[i], '$i').replaceAll('۰۱۲۳۴۵۶۷۸۹'[i], '$i');
    }
    s = s.replaceAll('٬', ',').replaceAll('٫', '.').replaceAll('−', '-');
    if (s.startsWith('(') && s.endsWith(')')) {
      s = '-${s.substring(1, s.length - 1)}';
    }
    if (s.endsWith('-')) s = '-${s.substring(0, s.length - 1)}';
    if (!RegExp(r'^-?(?:\d+|\d{1,3}(?:,\d{3})+)(?:\.\d+)?$').hasMatch(s)) {
      return null;
    }
    s = s.replaceAll(',', '');
    if (s
            .replaceAll(RegExp(r'[^0-9]'), '')
            .replaceFirst(RegExp(r'^0+'), '')
            .length >
        15) {
      return null;
    }
    return s;
  }

  static const _styles =
      '''<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><numFmts count="1"><numFmt numFmtId="164" formatCode="#,##0.###############;[Red](#,##0.###############)"/></numFmts><fonts count="3"><font><sz val="11"/><name val="Arial"/></font><font><b/><sz val="18"/><color rgb="FF12385B"/><name val="Arial"/></font><font><b/><sz val="11"/><color rgb="FFFFFFFF"/><name val="Arial"/></font></fonts><fills count="4"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill><fill><patternFill patternType="solid"><fgColor rgb="FF155C85"/><bgColor indexed="64"/></patternFill></fill><fill><patternFill patternType="solid"><fgColor rgb="FFF0F5FA"/><bgColor indexed="64"/></patternFill></fill></fills><borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders><cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs><cellXfs count="6"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/><xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" applyAlignment="1"><alignment horizontal="right" vertical="center" readingOrder="2"/></xf><xf numFmtId="0" fontId="2" fillId="2" borderId="0" xfId="0" applyAlignment="1" applyFill="1"><alignment horizontal="right" vertical="center" wrapText="1" readingOrder="2"/></xf><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0" applyAlignment="1"><alignment horizontal="right" vertical="center" wrapText="1" readingOrder="2"/></xf><xf numFmtId="164" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1" applyAlignment="1"><alignment horizontal="right" vertical="center"/></xf><xf numFmtId="0" fontId="0" fillId="3" borderId="0" xfId="0" applyAlignment="1" applyFill="1"><alignment horizontal="right" vertical="center" wrapText="1" readingOrder="2"/></xf></cellXfs><cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles></styleSheet>''';
}
