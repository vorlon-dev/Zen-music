package com.zen.music.zenmusic.liquid

// SP-54: Liquid Glass — a single glass panel surface, drawn natively in Kotlin.
//
// Hosted by the Flutter side inside ZenGlassPanel as platform view
// "zen_liquid_glass" (kind:"surface"); the Flutter child content is stacked
// ABOVE this view and keeps all gestures.
//
// What it paints (iOS-26-style liquid glass read, zero blur passes):
//   1. vertical translucent fill — bright at the top (light catch),
//      fading down, so panels look like curved glass over the aurora;
//   2. a 1px horizontal specular hairline across the top edge;
//   3. a soft diagonal sheen band (the "liquid" highlight);
//   4. an accent-tinted rim glow in the bottom corner.
//
// All shaders are pre-softened gradients — deliberately NO RenderEffect /
// gaussian pass, which is what keeps this smooth on budget phones. Panels
// sit over the aurora backdrop, and a translucent gradient over a gradient
// reads exactly like frosted glass.

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RadialGradient
import android.graphics.RectF
import android.graphics.Shader
import android.view.View

class LiquidGlassSurfaceView(
    context: Context,
    args: Map<String, Any?>? = null,
) : View(context) {

    private val density = context.resources.displayMetrics.density

    /** Corner radius in px (Flutter sends logical px). */
    private var radiusPx = ((args?.get("radius") as? Number)?.toFloat() ?: 20f) * density

    private val fillPaint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val hairlinePaint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val sheenPaint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val rimPaint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val clipPath = Path()
    private val rect = RectF()

    private var builtAtRevision = -1
    private var builtForDark: Boolean? = null

    override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
        super.onSizeChanged(w, h, oldw, oldh)
        buildShaders(w.toFloat(), h.toFloat())
    }

    override fun onDraw(canvas: Canvas) {
        val dark = ZenLiquidGlassEngine.dark
        if (builtAtRevision != ZenLiquidGlassEngine.revision || builtForDark != dark) {
            buildShaders(width.toFloat(), height.toFloat())
        }
        if (width == 0 || height == 0) return

        // 1 — translucent vertical fill.
        canvas.drawRoundRect(rect, radiusPx, radiusPx, fillPaint)

        // 2 — top specular hairline.
        canvas.drawRoundRect(rect, radiusPx, radiusPx, hairlinePaint)

        // 3 — diagonal sheen, clipped to the glass shape.
        val save = canvas.save()
        canvas.clipPath(clipPath)
        canvas.drawRect(rect, sheenPaint)
        // 4 — accent rim glow in the bottom corner.
        canvas.drawCircle(
            rect.right - radiusPx, rect.bottom - radiusPx,
            radiusPx * 1.6f, rimPaint
        )
        canvas.restoreToCount(save)
    }

    private fun buildShaders(w: Float, h: Float) {
        val dark = ZenLiquidGlassEngine.dark
        builtAtRevision = ZenLiquidGlassEngine.revision
        builtForDark = dark
        if (w <= 0f || h <= 0f) return

        rect.set(0f, 0f, w, h)
        clipPath.reset()
        clipPath.addRoundRect(rect, radiusPx, radiusPx, Path.Direction.CW)

        // Fill: white catches light at the top, fades to nearly nothing.
        val topA = if (dark) 0x2E else 0x59 // ~18% / ~35%
        val botA = if (dark) 0x12 else 0x28 // ~7%  / ~16%
        fillPaint.shader = LinearGradient(
            0f, 0f, 0f, h,
            Color.argb(topA, 255, 255, 255),
            Color.argb(botA, 255, 255, 255),
            Shader.TileMode.CLAMP
        )

        // Hairline: strongest mid-top, fading to the sides.
        val lineA = if (dark) 0x5C else 0x99
        hairlinePaint.style = Paint.Style.STROKE
        hairlinePaint.strokeWidth = density
        hairlinePaint.shader = LinearGradient(
            0f, 0f, w, 0f,
            intArrayOf(
                Color.argb(0x00, 255, 255, 255),
                Color.argb(lineA, 255, 255, 255),
                Color.argb(0x00, 255, 255, 255)
            ),
            floatArrayOf(0f, 0.42f, 1f),
            Shader.TileMode.CLAMP
        )

        // Diagonal sheen band.
        val sheenA = if (dark) 0x14 else 0x2E
        sheenPaint.shader = LinearGradient(
            0f, 0f, w, h,
            intArrayOf(
                Color.argb(0x00, 255, 255, 255),
                Color.argb(sheenA, 255, 255, 255),
                Color.argb(0x00, 255, 255, 255)
            ),
            floatArrayOf(0.12f, 0.42f, 0.85f),
            Shader.TileMode.CLAMP
        )

        // Accent rim glow.
        val ac = ZenLiquidGlassEngine.accentArgb
        val rimA = if (dark) 0x30 else 0x26
        rimPaint.shader = RadialGradient(
            rect.right - radiusPx, rect.bottom - radiusPx, radiusPx * 1.6f,
            intArrayOf(
                Color.argb(rimA, Color.red(ac), Color.green(ac), Color.blue(ac)),
                Color.argb(0, Color.red(ac), Color.green(ac), Color.blue(ac))
            ),
            floatArrayOf(0f, 1f),
            Shader.TileMode.CLAMP
        )
    }
}
