import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:get/get.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/server_address.dart';
import '../models/bridge_request.dart';
import '../services/portal_transport.dart';
import '../services/print_document.dart';
import '../services/server_binding.dart';
import '../services/pdf_exporter.dart';
import '../services/xlsx_exporter.dart';
import '../models/export_format.dart';
import '../views/export_format_dialog.dart';

class PortalController extends GetxController {
  final server = Rxn<ServerAddress>();
  final verified = false.obs, busy = false.obs;
  final serverLocked = false.obs;
  final error = ''.obs, progress = 0.0.obs;
  final printMessage = ''.obs;
  Timer? printPreparationTimer;
  final transport = PortalTransport();
  final address = TextEditingController();
  InAppWebViewController? web;
  final pdfExporter = PdfExporter();
  int generation = 0;
  final Set<String> seen = {};
  bool operation = false;
  bool choosingExportFormat = false;
  String? activeRequestId;
  Future<void> restore() async {
    final temp = await getTemporaryDirectory();
    await for (final entry in temp.list()) {
      if (entry is Directory &&
          entry.path.split(Platform.pathSeparator).last.startsWith('portal_')) {
        // A receiving app may still read the latest shared file.
        if (DateTime.now().difference((await entry.stat()).modified).inDays >=
            1) {
          await entry.delete(recursive: true);
        }
      }
    }
    final binding = ServerBinding(await SharedPreferences.getInstance());
    serverLocked.value = binding.isLocked;
    try {
      server.value = binding.read();
    } on FormatException {
      // Never unlock a saved installation automatically on corrupt storage.
      error.value = 'تعذر فتح الاتصال المحفوظ. تواصل مع مسؤول النظام.';
    }
  }

  Future<bool> confirm(String title, String message) async =>
      await Get.dialog<bool>(
        AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Get.back(result: false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () => Get.back(result: true),
              child: const Text('متابعة'),
            ),
          ],
        ),
      ) ??
      false;

  Future<List<String>?> credentials() async {
    final user = TextEditingController(), password = TextEditingController();
    final result = await Get.dialog<List<String>>(
      AlertDialog(
        title: const Text('التحقق من الوصول'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('أدخل بيانات الوصول التي زوّدك بها مسؤول النظام.'),
            TextField(
              controller: user,
              decoration: const InputDecoration(labelText: 'اسم المستخدم'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: password,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'كلمة المرور'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Get.back(), child: const Text('إلغاء')),
          FilledButton(
            onPressed: () => Get.back(result: [user.text, password.text]),
            child: const Text('دخول'),
          ),
        ],
      ),
    );
    // Dialog route disposal happens after its closing animation.
    Future.delayed(const Duration(seconds: 1), () {
      user.dispose();
      password.dispose();
    });
    return result;
  }

  Future<void> connect() async {
    if (busy.value) return;
    busy.value = true;
    error.value = '';
    try {
      final binding = ServerBinding(await SharedPreferences.getInstance());
      serverLocked.value = binding.isLocked;
      final candidate = binding.isLocked
          ? binding.read()!
          : ServerAddress.parse(address.text);
      try {
        await check(candidate);
      } on HttpException catch (e) {
        if (!e.message.contains('401')) rethrow;
        final auth = await credentials();
        if (auth == null) {
          throw const FormatException('تم إلغاء الدخول إلى البوابة.');
        }
        transport.authorize(
          candidate,
          'Basic ${base64Encode(utf8.encode('${auth[0]}:${auth[1]}'))}',
        );
        await check(candidate);
      }
      await binding.bind(candidate);
      server.value = candidate;
      serverLocked.value = true;
      address.clear();
      verified.value = true;
    } catch (e) {
      error.value = message(e);
    } finally {
      busy.value = false;
    }
  }

  Future<void> check(ServerAddress candidate) async {
    final body = await transport.bytes(
      candidate,
      candidate.resolve('/mobile-config'),
      limit: 65536,
    );
    final data = jsonDecode(utf8.decode(body));
    if (data is! Map ||
        data['application'] != 'business_portal' ||
        data['protocol_version'] != 1) {
      throw const FormatException(
        'تعذر الاتصال بهذا العنوان. تواصل مع مسؤول النظام.',
      );
    }
  }

  String message(Object e) => e is FormatException
      ? 'تعذر الاتصال بهذا العنوان. راجع بيانات الاتصال مع مسؤول النظام.'
      : 'تعذر الاتصال الآن. تحقق من الإنترنت ثم أعد المحاولة.';

  void invalidate() {
    clearPrintFeedback();
    generation++;
    transport.token.cancel();
    transport.token = CancelToken();
    unawaited(pdfExporter.cancel());
  }

  Future<void> created(InAppWebViewController controller) async {
    web = controller;
    final selected = server.value!;
    try {
      await controller.addWebMessageListener(
        WebMessageListener(
          jsObjectName: 'PortalPrintState',
          allowedOriginRules: {selected.toString()},
          onPostMessage: (message, origin, mainFrame, _) async {
            if (!mainFrame ||
                !selected.contains(origin) ||
                !selected.contains(await controller.getUrl())) {
              return;
            }
            if (message?.data == 'start') beginPrintPreparation();
            if (message?.data == 'finish') await finishPrintPreparation();
          },
        ),
      );
      await controller.addWebMessageListener(
        WebMessageListener(
          jsObjectName: 'PortalNative',
          allowedOriginRules: {selected.toString()},
          onPostMessage:
              (message, sourceOrigin, isMainFrame, replyProxy) async {
                if (isMainFrame &&
                    selected.contains(sourceOrigin) &&
                    message?.data is String) {
                  await handle(message!.data as String);
                }
              },
        ),
      );
      await controller.loadUrl(
        urlRequest: URLRequest(
          url: WebUri(selected.resolve('/login').toString()),
        ),
      );
    } catch (_) {
      error.value = 'تعذر فتح التطبيق. أعد المحاولة أو حدّث مكونات الجهاز.';
    }
  }

  Future<void> handle(String raw) async {
    final selected = server.value, controller = web;
    if (selected == null ||
        controller == null ||
        !selected.contains(await controller.getUrl())) {
      return;
    }
    BridgeRequest request;
    try {
      request = BridgeRequest.parse(raw, selected);
    } catch (_) {
      return;
    }
    if (seen.contains(request.id)) return;
    final epoch = generation;
    if (seen.length >= 4096) {
      await complete(
        request.id,
        false,
        'أعد فتح التطبيق لبدء عمليات جديدة.',
        epoch,
      );
      return;
    }
    seen.add(request.id);
    if (operation) {
      await complete(
        request.id,
        false,
        'انتظر انتهاء العملية الحالية أو أعد فتح التطبيق.',
        epoch,
      );
      return;
    }
    operation = true;
    activeRequestId = request.id;
    final hasPrintFeedback =
        request.type == 'print_html' || printMessage.value.isNotEmpty;
    if (hasPrintFeedback) {
      printPreparationTimer?.cancel();
      printMessage.value = 'جارٍ تجهيز ملف PDF…';
    }
    final timer = Timer(const Duration(seconds: 55), () async {
      if (epoch == generation) {
        if (choosingExportFormat && Get.isDialogOpen == true) Get.back();
        await complete(
          request.id,
          false,
          'انتهت المهلة. تحقق من العملية قبل تكرارها.',
          epoch,
        );
        if (activeRequestId == request.id && epoch == generation) invalidate();
      }
    });
    try {
      if (hasPrintFeedback) await WidgetsBinding.instance.endOfFrame;
      if (request.type == 'download') {
        await download(selected, Uri.parse(request.data['url']), epoch);
      } else {
        printMessage.value = 'اختر صيغة المشاركة';
        choosingExportFormat = true;
        ExportFormat? format;
        try {
          format = await Get.dialog<ExportFormat>(const ExportFormatDialog());
        } finally {
          choosingExportFormat = false;
        }
        if (format == null) throw const FormatException('تم إلغاء المشاركة.');
        if (epoch != generation) return;
        printMessage.value = format == ExportFormat.pdf
            ? 'جارٍ تجهيز ملف PDF…'
            : 'جارٍ تجهيز ملف Excel…';
        await WidgetsBinding.instance.endOfFrame;
        late Uint8List bytes;
        if (format == ExportFormat.pdf) {
          final document = await PrintDocument(
            transport,
            selected,
          ).prepareDocument(request.data['html']);
          if (epoch != generation) return;
          bytes = await pdfExporter.convert(
            document.html,
            landscape: document.landscape,
          );
        } else {
          bytes = (await compute(
            buildXlsx,
            request.data['html'] as String,
          )).bytes;
        }
        if (epoch != generation) return;
        final directory = await getTemporaryDirectory();
        final folder = await Directory(
          '${directory.path}/portal_${DateTime.now().microsecondsSinceEpoch}',
        ).create();
        final extension = format == ExportFormat.pdf ? 'pdf' : 'xlsx';
        final file = File('${folder.path}/مستند.$extension');
        await file.writeAsBytes(bytes, flush: true);
        if (epoch != generation) return;
        printMessage.value = 'جارٍ فتح المشاركة…';
        final result = await SharePlus.instance.share(
          ShareParams(
            files: [
              XFile(
                file.path,
                mimeType: format == ExportFormat.pdf
                    ? 'application/pdf'
                    : XlsxExporter.mime,
              ),
            ],
            excludedCupertinoActivities: [CupertinoActivityType.print],
            sharePositionOrigin: const Rect.fromLTWH(24, 80, 1, 1),
          ),
        );
        if (result.status == ShareResultStatus.dismissed) {
          throw const FormatException('تم إلغاء المشاركة.');
        }
      }
      await complete(request.id, true, 'تم فتح الواجهة الأصلية.', epoch);
    } catch (_) {
      await complete(
        request.id,
        false,
        'أُلغيت العملية أو تعذر تنفيذها. تحقق قبل تكرارها.',
        epoch,
      );
    } finally {
      timer.cancel();
      operation = false;
      activeRequestId = null;
      if (hasPrintFeedback) {
        clearPrintFeedback();
        await releasePrintClickGuard();
      }
    }
  }

  Future<void> complete(String id, bool ok, String text, int epoch) async {
    final controller = web, selected = server.value;
    if (controller == null ||
        selected == null ||
        epoch != generation ||
        !selected.contains(await controller.getUrl())) {
      return;
    }
    final args = [id, ok, text].map(jsonEncode).join(',');
    await controller.evaluateJavascript(
      source: 'window.PortalMobile?.complete($args);',
    );
  }

  Future<void> download(ServerAddress selected, Uri uri, int epoch) async {
    // Exactly one streaming GET. No HEAD/probe, retries, or redirects to other origins.
    final response = await transport.get(selected, uri);
    if ((response.headers.value('content-type') ?? '').contains('text/html')) {
      await response.data!.stream.drain<void>();
      throw const FormatException('انتهت الجلسة أو الرابط غير صالح للتنزيل.');
    }
    final dir = await getTemporaryDirectory();
    final folder = await Directory(
      '${dir.path}/portal_${DateTime.now().microsecondsSinceEpoch}',
    ).create();
    final disposition = response.headers.value('content-disposition') ?? '';
    final match = RegExp(
      r'''filename\*?=(?:UTF-8''|"?)([^";]+)''',
      caseSensitive: false,
    ).firstMatch(disposition);
    var name = match == null
        ? uri.pathSegments.lastOrNull ?? 'download.bin'
        : Uri.decodeComponent(match[1]!);
    name = name.replaceAll(RegExp(r'[^\w.\-\u0600-\u06ff]'), '_');
    if (name.isEmpty || name == '.' || name == '..') name = 'download.bin';
    final file = File('${folder.path}/$name');
    final sink = file.openWrite();
    var length = 0;
    try {
      await for (final chunk in response.data!.stream) {
        if (epoch != generation) throw const FormatException('أُلغيت العملية.');
        length += chunk.length;
        if (length > 256 * 1024 * 1024) {
          throw const FormatException('الملف أكبر من 256 ميغابايت.');
        }
        sink.add(chunk);
        await sink.flush();
      }
      await sink.flush();
      await sink.close();
      if (epoch != generation) return;
      final result = await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          sharePositionOrigin: const Rect.fromLTWH(24, 80, 1, 1),
        ),
      );
      if (result.status == ShareResultStatus.dismissed) {
        throw const FormatException('تم إلغاء المشاركة.');
      }
    } finally {
      await sink.close();
      // Keep shared files for the receiving app; purge after 24 hours on startup.
    }
  }

  Future<void> back() async {
    if (printMessage.value.isNotEmpty) return;
    if (await web?.canGoBack() ?? false) {
      final dirty = await web?.evaluateJavascript(
        source: "typeof editorDirty !== 'undefined' && editorDirty === true",
      );
      if (dirty == true) {
        if (!await confirm(
          'تغييرات غير محفوظة',
          'هل تريد مغادرة الفاتورة دون حفظ؟',
        )) {
          return;
        }
        await web?.evaluateJavascript(
          source:
              "if (typeof editorDirty !== 'undefined') editorDirty = false;",
        );
      }
      await web?.goBack();
      return;
    }
    if (await confirm(
      'مغادرة التطبيق',
      'احفظ أي تغييرات قبل إغلاق التطبيق. هل تريد المغادرة؟',
    )) {
      await SystemNavigator.pop();
    }
  }

  void beginPrintPreparation() {
    if (operation || printMessage.value.isNotEmpty) return;
    printMessage.value = 'جارٍ تجهيز ملف PDF…';
    printPreparationTimer = Timer(const Duration(minutes: 3), () {
      if (!operation) {
        clearPrintFeedback();
        unawaited(releasePrintClickGuard());
      }
    });
  }

  void clearPrintFeedback() {
    printPreparationTimer?.cancel();
    printPreparationTimer = null;
    printMessage.value = '';
  }

  Future<void> releasePrintClickGuard() async {
    final controller = web, selected = server.value;
    if (controller == null || selected == null) return;
    try {
      if (selected.contains(await controller.getUrl())) {
        await controller.evaluateJavascript(
          source: 'window.__portalFinishPrint?.();',
        );
      }
    } catch (_) {
      /* The page may have been disposed or navigated. */
    }
  }

  Future<void> finishPrintPreparation() async {
    if (operation) return;
    clearPrintFeedback();
    await releasePrintClickGuard();
  }

  Future<void> textAction(String action) async {
    final controller = web, selected = server.value;
    if (controller == null ||
        selected == null ||
        !selected.contains(await controller.getUrl())) {
      return;
    }
    if (action == 'copy' || action == 'cut') {
      final text = await controller.evaluateJavascript(
        source: '''(() => {
        const e = document.activeElement;
        if (e?.type === 'password') return '';
        if (e && typeof e.selectionStart === 'number') return e.value.substring(e.selectionStart, e.selectionEnd);
        return window.getSelection()?.toString() || '';
      })()''',
      );
      if (text is! String || text.isEmpty || text.length > 1024 * 1024) return;
      await Clipboard.setData(ClipboardData(text: text));
      if (action == 'cut') {
        await controller.evaluateJavascript(
          source: "document.execCommand('delete');",
        );
      }
    } else if (action == 'paste') {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text;
      if (text == null ||
          text.length > 1024 * 1024 ||
          !selected.contains(await controller.getUrl())) {
        return;
      }
      await controller.evaluateJavascript(
        source:
            '''(() => {
        const e = document.activeElement;
        if (e && !e.disabled && !e.readOnly && (e.isContentEditable || ['INPUT','TEXTAREA'].includes(e.tagName))) {
          document.execCommand('insertText', false, ${jsonEncode(text)});
        }
      })()''',
      );
    } else if (action == 'selectAll') {
      await controller.evaluateJavascript(
        source: '''(() => {
        const e = document.activeElement;
        if (e && ['INPUT','TEXTAREA'].includes(e.tagName)) e.select();
        else document.execCommand('selectAll');
      })()''',
      );
    }
  }

  @override
  void onClose() {
    invalidate();
    address.dispose();
    super.onClose();
  }
}
