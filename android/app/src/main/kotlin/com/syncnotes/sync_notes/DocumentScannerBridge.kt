package com.syncnotes.sync_notes

import android.app.Activity
import android.content.Intent
import com.google.mlkit.vision.documentscanner.GmsDocumentScannerOptions
import com.google.mlkit.vision.documentscanner.GmsDocumentScanning
import com.google.mlkit.vision.documentscanner.GmsDocumentScanningResult
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.io.File
import java.util.UUID

/** One-page scans keep the uncertainty interval explicit, not a fake shutter time. */
class DocumentScannerBridge(private val activity: Activity) {
    companion object { const val REQUEST = 24709 }
    private val directory get() = File(activity.filesDir, "document_scans").apply { mkdirs() }
    private val preferences = activity.getSharedPreferences("document_scan", 0)
    private var pending: MethodChannel.Result? = null

    fun handle(call: io.flutter.plugin.common.MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "scan" -> {
                if (pending != null) {
                    result.error("busy", "已有文档扫描正在进行", null)
                    return
                }
                val metadata = JSONObject().apply {
                    put("id", UUID.randomUUID().toString())
                    put("sessionId", call.argument<String>("sessionId"))
                    put("offsetMs", call.argument<Number>("offsetMs")?.toLong() ?: 0)
                    put("deviceTimeMs", call.argument<Number>("deviceTimeMs")?.toLong() ?: System.currentTimeMillis())
                }
                pending = result
                preferences.edit().putString("active", metadata.toString()).commit()
                val options = GmsDocumentScannerOptions.Builder()
                    .setGalleryImportAllowed(false)
                    .setPageLimit(1)
                    .setResultFormats(GmsDocumentScannerOptions.RESULT_FORMAT_JPEG)
                    .setScannerMode(GmsDocumentScannerOptions.SCANNER_MODE_FULL)
                    .build()
                try {
                    GmsDocumentScanning.getClient(options).getStartScanIntent(activity)
                    .addOnSuccessListener { sender ->
                        try {
                            activity.startIntentSenderForResult(sender, REQUEST, null, 0, 0, 0)
                        } catch (error: Exception) { fail(error) }
                    }
                    .addOnFailureListener { fail(it) }
                } catch (error: Exception) { fail(error) }
            }
            "pending" -> {
                val sessionId = call.argument<String>("sessionId")
                val records = directory.listFiles()?.filter { it.extension == "json" }?.mapNotNull {
                    try {
                        val json = JSONObject(it.readText())
                        if (json.optString("sessionId") == sessionId) json.toString() else null
                    } catch (_: Exception) { null }
                } ?: emptyList()
                result.success(records)
            }
            "acknowledge" -> {
                val id = call.argument<String>("id") ?: ""
                if (!id.matches(Regex("[a-f0-9-]{36}"))) {
                    result.error("invalid_id", "无效扫描编号", null)
                    return
                }
                File(directory, "$id.json").delete()
                File(directory, "$id.jpg").delete()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun fail(error: Exception) {
        pending?.error("scanner_unavailable", "文档扫描不可用，可改用内置相机：${error.message}", null)
        pending = null
        preferences.edit().remove("active").apply()
    }

    fun onResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode != REQUEST) return
        if (resultCode != Activity.RESULT_OK) {
            pending?.success(null)
            pending = null
            preferences.edit().remove("active").apply()
            return
        }
        val uri = GmsDocumentScanningResult.fromActivityResultIntent(data)?.pages?.firstOrNull()?.imageUri
        val active = preferences.getString("active", null)
        if (uri == null || active == null) {
            fail(IllegalStateException("未收到扫描图片"))
            return
        }
        // Save a recovery journal before returning to Flutter. If its Activity
        // was recreated, the next live page can import this result idempotently.
        Thread {
            try {
                val metadata = JSONObject(active)
                val id = metadata.getString("id")
                val image = File(directory, "$id.jpg")
                activity.contentResolver.openInputStream(uri).use { source ->
                    requireNotNull(source)
                    image.outputStream().use { target -> source.copyTo(target); target.fd.sync() }
                }
                metadata.put("path", image.absolutePath)
                metadata.put("completedAtMs", System.currentTimeMillis())
                val journal = File(directory, "$id.json")
                val temp = File(directory, "$id.json.tmp")
                temp.outputStream().use { it.write(metadata.toString().toByteArray()); it.fd.sync() }
                check(temp.renameTo(journal))
                preferences.edit().remove("active").commit()
                activity.runOnUiThread {
                    pending?.success(metadata.toString())
                    pending = null
                }
            } catch (error: Exception) { activity.runOnUiThread { fail(error) } }
        }.start()
    }
}
