package com.example.flutter_baji_demo

import android.graphics.Bitmap
import android.media.MediaMetadataRetriever
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import kotlin.math.max
import kotlin.math.min

/**
 * 视频抽帧 / 预览的原生实现。
 *
 * Flutter 侧没有稳定的跨平台视频解码 API，这里用 MediaMetadataRetriever
 * 抽取 JPEG 帧，交给 Dart 侧统一做尺寸裁切与 bin 封装。
 */
class MainActivity : FlutterActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "load" -> {
                    val path = call.argument<String>("path")
                    val maxSize = call.argument<Int>("maxSize") ?: 720
                    if (path == null) {
                        result.error("bad_args", "path is required", null)
                        return@setMethodCallHandler
                    }
                    runAsync(result) { loadVideo(path, maxSize) }
                }

                "extract" -> {
                    val path = call.argument<String>("path")
                    val intervalMs = call.argument<Int>("intervalMs") ?: 100
                    val maxFrames = call.argument<Int>("maxFrames") ?: 30
                    val maxDurationMs = call.argument<Int>("maxDurationMs") ?: 3000
                    val size = call.argument<Int>("size") ?: 368
                    if (path == null) {
                        result.error("bad_args", "path is required", null)
                        return@setMethodCallHandler
                    }
                    runAsync(result) {
                        extractFrames(path, intervalMs, maxFrames, maxDurationMs, size)
                    }
                }

                else -> result.notImplemented()
            }
        }
    }

    private fun runAsync(result: MethodChannel.Result, block: () -> Any?) {
        Thread {
            try {
                val value = block()
                runOnUiThread { result.success(value) }
            } catch (t: Throwable) {
                runOnUiThread { result.error("video_error", t.message ?: "视频处理失败", null) }
            }
        }.start()
    }

    private fun loadVideo(path: String, maxSize: Int): Map<String, Any?> {
        val retriever = MediaMetadataRetriever()
        try {
            retriever.setDataSource(path)
            val durationMs = retriever
                .extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)
                ?.toLongOrNull() ?: 0L
            val frame = retriever.getFrameAtTime(0L, MediaMetadataRetriever.OPTION_CLOSEST_SYNC)
            val preview = frame?.let { scalePreview(it, maxSize) }
            return mapOf("durationMs" to durationMs, "preview" to preview)
        } finally {
            retriever.release()
        }
    }

    private fun extractFrames(
        path: String,
        intervalMs: Int,
        maxFrames: Int,
        maxDurationMs: Int,
        size: Int,
    ): List<ByteArray> {
        val retriever = MediaMetadataRetriever()
        try {
            retriever.setDataSource(path)
            val durationMs = retriever
                .extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)
                ?.toLongOrNull() ?: 0L
            val effective = min(durationMs, maxDurationMs.toLong())
            val count = if (effective > 0) {
                min(maxFrames, max(1, (effective / intervalMs).toInt()))
            } else {
                1
            }
            val output = ArrayList<ByteArray>(count)
            for (index in 0 until count) {
                val frame = retriever.getFrameAtTime(
                    index.toLong() * intervalMs * 1_000L,
                    MediaMetadataRetriever.OPTION_CLOSEST,
                ) ?: continue
                val jpeg = squareJpeg(frame, size)
                if (jpeg != null) output += jpeg
                frame.recycle()
            }
            return output
        } finally {
            retriever.release()
        }
    }

    private fun scalePreview(source: Bitmap, maxSize: Int): ByteArray? {
        val maxDimension = max(source.width, source.height)
        val scale = if (maxDimension <= maxSize) 1f else maxSize.toFloat() / maxDimension
        val width = max(1, (source.width * scale).toInt())
        val height = max(1, (source.height * scale).toInt())
        val scaled = if (width == source.width && height == source.height) {
            source
        } else {
            Bitmap.createScaledBitmap(source, width, height, true)
        }
        return try {
            compressJpeg(scaled)
        } finally {
            if (scaled !== source) scaled.recycle()
            source.recycle()
        }
    }

    private fun squareJpeg(source: Bitmap, size: Int): ByteArray? {
        val side = min(source.width, source.height)
        if (side <= 0) return null
        val left = (source.width - side) / 2
        val top = (source.height - side) / 2
        val cropped = Bitmap.createBitmap(source, left, top, side, side)
        val target = size.coerceAtLeast(1)
        val scaled = if (cropped.width == target && cropped.height == target) {
            cropped
        } else {
            Bitmap.createScaledBitmap(cropped, target, target, true)
        }
        return try {
            compressJpeg(scaled)
        } finally {
            if (scaled !== cropped) scaled.recycle()
            cropped.recycle()
        }
    }

    private fun compressJpeg(bitmap: Bitmap): ByteArray =
        ByteArrayOutputStream().use { stream ->
            bitmap.compress(Bitmap.CompressFormat.JPEG, 90, stream)
            stream.toByteArray()
        }

    private companion object {
        const val CHANNEL = "baji/video"
    }
}
