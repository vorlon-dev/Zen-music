// ZenMusic · vorlon-dev
//
// One entry point for the whole library.
//
//   // MainActivity.onCreate / configureFlutterEngine
//   ZenKit.init(
//       activity = this,
//       backendUrl = "https://my-zen-music.pages.dev",  // your self-hosted backend
//       apiKey = "YOUR_KEY",                              // or null
//       debug = false,
//   )
//
//   // data (blocking: call off the main thread)
//   val songs = ZenKit.api.searchSongs(Source.YTM, "arijit")
//
//   // on-device playback of a YouTube id from the backend
//   val audio = ZenKit.resolveAudioBlocking(songs.first().id)
//
// The backend only returns metadata. Stream resolving, signature solving and
// the PO token all run on the device, inside this library.

package dev.vorlon.zenkit

import android.app.Activity
import com.zen.music.zenmusic.innertube.ZenInnertubeResolver
import com.zen.music.zenmusic.potoken.ZenPoTokenBridge

/** A resolved audio stream. Play [url] with [headers] (for example in ExoPlayer). */
class ResolvedAudio(
  val videoId: String,
  val url: String,
  val kbps: Int,
  val mimeType: String,
  val headers: Map<String, String>,
)

object ZenKit {
  @Volatile
  private var client: ZenApi? = null

  /** Data client for your backend. Call [init] with a backend URL first. */
  val api: ZenApi
    get() = client ?: error("ZenKit.init(...) was not called with a backendUrl")

  /**
   * Starts the on-device engine and, when [backendUrl] is not blank, creates
   * the data client for your self-hosted backend.
   */
  fun init(
    activity: Activity,
    backendUrl: String? = null,
    apiKey: String? = null,
    debug: Boolean = false,
  ) {
    client = if (backendUrl.isNullOrBlank()) null else ZenApi(backendUrl, apiKey)
    ZenInnertubeResolver.debugLogs = debug
    ZenInnertubeResolver.init(activity.applicationContext)
    // The PO-token WebView must be attached to a window to run its scripts.
    ZenPoTokenBridge.attachActivity(activity)
  }

  /**
   * Resolves an audio stream for a YouTube / YouTube Music [videoId] on the
   * device. Blocking: call from a background thread. Returns null on failure.
   */
  fun resolveAudioBlocking(
    videoId: String,
    maxKbps: Int = 0,
    requireM4a: Boolean = false,
  ): ResolvedAudio? {
    val e = ZenInnertubeResolver.extractBlocking(
      videoId = videoId,
      maxKbps = maxKbps,
      skipClients = emptySet(),
      requireM4a = requireM4a,
    ) ?: return null
    return ResolvedAudio(e.videoId, e.url, e.kbps, e.mimeType, e.headers)
  }

  /** Request headers the stream at [url] needs, if it was resolved by this library. */
  fun headersFor(url: String): Map<String, String>? = ZenInnertubeResolver.headersFor(url)
}
