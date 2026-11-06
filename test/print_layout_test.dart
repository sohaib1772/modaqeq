import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart';
import 'package:modaqeq_maktabali/services/print_document.dart';
import 'package:modaqeq_maktabali/services/portal_transport.dart';
import 'package:modaqeq_maktabali/models/server_address.dart';

void main() {
  final server = ServerAddress.parse('fixture.example');
  Future<dynamic> prepare(String html) =>
      PrintDocument(PortalTransport(), server).prepareDocument(html);
  test(
    'operational notices are omitted, financial notes and all cells stay',
    () async {
      final result = await prepare(
        '''<html><body>
      <header class="app-chrome">قائمة الموقع</header>
      <main><div class="panel"><h3>كشف الحساب</h3>
      <p class="note">الرصيد النهائي يتضمن الرصيد السابق للمدة.</p>
      <div class="scroll"><table><tr><th>البيان</th><th>مدين</th><th>دائن</th></tr>
      <tr><td>فاتورة رقم 123</td><td>12000</td><td>0</td></tr></table></div></div>
      <div class="note">شغّله على شبكة موثوقة؛ اتصال HTTP غير مشفّر.</div></main>
      <aside role="alert">تنتهي الجلسة بعد 12 ساعة. تسجيل الدخول</aside></body></html>''',
      );
      final doc = parse(result.html);
      expect(doc.querySelectorAll('table td').map((e) => e.text), [
        'فاتورة رقم 123',
        '12000',
        '0',
      ]);
      expect(doc.body!.text, contains('الرصيد النهائي يتضمن الرصيد السابق'));
      expect(doc.body!.text, isNot(contains('تسجيل الدخول')));
      expect(doc.body!.text, isNot(contains('HTTP')));
      expect(doc.body!.text, isNot(contains('قائمة الموقع')));
    },
  );
  test(
    'website maintenance banner never enters invoice or statement PDF',
    () async {
      final result = await prepare(
        '''<html><body><div class="a4-paper"><h1>فاتورة</h1><table><tr><td>1000</td></tr></table></div>
      <aside role="status" style="margin:12px 20px;padding:14px;border:1px solid #e6b96e;background:#fff4df">
      تنبيه الفترة 1-2: 15 اختلاف يحتاج مراجعة، و0 فاتورة غير مرحّلة مخزنياً.
      <a href="/maintenance">فحص البيانات والمعالجة اليدوية</a></aside></body></html>''',
      );
      expect(parse(result.html).body!.text, contains('1000'));
      expect(parse(result.html).body!.text, isNot(contains('تنبيه الفترة')));
      expect(parse(result.html).querySelector('aside'), isNull);
    },
  );
  test(
    'wide statement uses A4 landscape and overrides scrolling/minimum width',
    () async {
      final headers = List.generate(12, (i) => '<th>حقل $i</th>').join();
      final cells = List.generate(12, (i) => '<td>قيمة $i</td>').join();
      final result = await prepare(
        '<style>.scroll{overflow:auto;max-height:72vh}table{min-width:1400px;white-space:nowrap}</style><div class="scroll"><table><tr>$headers</tr><tr>$cells</tr></table></div>',
      );
      expect(result.landscape, true);
      final doc = parse(result.html);
      expect(doc.querySelectorAll('td').length, 12);
      expect(
        doc.querySelector('.scroll')!.classes,
        contains('portal-print-expand'),
      );
      expect(result.html, contains('table-layout:fixed!important'));
      expect(result.html, contains('size: A4 landscape'));
    },
  );
  test(
    'explicit report orientation is honored and hidden rows stay hidden',
    () async {
      final result = await prepare(
        '<style>@page{size:A4 landscape}@page{size:A4 portrait}</style><table><tr hidden><td>مسودة مخفية</td></tr><tr><td>فاتورة</td></tr></table>',
      );
      expect(result.landscape, false);
      expect(
        parse(
          result.html,
        ).querySelector('tr')!.attributes.containsKey('hidden'),
        true,
      );
    },
  );
  test('A4 designer invoice geometry is preserved', () async {
    final result = await prepare(
      '<style>@page{size:297mm 210mm}.a4-paper{width:297mm;height:210mm}</style><div class="a4-paper"><table><tr><td>فاتورة مصممة</td></tr></table></div>',
    );
    expect(result.landscape, true);
    expect(result.html, isNot(contains('portal-pdf-report')));
    expect(result.html, contains('width:297mm;height:210mm'));
  });
  test(
    'rendered invoice pages survive dialog cleanup with their painted content',
    () async {
      final result = await prepare(
        '''<html><head><style>
      @page{size:A4 portrait;margin:0}.a4-paper{width:210mm;height:297mm;position:relative}
      .print-element{position:absolute}#designPreview:not([open]){display:none!important}
      </style></head><body class="print-view"><div class="design-workspace"><div class="a4-paper design-mode">EDITOR_ONLY</div></div>
      <dialog id="designPreview" open><div class="print-controls"><button>طباعة</button></div><div id="printPages">
      <div class="a4-paper"><div class="print-element" style="left:15mm;top:20mm;width:100mm;height:20mm">INVOICE_123 — فاتورة بيع</div><table><tr><td>الإجمالي</td><td>25000</td></tr></table></div>
      <div class="a4-paper"><div class="print-element" style="top:20mm">PAGE_2 — الصفحة الثانية</div></div>
      </div></dialog><aside role="status">تنبيه الفترة</aside></body></html>''',
      );
      final doc = parse(result.html);
      expect(doc.querySelectorAll('#printPages > .a4-paper').length, 2);
      expect(doc.body!.text, contains('INVOICE_123'));
      expect(doc.body!.text, contains('25000'));
      expect(doc.body!.text, contains('PAGE_2'));
      expect(doc.body!.text, isNot(contains('EDITOR_ONLY')));
      expect(doc.querySelector('dialog'), isNull);
      expect(
        doc.querySelector('.print-element')!.attributes['style'],
        contains('left:15mm'),
      );
      expect(result.html, isNot(contains('portal-pdf-report')));
      expect(result.landscape, false);
    },
  );
  test('empty invoice preview fails rather than sharing a blank PDF', () async {
    await expectLater(
      prepare('<dialog><div id="printPages"></div></dialog>'),
      throwsFormatException,
    );
  });
}
