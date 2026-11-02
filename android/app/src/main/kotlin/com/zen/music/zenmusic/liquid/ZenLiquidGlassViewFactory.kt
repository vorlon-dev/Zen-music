// ZenMusic · vorlon-dev

package com.zen.music.zenmusic.liquid


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
