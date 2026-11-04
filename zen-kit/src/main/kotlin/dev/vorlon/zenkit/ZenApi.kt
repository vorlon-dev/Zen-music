// ZenMusic · vorlon-dev
//
// Kotlin client for the ZenMusic API (see docs/API.md).
// Every call blocks: run it off the main thread (coroutines, executor...).

package dev.vorlon.zenkit

import org.json.JSONArray
import org.json.JSONObject
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder

enum class Source(val id: String) { JIO("jio"), YTM("ytm"), YT("yt") }

data class Stream(val quality: String, val url: String)

/** How to play a song. */
sealed interface Playback {
  /** JioSaavn: [url] is a direct audio link. */
  data class Direct(val url: String, val streams: List<Stream>) : Playback

  /** YouTube / YouTube Music: play [videoId] with the official YouTube player. */
  data class YouTube(val videoId: String, val embedUrl: String) : Playback
}

data class Song(
  val id: String,
  val source: Source,
  val title: String,
  val artist: String,
  val album: String,
  val image: String,
  val durationSeconds: Int,
  val playback: Playback,
)

/** An album or playlist in a search result. */
data class Collection(
  val id: String,
  val source: Source,
  val kind: String,
  val title: String,
  val subtitle: String,
  val image: String,
)

/** A playlist or album with its songs. */
data class SongList(
  val id: String,
  val source: Source,
  val kind: String,
  val title: String,
  val image: String,
  val songs: List<Song>,
)

class ZenApiException(message: String, val status: Int) : IOException(message)

/**
 * @param baseUrl your deployment, for example `https://my-music.pages.dev`
 * @param apiKey the value of the `API_KEY` variable, if you set one
 */
class ZenApi(
  baseUrl: String,
  private val apiKey: String? = null,
  private val timeoutMs: Int = 15_000,
) {
  private val base = baseUrl.trimEnd('/')

  /** Songs for [query]. */
  fun searchSongs(source: Source, query: String): List<Song> {
    val data = get("/v1/search", "source" to source.id, "q" to query, "type" to "song")
    return songs(data.optJSONArray("results"))
  }

  /** Albums or playlists ([type] = "album" or "playlist"); JioSaavn only. */
  fun searchCollections(query: String, type: String): List<Collection> {
    require(type == "album" || type == "playlist") { "type must be album or playlist" }
    val data = get("/v1/search", "source" to "jio", "q" to query, "type" to type)
    val arr = data.optJSONArray("results") ?: return emptyList()
    return List(arr.length()) { collection(arr.getJSONObject(it)) }
  }

  /** One JioSaavn song with its stream links. */
  fun song(id: String): Song = song(get("/v1/song", "source" to "jio", "id" to id))

  fun playlist(source: Source, id: String): SongList =
    songList(get("/v1/playlist", "source" to source.id, "id" to id))

  /** JioSaavn album. */
  fun album(id: String): SongList =
    songList(get("/v1/album", "source" to "jio", "id" to id))

  // ---- HTTP -----------------------------------------------------------

  private fun get(path: String, vararg params: Pair<String, String>): JSONObject {
    val query = params.joinToString("&") { (k, v) ->
      "${URLEncoder.encode(k, "UTF-8")}=${URLEncoder.encode(v, "UTF-8")}"
    }
    val conn = URL("$base$path?$query").openConnection() as HttpURLConnection
    try {
      conn.connectTimeout = timeoutMs
      conn.readTimeout = timeoutMs
      conn.setRequestProperty("Accept", "application/json")
      if (!apiKey.isNullOrEmpty()) conn.setRequestProperty("x-api-key", apiKey)
      val status = conn.responseCode
      val stream = if (status in 200..299) conn.inputStream else conn.errorStream
      val body = stream?.bufferedReader(Charsets.UTF_8)?.use { it.readText() }.orEmpty()
      val root = try {
        JSONObject(body)
      } catch (e: Exception) {
        throw ZenApiException("Unexpected response (HTTP $status)", status)
      }
      if (!root.optBoolean("ok")) {
        throw ZenApiException(root.optString("error", "Request failed"), status)
      }
      return root.getJSONObject("data")
    } finally {
      conn.disconnect()
    }
  }

  // ---- parsing --------------------------------------------------------

  private fun songs(arr: JSONArray?): List<Song> =
    if (arr == null) emptyList() else List(arr.length()) { song(arr.getJSONObject(it)) }

  private fun source(id: String): Source =
    Source.values().firstOrNull { it.id == id } ?: Source.JIO

  private fun song(o: JSONObject): Song {
    val p = o.getJSONObject("playback")
    val playback = if (p.optString("type") == "youtube") {
      Playback.YouTube(p.optString("videoId"), p.optString("embedUrl"))
    } else {
      val arr = p.optJSONArray("streams")
      val streams = if (arr == null) emptyList() else List(arr.length()) {
        val s = arr.getJSONObject(it)
        Stream(s.optString("quality"), s.optString("url"))
      }
      Playback.Direct(p.optString("url"), streams)
    }
    return Song(
      id = o.optString("id"),
      source = source(o.optString("source")),
      title = o.optString("title"),
      artist = o.optString("artist"),
      album = o.optString("album"),
      image = o.optString("image"),
      durationSeconds = o.optInt("duration"),
      playback = playback,
    )
  }

  private fun collection(o: JSONObject) = Collection(
    id = o.optString("id"),
    source = source(o.optString("source")),
    kind = o.optString("kind"),
    title = o.optString("title"),
    subtitle = o.optString("subtitle"),
    image = o.optString("image"),
  )

  private fun songList(o: JSONObject) = SongList(
    id = o.optString("id"),
    source = source(o.optString("source")),
    kind = o.optString("kind"),
    title = o.optString("title"),
    image = o.optString("image"),
    songs = songs(o.optJSONArray("songs")),
  )
}
