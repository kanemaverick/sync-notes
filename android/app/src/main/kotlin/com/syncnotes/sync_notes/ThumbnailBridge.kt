package com.syncnotes.sync_notes

import android.app.Activity
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.os.SystemClock
import android.util.Log
import androidx.exifinterface.media.ExifInterface
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import kotlin.math.max
import kotlin.math.roundToInt

/** Decode only thumbnail-sized pixels; never rewrite the source photo. */
class ThumbnailBridge(private val activity: Activity) {
    fun handle(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "create") { result.notImplemented(); return }
        val source = call.argument<String>("source")
        val destination = call.argument<String>("destination")
        if (source == null || destination == null) {
            result.error("invalid_path", "缺少照片路径", null); return
        }
        Thread {
            val bitmaps = mutableListOf<Bitmap>()
            var temporary: File? = null
            try {
                val start = SystemClock.elapsedRealtime()
                val privateRoot = File(activity.applicationInfo.dataDir).canonicalPath + "/"
                val input = File(source).canonicalFile
                val output = File(destination).canonicalFile
                require(input.path.startsWith(privateRoot) && output.path.startsWith(privateRoot))
                require(input != output)
                val options = BitmapFactory.Options().apply { inJustDecodeBounds = true }
                BitmapFactory.decodeFile(input.path, options)
                require(options.outWidth > 0 && options.outHeight > 0) { "无法读取照片尺寸" }
                val originalWidth = options.outWidth
                val originalHeight = options.outHeight
                val longest = max(originalWidth, originalHeight)
                while (longest / (options.inSampleSize * 2) >= 480) options.inSampleSize *= 2
                options.inJustDecodeBounds = false
                var bitmap = requireNotNull(BitmapFactory.decodeFile(input.path, options))
                bitmaps.add(bitmap)
                // Some decodable formats (for example GIF) do not carry EXIF.
                val exif = runCatching { ExifInterface(input) }.getOrNull()
                val transform = Matrix().apply {
                    if (exif?.isFlipped == true) postScale(-1f, 1f)
                    postRotate((exif?.rotationDegrees ?: 0).toFloat())
                }
                if (!transform.isIdentity) {
                    bitmap = Bitmap.createBitmap(bitmap, 0, 0, bitmap.width, bitmap.height, transform, true)
                    bitmaps.add(bitmap)
                }
                val scale = minOf(1.0, 480.0 / max(bitmap.width, bitmap.height))
                if (scale < 1) {
                    bitmap = Bitmap.createScaledBitmap(bitmap,
                        max(1, (bitmap.width * scale).roundToInt()),
                        max(1, (bitmap.height * scale).roundToInt()), true)
                    bitmaps.add(bitmap)
                }
                temporary = File(output.path + ".tmp")
                temporary.outputStream().use {
                    check(bitmap.compress(Bitmap.CompressFormat.JPEG, 82, it))
                    it.fd.sync()
                }
                check(temporary.renameTo(output)) { "无法保存缩略图" }
                Log.d("SyncNotesThumbnail", "${originalWidth}x${originalHeight} -> ${bitmap.width}x${bitmap.height} in ${SystemClock.elapsedRealtime() - start}ms")
                activity.runOnUiThread { result.success(null) }
            } catch (error: Exception) {
                temporary?.delete()
                activity.runOnUiThread { result.error("thumbnail_failed", error.message, null) }
            } finally {
                bitmaps.distinct().forEach { if (!it.isRecycled) it.recycle() }
            }
        }.start()
    }
}
