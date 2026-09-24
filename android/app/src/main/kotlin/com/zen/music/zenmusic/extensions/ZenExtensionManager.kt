package com.zen.music.zenmusic.extensions

import android.content.Context
import android.util.Log
import dev.brahmkshatriya.echo.common.clients.AlbumClient
import dev.brahmkshatriya.echo.common.clients.ArtistClient
import dev.brahmkshatriya.echo.common.clients.ExtensionClient
import dev.brahmkshatriya.echo.common.clients.HomeFeedClient
import dev.brahmkshatriya.echo.common.clients.PlaylistClient
import dev.brahmkshatriya.echo.common.clients.SearchFeedClient
import dev.brahmkshatriya.echo.common.clients.TrackClient
import dev.brahmkshatriya.echo.common.models.Album
import dev.brahmkshatriya.echo.common.models.Artist
import dev.brahmkshatriya.echo.common.models.EchoMediaItem
import dev.brahmkshatriya.echo.common.models.Feed.Companion.loadAll
import dev.brahmkshatriya.echo.common.models.ImageHolder
import dev.brahmkshatriya.echo.common.models.ImportType
import dev.brahmkshatriya.echo.common.models.Metadata
import dev.brahmkshatriya.echo.common.models.Playlist
import dev.brahmkshatriya.echo.common.models.Shelf
import dev.brahmkshatriya.echo.common.models.Streamable
import dev.brahmkshatriya.echo.common.models.Track
import dev.brahmkshatriya.echo.common.providers.MetadataProvider
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.Json
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
    //  that are directly readable — no ContentResolver needed).
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

    // Icon → flat json: url+headers, or hex, or empty (fallback icon).
    fun iconJson(icon: ImageHolder?): JSONObject {
        val obj = JSONObject()
        when (icon) {
            is ImageHolder.NetworkRequestImageHolder -> {
                obj.put("url", icon.request.url)
                obj.put("headers", JSONObject(icon.request.headers))
            }
            is ImageHolder.HexColorImageHolder -> obj.put("hex", icon.hex)
            else -> {} // ResourceUri/ResourceId holders are not renderable here
        }
        return obj
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
                    .put("icon", iconJson(ext.metadata.icon))
                    .put("isActive", ext.metadata.id == activeId)
            )
        }
        return arr
    }

    fun select(id: String): Boolean {
        val ext = installed[id] ?: return false
        activate(ext) // injects providers before init, nulls active on failure
        if (active == null) return false
        // Persist only a selection that actually activated — a failed
        // activation must not report itself as active in list().
        prefs.edit().putString("active", id).apply()
        return true
    }

    /// Clears the active extension — the app returns to built-in sources.
    fun clearActive(): Boolean {
        val had = prefs.getString("active", null) != null
        prefs.edit().remove("active").apply()
        active = null
        return had
    }

    fun active(): ParsedExtension? = active

    private var active: ParsedExtension? = null

    // Clients that completed onInitialize — id → instance.
    private val initializedClients = mutableMapOf<String, ExtensionClient>()

    /// Returns the active client, re-running activation if a previous
    //  activation failed or was lost (half-initialized extension).
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
        try {
            // Contract: injections → onInitialize once per client instance;
            // onExtensionSelected on every (re)select.
            if (initializedClients[ext.metadata.id] !== ext.client) {
                Log.i("ZenExt", "extension ${ext.metadata.id}: injecting providers...")
                (ext.client as? MetadataProvider)?.setMetadata(ext.metadata)
                ext.client.setSettings(ZenExtensionSettings(context, ext.metadata.id))
                Log.i("ZenExt", "extension ${ext.metadata.id}: onInitialize...")
                runBlocking { ext.client.onInitialize() }
                initializedClients[ext.metadata.id] = ext.client
                Log.i("ZenExt", "✅ extension ${ext.metadata.id}: initialized")
            }
            runBlocking { ext.client.onExtensionSelected() }
            Log.i("ZenExt", "✅ extension ${ext.metadata.id}: selected")
        } catch (t: Throwable) {
            Log.e("ZenExt", "❌ extension ${ext.metadata.id}: activation failed", t)
            active = null // half-initialized extension must not answer calls
        }
    }

    // ── Search (PagedData walker) ──

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

    // ── Home feed (HomeFeedClient — paged, Dart drives continuation) ──

    fun homeFeedPage(continuation: String?): JSONObject {
        val client = activeClient() as? HomeFeedClient
            ?: error("Extension does not provide a home feed")

        val feed = runBlocking { client.loadHomeFeed() }
        val pagedData = runBlocking {
            feed.getPagedData(feed.notSortTabs.firstOrNull())
        }.pagedData

        val page = runBlocking { pagedData.loadPage(continuation) }
        return JSONObject()
            .put(
                "data",
                JSONArray(
                    Json.encodeToString(ListSerializer(Shelf.serializer()), page.data)
                )
            )
            .put("continuation", page.continuation ?: JSONObject.NULL)
    }

    // ── Detail pages: album / playlist / artist ──

    fun loadDetail(itemJson: String): JSONObject {
        val item = try {
            Json.decodeFromString(EchoMediaItem.serializer(), itemJson)
        } catch (t: Throwable) {
            error("Malformed media item: ${t.message}")
        }
        val client = activeClient()
        val result = JSONObject()

        // NOTE: item + tracks are encoded via EchoMediaItem.serializer()
        // (the sealed parent) — concrete serializers omit the
        // mediaItemType discriminator and Dart parsing depends on it.
        when (item) {
            is Album -> {
                val c = client as? AlbumClient
                    ?: error("Extension does not support albums")
                val loaded = runBlocking { c.loadAlbum(item) }
                result.put(
                    "item",
                    JSONObject(Json.encodeToString(EchoMediaItem.serializer(), loaded))
                )
                // Contract's own Feed.loadAll walks every not-sort tab —
                // a first-tab walk misses tabbed feeds.
                val tracks: List<Track> = runBlocking {
                    c.loadTracks(loaded)?.loadAll() ?: emptyList()
                }
                Log.i("ZenExt", "album ${loaded.id}: ${tracks.size} tracks")
                result.put(
                    "tracks",
                    JSONArray(
                        Json.encodeToString(
                            ListSerializer(EchoMediaItem.serializer()), tracks
                        )
                    )
                )
            }
            is Playlist -> {
                val c = client as? PlaylistClient
                    ?: error("Extension does not support playlists")
                val loaded = runBlocking { c.loadPlaylist(item) }
                result.put(
                    "item",
                    JSONObject(Json.encodeToString(EchoMediaItem.serializer(), loaded))
                )
                val tracks: List<Track> = runBlocking {
                    c.loadTracks(loaded).loadAll()
                }
                Log.i("ZenExt", "playlist ${loaded.id}: ${tracks.size} tracks")
                result.put(
                    "tracks",
                    JSONArray(
                        Json.encodeToString(
                            ListSerializer(EchoMediaItem.serializer()), tracks
                        )
                    )
                )
            }
            is Artist -> {
                val c = client as? ArtistClient
                    ?: error("Extension does not support artists")
                val loaded = runBlocking { c.loadArtist(item) }
                result.put(
                    "item",
                    JSONObject(Json.encodeToString(EchoMediaItem.serializer(), loaded))
                )
                val shelves: List<Shelf> = runBlocking {
                    c.loadFeed(loaded).loadAll()
                }
                Log.i("ZenExt", "artist ${loaded.id}: ${shelves.size} shelves")
                result.put(
                    "shelves",
                    JSONArray(Json.encodeToString(ListSerializer(Shelf.serializer()), shelves))
                )
            }
            else -> error("No detail page for ${item::class.simpleName}")
        }
        return result
    }

    // ── Playback bridge: track json → resolved stream json ──

    // Ranks every Http source across all servers: non-DRM, non-live,
    // highest quality first (ties → later entries, extensions list
    // best last). Lossless sniffing is title/url-based — the contract
    // has no codec metadata.
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

        // Stage 1: load all servers.
        val loaded = runBlocking { client.loadTrack(track, false) }
        val servers = loaded.servers
        if (servers.isEmpty()) error("Extension returned no servers for this track")

        // Stage 2: resolve every server's media, collect Http sources.
        data class Candidate(
            val url: String,
            val headers: Map<String, String>,
            val sourceType: String,
            val quality: Int,
            val title: String?,
            val lossless: Boolean,
        )

        val candidates = mutableListOf<Candidate>()
        for (server in servers) {
            val media = try {
                runBlocking { client.loadStreamableMedia(server, false) }
            } catch (t: Throwable) {
                Log.w("ZenExt", "server ${server.id} failed to load: ${t.message}")
                continue
            }
            val serverMedia = media as? Streamable.Media.Server ?: continue
            for (source in serverMedia.sources) {
                val http = source as? Streamable.Source.Http ?: continue
                if (http.decryption != null) continue // DRM — unplayable here
                if (http.isLive) continue
                val url = http.request.url
                val label = (http.title ?: "").lowercase()
                val lossless = label.contains("flac") ||
                        label.contains("lossless") ||
                        url.lowercase().contains(".flac")
                candidates.add(
                    Candidate(
                        url = url,
                        headers = http.request.headers,
                        sourceType = when (http.type) {
                            Streamable.SourceType.HLS -> "HLS"
                            Streamable.SourceType.DASH -> "DASH"
                            Streamable.SourceType.Progressive -> "PROGRESSIVE"
                        },
                        quality = http.quality,
                        title = http.title,
                        lossless = lossless,
                    )
                )
            }
        }
        if (candidates.isEmpty()) error("No playable Http source for this track")

        // Prefer-lossless: lossless first, then quality desc, then
        // position desc (later sources win ties).
        val indexed = candidates.withIndex().toList()
        val best = indexed.maxWith(
            compareBy(
                { it.value.lossless },
                { it.value.quality },
                { it.index },
            )
        ).value

        Log.i(
            "ZenExt",
            "resolved ${candidates.size} sources; picked q=${best.quality} " +
                    "lossless=${best.lossless} ${best.title ?: ""}"
        )
        return JSONObject()
            .put("url", best.url)
            .put("headers", JSONObject(best.headers))
            .put("sourceType", best.sourceType)
            .put("quality", best.quality)
            .put("qualityLabel", best.title ?: (if (best.lossless) "Lossless" else ""))
            .put("lossless", best.lossless)
    }
}