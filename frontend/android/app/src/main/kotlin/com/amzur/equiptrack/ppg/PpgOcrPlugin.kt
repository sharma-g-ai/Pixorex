package com.amzur.equiptrack.ppg

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Bundled ML Kit Latin text recognition adapter.
 * Exports word elements, line groupings, and symbol boxes when available.
 */
class PpgOcrPlugin : MethodChannel.MethodCallHandler {
    private val recognizer =
        TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "recognize" -> {
                val path = call.argument<String>("imagePath")
                if (path.isNullOrBlank()) {
                    result.error("bad_args", "imagePath required", null)
                    return
                }
                val file = File(path)
                if (!file.exists()) {
                    result.error("missing", "Image not found: $path", null)
                    return
                }
                val sourceBitmap = BitmapFactory.decodeFile(path)
                if (sourceBitmap == null) {
                    result.error("decode", "Could not decode image", null)
                    return
                }
                val crop = call.argument<Map<String, Any?>>("crop")
                val bitmap = if (crop == null) {
                    sourceBitmap
                } else {
                    fun coord(name: String): Int? = (crop[name] as? Number)?.toInt()
                    val left = coord("left")
                    val top = coord("top")
                    val right = coord("right")
                    val bottom = coord("bottom")
                    if (left == null || top == null || right == null || bottom == null ||
                        left < 0 || top < 0 || right > sourceBitmap.width ||
                        bottom > sourceBitmap.height || right <= left || bottom <= top) {
                        result.error("bad_crop", "Invalid field crop", null)
                        return
                    }
                    val field = Bitmap.createBitmap(sourceBitmap, left, top, right - left, bottom - top)
                    val scale = minOf(3.0, 1200.0 / maxOf(field.width, field.height))
                    if (scale > 1.0) {
                        Bitmap.createScaledBitmap(
                            field,
                            (field.width * scale).toInt(),
                            (field.height * scale).toInt(),
                            true,
                        )
                    } else field
                }
                val image = InputImage.fromBitmap(bitmap, 0)
                recognizer.process(image)
                    .addOnSuccessListener { visionText ->
                        val elements = mutableListOf<Map<String, Any?>>()
                        val lines = mutableListOf<Map<String, Any?>>()
                        val symbols = mutableListOf<Map<String, Any?>>()

                        for (block in visionText.textBlocks) {
                            for (line in block.lines) {
                                val lineBox = line.boundingBox
                                val lineWords = mutableListOf<Map<String, Any?>>()
                                for (element in line.elements) {
                                    val box = element.boundingBox
                                    val word = mapOf(
                                        "text" to element.text,
                                        "left" to (box?.left?.toDouble() ?: 0.0),
                                        "top" to (box?.top?.toDouble() ?: 0.0),
                                        "right" to (box?.right?.toDouble() ?: 0.0),
                                        "bottom" to (box?.bottom?.toDouble() ?: 0.0),
                                        "confidence" to element.confidence?.toDouble(),
                                    )
                                    elements.add(word)
                                    lineWords.add(word)

                                    // Symbol-level geometry when the API exposes it.
                                    try {
                                        val symbolsMethod = element.javaClass.methods
                                            .firstOrNull { it.name == "getSymbols" && it.parameterCount == 0 }
                                        val symbolList = symbolsMethod?.invoke(element) as? List<*>
                                        if (symbolList != null) {
                                            for (sym in symbolList) {
                                                if (sym == null) continue
                                                val text = sym.javaClass.methods
                                                    .firstOrNull { it.name == "getText" && it.parameterCount == 0 }
                                                    ?.invoke(sym) as? String
                                                val sBox = sym.javaClass.methods
                                                    .firstOrNull { it.name == "getBoundingBox" && it.parameterCount == 0 }
                                                    ?.invoke(sym) as? android.graphics.Rect
                                                val conf = sym.javaClass.methods
                                                    .firstOrNull { it.name == "getConfidence" && it.parameterCount == 0 }
                                                    ?.invoke(sym) as? Float
                                                if (text != null) {
                                                    symbols.add(
                                                        mapOf(
                                                            "text" to text,
                                                            "left" to (sBox?.left?.toDouble() ?: 0.0),
                                                            "top" to (sBox?.top?.toDouble() ?: 0.0),
                                                            "right" to (sBox?.right?.toDouble() ?: 0.0),
                                                            "bottom" to (sBox?.bottom?.toDouble() ?: 0.0),
                                                            "confidence" to conf?.toDouble(),
                                                        ),
                                                    )
                                                }
                                            }
                                        }
                                    } catch (_: Exception) {
                                        // Symbol API not present on this ML Kit version.
                                    }
                                }
                                lines.add(
                                    mapOf(
                                        "text" to line.text,
                                        "left" to (lineBox?.left?.toDouble() ?: 0.0),
                                        "top" to (lineBox?.top?.toDouble() ?: 0.0),
                                        "right" to (lineBox?.right?.toDouble() ?: 0.0),
                                        "bottom" to (lineBox?.bottom?.toDouble() ?: 0.0),
                                        "confidence" to line.confidence?.toDouble(),
                                        "words" to lineWords,
                                    ),
                                )
                            }
                        }
                        result.success(
                            mapOf(
                                "engineName" to "mlkit_latin_bundled",
                                "engineVersion" to "text-recognition",
                                "imageWidth" to bitmap.width,
                                "imageHeight" to bitmap.height,
                                "elements" to elements,
                                "lines" to lines,
                                "symbols" to symbols,
                                "coordinateSpace" to "rectified_image_pixels",
                            ),
                        )
                    }
                    .addOnFailureListener { e ->
                        result.error("ocr_failed", e.message, null)
                    }
            }
            else -> result.notImplemented()
        }
    }
}
