package com.example.gmwf

import android.content.ClipData
import android.content.Intent
import android.net.Uri
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.gmwf.app/whatsapp_share"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "sharePdfToWhatsAppNumber") {
                val filePath = call.argument<String>("filePath")
                val text = call.argument<String>("text")

                if (filePath == null) {
                    result.error("INVALID_PATH", "File path is null", null)
                    return@setMethodCallHandler
                }

                try {
                    val file = File(filePath)
                    if (!file.exists()) {
                        result.error("FILE_NOT_FOUND", "File does not exist at $filePath", null)
                        return@setMethodCallHandler
                    }

                    val fileUri: Uri = FileProvider.getUriForFile(
                        context,
                        "${context.packageName}.fileprovider",
                        file
                    )

                    val intent = Intent(Intent.ACTION_SEND).apply {
                        type = "application/pdf"
                        putExtra(Intent.EXTRA_STREAM, fileUri)
                        clipData = ClipData.newRawUri("Prescription PDF", fileUri)
                        if (!text.isNullOrEmpty()) {
                            putExtra(Intent.EXTRA_TEXT, text)
                        }
                        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                    }

                    // 1. Try standard WhatsApp (com.whatsapp)
                    intent.setPackage("com.whatsapp")
                    if (intent.resolveActivity(packageManager) != null) {
                        startActivity(intent)
                        result.success(true)
                        return@setMethodCallHandler
                    }

                    // 2. Try WhatsApp Business (com.whatsapp.w4b)
                    intent.setPackage("com.whatsapp.w4b")
                    if (intent.resolveActivity(packageManager) != null) {
                        startActivity(intent)
                        result.success(true)
                        return@setMethodCallHandler
                    }

                    // 3. Fallback to chooser without package lock
                    intent.setPackage(null)
                    val chooser = Intent.createChooser(intent, "Share Prescription PDF")
                    startActivity(chooser)
                    result.success(true)
                } catch (e: Exception) {
                    result.error("SHARE_FAILED", e.localizedMessage, null)
                }
            } else {
                result.notImplemented()
            }
        }
    }
}
