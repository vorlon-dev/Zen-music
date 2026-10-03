package com.zen.music.zenmusic.innertubex

import android.content.Context
import android.webkit.CookieManager
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.GlobalScope
import kotlinx.coroutines.TimeoutCancellationException
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout
import timber.log.Timber

class PoTokenGenerator(private val appContext: Context) {
    private val TAG = "PoTokenGenerator"

    private val webViewSupported by lazy { runCatching { CookieManager.getInstance() }.isSuccess }
    private var webViewBadImpl = false // whether the system has a bad WebView implementation

    private val webPoTokenGenLock = Mutex()
    private var webPoTokenSessionId: String? = null
    private var webPoTokenStreamingPot: String? = null
    private var webPoTokenGenerator: PoTokenWebView? = null

    fun initialize() {
        if (!webViewSupported || webViewBadImpl) return
        kotlinx.coroutines.GlobalScope.launch(Dispatchers.Main) {
            try {
                webPoTokenGenLock.withLock {
                    if (webPoTokenGenerator == null) {
                        Timber.tag(TAG).d("Pre-initializing PoTokenWebView in background...")
                        webPoTokenSessionId = "init-" + System.currentTimeMillis()
                        webPoTokenGenerator =
                            PoTokenWebView.getNewPoTokenGenerator(appContext)
                        webPoTokenStreamingPot = webPoTokenGenerator!!.generatePoToken(webPoTokenSessionId!!)
                    }
                }
            } catch (e: Exception) {
                Timber.tag(TAG).e(e, "Failed to pre-initialize PoTokenWebView")
            }
        }
    }

    fun getWebClientPoToken(videoId: String, sessionId: String): PoTokenResult? {
        Timber.tag(TAG).d("getWebClientPoToken called: videoId=$videoId, sessionId=$sessionId")
        if (!webViewSupported || webViewBadImpl) {
            Timber.tag(TAG)
                .d("WebView not available: supported=$webViewSupported, badImpl=$webViewBadImpl")
            return null
        }

        return try {
            runBlocking {
                withTimeout(POTOKEN_TIMEOUT_MS) {
                    getWebClientPoToken(videoId, sessionId, forceRecreate = false)
                }
            }
        } catch (e: TimeoutCancellationException) {
            // The WebView's sandboxed process can be culled by the OS, which
            // leaves the PoToken call hung indefinitely. Cap it so extraction
            // falls through to non-PoToken fallback clients instead of
            // blocking the playback path.
            Timber.tag(TAG).w("poToken generation timed out after ${POTOKEN_TIMEOUT_MS}ms; proceeding without PoToken")
            runBlocking {
                webPoTokenGenLock.withLock {
                    try {
                        withContext(Dispatchers.Main) { webPoTokenGenerator?.close() }
                    } catch (closeEx: Exception) {
                        Timber.tag(TAG).e(closeEx, "Exception closing PoTokenWebView during timeout cleanup")
                    }
                    webPoTokenGenerator = null
                    webPoTokenStreamingPot = null
                    webPoTokenSessionId = null
                }
            }
            null
        } catch (e: Exception) {
            Timber.tag(TAG).e(e, "poToken generation exception: ${e.javaClass.simpleName}: ${e.message}")
            when (e) {
                is BadWebViewException -> {
                    Timber.tag(TAG).e(e, "Could not obtain poToken because WebView is broken")
                    webViewBadImpl = true
                    null
                }
                else -> throw e
            }
        }
    }

    private companion object {
        // Healthy cold-start is ~2-5s; 8s leaves slack for a slow device
        // before the fallback chain takes over when the WebView hangs.
        const val POTOKEN_TIMEOUT_MS = 8_000L
    }

    private suspend fun getWebClientPoToken(
        videoId: String,
        sessionId: String,
        forceRecreate: Boolean
    ): PoTokenResult {
        Timber.tag(TAG).d("Web poToken requested: videoId=$videoId, sessionId=$sessionId")

        val (poTokenGenerator, streamingPot, hasBeenRecreated) =
            webPoTokenGenLock.withLock {
                val shouldRecreate =
                    forceRecreate ||
                            webPoTokenGenerator == null ||
                            webPoTokenGenerator!!.isExpired ||
                            webPoTokenSessionId != sessionId

                if (shouldRecreate) {
                    Timber.tag(TAG).d("Creating new PoTokenWebView (forceRecreate=$forceRecreate)")
                    webPoTokenSessionId = sessionId

                    withContext(Dispatchers.Main) { webPoTokenGenerator?.close() }

                    webPoTokenGenerator = PoTokenWebView.getNewPoTokenGenerator(appContext)

                    // The streaming poToken must be generated exactly once before
                    // any other (player) tokens.
                    webPoTokenStreamingPot = webPoTokenGenerator!!.generatePoToken(webPoTokenSessionId!!)
                    Timber.tag(TAG)
                        .d("Streaming poToken generated for sessionId=${webPoTokenSessionId?.take(20)}...")
                }

                Triple(webPoTokenGenerator!!, webPoTokenStreamingPot!!, shouldRecreate)
            }

        val playerPot =
            try {
                poTokenGenerator.generatePoToken(videoId)
            } catch (throwable: Throwable) {
                if (hasBeenRecreated) {
                    throw throwable
                } else {
                    // Retry once, recreating the generator from scratch — happens
                    // e.g. when the app goes to background and WebView content is
                    // lost.
                    Timber.tag(TAG).e(throwable, "Failed to obtain poToken, retrying")
                    return getWebClientPoToken(videoId = videoId, sessionId = sessionId, forceRecreate = true)
                }
            }

        Timber.tag(TAG)
            .d("poToken generated successfully: session=${streamingPot.take(20)}..., video=${playerPot.take(20)}...")

        // Content binding, per yt-dlp's get_webpo_content_binding and
        // NewPipe's PoTokenProviderImpl — WEB_REMIX is special-cased into
        // the session branch on BOTH sides (see Echo's measurement note):
        // playerRequestPoToken = session-bound, streamingDataPoToken =
        // session-bound. Swapping fields would fix the URL and break the
        // /player request.
        return PoTokenResult(
            playerRequestPoToken = streamingPot,
            streamingDataPoToken = streamingPot,
        )
    }
}