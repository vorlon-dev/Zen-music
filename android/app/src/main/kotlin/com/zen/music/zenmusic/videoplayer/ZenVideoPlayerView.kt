package com.zen.music.zenmusic.videoplayer

import android.content.Context
import android.graphics.Color
import android.view.Gravity
import android.view.TextureView
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import androidx.annotation.OptIn
import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.DefaultDataSource
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.exoplayer.DefaultLoadControl
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.source.MediaSource
import androidx.media3.exoplayer.source.MergingMediaSource
import androidx.media3.exoplayer.source.ProgressiveMediaSource
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.plugin.platform.PlatformView

/**
 * Native merged-stream video player for the video watch page —
 * LibreTube's architecture: video-only + audio-only streams played
 * by ONE ExoPlayer instance via MergingMediaSource. One player =
 * zero drift by construction, full 1080p restored (muxed caps at
 * 720p). Rendered through a TextureView so it composites correctly
 * inside Flutter's view hierarchy; all controls stay in Dart.
 *
 * AUDIO FOCUS: handleAudioFocus is FALSE. The app's audio_service
 * session owns focus for music; the watch screen pauses it before
 * opening a video, so this player must never arbitrate focus —
 * with focus handling on, ExoPlayer deferred (or suppressed) its
 * start behind the app's own session and the video sat paused at
 * 00:00 until the user scrubbed. With it off, prepare() plays,
 * period. Player errors are captured and reported through the
 * position poll so Dart can fall back to the muxed tier.
 *
 * Channel contract ("zen/video_player_<viewId>", one per instance):
 *   prepare   {videoUrl, audioUrl?, headers, videoHeaders?,
 *              audioHeaders?, startPositionMs?}
 *   play / pause / seekTo {ms} / setVolume {0..1} / setSpeed {x} /
 *   setLoop {bool} / release
 *   position  → {positionMs, durationMs, isPlaying, ready, ended,
 *                error}
 */
@OptIn(UnstableApi::class)
class ZenVideoPlayerView(
    private val context: Context,
    private val channel: MethodChannel,
) : PlatformView, MethodCallHandler {

    companion object {
        // LibreTube PlayerHelper parity: 10s minimum buffer, 3min
        // back buffer, defaults for buffer-for-playback.
        private const val MINIMUM_BUFFER_DURATION = 1000 * 10
        private const val BACK_BUFFER_DURATION = 1000 * 60 * 3
    }

    private val container = FrameLayout(context).apply {
        setBackgroundColor(Color.BLACK)
    }
    private val textureView = TextureView(context).apply {
        layoutParams = FrameLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.MATCH_PARENT,
            Gravity.CENTER,
        )
    }

    private var player: ExoPlayer? = null
    private var ended = false
    private var lastError: String? = null

    init {
        container.addView(textureView)
        channel.setMethodCallHandler(this)
    }

    // ── Player construction (LibreTube PlayerHelper.createPlayer
    //    parity, minimal — no track selector, no text renderers) ──

    private fun buildPlayer(): ExoPlayer {
        val audioAttributes = AudioAttributes.Builder()
            .setUsage(C.USAGE_MEDIA)
            .setContentType(C.AUDIO_CONTENT_TYPE_MOVIE)
            .build()
        val loadControl = DefaultLoadControl.Builder()
            .setBackBuffer(BACK_BUFFER_DURATION, true)
            .setBufferDurationsMs(
                MINIMUM_BUFFER_DURATION,
                DefaultLoadControl.DEFAULT_MAX_BUFFER_MS,
                DefaultLoadControl.DEFAULT_BUFFER_FOR_PLAYBACK_MS,
                DefaultLoadControl.DEFAULT_BUFFER_FOR_PLAYBACK_AFTER_REBUFFER_MS,
            )
            .build()
        return ExoPlayer.Builder(context)
            .setLoadControl(loadControl)
            .setHandleAudioBecomingNoisy(true)
            // handleAudioFocus = FALSE — see the class doc. This is
            // the deterministic-autoplay fix: no focus arbitration,
            // no deferral, prepare() plays.
            .setAudioAttributes(audioAttributes, false)
            .build()
    }

    /// One DataSource.Factory per prepare — carries the UA-gated
    /// headers for googlevideo, with cross-protocol redirects
    /// allowed (googlevideo redirects http↔https; without this the
    /// first redirect fails).
    private fun dataSourceFactory(
        headers: Map<String, String>,
    ): DefaultDataSource.Factory {
        val http = DefaultHttpDataSource.Factory()
            .setDefaultRequestProperties(headers)
            .setAllowCrossProtocolRedirects(true)
            .setConnectTimeoutMs(15_000)
            .setReadTimeoutMs(30_000)
        return DefaultDataSource.Factory(context, http)
    }

    private fun progressiveSource(
        url: String,
        headers: Map<String, String>,
    ): ProgressiveMediaSource =
        ProgressiveMediaSource.Factory(dataSourceFactory(headers))
            .createMediaSource(MediaItem.fromUri(url))

    private fun prepare(
        videoUrl: String,
        videoHeaders: Map<String, String>,
        audioUrl: String?,
        audioHeaders: Map<String, String>,
        startPositionMs: Long,
    ) {
        releasePlayer()
        ended = false
        lastError = null

        val p = buildPlayer()
        p.setVideoTextureView(textureView)

        val video = progressiveSource(videoUrl, videoHeaders)
        val source: MediaSource =
            if (audioUrl.isNullOrEmpty()) {
                // Muxed stream (carries its own audio).
                video
            } else {
                // LibreTube parity: MergingMediaSource — video-only +
                // audio-only inside ONE player. Same recording when
                // both come from one response; when the layers come
                // from different extractors they are still the same
                // videoId's own streams.
                MergingMediaSource(
                    video,
                    progressiveSource(audioUrl, audioHeaders),
                )
            }

        p.addListener(object : Player.Listener {
            override fun onPlaybackStateChanged(playbackState: Int) {
                when (playbackState) {
                    Player.STATE_ENDED -> ended = true
                    Player.STATE_READY -> {
                        // Belt-and-suspenders with handleAudioFocus
                        // = false: play() is idempotent.
                        if (!ended) p.play()
                    }
                    else -> {}
                }
            }

            override fun onPlayerError(error: PlaybackException) {
                // Surfaced through the position poll — Dart reads it
                // and falls back to the muxed tier.
                lastError = error.errorCodeName
            }
        })

        p.setMediaSource(source)
        if (startPositionMs > 0) p.seekTo(startPositionMs)
        p.playWhenReady = true
        p.prepare()
        player = p
    }

    private fun releasePlayer() {
        // release() detaches all listeners and the surface — no
        // explicit removeListener needed (and Player.Listener is an
        // all-defaults interface: a bare-lambda removeListener would
        // not compile anyway).
        player?.run {
            stop()
            release()
        }
        player = null
    }

    // ── Method channel ──

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "prepare" -> {
                val videoUrl = call.argument<String>("videoUrl").orEmpty()
                if (videoUrl.isEmpty()) {
                    result.error("BAD_ARGS", "videoUrl required", null)
                    return
                }
                val audioUrl = call.argument<String>("audioUrl")
                val headers = (call.argument<Map<*, *>>("headers") ?: emptyMap<Any?, Any?>())
                    .mapNotNull { (k, v) ->
                        (k as? String)?.let { key -> (v as? String)?.let { key to it } }
                    }
                    .toMap()
                // Per-source headers: the video and audio URLs can come
                // from DIFFERENT extraction layers (e.g. Dart visionOs
                // video + native audio), each with its own UA-gate.
                // Absent keys fall back to the shared `headers`.
                val videoHeaders = (call.argument<Map<*, *>>("videoHeaders")
                    ?: emptyMap<Any?, Any?>())
                    .mapNotNull { (k, v) ->
                        (k as? String)?.let { key -> (v as? String)?.let { key to it } }
                    }
                    .toMap()
                    .ifEmpty { headers }
                val audioHeaders = (call.argument<Map<*, *>>("audioHeaders")
                    ?: emptyMap<Any?, Any?>())
                    .mapNotNull { (k, v) ->
                        (k as? String)?.let { key -> (v as? String)?.let { key to it } }
                    }
                    .toMap()
                    .ifEmpty { headers }
                val startPositionMs =
                    (call.argument<Any?>("startPositionMs") as? Number)?.toLong() ?: 0L
                prepare(videoUrl, videoHeaders, audioUrl, audioHeaders, startPositionMs)
                result.success(null)
            }
            "play" -> {
                player?.play()
                result.success(null)
            }
            "pause" -> {
                player?.pause()
                result.success(null)
            }
            "seekTo" -> {
                val ms = (call.arguments as? Number)?.toLong() ?: 0L
                player?.seekTo(ms)
                ended = false
                result.success(null)
            }
            "setVolume" -> {
                val v = ((call.arguments as? Number)?.toDouble() ?: 1.0)
                    .coerceIn(0.0, 1.0)
                player?.volume = v.toFloat()
                result.success(null)
            }
            "setSpeed" -> {
                val s = ((call.arguments as? Number)?.toDouble() ?: 1.0)
                    .coerceIn(0.25, 4.0).toFloat()
                player?.setPlaybackSpeed(s)
                result.success(null)
            }
            "setLoop" -> {
                val loop = call.arguments as? Boolean == true
                player?.repeatMode =
                    if (loop) Player.REPEAT_MODE_ONE else Player.REPEAT_MODE_OFF
                result.success(null)
            }
            "position" -> {
                val p = player
                result.success(
                    mapOf(
                        "positionMs" to (p?.currentPosition ?: 0L),
                        "durationMs" to
                                (if (p != null && p.duration != C.TIME_UNSET) p.duration else 0L),
                        "isPlaying" to (p?.isPlaying ?: false),
                        "ready" to (p?.playbackState == Player.STATE_READY),
                        "ended" to ended,
                        "error" to lastError,
                    )
                )
            }
            "release" -> {
                releasePlayer()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    // ── PlatformView ──

    override fun getView(): View = container

    override fun dispose() {
        channel.setMethodCallHandler(null)
        releasePlayer()
    }
}