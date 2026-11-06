package com.almizan.almizan_mobile

import io.flutter.embedding.android.FlutterActivity
import android.print.PortalPdfExporter
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var pdfExporter: PortalPdfExporter? = null
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        pdfExporter = PortalPdfExporter(this)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "portal/pdf")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "convert" -> pdfExporter!!.convert(call.argument<String>("html"), call.argument<Boolean>("landscape") == true, result)
                    "cancel" -> { pdfExporter?.cancel(); result.success(null) }
                    else -> result.notImplemented()
                }
            }
    }
    override fun onDestroy() { pdfExporter?.cancel(); super.onDestroy() }
}
