import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:modaqeq_maktabali/services/pdf_exporter.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(
    () => binding.defaultBinaryMessenger.setMockMethodCallHandler(
      PdfExporter.channel,
      null,
    ),
  );
  test(
    'PDF export returns valid bytes from a single native conversion',
    () async {
      var calls = 0;
      binding.defaultBinaryMessenger.setMockMethodCallHandler(
        PdfExporter.channel,
        (call) async {
          expect(call.method, 'convert');
          expect((call.arguments as Map)['html'], '<p>فاتورة</p>');
          expect((call.arguments as Map)['landscape'], true);
          calls++;
          return Uint8List.fromList('%PDF-1.7\nfixture'.codeUnits);
        },
      );
      final result = await PdfExporter().convert(
        '<p>فاتورة</p>',
        landscape: true,
      );
      expect(String.fromCharCodes(result.take(5)), '%PDF-');
      expect(calls, 1);
    },
  );
  test('export refuses non-PDF data returned by a platform', () async {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      PdfExporter.channel,
      (_) async => Uint8List.fromList('<html>'.codeUnits),
    );
    await expectLater(
      PdfExporter().convert('<p>فاتورة</p>'),
      throwsFormatException,
    );
  });
  test('cancelling calls the native cancellation method', () async {
    var cancelled = false;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      PdfExporter.channel,
      (call) async {
        expect(call.method, 'cancel');
        cancelled = true;
        return null;
      },
    );
    await PdfExporter().cancel();
    expect(cancelled, true);
  });
}
