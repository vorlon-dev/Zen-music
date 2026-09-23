package com.zen.music.zenmusic.extensions

import android.content.Context
import android.net.Uri
import android.util.Log
import dev.brahmkshatriya.echo.common.clients.ExtensionClient
import dev.brahmkshatriya.echo.common.clients.SearchFeedClient
import dev.brahmkshatriya.echo.common.clients.TrackClient
import dev.brahmkshatriya.echo.common.models.ImportType
import dev.brahmkshatriya.echo.common.models.Metadata
import dev.brahmkshatriya.echo.common.models.Shelf
import dev.brahmkshatriya.echo.common.models.Streamable
import dev.brahmkshatriya.echo.common.models.Track
import dev.brahmkshatriya.echo.common.providers.MetadataProvider
import dev.brahmkshatriya.echo.common.providers.SettingsProvider
import kotlinx.coroutines.runBlocking
import org.json.JSONArray
import org.json.JSONObject
import java.io.File


/** Minimal manager: install .eapk files, list, select, search, resolve streams. */
class ZenExtensionManager(private val context: Context) {
    private val parser = ZenExtensionParser(context)
    private val prefs = context.getSharedPreferences("zen_extensions", Context.MODE_PRIVATE)

    private val installed = mutableMapOf<String, ParsedExtension>()

    // ── Persistence ──

    private fun saveList() {
        val arr = JSONArray()
        installed.values.forEach {
            arr.put(
                JSONObject()
                    .put("id", it.metadata.id)
                    .put("path", it.metadata.path)
                    .put("name", it.metadata.name)
            )
        }
        prefs.edit().putString("installed", arr.toString()).apply()
    }

    fun restoreInstalled() {
        val arr = JSONArray(prefs.getString("installed", "[]") ?: "[]")
        for (i in 0 until arr.length()) {
            val obj = arr.getJSONObject(i)
            val file = File(obj.getString("path"))
            if (!file.exists()) continue
            parser.parse(file, importType()).fold(
                onSuccess = { parsed -> installed[parsed.metadata.id] = parsed },
                onFailure = { e -> println("Failed to restore ${file.name}: $e") }
            )
        }
        // Restore the active selection — synchronous, logged.
        val activeId = prefs.getString("active", null)
        if (activeId != null) {
            installed[activeId]?.let { activate(it) }
        }
    }

    // Enum-agnostic: compiles regardless of ImportType's entry names.
    private fun importType(): ImportType = ImportType.entries.first()

    // ── Install / list / select ──

    /// Installs from a plain file path (file_picker returns cache paths
    /// that are directly readable — no ContentResolver needed).
    fun installFromPath(path: String): Result<Metadata> {
        val file = File(path)
        if (!file.exists()) {
            return Result.failure(Exception("File not found: $path"))
        }
        return installFromFile(file)
    }

    fun installFromFile(file: File): Result<Metadata> {
        // Only .eapk extension packages are accepted.
        if (!file.name.lowercase().endsWith(".eapk") &&
            !file.name.lowercase().endsWith(".apk")) {
            return Result.failure(Exception("Only .eapk files are supported"))
        }
        return parser.parse(file, importType()).fold(
            onSuccess = { ext ->
                installed[ext.metadata.id] = ext
                saveList()
                Result.success(ext.metadata)
            },
            onFailure = { e ->
                e.printStackTrace() // full parse error in logcat
                Result.failure(e)
            }
        )
    }

    fun list(): JSONArray {
        val activeId = prefs.getString("active", null)
        val arr = JSONArray()
        installed.values.forEach { ext ->
            arr.put(
                JSONObject()
                    .put("id", ext.metadata.id)
                    .put("name", ext.metadata.name)
                    .put("version", ext.metadata.version)
                    .put("description", ext.metadata.description)
                    .put("author", ext.metadata.author)
                    .put("isActive", ext.metadata.id == activeId)
            )
        }
        return arr
    }

    fun select(id: String): Boolean {
        val ext = installed[id] ?: return false
        prefs.edit().putString("active", id).apply()
        return try {
            runBlocking {
                ext.client.onInitialize()
                ext.client.onExtensionSelected()
            }
            active = ext
            Log.i("ZenExt", "✅ extension $id: activated")
            true
        } catch (e: Exception) {
            Log.e("ZenExt", "❌ extension $id: activation failed", e)
            // Leave active unset — the next search/resolve call will
            // attempt auto-reactivation and surface the real error.
            false
        }
    }

    fun active(): ParsedExtension? = active

    private var active: ParsedExtension? = null

    /// Returns the active extension client, re-running activation if a
    /// previous activation failed or was lost (half-initialized extension).
    private fun activeClient(): ExtensionClient {
        val cur = active
        if (cur != null) return cur.client

        // Try to re-activate the saved selection.
        val id = prefs.getString("active", null)
            ?: error("No extension selected — activate one in Extensions")
        val ext = installed[id] ?: error("Active extension not installed")
        activate(ext)
        return active?.client
            ?: error("Extension failed to initialize — see logcat")
    }

    private fun activate(ext: ParsedExtension) {
        active = ext
        // Lifecycle per Echo's real host: inject providers
        // (Metadata → Settings) BEFORE onInitialize, then
        // onExtensionSelected. Synchronous + logged so a failed init
        // never leaves a half-initialized extension answering calls.
        try {
            Log.i("ZenExt", "extension ${ext.metadata.id}: injecting providers...")
            (ext.client as? MetadataProvider)?.setMetadata(ext.metadata)
            (ext.client as? SettingsProvider)?.setSettings(
                ZenExtensionSettings(context, ext.metadata.id)
            )
            Log.i("ZenExt", "extension ${ext.metadata.id}: onInitialize...")
            runBlocking {
                ext.client.onInitialize()
                ext.client.onExtensionSelected()
            }
            Log.i("ZenExt", "✅ extension ${ext.metadata.id}: initialized")
        } catch (t: Throwable) {
            Log.e("ZenExt", "❌ extension ${ext.metadata.id}: init threw", t)
            active = null // half-initialized extension must not answer calls
        }
    }

    // ── Search (PagedData walker — uses only pasted Feed/Shelf API) ──

    fun search(query: String): JSONArray {
        val client = activeClient() as? SearchFeedClient
            ?: error("Extension does not support search")

        val feed = runBlocking { client.loadSearchFeed(query) }
        val shelves: List<Shelf> = runBlocking {
            val data = feed.getPagedData(feed.notSortTabs.firstOrNull())
            data.pagedData.loadAll()
        }

        val tracks = mutableListOf<Track>()
        for (shelf in shelves) when (shelf) {
            is Shelf.Lists.Tracks -> tracks.addAll(shelf.list)
            is Shelf.Lists.Items -> tracks.addAll(
                shelf.list.filterIsInstance<Track>()
            )
            is Shelf.Item -> (shelf.media as? Track)?.let { tracks.add(it) }
            else -> {} // Categories / page-navigation shelves: skipped in v1
        }

        val arr = JSONArray()
        for (t in tracks) {
            arr.put(
                JSONObject()
                    .put("id", t.id)
                    .put("title", t.title)
                    .put("artist", t.artists.firstOrNull()?.name ?: "Unknown")
                    .put("thumbnail", "")
                    .put("durationMs", t.duration ?: 0)
            )
        }
        return arr
    }

    // ── Playback bridge: track json → resolved stream json ──

    fun resolveStream(trackJson: JSONObject): JSONObject {
        val client = activeClient() as? TrackClient
            ?: error("Extension does not support streaming")

        val artists = trackJson.optJSONArray("artists")?.let { arr ->
            (0 until arr.length()).mapNotNull { i ->
                val obj = arr.optJSONObject(i) ?: return@mapNotNull null
                val name = obj.optString("name")
                if (name.isBlank()) null
                else dev.brahmkshatriya.echo.common.models.Artist(
                    id = name, name = name
                )
            }
        } ?: emptyList()

        val durationMs = trackJson.optLong("durationMs", 0L)
        val track = Track(
            id = trackJson.getString("id"),
            title = trackJson.optString("title", "Unknown"),
            artists = artists,
            duration = if (durationMs > 0) durationMs else null,
        )

        // Stage 1: populate servers.
        val loaded = runBlocking { client.loadTrack(track, false) }
        val server = loaded.servers.firstOrNull()
            ?: error("Extension returned no servers for this track")

        // Stage 2: resolve the media of the first server.
        val media = runBlocking {
            client.loadStreamableMedia(server, false)
        }
        val serverMedia = media as? Streamable.Media.Server
            ?: error("Unexpected media type: ${media::class.simpleName}")

        // First Http source → url + headers + source type.
        for (source in serverMedia.sources) {
            val http = source as? Streamable.Source.Http ?: continue
            val type = when (http.type) {
                Streamable.SourceType.HLS -> "HLS"
                Streamable.SourceType.DASH -> "DASH"
                else -> "PROGRESSIVE"
            }
            return JSONObject()
                .put("url", http.request.url)
                .put("headers", org.json.JSONObject(http.request.headers))
                .put("sourceType", type)
        }
        error("No Http source in the loaded media")
    }
}