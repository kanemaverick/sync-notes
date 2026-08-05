package com.syncnotes.sync_notes

import android.os.SystemClock
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "sync_notes/clock")
            .setMethodCallHandler { call, result ->
                if (call.method == "elapsedRealtimeMs") {
                    result.success(SystemClock.elapsedRealtime())
                } else {
                    result.notImplemented()
                }
            }
    }
}
