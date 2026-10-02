package com.zen.music.zenmusic

import android.Manifest
import android.annotation.SuppressLint
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
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
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject

class MainActivity : AudioServiceActivity() {
    private lateinit var extensionManager: ZenExtensionManager
    private val mainHandler = Handler(Looper.getMainLooper())

    private var audioDeviceEvents: EventChannel.EventSink? = null
    private var audioReceiver: BroadcastReceiver? = null
    private var volumeEvents: EventChannel.EventSink? = null
    private var volumeReceiver: BroadcastReceiver? = null
    private var bluetoothPermissionResult: MethodChannel.Result? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Full-screen under the display cutout (notch) — no black
        // status-bar strip when the system bars are hidden.
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
        InstallApkPlugin.register(flutterEngine, this)
    }

    // ═══════════════════════════════════════════
    // AUDIO DEVICE EVENTS — receiver-only (do NOT re-add
    // AudioDeviceCallback — unresolved in this toolchain).
    // RACE NOTE: ACL_DISCONNECTED fires before A2DP teardown — the
    // delayed re-pushes (500/1200ms) read the settled state. Do not
    // remove them.
    // ═══════════════════════════════════════════

    private fun registerAudioDeviceEvents(flutterEngine: FlutterEngine) {
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "zen/audio_device")
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(args: Any?, events: EventChannel.EventSink?) {
                    audioDeviceEvents = events
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
                    registerReceiver(receiver, filter)
                }

                override fun onCancel(args: Any?) {
                    audioReceiver?.let {
                        try {
                            unregisterReceiver(it)
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
    // VOLUME EVENTS — STREAM_MUSIC {volume, max} on change + subscribe.
    // ═══════════════════════════════════════════

    private fun registerVolumeEvents(flutterEngine: FlutterEngine) {
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "zen/volume_events")
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(args: Any?, events: EventChannel.EventSink?) {
                    volumeEvents = events
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
                    registerReceiver(
                        receiver, IntentFilter("android.media.VOLUME_CHANGED_ACTION")
                    )
                }

                override fun onCancel(args: Any?) {
                    volumeReceiver?.let {
                        try {
                            unregisterReceiver(it)
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