// ZenMusic · vorlon-dev

package com.zen.music.zenmusic.liquid


import android.content.Context
import android.view.View
import io.flutter.plugin.platform.PlatformView

class ZenLiquidGlassPlatformView(
    private val context: Context,
    args: Map<String, Any?>?,
) : PlatformView {

    private val view: View = when ((args?.get("kind") as? String) ?: "surface") {
        "backdrop" -> LiquidGlassBackdropView(context)
        else -> LiquidGlassSurfaceView(context, args)
    }

    override fun getView(): View = view

    override fun dispose() {
        // Views clean up in onDetachedFromWindow; nothing owned here.
    }
}
