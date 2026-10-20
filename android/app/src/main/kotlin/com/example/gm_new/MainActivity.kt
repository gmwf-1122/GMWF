package com.example.gm_new

import android.content.ClipData
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.gmwf.app/whatsapp_share"
    private val INSTALL_CHANNEL = "com.gmwf.app/install"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // WhatsApp share channel
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

        // APK install channel — validates integrity, checks install unknown apps permission,
        // and uses FileProvider with explicit URI grant to prevent 'App not installed' errors.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, INSTALL_CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "installApk") {
                val filePath = call.argument<String>("filePath")

                if (filePath == null) {
                    result.error("INVALID_PATH", "APK file path is null", null)
                    return@setMethodCallHandler
                }

                try {
                    val file = File(filePath)
                    if (!file.exists() || file.length() < 1024 * 100) {
                        result.error("FILE_NOT_FOUND", "APK file does not exist or is incomplete at $filePath", null)
                        return@setMethodCallHandler
                    }

                    // 1. Pre-validate APK integrity before launching installer
                    val archiveInfo = packageManager.getPackageArchiveInfo(file.absolutePath, 0)
                    if (archiveInfo == null) {
                        result.error(
                            "PARSE_FAILED",
                            "Downloaded APK package parser verification failed (file may be corrupted or architecture incompatible). Please retry download.",
                            null
                        )
                        return@setMethodCallHandler
                    }

                    // 2. On Android 8.0+ (Oreo+), check if unknown sources permission is granted
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        if (!packageManager.canRequestPackageInstalls()) {
                            // Direct user to settings to allow install from this app
                            val settingsIntent = Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES).apply {
                                data = Uri.parse("package:${context.packageName}")
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            }
                            startActivity(settingsIntent)
                            result.error(
                                "PERMISSION_DENIED",
                                "Permission required: Please allow 'Install unknown apps' for GMWF in Settings, then tap Update again.",
                                null
                            )
                            return@setMethodCallHandler
                        }
                    }

                    // 3. Construct install intent with required flags
                    val intent = Intent(Intent.ACTION_VIEW).apply {
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP)
                        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                        putExtra(Intent.EXTRA_NOT_UNKNOWN_SOURCE, true)
                    }

                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                        val contentUri = FileProvider.getUriForFile(
                            context,
                            "${context.packageName}.fileprovider",
                            file
                        )
                        intent.setDataAndType(contentUri, "application/vnd.android.package-archive")

                        // Explicitly grant URI read permissions to package installer activities
                        val resolveList = packageManager.queryIntentActivities(intent, 0)
                        for (resolveInfo in resolveList) {
                            val pkg = resolveInfo.activityInfo.packageName
                            context.grantUriPermission(pkg, contentUri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
                        }
                    } else {
                        intent.setDataAndType(Uri.fromFile(file), "application/vnd.android.package-archive")
                    }

                    startActivity(intent)
                    result.success(true)
                } catch (e: Exception) {
                    result.error("INSTALL_FAILED", e.localizedMessage, null)
                }
            } else {
                result.notImplemented()
            }
        }
    }
}
