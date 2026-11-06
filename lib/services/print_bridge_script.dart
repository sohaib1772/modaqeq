import 'dart:convert';

/// Frame-local print() must capture that frame's prepared document, rather than
/// a mobile viewport snapshot of the whole site. Requests still originate in
/// the approved top frame and pass the native origin/main-frame checks.
String printBridgeScript(String origin) =>
    '''
(() => {
  const approved = ${jsonEncode(origin)};
  function allowed() {
    try { return window.top.location.origin === approved && !!window.top.document; }
    catch (_) { return false; }
  }
  if (!allowed()) return;
  function install(target) {
    try {
      // Reading document throws for foreign frames, including redirects.
      if (!target.document || target === window.top) return;
      target.print = function() {
        if (!allowed()) return;
        const portal = window.top.PortalMobile;
        if (portal && typeof portal.printHtml === 'function') {
          return portal.printHtml(target.document.documentElement.outerHTML)
            .catch(() => window.top.alert('تعذر تجهيز الملف. أعد المحاولة.'))
            .finally(() => {
              try { target.dispatchEvent(new target.Event('afterprint')); } catch (_) {}
            });
        }
      };
    } catch (_) {}
  }
  install(window);
  // Capturing load runs before a report iframe's own onload print handler.
  document.addEventListener('load', event => {
    if (event.target?.tagName === 'IFRAME') install(event.target.contentWindow);
  }, true);
})();
''';
