package com.syncnotes.sync_notes

import android.os.SystemClock
import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val documentScanner by lazy { DocumentScannerBridge(this) }
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "sync_notes/document_scanner")
            .setMethodCallHandler(documentScanner::handle)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "sync_notes/clock")
            .setMethodCallHandler { call, result ->
                if (call.method == "elapsedRealtimeMs") {
                    result.success(SystemClock.elapsedRealtime())
                } else {
                    result.notImplemented()
                }
            }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        documentScanner.onResult(requestCode, resultCode, data)
    }
}
