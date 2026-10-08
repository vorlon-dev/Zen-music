package com.zen.music.zenmusic.potoken

import android.annotation.SuppressLint
import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Base64
import android.util.Log
import android.webkit.JavascriptInterface
import android.webkit.WebChromeClient
import android.webkit.WebView
import android.webkit.WebViewClient
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicReference

/**
 * WebView BotGuard po-token minter — LibreTube's architecture:
 * assets/po_token.html runs YouTube's BotGuard VM inside an
 * offscreen WebView; this bridge drives it over evaluateJavascript
 * and collects results through a @JavascriptInterface.
 *
 * Lifecycle: init() starts session setup (challenge fetch → VM run →
 * integrity token) once per process. playerTokenBlocking() mints a
 * per-video token bound to (videoId + visitorData) and is SAFE TO
 * CALL FROM ANY THREAD — it returns null on ANY failure and callers
 * simply proceed without a token (current behavior). No failure here
 * can ever break playback.
 *
 * WARNING-UNVERIFIED-SHAPE (flagged in po_token.html too): the WAA
 * request key and response indexing come from the bgutils/YouTube.js
 * ecosystem, not from pasted code. On mismatch, the JS side reports
 * the raw response head through onSession(false, ...) — that message
 * is the first-run diagnostic.
 */
object ZenPoTokenBridge {

    private const val TAG = "ZenPoToken"

    @Volatile
    var debugLogs: Boolean = false

    private val main = Handler(Looper.getMainLooper())
    private val started = AtomicBoolean(false)
    private var webView: WebView? = null

    private val sessionReady = AtomicBoolean(false)
    private val sessionLatch = CountDownLatch(1)
    private val sessionInfo = AtomicReference<String?>(null)

    private val mintLatches = ConcurrentHashMap<Int, CountDownLatch>()
    private val mintResults = ConcurrentHashMap<Int, String?>()
    private val mintCounter = java.util.concurrent.atomic.AtomicInteger(1)

    // Token cache: (videoId) -> [token, mintedAtMs]. Tokens bind to
    // (videoId + visitorData) and are short-lived; 30 min is generous.
    private val tokenCache = ConcurrentHashMap<String, Pair<String, Long>>()
    private val tokenTtlMs = 30 * 60 * 1000L

    /// Called from ZenInnertubeResolver.init — idempotent, starts the
    /// WebView session on the main thread. Fire-and-forget: playback
    /// never waits on this.
    fun init(context: Context) {
        if (!started.compareAndSet(false, true)) return
        val app = context.applicationContext
        main.post {
            try {
                startWebView(app)
            } catch (t: Throwable) {
                Log.w(TAG, "webview init failed: ${t.message}")
                sessionInfo.set("webview init failed: ${t.message}")
                sessionLatch.countDown()
            }
        }
    }

    /// JS string literal escape (TextUtils.quote is hidden API).
    private fun jsString(s: String): String =
        "\"" + s.replace("\\", "\\\\")
            .replace("\"", "\\\"")
            .replace("\n", "\\n")
            .replace("\r", "\\r") + "\""

    @SuppressLint("SetJavaScriptEnabled")
    private fun startWebView(app: Context) {
        val wv = WebView(app)
        wv.layout(0, 0, 1080, 1920)
        wv.settings.javaScriptEnabled = true
        wv.settings.domStorageEnabled = true
        wv.addJavascriptInterface(BridgeInterface(), "ZenPo")
        wv.webViewClient = object : WebViewClient() {
            override fun onPageFinished(view: WebView?, url: String?) {
                // Visitor data rides along for logging/diagnostics.
                val vd = ZenVisitorDataHolder.visitorData ?: ""
                view?.evaluateJavascript(
                    "initSession(${jsString(vd)});", null
                )
            }
        }
        wv.webChromeClient = WebChromeClient()
        webView = wv
        wv.loadUrl("file:///android_asset/po_token.html")
    }

    /// The resolver publishes its bootstrapped visitorData here so
    /// the bridge can bind tokens to it.
    fun publishVisitorData(vd: String?) {
        ZenVisitorDataHolder.visitorData = vd
    }

    /// Mints (or returns cached) po-token for [videoId]. Null-safe:
    /// returns null when the session is not ready, minting failed,
    /// or timed out. Blocking — call from a background thread only.
    fun playerTokenBlocking(videoId: String, visitorData: String?): String? {
        if (!started.get()) return null
        if (visitorData.isNullOrEmpty()) return null

        val cached = tokenCache[videoId]
        if (cached != null && System.currentTimeMillis() - cached.second < tokenTtlMs) {
            return cached.first
        }

        // Wait for the session (bounded) — one-time cost per process.
        if (!sessionReady.get()) {
            sessionLatch.await(45, TimeUnit.SECONDS)
            if (!sessionReady.get()) {
                if (debugLogs) Log.d(TAG, "session not ready: ${sessionInfo.get()}")
                return null
            }
        }

        // Identifier binding: videoId + visitorData (bgutils parity).
        val identifier = (videoId + visitorData).toByteArray(Charsets.UTF_8)
        val identifierB64 =
            Base64.encodeToString(identifier, Base64.NO_WRAP)

        val id = mintCounter.getAndIncrement()
        val latch = CountDownLatch(1)
        mintLatches[id] = latch
        mintResults.remove(id)

        main.post {
            webView?.evaluateJavascript(
                "mintPoToken($id, '$identifierB64');", null
            ) ?: latch.countDown()
        }

        val ok = latch.await(10, TimeUnit.SECONDS)
        val result = if (ok) mintResults.remove(id) else null
        mintLatches.remove(id)
        if (!ok && debugLogs) Log.d(TAG, "mint timeout for $videoId")

        if (result.isNullOrEmpty()) return null

        // googlevideo expects base64url without padding.
        val urlSafe = Base64.encodeToString(
            Base64.decode(result, Base64.DEFAULT),
            Base64.URL_SAFE or Base64.NO_PADDING or Base64.NO_WRAP
        )
        tokenCache[videoId] = Pair(urlSafe, System.currentTimeMillis())
        if (debugLogs) Log.d(TAG, "minted token for $videoId")
        return urlSafe
    }

    /// JS bridge. Methods run on the WebView's JS thread.
    private class BridgeInterface {
        @JavascriptInterface
        fun onSession(ok: Boolean, info: String?) {
            sessionInfo.set(info)
            if (ok) {
                sessionReady.set(true)
                Log.i(TAG, "session ready: $info")
            } else {
                Log.w(TAG, "session FAILED: $info")
            }
            sessionLatch.countDown()
        }

        @JavascriptInterface
        fun mintResult(requestId: Int, tokenB64: String?) {
            mintResults[requestId] = tokenB64
            mintLatches[requestId]?.countDown()
        }
    }
}

/// Plain holder so the WebView can read the visitorData at page-load
/// time without reaching into the innertube module.
object ZenVisitorDataHolder {
    @Volatile
    var visitorData: String? = null
}