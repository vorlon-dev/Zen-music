package com.zen.music.zenmusic

import android.Manifest
import android.annotation.SuppressLint
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.WindowManager
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.core.view.WindowCompat
import cc.tomko.outify.SpotifyPlaybackBridge
import com.ryanheise.audioservice.AudioServiceActivity
import com.zen.music.zenmusic.extensions.ZenExtensionManager
import com.zen.music.zenmusic.innertubex.InnerTubeXResolver
import com.zen.music.zenmusic.innertubex.itxDebugLogs
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import timber.log.Timber

class MainActivity : AudioServiceActivity() {
    private lateinit var extensionManager: ZenExtensionManager
    private val mainHandler = Handler(Looper.getMainLooper())

    // Audio-device (Bluetooth) event stream state.
    private var audioDeviceEvents: EventChannel.EventSink? = null
    private var audioReceiver: BroadcastReceiver? = null

    // Volume events + audio channel state.
    private var volumeEvents: EventChannel.EventSink? = null
    private var volumeReceiver: BroadcastReceiver? = null
    private var bluetoothPermissionResult: MethodChannel.Result? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Full-screen under the display cutout (notch) — no black
        // status-bar strip when the system bars are hidden. Flutter
        // has no API for this; it must be set natively. The window
        // extends into the cutout on ALL edges (ALWAYS on API 30+,
        // SHORT_EDGES on API 28-29; pre-28 devices have no cutout
        // reporting and need nothing).
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            WindowCompat.setDecorFitsSystemWindows(window, false)
            window.attributes.layoutInDisplayCutoutMode =
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                    WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_ALWAYS
                } else {
                    WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
                }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        SpotifyPlaybackBridge.registerChannels(
            applicationContext,
            flutterEngine.dartExecutor.binaryMessenger,
        )
        registerExtensions(flutterEngine)
        registerAudioDeviceEvents(flutterEngine)
        registerVolumeEvents(flutterEngine)
        registerAudioChannel(flutterEngine)
        registerInnertubexChannel(flutterEngine)
        // In-app APK installer channel (OTA updates)
        InstallApkPlugin.register(flutterEngine, this)
        // Flutter apps have no BuildConfig — use the runtime debuggable
        // flag instead. Also gates the innertubex package's verbose logs.
        val isDebuggable =
            (applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0
        if (isDebuggable) Timber.plant(Timber.DebugTree())
        itxDebugLogs = isDebuggable
        InnerTubeXResolver.init(applicationContext)
    }

    // ═══════════════════════════════════════════
    // AUDIO DEVICE (Bluetooth) EVENTS — receiver-only (do NOT re-add
    // AudioDeviceCallback — unresolved in this project's toolchain;
    // the broadcast set fully covers the feature).
    //
    // LEAK-SAFE REGISTRATION (do not revert): receivers register on
    // applicationContext, NEVER on the Activity. The Dart listener is
    // app-lifetime and never cancels, so if the Activity is destroyed
    // first (hot restart, background kill/restore), onCancel never runs
    // — an Activity-tied receiver would leak (IntentReceiverLeaked).
    // Application-context receivers are process-scoped: no leak.
    // onListen also unregisters any previous receiver first, so engine
    // restarts without onCancel never accumulate duplicates.
    //
    // RACE NOTE (do not remove the delayed re-pushes): ACL_DISCONNECTED
    // fires BEFORE the A2DP profile teardown completes, so the device
    // is still present in getDevices() when the broadcast arrives.
    // Re-checking at +500ms and +1200ms reads the settled state — the
    // disconnect then pushes null. Repeated pushes are harmless:
    // Dart's ValueNotifier ignores same-value writes.
    // ═══════════════════════════════════════════

    private fun registerAudioDeviceEvents(flutterEngine: FlutterEngine) {
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "zen/audio_device")
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(args: Any?, events: EventChannel.EventSink?) {
                    audioDeviceEvents = events
                    // Drop any leftover receiver (engine restart without
                    // onCancel) before registering a fresh one.
                    audioReceiver?.let {
                        try {
                            applicationContext.unregisterReceiver(it)
                        } catch (_: Exception) {
                        }
                    }
                    scheduleAudioDevicePushes()

                    val filter = IntentFilter().apply {
                        addAction(Intent.ACTION_HEADSET_PLUG)
                        addAction("android.bluetooth.adapter.action.STATE_CHANGED")
                        addAction("android.bluetooth.device.action.ACL_CONNECTED")
                        addAction("android.bluetooth.device.action.ACL_DISCONNECTED")
                        addAction("android.media.AUDIO_BECOMING_NOISY")
                    }
                    val receiver = object : BroadcastReceiver() {
                        override fun onReceive(context: Context?, intent: Intent?) {
                            scheduleAudioDevicePushes()
                        }
                    }
                    audioReceiver = receiver
                    applicationContext.registerReceiver(receiver, filter)
                }

                override fun onCancel(args: Any?) {
                    audioReceiver?.let {
                        try {
                            applicationContext.unregisterReceiver(it)
                        } catch (_: Exception) {
                        }
                    }
                    audioReceiver = null
                    audioDeviceEvents = null
                    mainHandler.removeCallbacksAndMessages(AUDIO_DEVICE_TOKEN)
                }
            })
    }

    private val AUDIO_DEVICE_TOKEN = Any()

    /// Immediate push + settled-state re-pushes (see the race note).
    private fun scheduleAudioDevicePushes() {
        pushAudioDeviceName()
        mainHandler.postDelayed(
            { pushAudioDeviceName() }, AUDIO_DEVICE_TOKEN, 500L
        )
        mainHandler.postDelayed(
            { pushAudioDeviceName() }, AUDIO_DEVICE_TOKEN, 1200L
        )
    }

    private fun pushAudioDeviceName() {
        audioDeviceEvents?.success(connectedBluetoothDeviceName())
    }

    /// The active Bluetooth output device's product name, or null.
    /// getDevices(OUTPUTS) is the source of truth on API 23+.
    private fun connectedBluetoothDeviceName(): String? {
        val audioManager =
            getSystemService(Context.AUDIO_SERVICE) as AudioManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val audioDevices =
                audioManager.getDevices(AudioManager.GET_DEVICES_OUTPUTS)
            val activeBluetoothDevice =
                audioDevices.find { it.type == AudioDeviceInfo.TYPE_BLUETOOTH_A2DP }
                    ?: audioDevices.find { it.type == AudioDeviceInfo.TYPE_BLUETOOTH_SCO }
            return activeBluetoothDevice?.productName?.toString()
        }
        @Suppress("DEPRECATION")
        if (!(audioManager.isBluetoothA2dpOn || audioManager.isBluetoothScoOn)) {
            return null
        }
        return null
    }

    // ═══════════════════════════════════════════
    // INNERTUBEX — Tier-0 stream extraction (cipher-resilient,
    // benchmarked client catalog). Round A: channel only; the Dart
    // tier-0 wiring lands in Round B.
    // ═══════════════════════════════════════════

    private fun registerInnertubexChannel(flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "zen/innertubex")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "extract" -> {
                        val videoId = call.argument<String>("videoId") ?: ""
                        val maxKbps = call.argument<Int>("maxKbps") ?: 160
                        val requireM4a = call.argument<Boolean>("requireM4a") ?: false
                        val skip = (call.argument<List<String>>("skipClients") ?: emptyList()).toSet()
                        Thread {
                            try {
                                val ex = InnerTubeXResolver.extractBlocking(
                                    videoId, maxKbps, skip, requireM4a
                                )
                                mainHandler.post {
                                    if (ex == null) {
                                        result.success(null)
                                    } else {
                                        result.success(
                                            mapOf(
                                                "videoId" to ex.videoId,
                                                "url" to ex.url,
                                                "kbps" to ex.kbps,
                                                "mimeType" to ex.mimeType,
                                                "loudnessDb" to ex.loudnessDb,
                                                "clientName" to ex.clientName,
                                                "profileId" to ex.profileId,
                                                "headers" to ex.headers,
                                            )
                                        )
                                    }
                                }
                            } catch (t: Throwable) {
                                mainHandler.post {
                                    result.error("EXTRACT_FAILED", t.message, null)
                                }
                            }
                        }.start()
                    }
                    "headersFor" -> {
                        val url = call.argument<String>("url") ?: ""
                        result.success(InnerTubeXResolver.headersFor(url))
                    }
                    "onRefused" -> {
                        val url = call.argument<String>("url") ?: ""
                        result.success(InnerTubeXResolver.onRefused(url))
                    }
                    "onSessionChanged" -> {
                        InnerTubeXResolver.onSessionChanged()
                        result.success(null)
                    }
                    "getVisitorData" -> {
                        Thread {
                            val vd = InnerTubeXResolver.visitorDataBlocking()
                            mainHandler.post { result.success(vd) }
                        }.start()
                    }
                    else -> result.notImplemented()
                }
            }
    }

    // ═══════════════════════════════════════════
    // VOLUME EVENTS — STREAM_MUSIC {volume, max} on change + subscribe.
    // Same leak-safe registration as above (applicationContext +
    // idempotent onListen).
    // ═══════════════════════════════════════════

    private fun registerVolumeEvents(flutterEngine: FlutterEngine) {
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "zen/volume_events")
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(args: Any?, events: EventChannel.EventSink?) {
                    volumeEvents = events
                    volumeReceiver?.let {
                        try {
                            applicationContext.unregisterReceiver(it)
                        } catch (_: Exception) {
                        }
                    }
                    pushVolume()

                    val receiver = object : BroadcastReceiver() {
                        override fun onReceive(context: Context?, intent: Intent?) {
                            val stream = intent?.getIntExtra(
                                "android.media.EXTRA_VOLUME_STREAM_TYPE", -1
                            ) ?: -1
                            if (stream == AudioManager.STREAM_MUSIC) {
                                pushVolume()
                            }
                        }
                    }
                    volumeReceiver = receiver
                    applicationContext.registerReceiver(
                        receiver, IntentFilter("android.media.VOLUME_CHANGED_ACTION")
                    )
                }

                override fun onCancel(args: Any?) {
                    volumeReceiver?.let {
                        try {
                            applicationContext.unregisterReceiver(it)
                        } catch (_: Exception) {
                        }
                    }
                    volumeReceiver = null
                    volumeEvents = null
                }
            })
    }

    private fun pushVolume() {
        val audioManager =
            getSystemService(Context.AUDIO_SERVICE) as AudioManager
        volumeEvents?.success(
            mapOf(
                "volume" to audioManager.getStreamVolume(AudioManager.STREAM_MUSIC),
                "max" to audioManager.getStreamMaxVolume(AudioManager.STREAM_MUSIC),
            )
        )
    }

    // ═══════════════════════════════════════════
    // AUDIO CHANNEL — enumeration, volume, BT permission.
    // ═══════════════════════════════════════════

    private fun registerAudioChannel(flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "zen/audio")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "listDevices" -> result.success(outputDevices())
                    "getVolume" -> {
                        val audioManager =
                            getSystemService(Context.AUDIO_SERVICE) as AudioManager
                        result.success(
                            mapOf(
                                "volume" to
                                        audioManager.getStreamVolume(AudioManager.STREAM_MUSIC),
                                "max" to
                                        audioManager.getStreamMaxVolume(AudioManager.STREAM_MUSIC),
                            )
                        )
                    }
                    "setVolume" -> {
                        val v = (call.arguments as? Number)?.toInt()
                        if (v == null) {
                            result.error("BAD_ARGS", "volume int expected", null)
                        } else {
                            val audioManager =
                                getSystemService(Context.AUDIO_SERVICE) as AudioManager
                            audioManager.setStreamVolume(
                                AudioManager.STREAM_MUSIC,
                                v.coerceIn(0, audioManager.getStreamMaxVolume(AudioManager.STREAM_MUSIC)),
                                0,
                            )
                            result.success(null)
                        }
                    }
                    "requestBluetoothPermission" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
                            ContextCompat.checkSelfPermission(
                                this, Manifest.permission.BLUETOOTH_CONNECT
                            ) != PackageManager.PERMISSION_GRANTED
                        ) {
                            bluetoothPermissionResult = result
                            ActivityCompat.requestPermissions(
                                this,
                                arrayOf(Manifest.permission.BLUETOOTH_CONNECT),
                                4001,
                            )
                        } else {
                            result.success(true)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 4001) {
            bluetoothPermissionResult?.success(
                grantResults.isNotEmpty() &&
                        grantResults[0] == PackageManager.PERMISSION_GRANTED
            )
            bluetoothPermissionResult = null
        }
    }

    /// All audio output devices:
    /// {name, type: bluetooth|wired|usb|hdmi|speaker, battery?, id}.
    private fun outputDevices(): List<Map<String, Any?>> {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return emptyList()
        val audioManager =
            getSystemService(Context.AUDIO_SERVICE) as AudioManager
        val out = mutableListOf<Map<String, Any?>>()
        val hasBtPermission =
            Build.VERSION.SDK_INT < Build.VERSION_CODES.S ||
                    ContextCompat.checkSelfPermission(
                        this, Manifest.permission.BLUETOOTH_CONNECT
                    ) == PackageManager.PERMISSION_GRANTED

        for (d in audioManager.getDevices(AudioManager.GET_DEVICES_OUTPUTS)) {
            val type = when (d.type) {
                AudioDeviceInfo.TYPE_BLUETOOTH_A2DP,
                AudioDeviceInfo.TYPE_BLUETOOTH_SCO -> "bluetooth"
                AudioDeviceInfo.TYPE_WIRED_HEADPHONES,
                AudioDeviceInfo.TYPE_WIRED_HEADSET -> "wired"
                AudioDeviceInfo.TYPE_USB_HEADSET,
                AudioDeviceInfo.TYPE_USB_DEVICE,
                AudioDeviceInfo.TYPE_USB_ACCESSORY -> "usb"
                AudioDeviceInfo.TYPE_HDMI -> "hdmi"
                AudioDeviceInfo.TYPE_BUILTIN_SPEAKER -> "speaker"
                else -> null
            } ?: continue

            val battery =
                if (d.type == AudioDeviceInfo.TYPE_BLUETOOTH_A2DP && hasBtPermission) {
                    // Match by MAC ADDRESS first (exact — productName
                    // often differs from the Bluetooth device name),
                    // falling back to a name match.
                    @SuppressLint("MissingPermission")
                    val address = try {
                        d.address
                    } catch (_: Exception) {
                        null
                    }
                    btBatteryLevel(
                        d.productName?.toString(), address
                    )
                } else {
                    null
                }

            out.add(
                mapOf(
                    "name" to (d.productName?.toString() ?: "Audio device"),
                    "type" to type,
                    "battery" to battery,
                    "id" to d.id,
                )
            )
        }
        return out
    }

    /// Battery of the BT device, via the hidden getBatteryLevel()
    /// (same approach as the reference). Address match is exact;
    /// junk reads (null, <= 0, > 100) return null so the UI shows
    /// no ring instead of a wrong percentage.
    private fun btBatteryLevel(name: String?, address: String?): Int? {
        return try {
            val manager =
                getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
                    ?: return null
            val adapter = manager.adapter ?: return null
            val hasPerm =
                Build.VERSION.SDK_INT < Build.VERSION_CODES.S ||
                        ContextCompat.checkSelfPermission(
                            this, Manifest.permission.BLUETOOTH_CONNECT
                        ) == PackageManager.PERMISSION_GRANTED
            if (!hasPerm) return null

            val candidates: List<BluetoothDevice> = buildList {
                @SuppressLint("MissingPermission")
                if (!address.isNullOrEmpty() && address.contains(":")) {
                    try {
                        adapter.getRemoteDevice(address)?.let { add(it) }
                    } catch (_: Exception) {
                    }
                }
                @SuppressLint("MissingPermission")
                if (isEmpty() && !name.isNullOrEmpty()) {
                    adapter.bondedDevices
                        ?.filter { it.name == name }
                        ?.let { addAll(it) }
                }
            }
            if (candidates.isEmpty()) return null

            for (d in candidates) {
                @SuppressLint("MissingPermission")
                val level = try {
                    BluetoothDevice::class.java
                        .getMethod("getBatteryLevel")
                        .invoke(d) as? Int
                } catch (_: Exception) {
                    null
                }
                if (level != null && level in 1..100) return level
            }
            null
        } catch (_: Exception) {
            null
        }
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
                    "homeFeedPage" -> {
                        val continuation = call.argument<String>("continuation")
                        Thread {
                            try {
                                val json = extensionManager.homeFeedPage(continuation)
                                mainHandler.post { result.success(json.toString()) }
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