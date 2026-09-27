package com.zen.music.zenmusic

import android.content.Intent
import android.net.Uri
import androidx.core.content.FileProvider
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

object InstallApkPlugin {
    private const val CHANNEL = "com.zen.music.install_apk"

    fun register(messenger: FlutterEngine, activity: MainActivity) {
        MethodChannel(messenger.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "install" -> {
                        val path = call.argument<String>("path")
                        if (path == null) {
                            result.error("INVALID", "path missing", null)
                            return@setMethodCallHandler
                        }
                        try {
                            val file = File(path)
                            val uri: Uri = FileProvider.getUriForFile(
                                activity,
                                "${activity.packageName}.fileprovider",
                                file
                            )
                            val intent = Intent(Intent.ACTION_VIEW).apply {
                                setDataAndType(uri, "application/vnd.android.package-archive")
                                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            }
                            activity.startActivity(intent)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("INSTALL_FAILED", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }
}