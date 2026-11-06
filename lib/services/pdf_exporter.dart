import 'package:flutter/services.dart';

class PdfExporter {
  static const channel = MethodChannel('portal/pdf');
  Future<Uint8List> convert(String html, {bool landscape = false}) async {
    final bytes = await channel.invokeMethod<Uint8List>('convert', {
      'html': html,
      'landscape': landscape,
    });
    if (bytes == null ||
        bytes.length < 5 ||
        bytes.length > 32 * 1024 * 1024 ||
        String.fromCharCodes(bytes.take(5)) != '%PDF-') {
      throw const FormatException('تعذر تجهيز الملف.');
    }
    return bytes;
  }

  Future<void> cancel() async {
    try {
      await channel.invokeMethod<void>('cancel');
    } on PlatformException {
      /* Conversion may already have completed. */
    } on MissingPluginException {
      /* No native renderer in Dart-only tests. */
    }
  }
}
