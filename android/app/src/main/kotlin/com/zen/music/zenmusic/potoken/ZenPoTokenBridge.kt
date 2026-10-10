package com.zen.music.zenmusic.potoken

import android.annotation.SuppressLint
import android.app.Activity
import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Base64
import android.util.Log
import android.view.ViewGroup
import android.webkit.JavascriptInterface
import android.webkit.WebChromeClient
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.FrameLayout
import java.time.Instant
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.RequestBody.Companion.toRequestBody

/**
 * WebView BotGuard po-token minter — LibreTube's architecture,
 * PORTED FROM THEIR PROVEN IMPLEMENTATION (PoTokenWebView +
 * JavaScriptUtil + PoTokenGenerator, pasted verbatim this session).
 *
 * Flow (theirs, exactly): page loads with youtube.com base →
 * self-bootstrap in the page calls ZenPo.downloadAndRunBotguard()
 * (onPageFinished backup) → Kotlin POSTs api/jnn/v1/Create with
 * [REQUEST_KEY] → parseChallengeData descrambles (base64 → +97/byte)
 * → runBotGuard in JS → Kotlin POSTs GenerateIT → integrity token
 * embedded → session READY → per-video obtainPoToken with the
 * videoId as the identifier → u8ToBase64 result.
 *
 * ATTACHMENT (this device's requirement): the WebView is attached to
 * the Activity's decor view at 1×1 px. An application-context,
 * never-attached WebView did not evaluate pages on this build (no
 * onPageFinished, no JS execution — ten rounds of logs). Attach +
 * one real window makes the page live.
 *
 * NOTE: no labeled returns into Handler.post lambdas — Java-SAM
 * lambda labels are unreliable on this toolchain (two compile
 * failures). Early-exits are structured as if/else instead.
 *
 * Failure anywhere returns null / stays tokenless: no path here can
 * break playback.
 */
object ZenPoTokenBridge {

    private const val TAG = "ZenPoToken"

    /// LibreTube's REQUEST_KEY, verbatim from PoTokenWebView.kt.
    private const val REQUEST_KEY = "O43z0dpjhgX20SCx4KAo"

    /// LibreTube's GOOGLE_API_KEY, verbatim from ExternalApi.kt — the
    /// NewPipe/YouTube.js-lineage project key (x-goog-api-key header).
    private const val GOOGLE_API_KEY = "AIzaSyDyT5W0Jh49F30Pqqtyfdf7pDLFKLJoAnw"

    /// Non-blocking readiness probe for extraction paths.
    fun isSessionReady(): Boolean = sessionReady && !expiredNow()

    private fun expiredNow(): Boolean =
        expirationInstant?.let { Instant.now().isAfter(it) } ?: false


    @Volatile
    var debugLogs: Boolean = false

    private val main = Handler(Looper.getMainLooper())
    private val started = AtomicBoolean(false)
    private var webView: WebView? = null

    @Volatile
    private var sessionReady = false

    @Volatile
    private var expirationInstant: Instant? = null

    @Volatile
    private var bootstrapStarted = false

    private var appContext: Context? = null
    private var activity: Activity? = null

    // Per-mint latches: identifier -> continuation results.
    private val mintLatches = ConcurrentHashMap<String, CountDownLatch>()
    private val mintResults = ConcurrentHashMap<String, String?>()

    // Token cache: videoId -> [token, mintedAtMs].
    private val tokenCache = ConcurrentHashMap<String, Pair<String, Long>>()
    private val tokenTtlMs = 30 * 60 * 1000L

    // Browser UA for the WebView + the two botguard requests (the
    // module's proven USER_AGENT_WEB string).
    private const val BROWSER_UA =
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:140.0) Gecko/20100101 Firefox/140.0"

    private val botguardClient = okhttp3.OkHttpClient()

    /// Kept for resolver compatibility; the proven flow does not bind
    /// tokens to visitorData (identifier = videoId alone).
    fun publishVisitorData(vd: String?) {
        // No-op by design (see the class doc).
    }
    /// Called from ZenInnertubeResolver.init — idempotent. Builds the
    /// WebView; it goes live when [attachActivity] runs.
    fun init(context: Context) {
        if (!started.compareAndSet(false, true)) return
        val app = context.applicationContext
        appContext = app
        main.post { startWebView(app) }
    }

    /// Called from MainActivity.configureFlutterEngine — attaches the
    /// WebView to the Activity's decor view at 1×1 px so its pages
    /// actually evaluate. Idempotent.
    fun attachActivity(a: Activity) {
        activity = a
        main.post { attachAndLoad() }
    }

    private fun readHtml(): String? = try {
        appContext!!.assets.open("po_token.html")
            .bufferedReader().use { it.readText() }
    } catch (t: Throwable) {
        Log.w(TAG, "po_token.html missing: ${t.message}")
        null
    }

    @SuppressLint("SetJavaScriptEnabled")
    private fun startWebView(app: Context) {
        val wv = WebView(app)
        wv.layout(0, 0, 1080, 1920)
        wv.settings.apply {
            javaScriptEnabled = true
            safeBrowsingEnabled = false
            userAgentString = BROWSER_UA
            domStorageEnabled = true
        }
        // The @JavascriptInterface methods live on THIS singleton.
        wv.addJavascriptInterface(this, "ZenPo")
        // JS console.log → logcat (the visibility channel).
        wv.webChromeClient = object : WebChromeClient() {
            override fun onConsoleMessage(message: android.webkit.ConsoleMessage?): Boolean {
                Log.d(TAG, "JS: ${message?.message()}")
                return true
            }
        }
        wv.webViewClient = object : WebViewClient() {
            override fun onPageFinished(view: WebView?, url: String?) {
                // Backup path — the HTML self-bootstrap is primary.
                if (debugLogs) Log.d(TAG, "page loaded (backup)")
                main.post { downloadAndRunBotguard() }
            }
        }
        webView = wv
        attachAndLoad()
    }

    /// Attaches the WebView to the live Activity's decor view (1×1,
    /// invisible) and loads the page. Re-runs safely; a load only
    /// happens for a page that is not already bootstrapped.
    private fun attachAndLoad() {
        val a = activity
        val wv = webView
        if (a == null || wv == null) return
        if (wv.parent == null) {
            try {
                (a.window.decorView as ViewGroup).addView(
                    wv,
                    FrameLayout.LayoutParams(1, 1)
                )
            } catch (t: Throwable) {
                Log.w(TAG, "attach failed: ${t.message}")
            }
        }
        if (bootstrapStarted) return
        val html = readHtml()
        if (html == null) return
        Log.d(TAG, "loading page (${html.length} chars)")
        wv.loadDataWithBaseURL(
            "https://www.youtube.com",
            html,
            "text/html",
            "utf-8",
            null,
        )
    }

    /// Recreates the session (their forceRecreate): reloads the page;
    /// the self-bootstrap/onPageFinished fires again.
    private fun recreateSession() {
        val wv = webView ?: return
        main.post {
            try {
                sessionReady = false
                bootstrapStarted = false
                val html = readHtml()
                if (html == null) {
                    Log.w(TAG, "recreate: no html")
                } else {
                    wv.loadDataWithBaseURL(
                        "https://www.youtube.com",
                        html,
                        "text/html",
                        "utf-8",
                        null,
                    )
                }
            } catch (t: Throwable) {
                Log.w(TAG, "recreate failed: ${t.message}")
            }
        }
    }

    // ── Bootstrap step 1: Create → parseChallengeData → runBotGuard ──

    /// @JavascriptInterface — the page's self-bootstrap AND the
    /// onPageFinished backup both land here; idempotent.
    @JavascriptInterface
    fun downloadAndRunBotguard() {
        if (bootstrapStarted) return
        bootstrapStarted = true
        if (debugLogs) Log.d(TAG, "bootstrap started")
        Thread {
            try {
                val responseBody = botguardRequest(
                    "https://www.youtube.com/api/jnn/v1/Create",
                    "[\"$REQUEST_KEY\"]"
                )
                if (responseBody.trimStart().startsWith("{")) {
                    throw IllegalStateException(
                        "Create refused: ${responseBody.take(300)}"
                    )
                }
                val parsed = parseChallengeData(responseBody)
                if (debugLogs) Log.d(TAG, "challenge parsed (${parsed.length} chars)")
                main.post {
                    webView?.evaluateJavascript(
                        """try {
                             data = $parsed
                             runBotGuard(data).then(function (result) {
                                 this.webPoSignalOutput = result.webPoSignalOutput
                                 ZenPo.onRunBotguardResult(result.botguardResponse)
                             }, function (error) {
                                 ZenPo.onJsInitializationError(error + "\n" + error.stack)
                             })
                         } catch (error) {
                             ZenPo.onJsInitializationError(error + "\n" + error.stack)
                         }""",
                        null
                    )
                }
            } catch (t: Throwable) {
                Log.w(TAG, "bootstrap failed: ${t.message}")
            }
        }.start()
    }

    // ── Bootstrap step 2: GenerateIT → integrity token embedded ──

    /// @JavascriptInterface — the VM's snapshot output.
    @JavascriptInterface
    fun onRunBotguardResult(botguardResponse: String) {
        Thread {
            try {
                val responseBody = botguardRequest(
                    "https://www.youtube.com/api/jnn/v1/GenerateIT",
                    "[\"$REQUEST_KEY\",${org.json.JSONObject.quote(botguardResponse)}]"
                )
                val (u8Literal, expirationSec) = parseIntegrityTokenData(responseBody)
                expirationInstant = Instant.now()
                    .plusSeconds(expirationSec - 600) // their 10-min margin

                main.post {
                    webView?.evaluateJavascript(
                        "this.integrityToken = $u8Literal"
                    ) {
                        sessionReady = true
                        Log.i(TAG, "session ready, expiration=${expirationSec}s")
                    }
                }
            } catch (t: Throwable) {
                Log.w(TAG, "GenerateIT failed: ${t.message}")
            }
        }.start()
    }

    /// @JavascriptInterface — JS-side initialization error.
    @JavascriptInterface
    fun onJsInitializationError(error: String) {
        Log.w(TAG, "init error from JS: $error")
    }

    // ── Minting ──

    /// Mints (or returns cached) po-token for [videoId]. Null-safe on
    /// ANY failure. Blocking — background thread only. [visitorData]
    /// is unused (their contract: identifier = videoId alone).
    fun playerTokenBlocking(videoId: String, visitorData: String?): String? {
        if (!started.get()) return null

        val cached = tokenCache[videoId]
        if (cached != null && System.currentTimeMillis() - cached.second < tokenTtlMs) {
            return cached.first
        }

        val expired = expirationInstant?.let { Instant.now().isAfter(it) } ?: false
        if (!sessionReady || expired) {
            if (expired) recreateSession()
            if (debugLogs) {
                Log.d(TAG, "not ready (ready=$sessionReady expired=$expired) — tokenless")
            }
            return null
        }

        val identifierB64 = stringToU8(videoId)

        val latch = CountDownLatch(1)
        mintLatches[videoId] = latch
        mintResults.remove(videoId)

        main.post {
            webView?.evaluateJavascript(
                """try {
                        identifier = "$videoId"
                        u8Identifier = $identifierB64
                        poTokenU8 = obtainPoToken(webPoSignalOutput, integrityToken, u8Identifier)
                        poTokenU8String = ""
                        for (i = 0; i < poTokenU8.length; i++) {
                            if (i != 0) poTokenU8String += ","
                            poTokenU8String += poTokenU8[i]
                        }
                        ZenPo.onObtainPoTokenResult(identifier, poTokenU8String)
                    } catch (error) {
                        ZenPo.onObtainPoTokenError(identifier, error + "\n" + error.stack)
                    }""",
                null
            ) ?: latch.countDown()
        }

        val ok = latch.await(10, TimeUnit.SECONDS)
        val result = if (ok) mintResults.remove(videoId) else null
        mintLatches.remove(videoId)
        if (!ok && debugLogs) Log.d(TAG, "mint timeout for $videoId")

        if (result.isNullOrEmpty()) return null

        val token = try {
            u8ToBase64(result)
        } catch (t: Throwable) {
            Log.w(TAG, "token decode failed: ${t.message}")
            return null
        }
        tokenCache[videoId] = Pair(token, System.currentTimeMillis())
        if (debugLogs) Log.d(TAG, "minted token for $videoId")
        return token
    }

    /// @JavascriptInterface — mint result (comma-separated bytes).
    @JavascriptInterface
    fun onObtainPoTokenResult(identifier: String, poTokenU8: String) {
        mintResults[identifier] = poTokenU8
        mintLatches[identifier]?.countDown()
    }

    /// @JavascriptInterface — mint error.
    @JavascriptInterface
    fun onObtainPoTokenError(identifier: String, error: String) {
        Log.w(TAG, "obtainPoToken error for $identifier: $error")
        mintResults[identifier] = null
        mintLatches[identifier]?.countDown()
    }

    // ── JavaScriptUtil ports (their parsing, org.json) ──

    // LibreTube ExternalApi.botguardRequest's EXACT header set —
    // verbatim from their pasted @Headers annotation. The
    // x-goog-api-key (NewPipe/YouTube.js-lineage project, where the
    // anti-abuse API IS enabled) is the identity mechanism: the
    // header route validates where ?key= and keyless both 403'd.
    // Content-Type is json+protobuf, NOT application/json; the
    // x-user-agent marks the grpc-web-javascript caller class.
    private fun botguardRequest(url: String, jsonBody: String): String {
        val resp = botguardClient.newCall(
            okhttp3.Request.Builder()
                .url(url)
                .header("User-Agent", BROWSER_UA)
                .header("Accept", "application/json")
                .header("Content-Type", "application/json+protobuf")
                .header("x-goog-api-key", GOOGLE_API_KEY)
                .header("x-user-agent", "grpc-web-javascript/0.1")
                .post(jsonBody.toRequestBody("application/json+protobuf".toMediaType()))
                .build()
        ).execute()
        val body = resp.body?.string().orEmpty()
        resp.close()
        return body
    }

    /// Their parseChallengeData: Create's response element [1] (when a
    /// string) is a SCRAMBLED challenge (base64 → +97/byte).
    private fun parseChallengeData(raw: String): String {
        val scrambled = org.json.JSONArray(raw)
        val challengeData: org.json.JSONArray =
            if (scrambled.length() > 1 && scrambled.opt(1) is String) {
                org.json.JSONArray(descramble(scrambled.getString(1)))
            } else {
                scrambled.getJSONArray(0)
            }

        val messageId = challengeData.getString(0)
        val interpreterHash = challengeData.getString(3)
        val program = challengeData.getString(4)
        val globalName = challengeData.getString(5)
        val clientExperimentsStateBlob = challengeData.getString(7)

        val interpreterJs = challengeData.optJSONArray(1)?.let { arr ->
            for (i in 0 until arr.length()) {
                val v = arr.opt(i)
                if (v is String) return@let v
            }
            null
        }
        val trustedUrl = challengeData.optJSONArray(2)?.let { arr ->
            for (i in 0 until arr.length()) {
                val v = arr.opt(i)
                if (v is String) return@let v
            }
            null
        }

        val interpreterJavascript = org.json.JSONObject()
            .put(
                "privateDoNotAccessOrElseSafeScriptWrappedValue",
                interpreterJs ?: org.json.JSONObject.NULL
            )
            .put(
                "privateDoNotAccessOrElseTrustedResourceUrlWrappedValue",
                trustedUrl ?: org.json.JSONObject.NULL
            )

        return org.json.JSONObject()
            .put("messageId", messageId)
            .put("interpreterJavascript", interpreterJavascript)
            .put("interpreterHash", interpreterHash)
            .put("program", program)
            .put("globalName", globalName)
            .put("clientExperimentsStateBlob", clientExperimentsStateBlob)
            .toString()
    }

    /// Their parseIntegrityTokenData: [0] = base64 token → JS
    /// Uint8Array literal, [1] = expiration seconds.
    private fun parseIntegrityTokenData(raw: String): Pair<String, Long> {
        val arr = org.json.JSONArray(raw)
        val bytes = base64ToBytes(arr.getString(0))
        val u8 = "new Uint8Array([" +
                bytes.joinToString(separator = ",") { (it.toInt() and 0xFF).toString() } +
                "])"
        return u8 to arr.getLong(1)
    }

    /// Their stringToU8 — identifier bytes → JS Uint8Array literal.
    private fun stringToU8(identifier: String): String =
        "new Uint8Array([" +
                identifier.toByteArray(Charsets.UTF_8)
                    .joinToString(separator = ",") { (it.toInt() and 0xFF).toString() } +
                "])"

    /// Their u8ToBase64: "97,98,99" byte-string → base64 → +→- /→_.
    private fun u8ToBase64(poTokenU8: String): String {
        val bytes = poTokenU8.split(",")
            .map { it.trim().toUByte().toByte() }
            .toByteArray()
        val b64 = Base64.encodeToString(bytes, Base64.NO_WRAP)
        return b64.replace("+", "-").replace("/", "_")
    }

    /// Their descramble: base64 (their char swaps) → +97/byte → text.
    private fun descramble(scrambled: String): String {
        val bytes = base64ToBytes(scrambled)
        return bytes.map { (it + 97).toByte() }
            .toByteArray()
            .decodeToString()
    }

    /// Their base64ToByteString: -→+ _→/ .→= then decode.
    private fun base64ToBytes(b64: String): ByteArray {
        val mod = b64
            .replace('-', '+')
            .replace('_', '/')
            .replace('.', '=')
        return Base64.decode(mod, Base64.DEFAULT)
    }
}