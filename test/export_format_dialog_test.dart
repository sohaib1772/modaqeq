import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:modaqeq_maktabali/models/export_format.dart';
import 'package:modaqeq_maktabali/views/export_format_dialog.dart';

void main() {
  for (final choice in ['PDF', 'Excel', 'إلغاء']) {
    testWidgets('share chooser returns $choice and closes', (tester) async {
      ExportFormat? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  result = await showDialog<ExportFormat>(
                    context: context,
                    builder: (_) => const ExportFormatDialog(),
                  );
                },
                child: const Text('فتح'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('فتح'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(choice));
      await tester.pumpAndSettle();
      expect(find.byType(ExportFormatDialog), findsNothing);
      expect(
        result,
        choice == 'PDF'
            ? ExportFormat.pdf
            : choice == 'Excel'
            ? ExportFormat.excel
            : null,
      );
    });
  }
}
