package com.zen.music.zenmusic.innertube

import android.content.Context
import android.os.SystemClock
import android.util.Log
import com.music.innertube.NewPipeExtractor
import com.music.innertube.YouTube
import com.music.innertube.models.WatchEndpoint
import com.music.innertube.models.YouTubeClient
import com.music.innertube.models.YouTubeLocale
import com.music.innertube.models.response.PlayerResponse
import com.zen.music.zenmusic.potoken.ZenPoTokenBridge
import java.util.concurrent.ConcurrentHashMap
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withContext

/**
 * Tier-0 stream extraction through the vendored :innertube module
 * (com.music.innertube — raw InnerTube player API).
 *
 * Replaces the InnerTubeX resolver (removed together with its
 * JitPack artifact). Contract-compatible with the old
 * zen/innertubex MethodChannel: identical method names, identical
 * payload keys — innertubex_bridge.dart is untouched and every Dart
 * call site keeps working.
 *
 * Client chain: ANDROID_VR 1.65.10 (documented OK with 100%
 * direct-url formats; requires a visitorData, which the module
 * sends to every client as X-Goog-Visitor-Id) → VISIONOS (the
 * proven video client) → WEB_REMIX (the poToken-armed escape
 * hatch, attempted ONLY when a BotGuard token was minted —
 * skipped without one). Both direct-URL clients answer without
 * cipher work; WEB_REMIX may return ciphered formats, which the
 * Tier-0 contract skips (url-null formats are passed over).
 *
 * PoToken: ZenPoTokenBridge mints a BotGuard token per video
 * (WebView session, fire-and-forget). No token = exact previous
 * behavior — extraction proceeds without one and nothing fails.
 *
 * visitorData is PERSISTED in the SAME prefs file/key the old
 * resolver used ("innertubex_player_config" /
 * "innertubex_visitor_data"). The legacy names are deliberate so
 * existing installs keep their persisted session identity across
 * this migration. Never invalidated in onSessionChanged; every
 * resolved value is published to the po-token bridge for token
 * binding.
 */
object ZenInnertubeResolver {

    private const val TAG = "ZenTube"

    /// One minted audio stream (Tier-0 contract, same shape as the
    /// old resolver's Extracted).
    class Extracted(
        val videoId: String,
        val url: String,
        val kbps: Int,
        val mimeType: String,
        val loudnessDb: Double?,
        val clientName: String,
        val profileId: String,
        val headers: Map<String, String>,
    )

    /// Audio + video from ONE player response — same client, same
    /// recording, sync guaranteed by construction. Used by the video
    /// watch page: audio via the handler pipeline, video muted +
    /// synced. [videoUrl] is null when the response has no direct
    /// video-only stream (callers fall back to their muxed tier).
    class VideoStreams(
        val videoId: String,
        val audioUrl: String?,
        val videoUrl: String?,
        val headers: Map<String, String>,
        val clientName: String,
    )

    /// Verbose logging gate, set from MainActivity's debuggable flag.
    @Volatile
    var debugLogs: Boolean = false

    private var prefs: android.content.SharedPreferences? = null
    private var warmup: Job? = null

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    // Minted streams, for onRefused / headersFor lookups.
    private val minted = ConcurrentHashMap<String, Extracted>()

    // videoId -> channelId, stashed from player responses (verified
    // VideoDetails.channelId) during extraction — the watch screen
    // always extracts natively before asking for channel art.
    private val channelIds = ConcurrentHashMap<String, String>()

    // channelId -> artist avatar (positive cache) + negative cache
    // so a failing artist page isn't re-requested on every reopen.
    private val channelThumbs = ConcurrentHashMap<String, String>()
    private val failedThumbs: MutableSet<String> = ConcurrentHashMap.newKeySet()

    // videoId -> (profileId -> exclusion expiry, elapsedRealtime ms)
    private val excluded = ConcurrentHashMap<String, ConcurrentHashMap<String, Long>>()

    /// Extraction candidate. [id] doubles as profileId — the
    /// skipClients values from the Dart side and the exclusion map
    /// key on both sides are this id.
    private class Candidate(val id: String, val client: YouTubeClient)

    private val audioChain =
        listOf(
            Candidate("VR_1_65_10", YouTubeClient.ANDROID_VR_1_65_10),
            Candidate("VISIONOS", YouTubeClient.VISIONOS),
            // PoToken-armed escape hatch (skipped without a token).
            Candidate("WEB_REMIX", YouTubeClient.WEB_REMIX),
        )

    // Video watch: VISIONOS first — the proven video client. Both
    // layers of a VideoStreams come from ONE of its responses.
    private val videoChain =
        listOf(
            Candidate("VISIONOS", YouTubeClient.VISIONOS),
            Candidate("VR_1_65_10", YouTubeClient.ANDROID_VR_1_65_10),
            Candidate("WEB_REMIX", YouTubeClient.WEB_REMIX),
        )

    fun init(context: Context) {
        val app = context.applicationContext
        // Legacy prefs name — preserves the visitorData persisted by
        // the old resolver (see class doc).
        prefs =
            app.getSharedPreferences("innertubex_player_config", Context.MODE_PRIVATE)
        // PoToken minter — starts the BotGuard WebView session once
        // per process. Fire-and-forget; playback never waits on it.
        ZenPoTokenBridge.debugLogs = debugLogs
        ZenPoTokenBridge.init(app)
        warmup?.cancel()
        warmup =
            scope.launch {
                delay(WARM_DELAY_MS)
                runCatching { ensureVisitorData() }
                    .onFailure { if (it is CancellationException) throw it }
                    .onFailure { Log.w(TAG, "warm-up failed: ${it.message}") }
                    .onSuccess { Log.d(TAG, "warmed (visitorData ready)") }
            }
    }

    // ── visitorData ──────────────────────────────────────────

    /// Restore → module scrape (music.youtube.com/sw.js_data) →
    /// legacy youtube.com homepage grep. First success persists.
    /// Kotlin MatchResult exposes groups via groupValues[index].
    /// Every resolved value is published to the po-token bridge so
    /// minted tokens bind to (videoId + visitorData).
    private suspend fun ensureVisitorData() {
        if (YouTube.visitorData != null) return

        val saved = prefs?.getString(VISITOR_DATA_KEY, null)
        if (!saved.isNullOrEmpty()) {
            YouTube.visitorData = saved
            ZenPoTokenBridge.publishVisitorData(saved)
            Log.d(TAG, "visitorData restored from prefs")
            return
        }

        val scraped = YouTube.visitorData().getOrNull()
        if (!scraped.isNullOrEmpty()) {
            YouTube.visitorData = scraped
            ZenPoTokenBridge.publishVisitorData(scraped)
            prefs?.edit()?.putString(VISITOR_DATA_KEY, scraped)?.apply()
            Log.d(TAG, "visitorData bootstrapped via sw.js_data + persisted")
            return
        }

        // Legacy fallback (kept from the ITX era).
        try {
            val body =
                withContext(Dispatchers.IO) {
                    pageClient.newCall(
                        okhttp3.Request.Builder()
                            .url("https://www.youtube.com/")
                            .header(
                                "User-Agent",
                                "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 " +
                                        "(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"
                            )
                            .build()
                    )
                        .execute()
                        .use { resp -> resp.body?.string().orEmpty() }
                }
            val match = Regex("\"visitorData\":\"([^\"]+)\"").find(body) ?: return
            val vd = match.groupValues[1]
            YouTube.visitorData = vd
            ZenPoTokenBridge.publishVisitorData(vd)
            prefs?.edit()?.putString(VISITOR_DATA_KEY, vd)?.apply()
            Log.d(TAG, "visitorData bootstrapped via page grep + persisted")
        } catch (_: Exception) {}
    }

    /// Blocking visitorData access for the MethodChannel (ensures the
    /// bootstrap has run first). Used by the home-chips service so
    /// its param-filtered browse carries the session identity.
    fun visitorDataBlocking(): String? =
        runBlocking {
            ensureVisitorData()
            YouTube.visitorData
        }

    // ── extraction ───────────────────────────────────────────

    suspend fun extract(
        videoId: String,
        maxKbps: Int,
        skipClients: Set<String> = emptySet(),
        requireM4a: Boolean = false,
    ): Extracted? {
        ensureVisitorData()
        // Pinned US/en — parity with the proven ITX-era behavior.
        YouTube.locale = YouTubeLocale(gl = "US", hl = "en")
        val poToken = ZenPoTokenBridge.playerTokenBlocking(videoId, YouTube.visitorData)
        val skip = excludedFor(videoId) + skipClients
        for (candidate in audioChain) {
            if (candidate.id in skip) continue
            // WEB_REMIX is the poToken-armed escape hatch, not a
            // default client — only attempted when a token exists.
            if (candidate.client == YouTubeClient.WEB_REMIX && poToken == null) continue
            try {
                val response =
                    YouTube.player(
                        videoId = videoId,
                        playlistId = null,
                        client = candidate.client,
                        signatureTimestamp =
                            if (candidate.client.useSignatureTimestamp) {
                                signatureTimestamp(videoId)
                            } else null,
                        poToken = if (candidate.client.useWebPoTokens) poToken else null,
                    )
                        .getOrNull() ?: continue
                if (response.playabilityStatus.status != "OK") {
                    debug {
                        "${candidate.id} playability ${response.playabilityStatus.status}" +
                                " (${response.playabilityStatus.reason})"
                    }
                    continue
                }
                response.videoDetails?.channelId?.let { channelIds[videoId] = it }
                val formats = response.streamingData?.adaptiveFormats.orEmpty()
                val best = pickAudio(formats, maxKbps, requireM4a) ?: continue
                val url = best.url ?: continue // ciphered: Tier-0 is direct-URL only
                val extracted =
                    Extracted(
                        videoId = videoId,
                        url = url,
                        kbps = best.bitrate / 1000,
                        mimeType = best.mimeType,
                        loudnessDb = best.loudnessDb,
                        clientName = candidate.client.clientName,
                        profileId = candidate.id,
                        headers = mapOf("User-Agent" to candidate.client.userAgent),
                    )
                if (minted.size >= MAX_REMEMBERED) minted.clear()
                minted[extracted.url] = extracted
                debug { "${candidate.id} $videoId ${extracted.kbps}kbps" }
                return extracted
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                Log.w(TAG, "extract via ${candidate.id} failed: ${e.message}")
            }
        }
        return null
    }

    /// Blocking wrapper for the MethodChannel worker thread.
    fun extractBlocking(
        videoId: String,
        maxKbps: Int,
        skipClients: Set<String>,
        requireM4a: Boolean,
    ): Extracted? = runBlocking { extract(videoId, maxKbps, skipClients, requireM4a) }

    /// Audio + video extraction for the video watch page. One player
    /// response per candidate — both layers from the same client.
    fun extractVideoBlocking(videoId: String): VideoStreams? =
        runBlocking {
            ensureVisitorData()
            YouTube.locale = YouTubeLocale(gl = "US", hl = "en")
            val poToken = ZenPoTokenBridge.playerTokenBlocking(videoId, YouTube.visitorData)
            try {
                for (candidate in videoChain) {
                    if (candidate.client == YouTubeClient.WEB_REMIX && poToken == null) {
                        continue
                    }
                    val response =
                        YouTube.player(
                            videoId = videoId,
                            playlistId = null,
                            client = candidate.client,
                            signatureTimestamp =
                                if (candidate.client.useSignatureTimestamp) {
                                    signatureTimestamp(videoId)
                                } else null,
                            poToken = if (candidate.client.useWebPoTokens) poToken else null,
                        )
                            .getOrNull() ?: continue
                    if (response.playabilityStatus.status != "OK") {
                        debug {
                            "${candidate.id} (video) playability " +
                                    response.playabilityStatus.status
                        }
                        continue
                    }
                    response.videoDetails?.channelId?.let { channelIds[videoId] = it }
                    val formats = response.streamingData?.adaptiveFormats.orEmpty()
                    val audio = pickAudio(formats, Int.MAX_VALUE, requireM4a = false)
                    val video = pickVideo(formats)
                    if (audio?.url == null && video?.url == null) continue
                    // Build the value FIRST, then return it — a newline
                    // between `return@runBlocking` and its expression
                    // terminates the return (Unit) in Kotlin.
                    val streams =
                        VideoStreams(
                            videoId = videoId,
                            audioUrl = audio?.url,
                            videoUrl = video?.url,
                            headers = mapOf("User-Agent" to candidate.client.userAgent),
                            clientName = candidate.client.clientName,
                        )
                    debug {
                        "${candidate.id} (video) $videoId audio=${audio?.bitrate ?: 0}" +
                                " video=${video?.height ?: 0}p"
                    }
                    return@runBlocking streams
                }
                null
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                Log.w(TAG, "extractVideo failed: ${e.message}")
                null
            }
        }

    /// Related songs for the video watch queue — module-native
    /// watch-next (WEB_REMIX at the module's own pinned client
    /// version). Second source alongside the Dart radio service:
    /// when the radio returns nothing (its known seed-only
    /// flakiness), the up-next queue still fills from here.
    /// SongItem fields id/title/artists/thumbnail are verified
    /// module surface; no duration in the payload (UI hides zeros).
    fun relatedSongsBlocking(videoId: String): List<Map<String, Any?>> =
        runBlocking {
            try {
                val result =
                    YouTube.next(WatchEndpoint(videoId = videoId)).getOrNull()
                        ?: return@runBlocking emptyList()
                result.items
                    .filter { it.id != videoId }
                    .take(20)
                    .map { s ->
                        mapOf<String, Any?>(
                            "id" to s.id,
                            "title" to s.title,
                            "artist" to s.artists.joinToString(", ") { it.name },
                            "thumbnail" to s.thumbnail,
                        )
                    }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                Log.w(TAG, "relatedSongs failed: ${e.message}")
                emptyList()
            }
        }

    /// Channel avatar URL for the video watch page — REAL channel
    /// art: the channelId comes from the stashed player-response
    /// VideoDetails (verified field), the avatar from the module's
    /// artist browse (verified YouTube.artist surface). Best-effort:
    /// null when the channelId was never stashed (muxed-only
    /// fallback tier) or the artist page has no thumbnail — the
    /// Dart UI keeps its letter-avatar fallback.
    fun channelThumbBlocking(videoId: String): String? =
        runBlocking {
            try {
                val channelId = channelIds[videoId] ?: return@runBlocking null
                channelThumbs[channelId]?.let { return@runBlocking it }
                if (channelId in failedThumbs) return@runBlocking null
                val page = YouTube.artist(channelId).getOrNull()
                val thumb = page?.artist?.thumbnail
                if (thumb.isNullOrEmpty()) {
                    failedThumbs.add(channelId)
                    null
                } else {
                    channelThumbs[channelId] = thumb
                    thumb
                }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                Log.w(TAG, "channelThumb failed: ${e.message}")
                null
            }
        }

    /// WEB_REMIX player signature timestamp (NewPipe's JS engine —
    /// module surface; first call downloads the player JS once).
    /// Null on failure — best-effort.
    private fun signatureTimestamp(videoId: String): Int? =
        runCatching { NewPipeExtractor.getSignatureTimestamp(videoId).getOrNull() }
            .getOrNull()

    // ── format picking ───────────────────────────────────────

    /// maxKbps semantics carried over from the old resolver: a
    /// LOW-quality trigger (≤64 → lowest bitrate), otherwise the
    /// best stream. requireM4a filters to AAC (audio/mp4).
    /// Auto-dubbed audio tracks are deprioritized.
    private fun pickAudio(
        formats: List<PlayerResponse.StreamingData.Format>,
        maxKbps: Int,
        requireM4a: Boolean,
    ): PlayerResponse.StreamingData.Format? {
        var candidates = formats.filter { it.isAudio && it.url != null }
        if (requireM4a) {
            candidates =
                candidates.filter {
                    it.mimeType.contains("mp4a", true) ||
                            it.mimeType.contains("audio/mp4", true)
                }
        }
        val originals = candidates.filter { it.isOriginal }
        if (originals.isNotEmpty()) candidates = originals
        if (candidates.isEmpty()) return null
        return if (maxKbps <= LOW_KBPS) candidates.minByOrNull { it.bitrate }
        else candidates.maxByOrNull { it.bitrate }
    }

    /// Video-only stream for the watch backdrop: highest bitrate at
    /// ≤1080p (4K decode is wasted on a backdrop); falls back to the
    /// highest overall when every stream is taller.
    private fun pickVideo(
        formats: List<PlayerResponse.StreamingData.Format>,
    ): PlayerResponse.StreamingData.Format? {
        val videos = formats.filter { !it.isAudio && it.url != null }
        if (videos.isEmpty()) return null
        val capped = videos.filter { (it.height ?: 0) in 1..1080 }
        return (if (capped.isNotEmpty()) capped else videos).maxByOrNull { it.bitrate }
    }

    // ── refusals / exclusions / session ──────────────────────

    fun headersFor(url: String): Map<String, String>? = minted[url]?.headers

    fun onRefused(url: String): String? {
        val refused = minted.remove(url) ?: return null
        exclude(refused.videoId, refused.profileId)
        return refused.videoId
    }

    fun exclude(videoId: String, profileId: String) {
        Log.w(TAG, "$profileId refused $videoId; excluding it for this track")
        excluded.getOrPut(videoId) { ConcurrentHashMap() }[profileId] =
            SystemClock.elapsedRealtime() + EXCLUDE_MS
    }

    fun onSessionChanged() {
        excluded.clear()
        minted.clear()
        warmup?.cancel()
        warmup = scope.launch { runCatching { ensureVisitorData() } }
    }

    private fun excludedFor(videoId: String): Set<String> {
        val entries = excluded[videoId] ?: return emptySet()
        val now = SystemClock.elapsedRealtime()
        entries.entries.removeAll { it.value <= now }
        return entries.keys.toSet()
    }

    private fun debug(message: () -> String) {
        if (debugLogs) Log.d(TAG, message())
    }

    // Legacy prefs key name — deliberate (see class doc).
    private const val VISITOR_DATA_KEY = "innertubex_visitor_data"
    private const val LOW_KBPS = 64
    private const val EXCLUDE_MS = 10 * 60 * 1000L
    private const val MAX_REMEMBERED = 64
    private const val WARM_DELAY_MS = 2_000L

    // Plain OkHttp for the legacy visitorData page-grep fallback.
    private val pageClient = okhttp3.OkHttpClient()
}