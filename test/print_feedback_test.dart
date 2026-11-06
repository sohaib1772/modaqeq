import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:almizan_mobile/controllers/portal_controller.dart';
import 'package:almizan_mobile/views/print_progress_overlay.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'repeat preparation does not create another timer or operation',
    () async {
      final portal = PortalController();
      portal.beginPrintPreparation();
      final timer = portal.printPreparationTimer;
      portal.beginPrintPreparation();
      expect(portal.printPreparationTimer, same(timer));
      expect(portal.printMessage.value, 'جارٍ تجهيز ملف PDF…');
      await portal.finishPrintPreparation();
      expect(portal.printMessage.value, isEmpty);
      expect(timer!.isActive, false);
    },
  );
  test('page errors cannot unlock an active native PDF operation', () async {
    final portal = PortalController();
    portal.beginPrintPreparation();
    portal.operation = true;
    await portal.finishPrintPreparation();
    expect(portal.printMessage.value, isNotEmpty);
    portal.clearPrintFeedback();
  });
  testWidgets('progress message blocks a second print tap', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              Center(
                child: FilledButton(
                  onPressed: () => taps++,
                  child: const Text('طباعة'),
                ),
              ),
              const Positioned.fill(
                child: PrintProgressOverlay(message: 'جارٍ تجهيز ملف PDF…'),
              ),
            ],
          ),
        ),
      ),
    );
    expect(find.text('جارٍ تجهيز ملف PDF…'), findsOneWidget);
    await tester.tap(find.text('طباعة'), warnIfMissed: false);
    await tester.pump();
    expect(taps, 0);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}
