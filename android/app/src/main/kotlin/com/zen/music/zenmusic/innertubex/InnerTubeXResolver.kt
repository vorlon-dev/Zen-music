package com.zen.music.zenmusic.innertubex

import android.content.Context
import android.os.SystemClock
import android.util.Log
import com.metrolist.innertubex.InnerTube
import com.metrolist.innertubex.InnerTubeLogLevel
import com.metrolist.innertubex.InnerTubeLogger
import com.metrolist.innertubex.cipher.PlayerConfigRepository
import com.metrolist.innertubex.cipher.RemotePlayerConfigStore
import com.metrolist.innertubex.cipher.YouTubeCipherService
import com.metrolist.innertubex.extraction.AudioQuality
import com.metrolist.innertubex.extraction.ContentHints
import com.metrolist.innertubex.extraction.InnerTubeExtractor
import com.metrolist.innertubex.extraction.PoTokenResult as ItxPoTokenResult
import com.metrolist.innertubex.extraction.TokenProvider
import com.metrolist.innertubex.extraction.TokenProviderCapabilities
import com.metrolist.innertubex.extraction.YtConfigParserImpl
import com.metrolist.innertubex.extraction.generateClientPlaybackNonce
import com.metrolist.innertubex.extraction.strategy.PoTokenProviderKind
import com.metrolist.innertubex.models.YouTubeLocale
import io.ktor.client.HttpClient
import io.ktor.client.engine.okhttp.OkHttp
import io.ktor.client.plugins.HttpTimeout
import io.ktor.client.plugins.contentnegotiation.ContentNegotiation
import io.ktor.serialization.kotlinx.json.json
import java.io.File
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
import kotlinx.serialization.json.Json

/**
 * YouTube stream extraction through InnerTubeX's live-benchmarked
 * client catalog and cipher tiers. ZenMusic adaptation: no account
 * cookie (login-gated age-restricted tracks may still fail — stated
 * limit), visitorData bootstrapped from a page fetch and PERSISTED —
 * after the first successful launch the fetch never runs again
 * (Echo's VisitorDataKey parity, adapted to SharedPreferences).
 */
object InnerTubeXResolver {

    private const val TAG = "ZenITX"

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

    private var prefs: android.content.SharedPreferences? = null
    private var poTokens: PoTokenGenerator? = null
    private var playerDir: File? = null
    private var warmup: Job? = null

    fun init(context: Context) {
        val app = context.applicationContext
        prefs = app.getSharedPreferences("innertubex_player_config", Context.MODE_PRIVATE)
        poTokens = PoTokenGenerator(app)
        playerDir = File(app.filesDir, "innertubex_players").apply { mkdirs() }
        scope.launch { warm(WARM_DELAY_MS) }
    }

    private fun warm(delayMs: Long) {
        warmup?.cancel()
        warmup =
            scope.launch {
                delay(delayMs)
                ensureVisitorData()
                val start = SystemClock.elapsedRealtime()
                runCatching {
                    // No cookie — ZenMusic has no account system.
                    innerTube.locale = YouTubeLocale(gl = "US", hl = "en")
                    extractor.prewarm()
                }
                    .onFailure { if (it is CancellationException) throw it }
                    .onFailure { Log.w(TAG, "InnerTubeX warm-up failed: ${it.message}") }
                    .onSuccess {
                        Log.d(TAG, "InnerTubeX warmed in ${SystemClock.elapsedRealtime() - start}ms")
                    }
            }
    }

    /// VisitorData resolution order:
    ///   1. Already set on the InnerTube client.
    ///   2. PERSISTED from a previous launch (Echo VisitorDataKey parity
    ///      — after the first successful fetch, this never runs again).
    ///   3. Page-fetch grep of youtube.com, then persisted.
    /// NOTE: Kotlin MatchResult exposes groups via groupValues[index],
    /// NOT group(index) (Java Matcher syntax).
    private suspend fun ensureVisitorData() {
        if (innerTube.visitorData != null) return

        // 2. Persisted value.
        val saved = prefs?.getString(VISITOR_DATA_KEY, null)
        if (!saved.isNullOrEmpty()) {
            innerTube.visitorData = saved
            Log.d(TAG, "InnerTubeX visitorData restored from prefs")
            return
        }

        // 3. Page-fetch grep, then persist.
        try {
            val body =
                withContext(Dispatchers.IO) {
                    httpEngine.newCall(
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
            innerTube.visitorData = vd
            prefs?.edit()?.putString(VISITOR_DATA_KEY, vd)?.apply()
            Log.d(TAG, "InnerTubeX visitorData bootstrapped + persisted")
        } catch (_: Exception) {
        }
    }

    /// Blocking visitorData access for the MethodChannel (ensures the
    /// bootstrap has run first). Used by the home-chips service so its
    /// param-filtered browse carries the session identity YouTube
    /// requires for filtered home content.
    fun visitorDataBlocking(): String? = runBlocking {
        ensureVisitorData()
        innerTube.visitorData
    }

    private fun readPlayer(key: String): String? =
        playerDir?.let { File(it, key) }?.takeIf { it.isFile }?.readText()

    private fun writePlayer(key: String, value: String?) {
        val dir = playerDir ?: return
        val file = File(dir, key)
        if (value == null) {
            file.delete()
            return
        }
        val tmp = File(dir, "$key.tmp")
        tmp.writeText(value)
        tmp.renameTo(file)
        dir
            .listFiles()
            ?.filter { !it.name.endsWith(".tmp") }
            ?.sortedByDescending { it.lastModified() }
            ?.drop(KEPT_PLAYERS)
            ?.forEach { it.delete() }
    }

    private val tokenProvider =
        object : TokenProvider {
            override val capabilities =
                TokenProviderCapabilities(
                    providers = setOf(PoTokenProviderKind.WEB_BOTGUARD),
                    usesWebView = true,
                )

            override suspend fun getPoToken(
                videoId: String,
                visitorData: String,
                cookie: String?
            ): ItxPoTokenResult? =
                poTokens?.getWebClientPoToken(videoId, visitorData)?.let { token ->
                    ItxPoTokenResult(
                        playerRequestToken = token.playerRequestPoToken,
                        streamingDataToken = token.streamingDataPoToken,
                        visitorData = visitorData,
                    )
                }

            override suspend fun close() {}
        }

    private val http =
        HttpClient(OkHttp) {
            install(ContentNegotiation) {
                json(
                    Json {
                        ignoreUnknownKeys = true
                        explicitNulls = false
                        encodeDefaults = true
                    }
                )
            }
            install(HttpTimeout) {
                requestTimeoutMillis = 30_000
                connectTimeoutMillis = 15_000
                socketTimeoutMillis = 20_000
            }
            expectSuccess = false
        }

    // Plain OkHttp for the visitorData bootstrap (no ktor in that path).
    private val httpEngine = okhttp3.OkHttpClient()

    private val logger = InnerTubeLogger { event ->
        if (event.level == InnerTubeLogLevel.DEBUG && !itxDebugLogs) return@InnerTubeLogger
        val details =
            if (event.details.isEmpty()) ""
            else
                event.details.entries.joinToString(prefix = " [", postfix = "]") { "${it.key}=${it.value}" }
        val line = "ITX ${event.tag}: ${event.message}$details"
        if (event.level == InnerTubeLogLevel.INFO || event.level == InnerTubeLogLevel.DEBUG)
            Log.d(TAG, line)
        else Log.w(TAG, line)
    }

    private val repository =
        object : PlayerConfigRepository {
            override val enabled: Boolean
                get() = prefs != null

            override val sourceUrl: String = PLAYER_CONFIG_URL
            override val defaultSourceUrl: String = PLAYER_CONFIG_URL
            override var cachedJson: String
                get() = prefs?.getString("json", "").orEmpty()
                set(value) {
                    prefs?.edit()?.putString("json", value)?.apply()
                }

            override var cachedAtMs: Long
                get() = prefs?.getLong("cached_at_ms", 0L) ?: 0L
                set(value) {
                    prefs?.edit()?.putLong("cached_at_ms", value)?.apply()
                }

            override var cachedSourceUrl: String
                get() = prefs?.getString("source_url", "").orEmpty()
                set(value) {
                    prefs?.edit()?.putString("source_url", value)?.apply()
                }

            override var cachedEtag: String
                get() = prefs?.getString("etag", "").orEmpty()
                set(value) {
                    prefs?.edit()?.putString("etag", value)?.apply()
                }
        }

    private val innerTube = InnerTube(http, logger = logger)
    private val remoteStore = RemotePlayerConfigStore(http, repository, logger)
    private val cipherService = YouTubeCipherService(http, remoteStore, logger)
    private val extractor =
        InnerTubeExtractor(
            configParser = YtConfigParserImpl(http, innerTube, remoteStore, logger),
            cipherService = cipherService,
            innerTube = innerTube,
            tokenProvider = tokenProvider,
            logger = logger,
        )

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    private val minted = ConcurrentHashMap<String, Extracted>()
    private val excluded = ConcurrentHashMap<String, ConcurrentHashMap<String, Long>>()

    suspend fun extract(
        videoId: String,
        maxKbps: Int,
        skipClients: Set<String> = emptySet(),
        requireM4a: Boolean = false,
    ): Extracted? {
        ensureVisitorData()
        // No cookie — ZenMusic has no account system.
        innerTube.locale = YouTubeLocale(gl = "US", hl = "en")
        val stream =
            extractor.extract(
                videoId = videoId,
                hints =
                    ContentHints()
                        .withStreamCapabilities(allowHls = false, allowSabr = false, allowBoundedRange = true),
                excludedClients = excludedFor(videoId) + skipClients,
                audioQuality =
                    when {
                        requireM4a -> AudioQuality.MP4
                        maxKbps <= LOW_KBPS -> AudioQuality.LOW
                        else -> AudioQuality.AUTO
                    },
                clientPlaybackNonce = generateClientPlaybackNonce(),
            ) ?: return null
        check(stream.sabrBootstrap == null) { "SABR is not supported by this playback engine" }
        val mime = stream.mimeType.orEmpty()
        val extracted =
            Extracted(
                videoId = videoId,
                url = stream.audioUrl,
                kbps = (stream.bitrate ?: 0) / 1000,
                mimeType =
                    if (stream.codecs.isNullOrBlank()) mime else "$mime; codecs=\"${stream.codecs}\"",
                loudnessDb = stream.loudnessDb,
                clientName = stream.clientName,
                profileId = stream.profileId,
                headers = stream.headers,
            )
        if (minted.size >= MAX_REMEMBERED) minted.clear()
        minted[extracted.url] = extracted
        return extracted
    }

    /// Blocking wrapper for the MethodChannel worker thread.
    fun extractBlocking(
        videoId: String,
        maxKbps: Int,
        skipClients: Set<String>,
        requireM4a: Boolean,
    ): Extracted? =
        runBlocking { extract(videoId, maxKbps, skipClients, requireM4a) }

    fun headersFor(url: String): Map<String, String>? = minted[url]?.headers

    fun onRefused(url: String): String? {
        val refused = minted.remove(url) ?: return null
        exclude(refused.videoId, refused.profileId)
        scope.launch { runCatching { cipherService.refreshAfterStreamRejection() } }
        return refused.videoId
    }

    fun exclude(videoId: String, profileId: String) {
        Log.w(TAG, "InnerTubeX: $profileId refused $videoId; skipping it for this track")
        excluded.getOrPut(videoId) { ConcurrentHashMap() }[profileId] =
            SystemClock.elapsedRealtime() + EXCLUDE_MS
    }

    fun onSessionChanged() {
        excluded.clear()
        minted.clear()
        if (prefs != null) warm(0)
    }

    private fun excludedFor(videoId: String): Set<String> {
        val entries = excluded[videoId] ?: return emptySet()
        val now = SystemClock.elapsedRealtime()
        entries.entries.removeAll { it.value <= now }
        return entries.keys.toSet()
    }

    private const val VISITOR_DATA_KEY = "innertubex_visitor_data"
    private const val PLAYER_CONFIG_URL =
        "https://raw.githubusercontent.com/ZemerTeam/zemer-cipher/master/library/src/main/assets/player_configs.json"
    private const val LOW_KBPS = 64
    private const val EXCLUDE_MS = 10 * 60 * 1000L
    private const val MAX_REMEMBERED = 64
    private const val WARM_DELAY_MS = 2_000L
    private const val KEPT_PLAYERS = 3
}