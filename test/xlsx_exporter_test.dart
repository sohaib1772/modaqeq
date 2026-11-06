import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xml/xml.dart';
import 'package:modaqeq_maktabali/services/xlsx_exporter.dart';

XmlDocument sheet(XlsxDocument result) {
  final archive = ZipDecoder().decodeBytes(result.bytes);
  expect(archive.findFile('xl/workbook.xml'), isNotNull);
  return XmlDocument.parse(
    utf8.decode(archive.findFile('xl/worksheets/sheet1.xml')!.content),
  );
}

void main() {
  test(
    'statement product details retain parent movement and exchange note',
    () {
      final result = buildXlsx(
        '''<h1>كشف الحساب</h1><table><tr><th>البيان</th><th>مدين</th></tr>
      <tr><td>فاتورة 123</td><td>25000</td></tr><tr class="invoice-items"><td colspan="2"><p>سعر الصرف 1500</p><strong>منتجات الفاتورة</strong><table><tr><th>المادة</th><th>الكمية</th></tr><tr><td>منتج أ</td><td>2</td></tr></table></td></tr>
      <tr><td>فاتورة 124</td><td>3000</td></tr><tr class="invoice-items"><td colspan="2"><table><tr><th>المادة</th><th>الكمية</th></tr><tr><td>منتج ب</td><td>1</td></tr></table></td></tr></table>''',
      );
      final values = sheet(
        result,
      ).findAllElements('t').map((e) => e.innerText).toList();
      expect(
        values,
        containsAll([
          'تفاصيل الحركة: فاتورة 123 | 25000',
          'سعر الصرف 1500',
          'منتج أ',
          'تفاصيل الحركة: فاتورة 124 | 3000',
          'منتج ب',
        ]),
      );
      expect(
        values.indexOf('منتج أ'),
        lessThan(values.indexOf('تفاصيل الحركة: فاتورة 124 | 3000')),
      );
    },
  );
  test('wide Arabic statements retain every row and field in real XLSX', () {
    final headers = List.generate(12, (c) => '<th>حقل $c</th>').join();
    final rows = List.generate(
      120,
      (r) =>
          '<tr>${List.generate(12, (c) => '<td>R${r + 1}C$c</td>').join()}</tr>',
    ).join();
    final result = buildXlsx(
      '<title>النظام</title><h1>كشف الحساب</h1><p class="note">الفترة 2026</p><table><thead><tr>$headers</tr></thead><tbody>$rows</tbody></table><aside role="status">تحذير الموقع</aside>',
    );
    final xml = sheet(result);
    expect(result.title, 'كشف الحساب');
    expect(result.dataRows, 120);
    final values = xml.findAllElements('t').map((e) => e.innerText).toList();
    for (var r = 1; r <= 120; r++) {
      for (var c = 0; c < 12; c++) {
        expect(values, contains('R${r}C$c'));
      }
    }
    expect(values, isNot(contains('تحذير الموقع')));
    expect(
      xml.findAllElements('sheetView').single.getAttribute('rightToLeft'),
      '1',
    );
    expect(
      xml.findAllElements('pageSetup').single.getAttribute('orientation'),
      'landscape',
    );
    expect(xml.findAllElements('autoFilter'), hasLength(1));
    Directory('validation/xlsx').createSync(recursive: true);
    File('validation/xlsx/statement.xlsx').writeAsBytesSync(result.bytes);
  });

  test(
    'inventory numbers calculate; codes, dates and formula-like text stay text',
    () {
      final result = buildXlsx(
        '''<h1>المخزن</h1><table><tr><th>كود المادة</th><th>البيان</th><th>الكمية</th><th>الرصيد</th><th>التاريخ</th><th>رقم</th><th hidden>الكلفة</th></tr>
      <tr><td>00123</td><td>=HYPERLINK("https://example.com")</td><td>١٢٫٣٤٥٦</td><td>١٬٢٣٤٫٥٠-</td><td>2026-11-06</td><td>1234567890123456</td><td hidden>سرية</td></tr></table>''',
      );
      final xml = sheet(result);
      final cells = xml.findAllElements('c').toList();
      final numeric = cells
          .where((c) => c.getElement('v') != null)
          .map((c) => c.getElement('v')!.innerText);
      expect(numeric, ['12.3456', '-1234.50']);
      expect(xml.findAllElements('f'), isEmpty);
      final values = xml.findAllElements('t').map((e) => e.innerText);
      expect(
        values,
        containsAll([
          '00123',
          '1234567890123456',
          '2026-11-06',
          '=HYPERLINK("https://example.com")',
        ]),
      );
      expect(values, isNot(contains('سرية')));
      File('validation/xlsx/inventory.xlsx').writeAsBytesSync(result.bytes);
    },
  );

  test('paginated invoice joins headers but retains identical product lines', () {
    const table =
        '<table><thead><tr><th>المادة</th><th>الكمية</th><th>السعر</th></tr></thead><tbody><tr><td>مادة أ</td><td>2</td><td>12500</td></tr><tr><td>مادة أ</td><td>2</td><td>12500</td></tr></tbody></table>';
    final result = buildXlsx(
      '<div class="design-mode a4-paper">محرر</div><dialog><div id="printPages"><div class="a4-paper"><div class="print-element">فاتورة 123</div><div class="print-element">العميل: علي</div><div class="print-element">$table</div></div><div class="a4-paper"><div class="print-element">$table</div><div class="print-element">الإجمالي: 100000</div></div></div></dialog>',
    );
    final xml = sheet(result);
    final values = xml.findAllElements('t').map((e) => e.innerText).toList();
    expect(result.dataRows, 4);
    expect(values.where((v) => v == 'المادة'), hasLength(1));
    expect(values.where((v) => v == 'مادة أ'), hasLength(4));
    expect(values, containsAll(['العميل: علي', 'الإجمالي: 100000']));
    expect(values, isNot(contains('محرر')));
    File('validation/xlsx/invoice.xlsx').writeAsBytesSync(result.bytes);
  });

  test(
    'empty or unprepared export is rejected instead of a blank workbook',
    () {
      expect(() => buildXlsx('<h1>لا بيانات</h1>'), throwsFormatException);
      expect(
        () => buildXlsx('<div id="printPages"></div>'),
        throwsFormatException,
      );
    },
  );
}
