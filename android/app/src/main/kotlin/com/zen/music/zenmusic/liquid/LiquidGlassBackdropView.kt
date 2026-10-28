package com.zen.music.zenmusic.liquid

// SP-54: Liquid Glass — the app-wide backdrop, drawn natively in Kotlin.
//
// A single fullscreen View mounted BEHIND all Flutter content (the Flutter
// side hosts it as platform view "zen_liquid_glass" with kind:"backdrop").
// It paints a slowly drifting aurora of soft colour orbs; all the glass
// panels in the app read their "liquid" feel from this layer.
//
// PERFORMANCE CONTRACT (low-end mobile first):
//   • Gradient-only painting. RadialGradients are inherently soft, so no
//     RenderEffect/blur pass is ever needed — that's why this stays 60fps
//     on phones where a real gaussian pass would crawl.
//   • high tier: animator at native vsync (~60fps).
//   • mid tier : animator gated to ~40fps (frame skipping in the updater).
//   • low tier : NO animator at all — one static frame is drawn, then the
//     view goes silent (zero GPU/CPU until the theme changes).
//   • The animator stops when the view is detached or the window loses
//     visibility, so the theme costs nothing while backgrounded.

import android.animation.ValueAnimator
import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RadialGradient
import android.graphics.Shader
import android.view.View
import android.view.animation.LinearInterpolator
import kotlin.math.cos
import kotlin.math.sin

class LiquidGlassBackdropView(context: Context) : View(context) {

    private val paint = Paint(Paint.ANTI_ALIAS_FLAG)
    private var animator: ValueAnimator? = null
    private var phase = 0f
    private var lastFrameMs = 0L

    /** Set by the theme-change listener; consumed + cleared in onDraw. */
    private var needsRedraw = true

    private val themeListener = { needsRedraw = true; kick() }

    // Aurora palette — violet / teal / rose / indigo / pine orbs.
    private val blobColorsDark = intArrayOf(
        0xFF5B4B8A.toInt(), 0xFF14536B.toInt(), 0xFF7A3B5E.toInt(),
        0xFF2E3A8C.toInt(), 0xFF3F6E5A.toInt()
    )
    private val blobColorsLight = intArrayOf(
        0xFFF2C4CE.toInt(), 0xFFBFD8F2.toInt(), 0xFFCDEBD8.toInt(),
        0xFFD8CCF2.toInt(), 0xFFF2E4C0.toInt()
    )
    private val blobRadius = floatArrayOf(0.62f, 0.55f, 0.50f, 0.58f, 0.45f)
    private val blobSpeed = floatArrayOf(0.11f, 0.16f, 0.08f, 0.13f, 0.19f)
    private val blobPhase = floatArrayOf(0.0f, 1.4f, 2.6f, 4.1f, 5.3f)
    private val blobAlpha = floatArrayOf(0.55f, 0.50f, 0.45f, 0.40f, 0.35f)

    /** Minimum ms between redraws (frame gating). 0 = every vsync. */
    private val frameIntervalMs: Long
        get() = when (ZenLiquidGlassEngine.tier) {
            "high" -> 0L
            "mid" -> 24L
            else -> 0L // low tier: animator never runs anyway
        }

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        ZenLiquidGlassEngine.addListener(themeListener)
        startAnim()
    }

    override fun onDetachedFromWindow() {
        ZenLiquidGlassEngine.removeListener(themeListener)
        stopAnim()
        super.onDetachedFromWindow()
    }

    override fun onWindowVisibilityChanged(visibility: Int) {
        super.onWindowVisibilityChanged(visibility)
        if (visibility == VISIBLE) startAnim() else stopAnim()
    }

    private fun startAnim() {
        needsRedraw = true
        if (ZenLiquidGlassEngine.tier == "low") {
            // Static aurora: draw once, never animate.
            invalidate()
            return
        }
        stopAnim()
        animator = ValueAnimator.ofFloat(0f, (2.0 * Math.PI).toFloat()).apply {
            duration = 30_000
            repeatCount = ValueAnimator.INFINITE
            interpolator = LinearInterpolator()
            addUpdateListener {
                phase = it.animatedValue as Float
                if (frameIntervalMs == 0L) {
                    postInvalidateOnAnimation() // SP-54.2: member call — the View static (View) overload is Java-only
                } else {
                    val now = System.nanoTime() / 1_000_000L
                    if (now - lastFrameMs >= frameIntervalMs) {
                        lastFrameMs = now
                        postInvalidateOnAnimation() // SP-54.2: member call — the View static (View) overload is Java-only
                    }
                }
            }
            start()
        }
    }

    private fun stopAnim() {
        animator?.cancel()
        animator = null
    }

    /** Light kick after a theme change so even a stopped (low-tier) view updates. */
    private fun kick() {
        stopAnim()
        startAnim()
    }

    override fun onDraw(canvas: Canvas) {
        val dark = ZenLiquidGlassEngine.dark
        canvas.drawColor(if (dark) 0xFF07070C.toInt() else 0xFFF4F5FB.toInt())

        val colors = if (dark) blobColorsDark else blobColorsLight
        val w = width.toFloat()
        val h = height.toFloat()
        val span = maxOf(w, h)

        for (i in colors.indices) {
            val cx = w * (0.5f + 0.36f * cos(phase * blobSpeed[i] * 6f + blobPhase[i]))
            val cy = h * (0.5f + 0.34f * sin(phase * blobSpeed[i] * 4.5f + blobPhase[i] * 1.7f))
            val r = span * blobRadius[i]
            val a = ((if (dark) blobAlpha[i] else blobAlpha[i] * 0.9f) * 255f).toInt()
            val c = colors[i]
            val top = Color.argb(a, Color.red(c), Color.green(c), Color.blue(c))
            val bottom = Color.argb(0, Color.red(c), Color.green(c), Color.blue(c))
            paint.shader = RadialGradient(
                cx, cy, r,
                intArrayOf(top, bottom),
                floatArrayOf(0f, 1f),
                Shader.TileMode.CLAMP
            )
            canvas.drawRect(0f, 0f, w, h, paint)
        }

        // Accent orb — tinted with the user's accent colour.
        val ac = ZenLiquidGlassEngine.accentArgb
        val aAcc = ((if (dark) 0.34f else 0.30f) * 255f).toInt()
        val cx = w * (0.5f + 0.30f * cos(phase * 0.54f + 2.2f))
        val cy = h * (0.5f + 0.30f * sin(phase * 0.54f + 3.4f))
        paint.shader = RadialGradient(
            cx, cy, span * 0.40f,
            intArrayOf(
                Color.argb(aAcc, Color.red(ac), Color.green(ac), Color.blue(ac)),
                Color.argb(0, Color.red(ac), Color.green(ac), Color.blue(ac))
            ),
            floatArrayOf(0f, 1f),
            Shader.TileMode.CLAMP
        )
        canvas.drawRect(0f, 0f, w, h, paint)
        paint.shader = null

        needsRedraw = false
    }
}
