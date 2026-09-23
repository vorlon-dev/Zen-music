package com.zen.music.zenmusic

import android.os.Handler
import android.os.Looper
import cc.tomko.outify.SpotifyPlaybackBridge
import com.ryanheise.audioservice.AudioServiceActivity
import com.zen.music.zenmusic.extensions.ZenExtensionManager
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject

class MainActivity : AudioServiceActivity() {
    private lateinit var extensionManager: ZenExtensionManager
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        SpotifyPlaybackBridge.registerChannels(
            applicationContext,
            flutterEngine.dartExecutor.binaryMessenger,
        )
        registerExtensions(flutterEngine)
    }

    private fun registerExtensions(flutterEngine: FlutterEngine) {
        extensionManager = ZenExtensionManager(applicationContext)
        extensionManager.restoreInstalled()

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "zen/extensions")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "list" -> result.success(extensionManager.list().toString())
                    "install" -> {
                        val path = call.argument<String>("uri") ?: ""
                        extensionManager.installFromPath(path).fold(
                            onSuccess = {
                                result.success(mapOf("id" to it.id, "name" to it.name))
                            },
                            onFailure = {
                                result.error("INSTALL_FAILED", it.message, null)
                            }
                        )
                    }
                    "select" -> result.success(
                        extensionManager.select(call.argument<String>("id") ?: "")
                    )
                    "deselect" -> result.success(extensionManager.clearActive())
                    "homeFeed" -> {
                        Thread {
                            try {
                                val json = extensionManager.homeFeed()
                                mainHandler.post { result.success(json) }
                            } catch (t: Throwable) {
                                mainHandler.post {
                                    result.error("HOME_FEED_FAILED", t.message, null)
                                }
                            }
                        }.start()
                    }
                    "search" -> {
                        val query = call.argument<String>("query") ?: ""
                        Thread {
                            try {
                                val json = extensionManager.search(query)
                                mainHandler.post { result.success(json.toString()) }
                            } catch (t: Throwable) {
                                mainHandler.post {
                                    result.error("SEARCH_FAILED", t.message, null)
                                }
                            }
                        }.start()
                    }
                    "loadDetail" -> {
                        val itemJson = call.argument<String>("item") ?: "{}"
                        Thread {
                            try {
                                val json = extensionManager.loadDetail(itemJson)
                                mainHandler.post { result.success(json.toString()) }
                            } catch (t: Throwable) {
                                mainHandler.post {
                                    result.error("LOAD_DETAIL_FAILED", t.message, null)
                                }
                            }
                        }.start()
                    }
                    "resolveStream" -> {
                        val trackJson =
                            JSONObject(call.argument<String>("track") ?: "{}")
                        Thread {
                            try {
                                val stream = extensionManager.resolveStream(trackJson)
                                mainHandler.post { result.success(stream.toString()) }
                            } catch (t: Throwable) {
                                mainHandler.post {
                                    result.error("RESOLVE_FAILED", t.message, null)
                                }
                            }
                        }.start()
                    }
                    else -> result.notImplemented()
                }
            }
    }
}