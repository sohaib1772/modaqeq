import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:almizan_mobile/controllers/portal_controller.dart';
import 'package:almizan_mobile/views/splash_view.dart';
import 'package:almizan_mobile/views/portal_view.dart';

void main() {
  tearDown(() => Get.reset());
  testWidgets(
    'animated splash reveals setup without overflow on a small phone',
    (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      Get.put(PortalController());
      await tester.pumpWidget(
        GetMaterialApp(
          locale: const Locale('ar'),
          supportedLocales: const [Locale('ar')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: const SplashView(),
        ),
      );
      await tester.pump(const Duration(milliseconds: 900));
      expect(find.text('المدقق المحاسبي'), findsOneWidget);
      expect(find.byType(PortalView), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpAndSettle();
      expect(find.byType(PortalView), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
