package cc.tomko.outify

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import cc.tomko.outify.core.AuthManager
import cc.tomko.outify.core.Session
import cc.tomko.outify.core.SessionCallback
import cc.tomko.outify.core.spirc.Spirc
import cc.tomko.outify.core.spirc.SpircBufferCallback
import cc.tomko.outify.core.spirc.SpircDeviceCallback
import cc.tomko.outify.core.spirc.SpircInitializationCallback
import cc.tomko.outify.playback.AudioEngine
import cc.tomko.outify.playback.PlaybackStateHolder
import cc.tomko.outify.playback.callbacks.PlayerEventCallback
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

object SpotifyPlaybackBridge : EventChannel.StreamHandler {
    private const val LIB_NAME = "librespot_ffi"

    private var appContext: Context? = null
    private var engine: AudioEngine? = null
    private var eventSink: EventChannel.EventSink? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    private var oauthServer: OAuthCallbackServer? = null

    private var sessionReady = false
    private var spircReady = false

    fun registerChannels(
        context: Context,
        messenger: BinaryMessenger,
    ) {
        System.loadLibrary(LIB_NAME)

        MethodChannel(messenger, "zen/spotify").setMethodCallHandler { call, result ->
            val safe = { block: () -> Boolean ->
                try {
                    block()
                } catch (t: Throwable) {
                    android.util.Log.e("SpotifyBridge", "${call.method} failed", t)
                    false
                }
            }
            when (call.method) {
                "initialize" -> {
                    val clientId = call.argument<String>("clientId") ?: ""
                    val clientSecret = call.argument<String>("clientSecret") ?: ""
                    result.success(initialize(context.applicationContext, clientId, clientSecret))
                }
                "hasCachedCredentials" -> result.success(safe {
                    AuthManager().hasCachedCredentials()
                })
                "startLogin" -> {
                    val url = startLogin(context.applicationContext)
                    result.success(url)
                }
                "logout" -> result.success(safe { AuthManager.logout() })
                "load" -> result.success(safe {
                    Spirc.load(call.argument<String>("uri"), call.argument<String>("playingTrack"))
                })
                "setQueue" -> result.success(safe {
                    val uris = call.argument<List<String>>("uris")?.toTypedArray()
                    val playingTrack = call.argument<String>("playingTrack")
                    if (uris != null) Spirc.setQueue(uris, playingTrack) else false
                })
                "addToQueue" -> result.success(safe {
                    Spirc.addToQueue(call.argument<String>("uri"))
                })
                "play" -> result.success(safe { Spirc.playerPlay() })
                "pause" -> result.success(safe { Spirc.playerPause() })
                "playPause" -> result.success(safe { Spirc.playerPlayPause() })
                "next" -> result.success(safe { Spirc.playerNext() })
                "previous" -> result.success(safe { Spirc.playerPrevious() })
                "seekTo" -> result.success(safe {
                    Spirc.seekTo((call.argument<Number>("positionMs") ?: 0L).toLong())
                })
                "shuffle" -> result.success(safe {
                    Spirc.shuffle(call.argument<Boolean>("enabled") == true)
                })
                "repeat" -> result.success(safe {
                    Spirc.repeat(
                        call.argument<Boolean>("repeat") == true,
                        call.argument<Boolean>("repeatTrack") == true,
                    )
                })
                "setVolume" -> result.success(safe {
                    Spirc.setVolume((call.argument<Number>("volume") ?: 32768).toInt())
                })
                "nextTracks" -> result.success(runCatching { Spirc.nextTracks() }.getOrNull())
                "previousTracks" -> result.success(runCatching { Spirc.previousTracks() }.getOrNull())
                else -> result.notImplemented()
            }
        }

        EventChannel(messenger, "zen/spotify_events").setStreamHandler(this)
    }

    private fun sendEvent(type: String, data: Map<String, Any?> = emptyMap()) {
        mainHandler.post {
            eventSink?.success(mapOf("type" to type) + data)
        }
    }

    // ── Boot chain: libInit → Session → Spirc ──

    private fun initialize(context: Context, clientId: String, clientSecret: String): Boolean {
        if (engine != null) return sessionReady && spircReady
        appContext = context

        // 1. Rust world init (tokio runtimes, logger, credentials).
        LibrespotFfi.libInit(context, clientId, clientSecret)

        // 2. Audio engine — registers PCM callback + player event listener in Rust.
        engine = AudioEngine(context, playerEventCallback, PlaybackStateHolder)

        // 3. Session (OAuth login happens inside Rust) — async.
        Session().initializeSession(sessionCallback)

        return true // readiness reported via events
    }

    // ── OAuth login flow ──

    private fun startLogin(context: Context): String? {
        val authManager = AuthManager()
        val url = try {
            authManager.getAuthorizationURL()
        } catch (t: Throwable) {
            android.util.Log.e("SpotifyBridge", "getAuthorizationURL failed", t)
            null
        } ?: return null

        // Catch the redirect code on 127.0.0.1:5588.
        oauthServer?.stop()
        oauthServer = OAuthCallbackServer(5588) { code, state ->
            handleOAuthCode(code, state)
        }.also { it.start() }

        // Open the Spotify login page.
        try {
            val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url))
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            context.startActivity(intent)
        } catch (t: Throwable) {
            android.util.Log.e("SpotifyBridge", "browser open failed", t)
        }
        return url
    }

    private fun handleOAuthCode(code: String, state: String) {
        // Network I/O — stays off the main thread (server thread is fine).
        Thread {
            try {
                val json = AuthManager().handleOAuthCode(code, state)
                val success = json.contains("\"success\":true")
                if (success) {
                    sendEvent("loginSuccess")
                    // Restart the session so it picks up the cached credentials.
                    runCatching { Session().shutdown() }
                    Thread.sleep(1500)
                    Session().initializeSession(sessionCallback)
                } else {
                    sendEvent("loginFailed", mapOf("json" to json))
                }
            } catch (t: Throwable) {
                sendEvent("loginFailed", mapOf("message" to (t.message ?: "unknown")))
            }
        }.start()
    }

    // ── Listeners (invoked from the Rust JNI dispatcher thread) ──

    private val sessionCallback = object : SessionCallback {
        override fun onInitialized() {
            sessionReady = true
            sendEvent("sessionReady")
            // Spirc boots only after the session is live.
            Spirc.initializeSpirc(
                spircInitCallback,
                gapless = true,
                normalisation = true,
                bitrateSpeed = 320,
                crossfadeMillis = 0,
                deviceName = "ZenMusic",
            )
        }

        override fun onShutdown() {
            sessionReady = false
            sendEvent("sessionShutdown")
        }

        override fun onAutoRestart() {
            sendEvent("sessionRestart")
        }
    }

    private val spircInitCallback = object : SpircInitializationCallback {
        override fun initialized() {
            spircReady = true
            Spirc.bufferCallback(bufferCallback)
            Spirc.deviceCallback(deviceCallback)
            sendEvent("spircReady")
        }

        override fun failed() {
            sendEvent("spircFailed")
        }
    }

    private val bufferCallback = object : SpircBufferCallback {
        override fun started() = sendEvent("bufferStarted")
        override fun stopped() = sendEvent("bufferStopped")
    }

    private val deviceCallback = object : SpircDeviceCallback {
        override fun becameActive() = sendEvent("deviceActive")
        override fun becameInactive() = sendEvent("deviceInactive")
        override fun volumeChanged(volume: Int) = sendEvent("volume", mapOf("volume" to volume))
    }

    private val playerEventCallback = object : PlayerEventCallback {
        override fun onTrackChange(spotify_uri: String, json: String) =
            sendEvent("trackChange", mapOf("uri" to spotify_uri, "json" to json))

        override fun onPositionUpdate(spotify_uri: String, position_ms: Long, json: String) =
            sendEvent(
                "position",
                mapOf("uri" to spotify_uri, "positionMs" to position_ms, "json" to json),
            )

        override fun onPlayingStatus(playing: Boolean) =
            sendEvent("playingStatus", mapOf("playing" to playing))
    }

    // ── EventChannel.StreamHandler ──

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }
}