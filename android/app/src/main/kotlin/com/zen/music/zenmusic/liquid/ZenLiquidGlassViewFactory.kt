package com.zen.music.zenmusic.liquid

// SP-54: Liquid Glass — platform-view factory.
//
// Registered in MainActivity.configureFlutterEngine as viewType
// "zen_liquid_glass". Creation args (StandardMessageCodec):
//   kind   : "backdrop" | "surface"  (default "surface")
//   radius : Float, logical px     (default 20, surface kind only)
//
// Same pattern as the existing ZenVideoPlayerViewFactory.

import android.content.Context
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

class ZenLiquidGlassViewFactory : PlatformViewFactory(StandardMessageCodec.INSTANCE) {

    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        @Suppress("UNCHECKED_CAST")
        val params = args as? Map<String, Any?>
        return ZenLiquidGlassPlatformView(context, params)
    }
}
