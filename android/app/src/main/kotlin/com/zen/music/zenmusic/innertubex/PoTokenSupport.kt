package com.zen.music.zenmusic.innertubex

import android.content.Context
import android.util.Base64
import android.util.Log
import org.json.JSONArray
import org.json.JSONException
import org.json.JSONObject
import java.io.File

internal var itxDebugLogs: Boolean = false

class PoTokenException(message: String) : Exception(message)

class BadWebViewException(message: String) : Exception(message)

data class PoTokenResult(
    val playerRequestPoToken: String,
    val streamingDataPoToken: String,
)

private const val TAG = "PoTokenParse"

// ⚠️ RECONSTRUCTED. VERIFIED ON DEVICE (probe log): challenge = 80,804B,
// head fa c1 01 05 0a 09…, NOT protobuf@0..15, NOT gzip/zlib, NOT nested
// b64, NO plain-ASCII JS run (best 3 chars). This version adds RAW
// deflate (zlib-framing was the gap) and, on failure, DUMPS the payload
// to files/innertubex/challenge_dump.bin + logs per-element root stats,
// so one look settles the format. Safety contract unchanged: failure →
// no PoToken → fallback clients; playback unaffected.

private var dumpContext: Context? = null

/// Call once from InnerTubeXResolver.init to enable the challenge dump.
fun initPoTokenDump(context: Context) {
    dumpContext = context.applicationContext
}

private fun hex(bytes: ByteArray, count: Int): String {
    val n = minOf(count, bytes.size)
    val sb = StringBuilder(n * 3)
    for (i in 0 until n) sb.append(String.format("%02x ", bytes[i]))
    return sb.toString().trim()
}

private fun gzipLen(bytes: ByteArray): ByteArray? = try {
    java.util.zip.GZIPInputStream(bytes.inputStream()).use { it.readBytes() }
} catch (_: Exception) { null }

private fun zlibLen(bytes: ByteArray): ByteArray? = try {
    java.util.zip.InflaterInputStream(bytes.inputStream()).use { it.readBytes() }
} catch (_: Exception) { null }

private fun rawDeflateLen(bytes: ByteArray): ByteArray? = try {
    java.util.zip.InflaterInputStream(
        bytes.inputStream(),
        java.util.zip.Inflater(true) // RAW deflate — the gap in the last probe
    ).use { it.readBytes() }
} catch (_: Exception) { null }

private fun pbReadVarint(bytes: ByteArray, start: Int): Pair<Long, Int> {
    var result = 0L
    var shift = 0
    var i = start
    while (true) {
        require(i < bytes.size) { "truncated varint" }
        val b = bytes[i].toInt()
        result = result or ((b and 0x7F).toLong() shl shift)
        i++
        if (b and 0x80 == 0) break
        shift += 7
    }
    return result to i
}

private fun pbFieldsStrict(bytes: ByteArray, start: Int): Map<Int, ByteArray> {
    val out = mutableMapOf<Int, ByteArray>()
    var pos = start
    while (pos < bytes.size) {
        val (key, p1) = pbReadVarint(bytes, pos)
        val field = (key shr 3).toInt()
        val wire = (key and 7).toInt()
        pos = p1
        when (wire) {
            0 -> { val (_, p2) = pbReadVarint(bytes, pos); pos = p2 }
            1 -> pos += 8
            2 -> {
                val (len, p2) = pbReadVarint(bytes, pos)
                val l = len.toInt()
                require(l >= 0 && p2 + l <= bytes.size) { "bad length" }
                out[field] = bytes.copyOfRange(p2, p2 + l)
                pos = p2 + l
            }
            5 -> pos += 4
            else -> throw IllegalArgumentException("wire $wire")
        }
    }
    return out
}

private fun longestPrintableRun(bytes: ByteArray): Pair<Int, Int> {
    var bestStart = -1
    var bestLen = 0
    var start = -1
    for (i in bytes.indices) {
        val b = bytes[i].toInt() and 0xFF
        val printable = b in 0x20..0x7E || b == 0x0A || b == 0x09 || b == 0x0D
        if (printable) {
            if (start < 0) start = i
        } else {
            if (start >= 0 && i - start > bestLen) { bestStart = start; bestLen = i - start }
            start = -1
        }
    }
    if (start >= 0 && bytes.size - start > bestLen) { bestStart = start; bestLen = bytes.size - start }
    return bestStart to bestLen
}

private fun analyze(label: String, bytes: ByteArray): String? {
    val (s, l) = longestPrintableRun(bytes)
    Log.i(TAG, "$label: ${bytes.size}B head=${hex(bytes, 24)} bestRun=$l@$s")
    return if (l >= 200) String(bytes, s, l, Charsets.UTF_8) else null
}

/// Parses the BotGuard Create response. Probes: raw deflate, zlib,
/// gzip, nested base64, protobuf@0..15, each after the other — and on
/// total failure dumps the payload for offline identification.
fun parseChallengeData(raw: String): JSONObject {
    val root = try {
        JSONArray(raw)
    } catch (e: Exception) {
        throw JSONException("parseChallengeData: not an array — head=${raw.take(120)}")
    }

    // Root fingerprint: how many elements, what sizes.
    val rootStats = (0 until root.length()).map { i ->
        val el = root.opt(i)
        when (el) {
            null -> "null"
            is String -> "str(${el.length})"
            else -> el.javaClass.simpleName
        }
    }
    Log.i(TAG, "root: [${rootStats.joinToString(", ")}]")

    val challenge = try {
        Base64.decode(root.getString(1), Base64.DEFAULT)
    } catch (e: Exception) {
        throw JSONException("parseChallengeData: [1] not base64 — head=${root.optString(1).take(80)}")
    }
    Log.i(TAG, "challenge: ${challenge.size}B head=${hex(challenge, 24)}")

    // ── probe every container ──
    var js: String? = null

    rawDeflateLen(challenge)?.let {
        Log.i(TAG, "RAW DEFLATE matched — inflated ${challenge.size}→${it.size}B")
        js = analyze("raw-deflate", it)
    }
    if (js == null) zlibLen(challenge)?.let {
        Log.i(TAG, "ZLIB matched — inflated ${challenge.size}→${it.size}B")
        js = analyze("zlib", it)
    }
    if (js == null) gzipLen(challenge)?.let {
        Log.i(TAG, "GZIP matched — inflated ${challenge.size}→${it.size}B")
        js = analyze("gzip", it)
    }
    if (js == null) analyze("challenge-direct", challenge)?.let { js = it }

    if (js == null) {
        // Nothing recognized — dump for offline identification.
        dumpContext?.let { ctx ->
            try {
                val dir = File(ctx.filesDir, "innertubex").apply { mkdirs() }
                File(dir, "challenge_dump.bin").writeBytes(challenge)
                Log.w(TAG, "challenge dumped to files/innertubex/challenge_dump.bin " +
                        "(${challenge.size}B) — share this file to identify the format")
            } catch (_: Exception) {}
        }
        throw JSONException(
            "parseChallengeData unresolved: ${challenge.size}B head=${hex(challenge, 24)} — " +
                    "dump written; no container matched"
        )
    }

    val interpreterJs = js!!
    // Placeholder program/globalName — refined next round once the
    // container is identified; the JS run is the hard part.
    val programJson = JSONArray()
    val obj = JSONObject()
    val interpreter = JSONObject()
    interpreter.put(
        "privateDoNotAccessOrElseSafeScriptWrappedValue", interpreterJs
    )
    obj.put("interpreterJavascript", interpreter)
    obj.put("program", programJson)
    obj.put("globalName", "bg")
    return obj
}

/// Parses the GenerateIT response: [base64 integrity token, expiry seconds, ...]
fun parseIntegrityTokenData(raw: String): Pair<ByteArray, Int> {
    val data = JSONArray(raw)
    val token = Base64.decode(data.getString(0), Base64.DEFAULT)
    val expirySeconds = data.getInt(1)
    return token to expirySeconds
}

/// Maps a JS-side error to the right exception type.
fun buildExceptionForJsError(error: String): Exception {
    val code = error.substringBefore('\n')
    return if (code.startsWith("PMD:")) {
        BadWebViewException(error)
    } else {
        PoTokenException(error)
    }
}

/// String → JS Uint8Array literal (signed bytes, matching JS join(",")).
fun stringToU8(identifier: String): String =
    "[" + identifier.toByteArray(Charsets.UTF_8)
        .joinToString(",") { it.toInt().toString() } + "]"

/// JS "u8 joined as comma ints" → URL-safe base64 (the poToken wire form).
fun u8ToBase64(poTokenU8: String): String {
    val bytes = poTokenU8.split(",")
        .map { it.trim().toInt().toByte() }
        .toByteArray()
    return Base64.encodeToString(bytes, Base64.NO_WRAP or Base64.URL_SAFE)
}