package com.zen.music.zenmusic

import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
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
                            // Android 8+: installing from outside the store
                            // requires the per-app "Install unknown apps"
                            // consent. Without it the installer intent
                            // dead-ends on several OEMs — open the consent
                            // screen instead and report false to Dart (the
                            // APK stays cached, so the next tap on Update
                            // goes straight to install).
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
                                !activity.packageManager.canRequestPackageInstalls()
                            ) {
                                activity.startActivity(
                                    Intent(
                                        Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                                        Uri.parse("package:${activity.packageName}")
                                    )
                                )
                                result.success(false)
                                return@setMethodCallHandler
                            }

                            val file = File(path)
                            val uri: Uri = FileProvider.getUriForFile(
                                activity,
                                "${activity.packageName}.fileprovider",
                                file
                            )
                            // ACTION_INSTALL_PACKAGE is the documented
                            // installer entry point (ACTION_VIEW with a
                            // package-archive MIME is increasingly
                            // unreliable on newer Android versions).
                            val intent = Intent(Intent.ACTION_INSTALL_PACKAGE).apply {
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