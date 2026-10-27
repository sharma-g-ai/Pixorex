package com.amzur.equiptrack

import android.app.Activity
import android.content.Intent
import android.content.IntentSender
import com.google.mlkit.vision.documentscanner.GmsDocumentScannerOptions
import com.google.mlkit.vision.documentscanner.GmsDocumentScanning
import com.google.mlkit.vision.documentscanner.GmsDocumentScanningResult
import com.amzur.equiptrack.ppg.PpgOcrPlugin
import com.amzur.equiptrack.ppg.PpgCanOcrPlugin
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

class MainActivity : FlutterActivity() {
    private var canOcr: PpgCanOcrPlugin? = null
    private var pendingDocumentScan: MethodChannel.Result? = null
    private var pendingAllPages = false
    private val documentScannerRequestCode = 0x5050

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.amzur.equiptrack/ppg_ocr",
        ).setMethodCallHandler(PpgOcrPlugin())

        canOcr = PpgCanOcrPlugin()
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger,
            "com.amzur.equiptrack/ppg_can_ocr").setMethodCallHandler(canOcr)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.amzur.equiptrack/document_scanner",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "scanDocument" -> startDocumentScan(result)
                // Multi-page variant used by the scanner research benchmark;
                // returns every page instead of only the first.
                "scanDocumentPages" -> startDocumentScan(
                    result,
                    pageLimit = call.argument<Int>("pageLimit") ?: 1,
                    scannerMode = when (call.argument<String>("mode")) {
                        "base" -> GmsDocumentScannerOptions.SCANNER_MODE_BASE
                        "base_with_filter" -> GmsDocumentScannerOptions.SCANNER_MODE_BASE_WITH_FILTER
                        else -> GmsDocumentScannerOptions.SCANNER_MODE_FULL
                    },
                    allPages = true,
                )
                else -> result.notImplemented()
            }
        }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger,
            "com.amzur.equiptrack/ppg_can_ocr").setMethodCallHandler(null)
        canOcr?.close()
        canOcr = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    private fun startDocumentScan(
        result: MethodChannel.Result,
        pageLimit: Int = 1,
        scannerMode: Int = GmsDocumentScannerOptions.SCANNER_MODE_FULL,
        allPages: Boolean = false,
    ) {
        if (pendingDocumentScan != null) {
            result.error("busy", "A document scan is already in progress", null)
            return
        }
        pendingDocumentScan = result
        pendingAllPages = allPages
        val options = GmsDocumentScannerOptions.Builder()
            .setGalleryImportAllowed(false)
            .setPageLimit(pageLimit)
            .setResultFormats(GmsDocumentScannerOptions.RESULT_FORMAT_JPEG)
            .setScannerMode(scannerMode)
            .build()
        GmsDocumentScanning.getClient(options)
            .getStartScanIntent(this)
            .addOnSuccessListener { sender ->
                try {
                    startIntentSenderForResult(
                        sender,
                        documentScannerRequestCode,
                        null,
                        0,
                        0,
                        0,
                    )
                } catch (error: IntentSender.SendIntentException) {
                    pendingDocumentScan?.error("scanner_launch_failed", error.message, null)
                    pendingDocumentScan = null
                }
            }
            .addOnFailureListener { error ->
                pendingDocumentScan?.error("scanner_unavailable", error.message, null)
                pendingDocumentScan = null
            }
    }

    @Deprecated("Deprecated by Android, retained for FlutterActivity result handling")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != documentScannerRequestCode) return
        val pending = pendingDocumentScan ?: return
        pendingDocumentScan = null
        if (resultCode == Activity.RESULT_CANCELED) {
            pending.success(null)
            return
        }
        if (resultCode != Activity.RESULT_OK) {
            pending.error("scan_failed", "Document scanner did not complete", null)
            return
        }
        try {
            val scan = GmsDocumentScanningResult.fromActivityResultIntent(data)
                ?: throw IllegalStateException("Document scanner returned no result")
            val pages = scan.pages
            if (pages.isNullOrEmpty()) {
                throw IllegalStateException("Document scanner returned no page image")
            }
            val stamp = System.currentTimeMillis()
            val paths = (if (pendingAllPages) pages else pages.take(1)).mapIndexed { index, page ->
                val file = File(cacheDir, "ppg_document_scan_${stamp}_$index.jpg")
                contentResolver.openInputStream(page.imageUri)?.use { input ->
                    FileOutputStream(file).use { output -> input.copyTo(output) }
                } ?: throw IllegalStateException("Could not read scanned page image")
                file.absolutePath
            }
            pending.success(if (pendingAllPages) paths else paths.first())
        } catch (error: Exception) {
            pending.error("scan_result_error", error.message, null)
        }
    }
}
