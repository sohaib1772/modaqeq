import 'package:flutter/material.dart';
import '../models/export_format.dart';

class ExportFormatDialog extends StatelessWidget {
  const ExportFormatDialog({super.key});
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('اختر صيغة المشاركة'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ListTile(
          leading: const Icon(Icons.picture_as_pdf_outlined),
          title: const Text('PDF'),
          subtitle: const Text('مستند جاهز للعرض والطباعة'),
          onTap: () => Navigator.pop(context, ExportFormat.pdf),
        ),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.table_chart_outlined),
          title: const Text('Excel'),
          subtitle: const Text('جدول قابل للتصفية والتحرير'),
          onTap: () => Navigator.pop(context, ExportFormat.excel),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('إلغاء'),
      ),
    ],
  );
}
