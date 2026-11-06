import 'dart:convert';

String printFeedbackScript(String origin) =>
    '''
(() => {
  if (window !== window.top || location.origin !== ${jsonEncode(origin)}) return;
  let busy = false, timer;
  function notify(value) {
    try { window.PortalPrintState?.postMessage(value); } catch (_) {}
  }
  window.__portalFinishPrint = function() {
    clearTimeout(timer); busy = false;
  };
  document.addEventListener('click', event => {
    if (busy) {
      // Site handlers may trigger internal synthetic clicks while preparing.
      if (event.isTrusted) { event.preventDefault(); event.stopImmediatePropagation(); }
      return;
    }
    const button = event.target?.closest?.('button,a,input[type="button"],input[type="submit"]');
    if (!button || button.disabled || button.id === 'layoutPreview' || button.id === 'closePrint') return;
    const text = [button.textContent, button.value, button.title,
      button.getAttribute('aria-label')].filter(Boolean).join(' ');
    const action = button.getAttribute('onclick') || '';
    if (!/طباعة|(?:تصدير|حفظ).*PDF|PDF.*(?:تصدير|حفظ)/i.test(text) &&
        !/window\\.print|export(?:Invoice|Statement|Inventory)PDF|showInlineInvoicePrint/i.test(action)) return;
    busy = true; notify('start');
    // Covers page-side data fetching before the print_html bridge request.
    timer = setTimeout(() => { busy = false; notify('finish'); }, 180000);
  }, true);
  // Existing invoice validation/save failures can be displayed inline instead
  // of an alert. Release preparation so the user can correct those fields.
  if (typeof MutationObserver === 'function') {
    new MutationObserver(records => {
      if (!busy) return;
      const failed = records.some(record => {
        const node = record.target.nodeType === 1 ? record.target : record.target.parentElement;
        const error = node?.closest?.('.entry-error,#designStatus');
        const text = error?.textContent?.trim() || '';
        return text && (error.id !== 'designStatus' || !text.startsWith('تم حفظ التصميم'));
      });
      if (failed) { clearTimeout(timer); busy = false; notify('finish'); }
    }).observe(document, {subtree:true, childList:true, characterData:true, attributes:true,
      attributeFilter:['class']});
  }
})();
''';
