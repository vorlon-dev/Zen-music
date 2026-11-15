// ZenMusic · vorlon-dev
//
// SP71 — the Kotlin mirror engine (Android hot-standby).
//
// The Dart engine (lib/desktop/lossless/mirror_source.dart) resolves FLAC
// from the community mirror pool, but on a flaky network / rate-limited
// upstream it opens its breaker and the session silently degrades to
// normal (lossy) quality — exactly the "works for a few songs, then
// normal songs play" report. This file is the SAME engine re-implemented
// natively so the two can alternate: while the Dart engine resolves,
// this one is never called (standby); when the Dart engine stops (breaker,
// timeouts, misses), the arbiter hands the track here and playback keeps
// streaming FLAC instead of dropping to lossy.
//
// Hosts, API key and timeouts are INJECTED from Dart at configure time
// (mirror_arbiter.dart reads them from MirrorConfig + the fixed qobuz
// endpoint) — nothing is hardcoded here, so endpoint redeploys never
// need a Kotlin change.
//
// Resolution order: qobuz (the fixed endpoint — healthiest) -> tidal ->
// deezer. Every candidate is scored the same way as the Dart engine
// (token Dice similarity, 0.62 / 0.70 gates, duration penalty) and every
// manifest is probed before it is served: the head of the CDN asset is
// fetched (Blowfish-decrypted for Deezer) and the REAL duration is read
// from the FLAC STREAMINFO header. 30-second previews never make it out
// of this file.
//
// Emergency mode (`emergency()`): used ONLY when both engines failed for
// a track. The fixed endpoint is asked for a stream URL directly — first
// via the manifest, then via its /api/stream relay which relays the full
// FLAC itself. The arbiter rate-limits this to once per 10 minutes so it
// stays a true emergency path.

package com.zen.music.zenmusic.mirror

import android.util.Log
import org.json.JSONArray
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder
import java.util.Locale
import java.util.concurrent.TimeUnit
import java.util.concurrent.locks.ReentrantLock

object MirrorEngine {
    private const val TAG = "ZenMirror"

    // ------------------------------------------------------- configuration

    @Volatile private var tidalHost: String? = null
    @Volatile private var deezerHost: String? = null
    @Volatile private var qobuzHost: String? = null
    @Volatile private var apiKey: String = ""
    @Volatile private var searchMs: Int = 4000
    @Volatile private var manifestMs: Int = 6000
    @Volatile private var probeMs: Int = 6000
    @Volatile private var streamConnectMs: Int = 8000
    @Volatile var configured: Boolean = false
        private set

    // Per-host search cooldown when the mirror answers "Too many requests"
    // upstream (same pattern as the Dart engine's SP70 behaviour: manifests
    // stay usable, only text search rests).
    private val rateLimitCooldownMs = 3 * 60 * 1000L
    private val rateLimitUntil = HashMap<String, Long>()

    // Breaker — same shape as the Dart engine: two consecutive network
    // failures open it for 2 minutes; the arbiter then stops calling this
    // engine and the chain falls through instantly.
    private val netLock = Any()
    private var netFailStreak = 0
    @Volatile private var openUntil = 0L

    // ------------------------------------------------------------- caches

    private val cacheLock = Any()
    // manifest cache: "kind|id|param" -> (descriptor, expiresAt)
    private val manifestCache = HashMap<String, Pair<ManifestDesc, Long>>()
    // per-track negative cache: "title|artist" (lowercased) -> expiresAt
    private val failCache = HashMap<String, Long>()

    private val manifestTtlMs = 4 * 60 * 1000L
    private val failTtlMs = 10 * 60 * 1000L
    private val maxCacheEntries = 64

    // Serialise resolution — gentle on the mirrors, matches the Dart
    // engine's bounded slots. A caller that would wait too long gets
    // {status: busy} and the chain falls through (never stalls).
    private val resolveLock = ReentrantLock()

    // ------------------------------------------------------------ types

    private class SearchHit(
        val trackId: String,
        val title: String,
        val artist: String,
        val durationMs: Int?,
        val hiRes: Boolean,
        val bitDepth: Int?,
        val sampleRate: Int?
    )

    private class SearchOutcome(
        val hits: List<SearchHit>?,
        val netError: Boolean,
        val rateLimited: Boolean
    )

    private class ManifestDesc(
        val url: String,
        val seconds: Int,
        val bitDepth: Int,
        val sampleRate: Int,
        val key: ByteArray? // deezer only
    )

    private class HttpReply(val status: Int, val body: ByteArray, val error: String?)

    // ---------------------------------------------------------- lifecycle

    /** Injected from Dart (mirror_arbiter.dart). No endpoint is hardcoded. */
    fun configure(
        tidal: String?,
        deezer: String?,
        qobuz: String?,
        apiKeyValue: String,
        timeouts: Map<String, Int>
    ): Boolean {
        tidalHost = tidal?.trim()?.trimEnd('/')?.ifBlank { null }
        deezerHost = deezer?.trim()?.trimEnd('/')?.ifBlank { null }
        qobuzHost = qobuz?.trim()?.trimEnd('/')?.ifBlank { null }
        apiKey = apiKeyValue ?: ""
        searchMs = timeouts["searchMs"] ?: 4000
        manifestMs = timeouts["manifestMs"] ?: 6000
        probeMs = timeouts["probeMs"] ?: 6000
        streamConnectMs = timeouts["streamConnectMs"] ?: 8000

        val problem = blowfishSelfTest()
        if (problem != null) {
            Log.e(TAG, "[zenmirror] blowfish self-test FAILED: $problem — deezer probe disabled")
        } else {
            Log.i(TAG, "[zenmirror] blowfish self-test OK")
        }
        synchronized(cacheLock) {
            manifestCache.clear()
            failCache.clear()
        }
        synchronized(rateLimitUntil) { rateLimitUntil.clear() }
        synchronized(netLock) {
            netFailStreak = 0
            openUntil = 0L
        }
        configured = true
        Log.i(TAG, "[zenmirror] configured (tidal=${tidalHost != null}, deezer=${deezerHost != null}, " +
            "qobuz=${qobuzHost != null}, search=${searchMs}ms, manifest=${manifestMs}ms)")
        return true
    }

    // ------------------------------------------------------------ resolve

    /**
     * Resolve one track the same way the Dart engine does.
     * Returns a map with `status` = ok | no_match | error | breaker | busy.
     * On ok: kind (tide|dz|relay), url, seconds, tier, trackId (+key64 for dz).
     */
    fun resolve(
        title: String,
        artist: String,
        durationMs: Int?,
        wantsHiRes: Boolean,
        budgetMs: Long
    ): Map<String, Any?> {
        if (!configured) return mapOf("status" to "error", "message" to "not configured")
        val failKey = "$title|$artist".lowercase(Locale.ROOT).trim()
        val now = nowMs()

        synchronized(cacheLock) {
            val until = failCache[failKey]
            if (until != null && now < until) {
                return mapOf("status" to "no_match")
            }
        }
        if (nowMs() < openUntil) {
            return mapOf("status" to "breaker")
        }
        if (!resolveLock.tryLock(500, TimeUnit.MILLISECONDS)) {
            return mapOf("status" to "busy")
        }
        try {
            val deadline = nowMs() + budgetMs.coerceIn(1500, 8000)
            var sawNetError = false

            // SP71d: the mirror searches run IN PARALLEL (the same lesson
            // the Dart engine learned in SP70 — one search window per track
            // instead of back-to-back timeouts). Priority is unchanged:
            // qobuz (the fixed endpoint) -> tidal -> deezer. When several
            // searches answer, the first leg in that order holding a
            // scoring-gate hit wins the manifest fetch; a dead or slow host
            // can no longer burn the whole budget AHEAD of the healthy ones
            // (its search thread simply finishes late or is abandoned).
            val hosts = listOf(
                Triple("qobuz", qobuzHost, 0.62),
                Triple("tidal", tidalHost, 0.62),
                Triple("deezer", deezerHost, 0.70)
            )
            val legs = ArrayList<Triple<String, String, Double>>()
            for ((kind, host, threshold) in hosts) {
                if (host == null) continue
                if (hostCoolingDown(host)) continue
                legs.add(Triple(kind, host, threshold))
            }

            val answers = ArrayList<Pair<String, SearchOutcome>>()
            if (legs.isNotEmpty()) {
                // Healthy mirrors answer in 1-2 s; a dead one ends at its
                // connect timeout (~searchMs). The wait window gathers all
                // search threads but never overruns the caller's deadline;
                // abandoned stragglers are daemons and just die quietly.
                val waitUntil = minOf(deadline, nowMs() + searchMs + 1500L)
                val workers = legs.map { (kind, host, _) ->
                    Thread {
                        val oc = try {
                            searchWithRetry(host, kind, title, artist, deadline)
                        } catch (t: Throwable) {
                            Log.i(TAG, "[zenmirror] $kind search worker failed: ${t.message}")
                            SearchOutcome(null, netError = true, rateLimited = false)
                        }
                        synchronized(answers) { answers.add(kind to oc) }
                    }.apply { isDaemon = true }
                }
                workers.forEach { it.start() }
                workers.forEach { w ->
                    val remain = waitUntil - nowMs()
                    if (remain > 0) w.join(remain) else w.join(1)
                }
            }

            // Process answers strictly by priority; the first scoring-gate
            // hit wins, and the ladder continues if its manifest fails.
            for ((kind, _, threshold) in hosts) {
                val oc = answers.firstOrNull { it.first == kind }?.second ?: continue
                if (oc.rateLimited) continue
                if (oc.netError) {
                    sawNetError = true
                    noteNetFail("$kind search")
                    continue
                }
                val best = bestHit(oc.hits, title, artist, durationMs, threshold)
                if (best == null) continue

                val manifest = when (kind) {
                    "qobuz" -> fetchQobuzManifest(best.trackId, deadline)
                    "tidal" -> fetchTidalManifest(
                        best.trackId,
                        if (wantsHiRes) "strict_24=1" else "prefer_16=1",
                        deadline
                    )
                    else -> fetchDeezerManifest(best.trackId, deadline)
                }
                if (manifest == null) continue
                if (!isFullTrack(manifest.seconds, durationMs)) {
                    Log.i(TAG, "[zenmirror] $kind ${best.trackId} preview/short cut " +
                        "rejected (${manifest.seconds}s)")
                    continue
                }
                noteNetOk()
                return descriptor(kind, best, manifest)
            }

            synchronized(cacheLock) {
                failCache[failKey] = nowMs() + failTtlMs
                evictLocked(failCache)
            }
            return if (sawNetError) {
                mapOf("status" to "error", "message" to "mirror network failures")
            } else {
                mapOf("status" to "no_match")
            }
        } finally {
            resolveLock.unlock()
        }
    }

    // ---------------------------------------------------------- emergency

    /**
     * EMERGENCY ONLY — called by the arbiter when BOTH engines failed for
     * a track and the emergency cooldown has expired. The fixed endpoint
     * is asked for a stream URL directly: first its manifest, then its
     * /api/stream relay which hands out the full FLAC itself.
     */
    fun emergency(
        title: String,
        artist: String,
        durationMs: Int?,
        budgetMs: Long
    ): Map<String, Any?> {
        val host = qobuzHost
        if (!configured || host == null) {
            return mapOf("status" to "error", "message" to "not configured")
        }
        if (!resolveLock.tryLock(500, TimeUnit.MILLISECONDS)) {
            return mapOf("status" to "busy")
        }
        try {
            val deadline = nowMs() + budgetMs.coerceIn(1500, 9000)
            Log.i(TAG, "[zenmirror] EMERGENCY resolve for '$title' by '$artist'")

            val outcome = searchWithRetry(host, "qobuz", title, artist, deadline)
            val best = bestHit(outcome.hits, title, artist, durationMs, 0.62)
                ?: return mapOf("status" to "no_match")

            // 1) manifest — the endpoint hands out a signed CDN stream URL
            //    (akamai honours Range, so playback seeks stay cheap).
            val manifest = fetchQobuzManifest(best.trackId, deadline)
            if (manifest != null && isFullTrack(manifest.seconds, durationMs)) {
                noteNetOk()
                return descriptor("tide", best, manifest)
            }

            // 2) relay — GET /api/stream/{id} answers the full FLAC itself.
            if (nowMs() < deadline) {
                val relayUrl = "$host/api/stream/${best.trackId}"
                val reply = httpGet(
                    relayUrl,
                    range = "bytes=0-63",
                    connectMs = streamConnectMs,
                    readMs = probeMs,
                    maxBytes = 64
                )
                if (reply.status in 200..299 && reply.body.size >= 42) {
                    val seconds = flacDurationSeconds(reply.body)
                    if (seconds != null && isFullTrack(seconds, durationMs)) {
                        noteNetOk()
                        Log.i(TAG, "[zenmirror] EMERGENCY relay accepted " +
                            "($seconds s) for ${best.trackId}")
                        return mapOf(
                            "status" to "ok",
                            "kind" to "relay",
                            "url" to relayUrl,
                            "seconds" to seconds,
                            "trackId" to best.trackId,
                            "tier" to tierOf(best.bitDepth ?: 16, best.sampleRate ?: 44100)
                        )
                    }
                    Log.i(TAG, "[zenmirror] EMERGENCY relay rejected " +
                        "(seconds=$seconds, not a verifiable full FLAC)")
                } else {
                    Log.i(TAG, "[zenmirror] EMERGENCY relay HTTP ${reply.status} " +
                        "${reply.error ?: ""}")
                }
            }
            return mapOf("status" to "no_match")
        } finally {
            resolveLock.unlock()
        }
    }

    // ------------------------------------------------------------- search

    /** Round 1 "title artist" -> (when empty) round 2 title-only rescue. */
    private fun searchWithRetry(
        host: String,
        kind: String,
        title: String,
        artist: String,
        deadline: Long
    ): SearchOutcome {
        val first = searchOnce(host, kind, title, artist, deadline)
        if (first.netError || first.rateLimited) return first
        if (!first.hits.isNullOrEmpty()) return first
        if (artist.isBlank()) return first
        if (nowMs() >= deadline) return first
        val retry = searchOnce(host, kind, title, "", deadline)
        if (retry.netError || retry.rateLimited) return first
        return retry
    }

    private fun searchOnce(
        host: String,
        kind: String,
        title: String,
        artist: String,
        deadline: Long
    ): SearchOutcome {
        val url = when (kind) {
            "qobuz" -> {
                val params = StringBuilder("title=").append(enc(title))
                if (artist.isNotBlank()) params.append("&artist=").append(enc(artist))
                params.append("&limit=5")
                "$host/api/search?$params"
            }
            "tidal" -> {
                val q = if (artist.isNotBlank()) "$title $artist" else title
                "$host/search/?s=${enc(q)}"
            }
            else -> {
                val params = StringBuilder("title=").append(enc(title))
                if (artist.isNotBlank()) params.append("&artist=").append(enc(artist))
                params.append("&limit=5")
                "$host/api/search?$params"
            }
        }
        val reply = httpGet(
            url,
            headers = baseHeaders(),
            connectMs = searchMs,
            readMs = searchMs,
            maxBytes = 512 * 1024
        )
        if (reply.status == -1) return SearchOutcome(null, netError = true, rateLimited = false)
        if (reply.status !in 200..299) {
            val body = String(reply.body, Charsets.UTF_8)
            if (body.lowercase(Locale.ROOT).contains("too many requests")) {
                synchronized(rateLimitUntil) {
                    rateLimitUntil[host] = nowMs() + rateLimitCooldownMs
                }
                Log.i(TAG, "[zenmirror] $kind search rate-limited upstream — cooling down 3 min")
                return SearchOutcome(null, netError = false, rateLimited = true)
            }
            return SearchOutcome(null, netError = false, rateLimited = false)
        }
        return try {
            SearchOutcome(parseSearch(kind, String(reply.body, Charsets.UTF_8)),
                netError = false, rateLimited = false)
        } catch (e: Exception) {
            Log.i(TAG, "[zenmirror] $kind search parse error: ${e.message}")
            SearchOutcome(null, netError = false, rateLimited = false)
        }
    }

    private fun parseSearch(kind: String, body: String): List<SearchHit> {
        val root = JSONObject(body)
        val items: JSONArray = when (kind) {
            "tidal" -> root.optJSONObject("data")?.optJSONArray("items") ?: JSONArray()
            else -> root.optJSONArray("results") ?: JSONArray()
        }
        val hits = ArrayList<SearchHit>()
        for (i in 0 until items.length()) {
            val raw = items.optJSONObject(i) ?: continue
            when (kind) {
                "tidal" -> hits.add(
                    SearchHit(
                        trackId = "${raw.opt("id") ?: ""}",
                        title = "${raw.opt("title") ?: ""}",
                        artist = raw.optJSONObject("artist")?.optString("name") ?: "",
                        durationMs = raw.opt("duration")?.let {
                            if (it is Number && it.toDouble() > 0) (it.toDouble() * 1000).toInt() else null
                        },
                        hiRes = "${raw.opt("audioQuality") ?: ""}".uppercase(Locale.ROOT)
                            .contains("HI_RES"),
                        bitDepth = null,
                        sampleRate = null
                    )
                )
                else -> hits.add(
                    SearchHit(
                        trackId = "${raw.opt("track_id") ?: ""}",
                        title = "${raw.opt("title") ?: ""}",
                        artist = "${raw.opt("artist") ?: ""}",
                        durationMs = raw.opt("duration_ms")?.let {
                            if (it is Number && it.toLong() > 0) it.toInt() else null
                        },
                        hiRes = "${raw.opt("quality") ?: ""}".uppercase(Locale.ROOT)
                            .contains("HIRES"),
                        bitDepth = raw.opt("bitDepth")?.let { if (it is Number) it.toInt() else null },
                        sampleRate = raw.opt("sampleRate")?.let { if (it is Number) it.toInt() else null }
                    )
                )
            }
        }
        return hits
    }

    // ---------------------------------------------------------- manifests

    private fun fetchQobuzManifest(trackId: String, deadline: Long): ManifestDesc? =
        fetchManifestCached("qobuz", trackId, "", deadline) { fetchPlainManifest("qobuz", it, "") }

    private fun fetchTidalManifest(trackId: String, param: String, deadline: Long): ManifestDesc? =
        fetchManifestCached("tidal", trackId, param, deadline) { fetchPlainManifest("tidal", it, param) }

    private fun fetchDeezerManifest(trackId: String, deadline: Long): ManifestDesc? =
        fetchManifestCached("deezer", trackId, "", deadline) { fetchDeezerManifestInner(it) }

    private fun fetchManifestCached(
        kind: String,
        trackId: String,
        param: String,
        deadline: Long,
        fetch: (String) -> ManifestDesc?
    ): ManifestDesc? {
        val cacheKey = "$kind|$trackId|$param"
        val now = nowMs()
        synchronized(cacheLock) {
            val hit = manifestCache[cacheKey]
            if (hit != null && now < hit.second) return hit.first
        }
        if (nowMs() >= deadline) return null
        val desc = fetch(trackId) ?: return null
        synchronized(cacheLock) {
            manifestCache[cacheKey] = desc to (nowMs() + manifestTtlMs)
            evictLocked(manifestCache)
        }
        return desc
    }

    /** qobuz + tidal: JSON manifest with a plain (unencrypted) FLAC URL. */
    private fun fetchPlainManifest(kind: String, trackId: String, param: String): ManifestDesc? {
        val host = if (kind == "qobuz") qobuzHost else tidalHost
        if (host == null) return null
        val suffix = if (param.isBlank()) "" else "?$param"
        val url = "$host/api/track/$trackId$suffix"
        val reply = httpGet(
            url,
            headers = baseHeaders(),
            connectMs = manifestMs,
            readMs = manifestMs,
            maxBytes = 512 * 1024
        )
        if (reply.status == -1) {
            noteNetFail("$kind manifest")
            return null
        }
        if (reply.status !in 200..299) return null
        return try {
            val data = JSONObject(String(reply.body, Charsets.UTF_8))
            val urls = data.optJSONArray("streamUrls")
            val url0 = (if (urls != null && urls.length() > 0) urls.optString(0) else "")
                .ifBlank { data.optString("streamUrl") }
            if (url0.isBlank()) return null
            val codec = data.optString("codec").lowercase(Locale.ROOT)
            if (codec.isNotEmpty() && !codec.contains("flac")) return null
            val quality = (if (data.has("audioQuality")) data.optString("audioQuality")
                else data.optString("quality")).uppercase(Locale.ROOT)
            if (quality.contains("PREVIEW")) return null
            if (looksLikePreviewUrl(url0)) return null
            val seconds = probeFlacSeconds(url0, blowfishKey = null) ?: run {
                Log.i(TAG, "[zenmirror] $kind manifest $trackId: not a verifiable full FLAC — rejected")
                return null
            }
            ManifestDesc(
                url = url0,
                seconds = seconds,
                bitDepth = data.opt("bitDepth")?.let { if (it is Number) it.toInt() else 16 } ?: 16,
                sampleRate = data.opt("sampleRate")?.let { if (it is Number) it.toInt() else 44100 } ?: 44100,
                key = null
            )
        } catch (e: Exception) {
            Log.i(TAG, "[zenmirror] $kind manifest error: ${e.message}")
            noteNetFail("$kind manifest")
            null
        }
    }

    /** deezer: manifest carries the CDN URL + the raw-ASCII Blowfish key. */
    private fun fetchDeezerManifestInner(trackId: String): ManifestDesc? {
        val host = deezerHost ?: return null
        val url = "$host/api/track/$trackId"
        val reply = httpGet(
            url,
            headers = baseHeaders(),
            connectMs = manifestMs,
            readMs = manifestMs,
            maxBytes = 512 * 1024
        )
        if (reply.status == -1) {
            noteNetFail("deezer manifest")
            return null
        }
        if (reply.status !in 200..299) return null
        return try {
            val data = JSONObject(String(reply.body, Charsets.UTF_8))
            val url0 = data.optString("streamUrl")
            val key0 = data.optString("decryptionKey")
            if (url0.isBlank() || key0.isBlank()) return null
            if (looksLikePreviewUrl(url0)) return null
            val keyBytes = key0.toByteArray(Charsets.ISO_8859_1)
            val seconds = probeFlacSeconds(url0, blowfishKey = keyBytes) ?: run {
                Log.i(TAG, "[zenmirror] deezer manifest $trackId: not a verifiable full FLAC — rejected")
                return null
            }
            ManifestDesc(url = url0, seconds = seconds, bitDepth = 16, sampleRate = 44100, key = keyBytes)
        } catch (e: Exception) {
            Log.i(TAG, "[zenmirror] deezer manifest error: ${e.message}")
            noteNetFail("deezer manifest")
            null
        }
    }

    // ------------------------------------------------- full-stream guard

    private val previewUrlPattern = Regex(
        "preview|cdn[-_]?preview|lowkey|\\.mp4($|\\?)|\\.m4a($|\\?)|\\.aac($|\\?)",
        RegexOption.IGNORE_CASE
    )

    private fun looksLikePreviewUrl(url: String): Boolean = previewUrlPattern.containsMatchIn(url)

    /** Port of MirrorSource.isFullTrack — same thresholds. */
    internal fun isFullTrack(seconds: Int?, expectedMs: Int?): Boolean {
        if (seconds == null) return false
        val expected = (expectedMs ?: 0) / 1000
        if (expected >= 100 && seconds * 1000 < (expectedMs ?: 0) * 0.6) return false
        if (seconds < 45 && expected >= 100) return false
        if (seconds < 45 && expectedMs == null) return false
        return true
    }

    /**
     * Head probe: fetch the first CDN bytes (Range) — decrypting them when
     * [blowfishKey] is set (Deezer, fixed IV, every third 2048-byte block)
     * — and read the REAL duration from the FLAC STREAMINFO header.
     */
    private fun probeFlacSeconds(url: String, blowfishKey: ByteArray?): Int? {
        val wantEnd = if (blowfishKey == null) 65535 else 6143
        val reply = httpGet(
            url,
            range = "bytes=0-$wantEnd",
            connectMs = streamConnectMs,
            readMs = probeMs,
            maxBytes = wantEnd + 1
        )
        if (reply.status !in 200..299) return null
        var bytes = reply.body
        if (blowfishKey != null) bytes = decryptHead(bytes, blowfishKey)
        return flacDurationSeconds(bytes)
    }

    /** Port of MirrorSource.decryptHead — same 2048-byte grid, same IV. */
    internal fun decryptHead(raw: ByteArray, key: ByteArray): ByteArray {
        val out = raw.copyOf()
        val blockSize = 2048
        var off = 0
        while (off + blockSize <= out.size) {
            if ((off / blockSize) % 3 == 0) {
                val dec = BlowfishCbcDecryptor(key, byteArrayOf(0, 1, 2, 3, 4, 5, 6, 7))
                var p = off
                while (p + 8 <= off + blockSize) {
                    val plain = dec.decryptBlock(out, p)
                    System.arraycopy(plain, 0, out, p, 8)
                    p += 8
                }
            }
            off += blockSize
        }
        return out
    }

    /** FLAC STREAMINFO duration (seconds), or null when not verifiable.
     *
     *  SP71 FIX vs the original Dart: total samples are the low nibble of
     *  b[21] plus b[22..25] — the 36-bit field starts AFTER the
     *  20+3+5 = 28 rate/channel/bps bits. The old b[20..24] indexing ate
     *  the bits-per-sample bits and made 30-second previews parse as
     *  "hours long", slipping them through the full-stream gate. */
    internal fun flacDurationSeconds(b: ByteArray): Int? {
        if (b.size < 34) return null
        if (b[0] != 0x66.toByte() || b[1] != 0x4C.toByte() ||
            b[2] != 0x61.toByte() || b[3] != 0x43.toByte()) return null // 'fLaC'
        if ((b[4].toInt() and 0x7F) != 0) return null // first block: STREAMINFO
        val sr = ((b[18].toInt() and 0xFF) shl 12) or
            ((b[19].toInt() and 0xFF) shl 4) or
            ((b[20].toInt() and 0xFF) shr 4)
        if (sr <= 0) return null
        val totalSamples = ((b[21].toLong() and 0x0F) shl 32) or
            ((b[22].toLong() and 0xFF) shl 24) or
            ((b[23].toLong() and 0xFF) shl 16) or
            ((b[24].toLong() and 0xFF) shl 8) or
            (b[25].toLong() and 0xFF)
        if (totalSamples <= 0) return null
        return Math.round(totalSamples.toDouble() / sr).toInt()
    }

    // ------------------------------------------------------------ scoring

    private val tokenSplit = Regex(
        "[^a-z0-9\\u0900-\\u097F\\u4e00-\\u9fff\\u3040-\\u30ff\\uAC00-\\uD7AF]+"
    )

    private fun tokens(s: String): Set<String> =
        s.lowercase(Locale.ROOT)
            .replace(tokenSplit, " ")
            .split(' ')
            .filter { it.isNotEmpty() && it.length > 1 }
            .toSet()

    private fun dice(a: Set<String>, b: Set<String>): Double {
        if (a.isEmpty() || b.isEmpty()) return 0.0
        var inter = 0
        for (t in a) if (b.contains(t)) inter++
        return 2.0 * inter / (a.size + b.size)
    }

    /** Port of MirrorSource._score — same weights, same duration penalties. */
    private fun score(
        title: String,
        artist: String,
        candTitle: String,
        candArtist: String,
        candMs: Int?,
        expectedMs: Int?
    ): Double {
        var s = 0.65 * dice(tokens(title), tokens(candTitle)) +
            0.35 * dice(tokens(artist), tokens(candArtist))
        if (expectedMs != null && candMs != null && candMs > 0) {
            val delta = Math.abs(expectedMs - candMs) / 1000.0
            if (delta > 30) s *= 0.5 else if (delta > 10) s *= 0.8
        }
        return s
    }

    private fun bestHit(
        hits: List<SearchHit>?,
        title: String,
        artist: String,
        expectedMs: Int?,
        threshold: Double
    ): SearchHit? {
        if (hits == null) return null
        var best: SearchHit? = null
        var bestScore = 0.0
        for (h in hits) {
            if (h.trackId.isBlank()) continue
            val s = score(title, artist, h.title, h.artist, h.durationMs, expectedMs)
            if (s > bestScore) {
                bestScore = s
                best = h
            }
        }
        // Mirrors relay best-effort catalog matches — a weak text match is
        // worse than falling through to the next host / the regular chain.
        return if (best != null && bestScore >= threshold) best else null
    }

    // -------------------------------------------------------------- http

    private fun baseHeaders(): Map<String, String> = buildMap {
        put("X-API-Key", apiKey)
        put("Accept", "application/json")
        put("User-Agent", "ZenMusic/1.0 (lossless mirror)")
    }

    private fun httpGet(
        urlStr: String,
        headers: Map<String, String> = emptyMap(),
        range: String? = null,
        connectMs: Int,
        readMs: Int,
        maxBytes: Int
    ): HttpReply {
        var conn: HttpURLConnection? = null
        return try {
            conn = (URL(urlStr).openConnection() as HttpURLConnection).apply {
                connectTimeout = connectMs
                readTimeout = readMs
                instanceFollowRedirects = true
                for ((k, v) in headers) setRequestProperty(k, v)
                if (range != null) setRequestProperty("Range", range)
            }
            val status = conn.responseCode
            if (status in 200..299) {
                val input = conn.inputStream
                val buf = ByteArrayOutputStream()
                val chunk = ByteArray(8192)
                var total = 0
                while (total < maxBytes) {
                    val n = input.read(chunk, 0, minOf(chunk.size, maxBytes - total))
                    if (n < 0) break
                    buf.write(chunk, 0, n)
                    total += n
                }
                runCatching { input.close() }
                HttpReply(status, buf.toByteArray(), null)
            } else {
                val err = runCatching { conn.errorStream?.readBytes() }.getOrNull() ?: ByteArray(0)
                HttpReply(status, err ?: ByteArray(0), null)
            }
        } catch (e: Exception) {
            HttpReply(-1, ByteArray(0), e.message ?: e.javaClass.simpleName)
        } finally {
            conn?.disconnect()
        }
    }

    private fun enc(value: String): String =
        URLEncoder.encode(value, "UTF-8")

    // ---------------------------------------------------------- bookkeeping

    private fun noteNetFail(stage: String) {
        synchronized(netLock) {
            netFailStreak++
            if (netFailStreak >= 2 && openUntil == 0L) {
                openUntil = nowMs() + 2 * 60 * 1000L
                Log.i(TAG, "[zenmirror] pool unreachable — engine resting for 2 min ($stage)")
            }
        }
    }

    private fun noteNetOk() {
        synchronized(netLock) {
            netFailStreak = 0
            openUntil = 0L
        }
    }

    private fun evictLocked(map: HashMap<*, *>) {
        while (map.size > maxCacheEntries) {
            val oldest = map.keys.firstOrNull() ?: break
            map.remove(oldest)
        }
    }

    private fun hostCoolingDown(host: String): Boolean =
        synchronized(rateLimitUntil) {
            (rateLimitUntil[host] ?: 0L) > nowMs()
        }

    private fun nowMs(): Long = System.currentTimeMillis()

    private fun tierOf(bitDepth: Int, sampleRate: Int): String =
        if (bitDepth >= 24 || sampleRate > 48000) "hires" else "cd"

    /** Build the channel reply for a verified manifest. */
    private fun descriptor(
        kind: String,
        best: SearchHit,
        manifest: ManifestDesc
    ): Map<String, Any?> {
        val out = HashMap<String, Any?>()
        out["status"] = "ok"
        // Arbiter contract: "dz" = Blowfish-decrypting passthrough (Deezer),
        // "tide" = plain byte passthrough (qobuz/tidal CDN URLs and the
        // endpoint's /api/stream relay), i.e. everything else.
        out["kind"] = when {
            manifest.key != null -> "dz"
            kind == "qobuz" || kind == "tidal" -> "tide"
            else -> kind
        }
        out["url"] = manifest.url
        out["seconds"] = manifest.seconds
        out["trackId"] = best.trackId
        out["tier"] = tierOf(
            manifest.bitDepth.takeIf { it > 0 } ?: best.bitDepth ?: 16,
            manifest.sampleRate.takeIf { it > 0 } ?: best.sampleRate ?: 44100
        )
        if (manifest.key != null) {
            out["key64"] = android.util.Base64.encodeToString(manifest.key, android.util.Base64.NO_WRAP)
        }
        Log.i(TAG, "[zenmirror] ok via $kind ${best.trackId} " +
            "(${manifest.seconds}s, tier=${out["tier"]})")
        return out
    }
}
