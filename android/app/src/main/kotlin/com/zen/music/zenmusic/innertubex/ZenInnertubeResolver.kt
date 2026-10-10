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
 * Client chain: ANDROID_VR 1.65.10 → VISIONOS → WEB_REMIX (the
 * poToken-armed escape hatch, attempted ONLY when a BotGuard token
 * is instantly available — skipped otherwise; a cold mint never
 * blocks extraction past the watch screen's stall window).
 *
 * QUALITY (video watch): the first successful video extraction
 * caches ALL video-only formats for the videoId (heights + urls +
 * UA). videoQualitiesBlocking serves the YouTube-style picker;
 * extractVideoBlocking(maxHeight) re-picks from the cache (or
 * re-extracts) at the chosen height — no full re-extraction when
 * the cache holds.
 */
object ZenInnertubeResolver {

    private const val TAG = "ZenTube"

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

    class VideoStreams(
        val videoId: String,
        val audioUrl: String?,
        val videoUrl: String?,
        val headers: Map<String, String>,
        val clientName: String,
    )

    @Volatile
    var debugLogs: Boolean = false

    private var prefs: android.content.SharedPreferences? = null
    private var warmup: Job? = null

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    private val minted = ConcurrentHashMap<String, Extracted>()

    private val channelIds = ConcurrentHashMap<String, String>()
    private val channelThumbs = ConcurrentHashMap<String, String>()
    private val failedThumbs: MutableSet<String> = ConcurrentHashMap.newKeySet()

    private val excluded = ConcurrentHashMap<String, ConcurrentHashMap<String, Long>>()

    // QUALITY CACHE: videoId -> the video-only formats of its last
    // successful player response + the response's UA. The first
    // extraction populates it; the picker reads it; a quality switch
    // re-picks from it without a second player call.
    private class CachedQualities(
        val ua: String,
        val formats: List<PlayerResponse.StreamingData.Format>,
    )
    private val qualityCache = ConcurrentHashMap<String, CachedQualities>()

    private class Candidate(val id: String, val client: YouTubeClient)

    private val audioChain =
        listOf(
            Candidate("VR_1_65_10", YouTubeClient.ANDROID_VR_1_65_10),
            Candidate("VISIONOS", YouTubeClient.VISIONOS),
            Candidate("WEB_REMIX", YouTubeClient.WEB_REMIX),
        )

    private val videoChain =
        listOf(
            Candidate("VISIONOS", YouTubeClient.VISIONOS),
            Candidate("VR_1_65_10", YouTubeClient.ANDROID_VR_1_65_10),
            Candidate("WEB_REMIX", YouTubeClient.WEB_REMIX),
        )

    fun init(context: Context) {
        val app = context.applicationContext
        prefs =
            app.getSharedPreferences("innertubex_player_config", Context.MODE_PRIVATE)
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
        YouTube.locale = YouTubeLocale(gl = "US", hl = "en")
        // Mint OFF the critical path: only when the session is warm.
        val poToken = if (ZenPoTokenBridge.isSessionReady()) {
            ZenPoTokenBridge.playerTokenBlocking(videoId, YouTube.visitorData)
        } else null
        val skip = excludedFor(videoId) + skipClients
        for (candidate in audioChain) {
            if (candidate.id in skip) continue
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
                val url = best.url ?: continue
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

    fun extractBlocking(
        videoId: String,
        maxKbps: Int,
        skipClients: Set<String>,
        requireM4a: Boolean,
    ): Extracted? = runBlocking { extract(videoId, maxKbps, skipClients, requireM4a) }

    /// Audio + video for the watch page. [maxHeight] caps the video
    /// stream (the quality picker's contract: null/0 = the default
    /// best ≤1080p pick). The response's video formats land in the
    /// quality cache either way.
    fun extractVideoBlocking(videoId: String, maxHeight: Int = 0): VideoStreams? =
        runBlocking {
            ensureVisitorData()
            YouTube.locale = YouTubeLocale(gl = "US", hl = "en")
            val poToken = if (ZenPoTokenBridge.isSessionReady()) {
                ZenPoTokenBridge.playerTokenBlocking(videoId, YouTube.visitorData)
            } else null
            try {
                // Quality-cache fast path: a picked quality re-serve
                // from the cached formats — no second player call.
                val cached = qualityCache[videoId]
                if (cached != null && maxHeight > 0) {
                    val pick = pickVideoAt(cached.formats, maxHeight)
                    if (pick?.url != null) {
                        debug {
                            "quality cache serve $videoId ${pick.height}p"
                        }
                        return@runBlocking VideoStreams(
                            videoId = videoId,
                            audioUrl = null, // audio layer unchanged — caller keeps it
                            videoUrl = pick.url,
                            headers = mapOf("User-Agent" to cached.ua),
                            clientName = "quality-cache",
                        )
                    }
                }
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
                    // Cache ALL video-only formats for the picker.
                    val videoFormats = formats.filter { !it.isAudio && it.url != null }
                    if (videoFormats.isNotEmpty()) {
                        qualityCache[videoId] =
                            CachedQualities(candidate.client.userAgent, videoFormats)
                    }
                    val audio = pickAudio(formats, Int.MAX_VALUE, requireM4a = false)
                    val video = if (maxHeight > 0) {
                        pickVideoAt(videoFormats, maxHeight)
                            ?: pickVideo(formats)
                    } else {
                        pickVideo(formats)
                    }
                    if (audio?.url == null && video?.url == null) continue
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

    /// The YouTube-style picker's data: distinct heights (descending)
    /// available for [videoId] from the quality cache. Empty when the
    /// cache is cold (muxed-only tier) — the UI hides the picker.
    fun videoQualitiesBlocking(videoId: String): List<Map<String, Any?>> =
        runBlocking {
            try {
                val cached = qualityCache[videoId] ?: return@runBlocking emptyList()
                cached.formats
                    .mapNotNull { f ->
                        val h = f.height ?: return@mapNotNull null
                        Triple(h, f.bitrate, f.url ?: return@mapNotNull null)
                    }
                    .groupBy { it.first }
                    .map { (height, entries) ->
                        mapOf<String, Any?>(
                            "height" to height,
                            "kbps" to entries.maxOf { it.second } / 1000,
                        )
                    }
                    .sortedByDescending { it["height"] as Int }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                Log.w(TAG, "videoQualities failed: ${e.message}")
                emptyList()
            }
        }

    // ── related / channel art ────────────────────────────────

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

    /// WEB_REMIX player signature timestamp (NewPipe's JS engine).
    private fun signatureTimestamp(videoId: String): Int? =
        runCatching { NewPipeExtractor.getSignatureTimestamp(videoId).getOrNull() }
            .getOrNull()

    // ── format picking ───────────────────────────────────────

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

    /// Default pick: highest bitrate at ≤1080p.
    private fun pickVideo(
        formats: List<PlayerResponse.StreamingData.Format>,
    ): PlayerResponse.StreamingData.Format? {
        val videos = formats.filter { !it.isAudio && it.url != null }
        if (videos.isEmpty()) return null
        val capped = videos.filter { (it.height ?: 0) in 1..1080 }
        return (if (capped.isNotEmpty()) capped else videos).maxByOrNull { it.bitrate }
    }

    /// Quality pick: the closest height ≤ [maxHeight] (highest
    /// bitrate within it); falls back to the smallest available when
    /// everything is taller than the request.
    private fun pickVideoAt(
        videos: List<PlayerResponse.StreamingData.Format>,
        maxHeight: Int,
    ): PlayerResponse.StreamingData.Format? {
        val eligible = videos.filter { (it.height ?: 0) in 1..maxHeight }
        return if (eligible.isNotEmpty()) {
            eligible.maxByOrNull { it.height ?: 0 }
        } else {
            videos.minByOrNull { it.height ?: Int.MAX_VALUE }
        }
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
        qualityCache.clear()
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

    private const val VISITOR_DATA_KEY = "innertubex_visitor_data"
    private const val LOW_KBPS = 64
    private const val EXCLUDE_MS = 10 * 60 * 1000L
    private const val MAX_REMEMBERED = 64
    private const val WARM_DELAY_MS = 2_000L

    private val pageClient = okhttp3.OkHttpClient()
}