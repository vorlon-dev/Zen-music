package com.zen.music.zenmusic

// SP-78: ZenWall — the playing song as the Android wallpaper.
//
// Dart (ZenWallService) decides WHAT goes on the wall and pushes a URL:
//   • fromCanvas=true  → a Spotify canvas mp4; the frame is grabbed here
//     with MediaMetadataRetriever (a static frame is all a wallpaper can
//     hold — live video wallpaper needs a WallpaperService engine).
//   • fromCanvas=false → the song's album art image.
// Either way the bitmap is centre-cropped to the display and set as the
// HOME wallpaper (never the lock screen). Runs on its own thread; the
// channel answer is posted back on the main thread exactly once.

import android.app.WallpaperManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.RectF
import android.media.MediaMetadataRetriever
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.net.HttpURLConnection
import java.net.URL

object ZenWallPlugin {
    private const val CHANNEL = "zen/zenwall"
    private val main = Handler(Looper.getMainLooper())

    fun register(flutterEngine: FlutterEngine, activity: MainActivity) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "set" -> {
                        val url = call.argument<String>("url")
                        val fromCanvas = call.argument<Boolean>("fromCanvas") ?: false
                        if (url.isNullOrEmpty()) {
                            result.error("INVALID", "url missing", null)
                            return@setMethodCallHandler
                        }
                        Thread {
                            var answered = false
                            fun answer(action: () -> Unit) {
                                main.post {
                                    if (!answered) {
                                        answered = true
                                        action()
                                    }
                                }
                            }
                            try {
                                val raw = if (fromCanvas) frameFromCanvas(url)
                                          else bitmapFromImage(url)
                                if (raw == null) {
                                    answer { result.error("DECODE", "no bitmap for $url", null) }
                                    return@Thread
                                }
                                val fitted = fitToScreen(raw, activity)
                                val wm = WallpaperManager.getInstance(activity)
                                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                                    // API 25+: explicit home-screen target.
                                    wm.setBitmap(
                                        fitted, null, true,
                                        WallpaperManager.FLAG_SYSTEM
                                    )
                                } else {
                                    wm.setBitmap(fitted)
                                }
                                answer { result.success(true) }
                            } catch (e: Exception) {
                                answer { result.error("FAIL", e.message, null) }
                            }
                        }.start()
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /** A frame from the canvas video (~1 s in — frame 0 is often a black
     *  fade-in), falling back to the very first frame. */
    private fun frameFromCanvas(url: String): Bitmap? {
        val retriever = MediaMetadataRetriever()
        return try {
            retriever.setDataSource(url, HashMap<String, String>())
            retriever.getFrameAtTime(
                1_000_000, MediaMetadataRetriever.OPTION_CLOSEST_SYNC
            ) ?: retriever.getFrameAtTime(
                0, MediaMetadataRetriever.OPTION_CLOSEST_SYNC
            )
        } catch (e: Exception) {
            null
        } finally {
            try { retriever.release() } catch (_: Exception) {}
        }
    }

    private fun bitmapFromImage(url: String): Bitmap? = try {
        val conn = URL(url).openConnection() as HttpURLConnection
        conn.connectTimeout = 8000
        conn.readTimeout = 8000
        conn.instanceFollowRedirects = true
        conn.setRequestProperty("User-Agent", "Mozilla/5.0 (Linux; Android) ZenMusic")
        conn.inputStream.use { BitmapFactory.decodeStream(it) }
    } catch (e: Exception) {
        null
    }

    /** Centre-crop to the display aspect, scaled to fit, capped at 2560 px
     *  so oversized art can't blow up the bitmap allocation. */
    private fun fitToScreen(src: Bitmap, activity: MainActivity): Bitmap {
        val metrics = activity.resources.displayMetrics
        val targetW = minOf(metrics.widthPixels, 2560).coerceAtLeast(1)
        val targetH = minOf(metrics.heightPixels, 2560).coerceAtLeast(1)

        val scale = maxOf(
            targetW.toFloat() / src.width,
            targetH.toFloat() / src.height
        )
        val scaledW = src.width * scale
        val scaledH = src.height * scale
        val left = (targetW - scaledW) / 2f
        val top = (targetH - scaledH) / 2f

        val out = Bitmap.createBitmap(targetW, targetH, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(out)
        canvas.drawBitmap(
            src, null,
            RectF(left, top, left + scaledW, top + scaledH),
            Paint(Paint.FILTER_BITMAP_FLAG or Paint.ANTI_ALIAS_FLAG)
        )
        if (src !== out && !src.isRecycled) src.recycle()
        return out
    }
}
