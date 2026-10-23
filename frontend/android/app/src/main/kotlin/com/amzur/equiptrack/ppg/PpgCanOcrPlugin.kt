package com.amzur.equiptrack.ppg

import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/** Live NV21 frames from Flutter CameraX; all recognition stays on device. */
class PpgCanOcrPlugin : MethodChannel.MethodCallHandler {
    private val recognizer = TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)
    private var busy = false

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "recognizeFrame") { result.notImplemented(); return }
        if (busy) { result.error("busy", "Frame analysis in progress", null); return }
        val bytes = call.argument<ByteArray>("bytes")
        val width = call.argument<Int>("width") ?: 0
        val height = call.argument<Int>("height") ?: 0
        val rotation = call.argument<Int>("rotation") ?: -1
        if (bytes == null || width <= 0 || height <= 0 || width % 2 != 0 || height % 2 != 0 ||
            bytes.size.toLong() != width.toLong() * height * 3 / 2 || rotation !in listOf(0, 90, 180, 270)) {
            result.error("bad_frame", "Expected a complete NV21 camera frame", null)
            return
        }
        try {
            busy = true
            val image = InputImage.fromByteArray(bytes, width, height, rotation, InputImage.IMAGE_FORMAT_NV21)
            recognizer.process(image).addOnSuccessListener { text ->
                val lines = text.textBlocks.flatMap { it.lines }.map { line ->
                    val box = line.boundingBox
                    mapOf(
                        "text" to line.text,
                        "left" to (box?.left?.toDouble() ?: 0.0),
                        "top" to (box?.top?.toDouble() ?: 0.0),
                        "right" to (box?.right?.toDouble() ?: 0.0),
                        "bottom" to (box?.bottom?.toDouble() ?: 0.0),
                        "confidence" to line.confidence?.toDouble(),
                    )
                }
                busy = false
                result.success(mapOf("lines" to lines,
                    "width" to if (rotation % 180 == 0) width else height,
                    "height" to if (rotation % 180 == 0) height else width))
            }.addOnFailureListener { error ->
                busy = false
                result.error("ocr_failed", error.message, null)
            }
        } catch (error: Exception) {
            busy = false
            result.error("ocr_failed", error.message, null)
        }
    }

    fun close() { recognizer.close() }
}
