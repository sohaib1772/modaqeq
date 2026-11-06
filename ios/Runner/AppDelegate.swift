import Flutter
import UIKit
import WebKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  private let pdfExporter = PortalPDFExporter()
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    for directory in [FileManager.SearchPathDirectory.documentDirectory, .libraryDirectory] {
      if var url = FileManager.default.urls(for: directory, in: .userDomainMask).first {
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
      }
    }
    GeneratedPluginRegistrant.register(with: self)
    if let controller = window?.rootViewController as? FlutterViewController {
      FlutterMethodChannel(name: "portal/pdf", binaryMessenger: controller.binaryMessenger)
        .setMethodCallHandler { [weak self] call, result in
          guard let renderer = self?.pdfExporter else { return }
          switch call.method {
          case "convert":
            let args = call.arguments as? [String: Any]
            renderer.convert(args?["html"] as? String, landscape: args?["landscape"] as? Bool ?? false, result: result)
          case "cancel": renderer.cancel(); result(nil)
          default: result(FlutterMethodNotImplemented)
          }
        }
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}

private final class PortalA4Renderer: UIPrintPageRenderer {
  var landscape = false
  override var paperRect: CGRect { CGRect(x: 0, y: 0, width: landscape ? 841.89 : 595.28, height: landscape ? 595.28 : 841.89) }
  override var printableRect: CGRect { paperRect }
}

private final class PortalPDFExporter: NSObject, WKNavigationDelegate {
  private var web: WKWebView?
  private var reply: FlutterResult?
  private var timeout: DispatchWorkItem?
  private var landscape = false
  func convert(_ html: String?, landscape: Bool, result: @escaping FlutterResult) {
    guard reply == nil else { result(FlutterError(code: "busy", message: "عملية أخرى قيد التنفيذ.", details: nil)); return }
    guard let html = html, html.utf8.count <= 40 * 1024 * 1024 else {
      result(FlutterError(code: "invalid", message: "المستند غير صالح.", details: nil)); return
    }
    self.landscape = landscape
    let configuration = WKWebViewConfiguration()
    configuration.preferences.javaScriptEnabled = false
    configuration.websiteDataStore = .nonPersistent()
    let view = WKWebView(frame: CGRect(x: 0, y: 0, width: landscape ? 1123 : 794, height: landscape ? 794 : 1123), configuration: configuration)
    web = view; reply = result
    view.navigationDelegate = self
    let work = DispatchWorkItem { [weak self] in self?.fail("timeout", "انتهت مهلة تجهيز الملف.") }
    timeout = work
    DispatchQueue.main.asyncAfter(deadline: .now() + 25, execute: work)
    view.loadHTMLString(html, baseURL: nil)
  }
  func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
               decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
    // The document has a restrictive CSP and embedded resources only.
    let url = navigationAction.request.url
    decisionHandler(url == nil || url?.scheme == "about" ? .allow : .cancel)
  }
  func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self, weak webView] in
      guard let self = self, let view = webView, self.web === view else { return }
      view.layoutIfNeeded()
      let renderer = PortalA4Renderer()
      renderer.landscape = self.landscape
      renderer.addPrintFormatter(view.viewPrintFormatter(), startingAtPageAt: 0)
      let data = NSMutableData()
      UIGraphicsBeginPDFContextToData(data, renderer.paperRect, nil)
      let count = renderer.numberOfPages
      guard count > 0 && count <= 300 else {
        UIGraphicsEndPDFContext(); self.fail("pages", "عدد صفحات الملف غير مسموح."); return
      }
      renderer.prepare(forDrawingPages: NSRange(location: 0, length: count))
      for index in 0..<count {
        UIGraphicsBeginPDFPageWithInfo(renderer.paperRect, nil)
        renderer.drawPage(at: index, in: renderer.paperRect)
      }
      UIGraphicsEndPDFContext()
      guard data.length > 0 && data.length <= 32 * 1024 * 1024 else {
        self.fail("size", "حجم الملف غير مسموح."); return
      }
      let result = self.reply
      self.reply = nil
      self.cleanup()
      result?(FlutterStandardTypedData(bytes: data as Data))
    }
  }
  func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
    if web === webView { fail("render", "تعذر تجهيز الملف.") }
  }
  func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
    if web === webView { fail("render", "تعذر تجهيز الملف.") }
  }
  func cancel() { fail("cancelled", "أُلغيت العملية.") }
  private func fail(_ code: String, _ message: String) {
    let result = reply; reply = nil
    cleanup()
    result?(FlutterError(code: code, message: message, details: nil))
  }
  private func cleanup() {
    timeout?.cancel(); timeout = nil
    web?.navigationDelegate = nil; web?.stopLoading(); web = nil
  }
}
