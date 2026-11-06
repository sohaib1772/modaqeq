import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:almizan_mobile/controllers/portal_controller.dart';
import 'package:almizan_mobile/views/portal_view.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() => Get.reset());
  testWidgets('Arabic setup rejects unsafe address without a network request', (
    tester,
  ) async {
    Get.put(PortalController());
    await tester.pumpWidget(
      GetMaterialApp(
        locale: const Locale('ar'),
        supportedLocales: const [Locale('ar')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: const PortalView(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('المدقق المحاسبي'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'http://example.com');
    await tester.ensureVisible(find.text('اتصال آمن'));
    await tester.tap(find.text('اتصال آمن'));
    await tester.pumpAndSettle();
    expect(find.textContaining('راجع بيانات الاتصال'), findsOneWidget);
    expect(Get.find<PortalController>().verified.value, isFalse);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'bound installation exposes no address editor or change-server action',
    (tester) async {
      final portal = Get.put(PortalController());
      portal.serverLocked.value = true;
      portal.error.value = 'تعذر الاتصال الآن.';
      await tester.pumpWidget(
        GetMaterialApp(
          locale: const Locale('ar'),
          supportedLocales: const [Locale('ar')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: const PortalView(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNothing);
      expect(find.byType(AppBar), findsNothing);
      expect(find.text('تغيير السيرفر'), findsNothing);
      expect(find.text('إعادة المحاولة'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
