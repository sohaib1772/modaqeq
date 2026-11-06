import 'dart:convert';
import 'dart:collection';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:get/get.dart';
import 'package:url_launcher/url_launcher.dart';
import '../controllers/portal_controller.dart';
import '../services/print_bridge_script.dart';
import '../services/print_feedback_script.dart';
import 'print_progress_overlay.dart';

class PortalView extends GetView<PortalController> {
  const PortalView({super.key});
  @override
  Widget build(BuildContext context) => Obx(
    () => controller.verified.value ? _browser(context) : _setup(context),
  );

  Widget _setup(BuildContext context) => controller.serverLocked.value
      ? _reconnect(context)
      : Scaffold(
          body: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Image.asset('assets/logo.png', height: 100),
                      const SizedBox(height: 28),
                      Text(
                        'المدقق المحاسبي',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'نظامك المحاسبي، أينما كنت',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 32),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const Icon(Icons.dns_outlined, size: 36),
                              const SizedBox(height: 16),
                              const Text(
                                'مرحباً بك',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'أدخل عنوان الاتصال الذي زوّدك به مسؤول النظام للبدء.',
                              ),
                              const SizedBox(height: 24),
                              TextField(
                                controller: controller.address,
                                textDirection: TextDirection.ltr,
                                keyboardType: TextInputType.url,
                                autocorrect: false,
                                enableSuggestions: false,
                                onSubmitted: (_) => controller.connect(),
                                decoration: const InputDecoration(
                                  labelText: 'عنوان الاتصال',
                                  hintText: 'https://portal.example.com',
                                  prefixIcon: Icon(Icons.link),
                                ),
                              ),
                              const SizedBox(height: 16),
                              Obx(
                                () => controller.error.value.isEmpty
                                    ? const SizedBox.shrink()
                                    : Padding(
                                        padding: const EdgeInsets.only(
                                          bottom: 16,
                                        ),
                                        child: Text(
                                          controller.error.value,
                                          style: TextStyle(
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.error,
                                          ),
                                        ),
                                      ),
                              ),
                              Obx(
                                () => FilledButton.icon(
                                  onPressed: controller.busy.value
                                      ? null
                                      : controller.connect,
                                  icon: controller.busy.value
                                      ? const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Icon(Icons.arrow_forward),
                                  label: Text(
                                    controller.busy.value
                                        ? 'جارٍ الاتصال…'
                                        : 'اتصال آمن',
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.lock_outline, size: 18),
                          SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              'خصوصيتك وأمان بياناتك أولويتنا',
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );

  Widget _reconnect(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset('assets/logo.png', width: 112, height: 112),
              const SizedBox(height: 24),
              Text(
                'المدقق المحاسبي',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 16),
              Text(
                controller.busy.value
                    ? 'جارٍ الاتصال…'
                    : controller.error.value,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              if (controller.busy.value)
                const CircularProgressIndicator()
              else
                FilledButton(
                  onPressed: controller.connect,
                  child: const Text('إعادة المحاولة'),
                ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _browser(BuildContext context) => PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) controller.back();
    },
    child: Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            InAppWebView(
              key: ValueKey(controller.server.value.toString()),
              initialUserScripts: UnmodifiableListView<UserScript>([
                UserScript(
                  source: printFeedbackScript(
                    controller.server.value.toString(),
                  ),
                  injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
                ),
                UserScript(
                  source: printBridgeScript(controller.server.value.toString()),
                  injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
                  forMainFrameOnly: false,
                ),
              ]),
              contextMenu: defaultTargetPlatform == TargetPlatform.iOS
                  ? ContextMenu(
                      settings: ContextMenuSettings(
                        hideDefaultSystemContextMenuItems: true,
                      ),
                      menuItems: [
                        ContextMenuItem(
                          id: 1,
                          title: 'نسخ',
                          action: () => controller.textAction('copy'),
                        ),
                        ContextMenuItem(
                          id: 2,
                          title: 'قص',
                          action: () => controller.textAction('cut'),
                        ),
                        ContextMenuItem(
                          id: 3,
                          title: 'لصق',
                          action: () => controller.textAction('paste'),
                        ),
                        ContextMenuItem(
                          id: 4,
                          title: 'تحديد الكل',
                          action: () => controller.textAction('selectAll'),
                        ),
                      ],
                    )
                  : null,
              initialSettings: InAppWebViewSettings(
                disabledActionModeMenuItems:
                    ActionModeMenuItem.MENU_ITEM_WEB_SEARCH |
                    ActionModeMenuItem.MENU_ITEM_PROCESS_TEXT |
                    ActionModeMenuItem.MENU_ITEM_SHARE,
                javaScriptEnabled: true,
                domStorageEnabled: true,
                incognito: false,
                cacheEnabled: true,
                sharedCookiesEnabled: true,
                thirdPartyCookiesEnabled: false,
                applicationNameForUserAgent: 'PortalApp/1.0',
                useShouldOverrideUrlLoading: true,
                useOnDownloadStart: true,
                supportMultipleWindows: true,
                javaScriptCanOpenWindowsAutomatically: true,
                allowFileAccess: false,
                allowContentAccess: true,
                mixedContentMode: MixedContentMode.MIXED_CONTENT_NEVER_ALLOW,
                allowsBackForwardNavigationGestures: true,
                allowsInlineMediaPlayback: true,
                isInspectable: false,
              ),
              onWebViewCreated: controller.created,
              shouldOverrideUrlLoading: (web, action) async {
                final uri = action.request.url;
                if (uri == null) return NavigationActionPolicy.ALLOW;

                if (uri.scheme == 'javascript' ||
                    uri.scheme == 'about' ||
                    uri.scheme == 'data') {
                  return NavigationActionPolicy.ALLOW;
                }
                if (controller.server.value!.contains(uri)) {
                  if (uri.path == '/database-admin-download') {
                    // Capture known one-use backup links before WebView consumes them.
                    await controller.handle(
                      '{"version":1,"id":"navigation-${DateTime.now().microsecondsSinceEpoch}","type":"download","url":${jsonEncode(uri.toString())}}',
                    );
                    return NavigationActionPolicy.CANCEL;
                  }
                  return NavigationActionPolicy.ALLOW;
                }
                if (!action.isForMainFrame) {
                  return NavigationActionPolicy.ALLOW;
                }
                if (['https', 'http', 'mailto', 'tel'].contains(uri.scheme)) {
                  if (await controller.confirm(
                    'فتح رابط خارجي',
                    'هل تريد فتح الرابط خارج التطبيق؟',
                  )) {
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  }
                }
                return NavigationActionPolicy.CANCEL;
              },
              onCreateWindow: (web, action) async {
                final actionUrl = action.request.url;
                if (actionUrl != null) {
                  final targetUri = Uri.tryParse(actionUrl.toString());
                  if (targetUri != null &&
                      controller.server.value?.contains(targetUri) == true) {
                    await web.loadUrl(urlRequest: action.request);
                    return true;
                  }
                  if (targetUri != null &&
                      [
                        'https',
                        'http',
                        'mailto',
                        'tel',
                      ].contains(targetUri.scheme)) {
                    if (await controller.confirm(
                      'فتح رابط خارجي',
                      'هل تريد فتح الرابط خارج التطبيق؟',
                    )) {
                      await launchUrl(
                        targetUri,
                        mode: LaunchMode.externalApplication,
                      );
                    }
                    return true;
                  }
                }
                return false;
              },
              onLoadStart: (web, url) async {
                controller.invalidate();
                if (!controller.server.value!.contains(url)) {
                  await web.stopLoading();
                  controller.error.value = 'تعذر فتح هذه الصفحة بأمان.';
                }
              },
              onLoadStop: (web, url) async {
                controller.progress.value = 1.0;
              },
              onProgressChanged: (_, value) =>
                  controller.progress.value = value / 100,
              onReceivedError: (_, request, error) {
                if (error.type == WebResourceErrorType.CANCELLED) return;
                if (request.isForMainFrame == true) {
                  controller.error.value =
                      'تعذر تحميل الصفحة. تحقق من الاتصال ثم أعد المحاولة.';
                }
              },
              onReceivedHttpError: (_, request, response) {
                if (request.isForMainFrame == true) {
                  controller.error.value =
                      'تعذر عرض الصفحة الآن. أعد المحاولة لاحقاً.';
                }
              },
              onReceivedHttpAuthRequest: (_, challenge) async {
                final space = challenge.protectionSpace;
                final selected = controller.server.value!;
                final port = (space.port ?? -1) <= 0 ? 443 : space.port!;
                if (space.host != selected.origin.host ||
                    space.protocol != 'https' ||
                    port != selected.origin.port) {
                  return HttpAuthResponse(
                    action: HttpAuthResponseAction.CANCEL,
                  );
                }
                final auth = await controller.credentials();
                if (auth != null) {
                  controller.transport.authorize(
                    controller.server.value!,
                    'Basic ${base64Encode(utf8.encode('${auth[0]}:${auth[1]}'))}',
                  );
                }
                return auth == null
                    ? HttpAuthResponse(action: HttpAuthResponseAction.CANCEL)
                    : HttpAuthResponse(
                        action: HttpAuthResponseAction.PROCEED,
                        username: auth[0],
                        password: auth[1],
                        permanentPersistence: false,
                      );
              },
              onJsBeforeUnload: (_, __) async => JsBeforeUnloadResponse(
                handledByClient: true,
                action:
                    await controller.confirm(
                      'تغييرات غير محفوظة',
                      'هل تريد مغادرة الصفحة دون حفظ؟',
                    )
                    ? JsBeforeUnloadResponseAction.CONFIRM
                    : JsBeforeUnloadResponseAction.CANCEL,
              ),
              onJsAlert: (_, __) async {
                await controller.finishPrintPreparation();
                return JsAlertResponse(handledByClient: false);
              },
              onDownloadStartRequest: (_, __) async {
                // Never re-fetch a URL after WebView has consumed a one-use response.
                Get.snackbar(
                  'تعذر استلام الملف',
                  'يرجى إعادة المحاولة من زر التنزيل داخل الصفحة.',
                );
              },
            ),
            Obx(
              () => controller.progress.value >= 1
                  ? const SizedBox.shrink()
                  : IgnorePointer(
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: LinearProgressIndicator(
                          value: controller.progress.value,
                        ),
                      ),
                    ),
            ),
            Obx(
              () => controller.error.value.isEmpty
                  ? const SizedBox.shrink()
                  : Positioned.fill(
                      child: ColoredBox(
                        color: Theme.of(context).scaffoldBackgroundColor,
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.all(28),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.cloud_off_outlined, size: 64),
                                const SizedBox(height: 20),
                                Text(
                                  controller.error.value,
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 20),
                                FilledButton.icon(
                                  onPressed: () {
                                    controller.error.value = '';
                                    controller.web?.reload();
                                  },
                                  icon: const Icon(Icons.refresh),
                                  label: const Text('إعادة المحاولة'),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
            ),
            Obx(
              () => controller.printMessage.value.isEmpty
                  ? const SizedBox.shrink()
                  : Positioned.fill(
                      child: PrintProgressOverlay(
                        message: controller.printMessage.value,
                      ),
                    ),
            ),
          ],
        ),
      ),
    ),
  );
}
