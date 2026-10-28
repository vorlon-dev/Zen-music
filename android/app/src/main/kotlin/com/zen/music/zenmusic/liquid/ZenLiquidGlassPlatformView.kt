package com.zen.music.zenmusic.liquid

// SP-54: Liquid Glass — PlatformView wrapper.
//
// One viewType ("zen_liquid_glass"), two kinds (mirrors ZenLiquidGlassView
// Factory contract and the Dart side in lib/desktop/liquid/):
//   kind = "backdrop" → LiquidGlassBackdropView (fullscreen aurora)
//   kind = "surface"  → LiquidGlassSurfaceView (a glass panel surface)
//
// The view is purely decorative — the Flutter side stacks its real content
// above it, so no gesture forwarding is needed here.

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
