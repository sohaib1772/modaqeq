package android.print

import android.app.Activity
import android.graphics.Color
import android.os.Bundle
import android.os.CancellationSignal
import android.os.Handler
import android.os.Looper
import android.os.ParcelFileDescriptor
import android.print.PageRange
import android.print.PrintAttributes
import android.print.PrintDocumentAdapter
import android.print.PrintDocumentInfo
import android.webkit.WebView
import android.webkit.WebViewClient
import io.flutter.plugin.common.MethodChannel
import java.io.File

/** Exports a sanitized, self-contained HTML snapshot without a print dialog. */
class PortalPdfExporter(private val activity: Activity) {
    private val handler = Handler(Looper.getMainLooper())
    private var view: WebView? = null
    private var reply: MethodChannel.Result? = null
    private var adapter: PrintDocumentAdapter? = null
    private var descriptor: ParcelFileDescriptor? = null
    private var output: File? = null
    private var cancellation: CancellationSignal? = null
    private var timeout: Runnable? = null

    fun convert(html: String?, landscape: Boolean, result: MethodChannel.Result) {
        if (reply != null) { result.error("busy", "عملية أخرى قيد التنفيذ.", null); return }
        if (html == null || html.toByteArray().size > 40 * 1024 * 1024) {
            result.error("invalid", "المستند غير صالح.", null); return
        }
        reply = result
        val current = WebView(activity)
        view = current
        current.setBackgroundColor(Color.WHITE)
        current.settings.apply {
            javaScriptEnabled = false
            domStorageEnabled = false
            allowFileAccess = false
            allowContentAccess = false
            blockNetworkLoads = true
            mixedContentMode = android.webkit.WebSettings.MIXED_CONTENT_NEVER_ALLOW
        }
        current.layout(0, 0, if (landscape) 1123 else 794, if (landscape) 794 else 1123)
        var started = false
        current.webViewClient = object : WebViewClient() {
            override fun onPageFinished(web: WebView, url: String) {
                if (view !== current || started) return
                started = true
                // All images/fonts are embedded data URIs; allow a rendering turn.
                handler.postDelayed({ if (view === current) write(current, landscape) }, 200)
            }
            override fun shouldOverrideUrlLoading(web: WebView, request: android.webkit.WebResourceRequest) = true
        }
        timeout = Runnable { fail("timeout", "انتهت مهلة تجهيز الملف.") }
        handler.postDelayed(timeout!!, 25000)
        current.loadDataWithBaseURL(null, html, "text/html", "UTF-8", null)
    }

    private fun write(web: WebView, landscape: Boolean) {
        try {
            val attributes = PrintAttributes.Builder()
                .setMediaSize(if (landscape) PrintAttributes.MediaSize.ISO_A4.asLandscape() else PrintAttributes.MediaSize.ISO_A4.asPortrait())
                .setResolution(PrintAttributes.Resolution("pdf", "PDF", 300, 300))
                .setMinMargins(PrintAttributes.Margins.NO_MARGINS)
                .setColorMode(PrintAttributes.COLOR_MODE_COLOR).build()
            val job = web.createPrintDocumentAdapter("document")
            adapter = job
            val signal = CancellationSignal()
            cancellation = signal
            job.onStart()
            job.onLayout(null, attributes, signal, object : PrintDocumentAdapter.LayoutResultCallback() {
                override fun onLayoutFinished(info: PrintDocumentInfo, changed: Boolean) {
                    if (view !== web || signal.isCanceled) return
                    try {
                        val file = File.createTempFile("portal_pdf_", ".pdf", activity.cacheDir)
                        output = file
                        val fd = ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_WRITE or ParcelFileDescriptor.MODE_TRUNCATE)
                        descriptor = fd
                        job.onWrite(arrayOf(PageRange.ALL_PAGES), fd, signal, object : PrintDocumentAdapter.WriteResultCallback() {
                            override fun onWriteFinished(pages: Array<out PageRange>) {
                                if (view !== web || signal.isCanceled) return
                                try {
                                    descriptor?.close(); descriptor = null
                                    if (file.length() == 0L || file.length() > 32 * 1024 * 1024) {
                                        fail("size", "حجم الملف غير مسموح."); return
                                    }
                                    val bytes = file.readBytes()
                                    val result = reply
                                    reply = null
                                    cleanup()
                                    result?.success(bytes)
                                } catch (_: Exception) { fail("write", "تعذر تجهيز الملف.") }
                            }
                            override fun onWriteFailed(error: CharSequence?) { if (view === web) fail("write", "تعذر تجهيز الملف.") }
                            override fun onWriteCancelled() { if (view === web) cancel() }
                        })
                    } catch (_: Exception) { fail("write", "تعذر تجهيز الملف.") }
                }
                override fun onLayoutFailed(error: CharSequence?) { if (view === web) fail("layout", "تعذر تنسيق الملف.") }
                override fun onLayoutCancelled() { if (view === web) cancel() }
            }, Bundle())
        } catch (_: Exception) { fail("render", "تعذر تجهيز الملف.") }
    }
    fun cancel() { fail("cancelled", "أُلغيت العملية.") }
    private fun fail(code: String, message: String) {
        val result = reply
        reply = null
        cleanup()
        result?.error(code, message, null)
    }
    private fun cleanup() {
        timeout?.let { handler.removeCallbacks(it) }; timeout = null
        val old = view; view = null
        cancellation?.cancel(); cancellation = null
        try { descriptor?.close() } catch (_: Exception) { }
        descriptor = null
        try { adapter?.onFinish() } catch (_: Exception) { }
        adapter = null
        old?.stopLoading(); old?.destroy()
        output?.delete(); output = null
    }
}
