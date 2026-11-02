// ZenMusic · vorlon-dev

package com.zen.music.zenmusic.material3

import android.content.Context
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

object Material3Tokens {
    const val CHANNEL = "zen/material3_tokens"

    // res/values/material3_tokens.xml names → map keys served to Dart.
    private val DARK_KEYS = listOf(
        "m3_dark_primary", "m3_dark_secondary", "m3_dark_tertiary",
        "m3_dark_background", "m3_dark_surface", "m3_dark_on_surface",
        "m3_dark_error", "m3_dark_primary_container",
        "m3_dark_on_primary_container", "m3_dark_secondary_container",
        "m3_dark_on_secondary_container", "m3_dark_surface_container_high",
        "m3_dark_surface_container_highest",
        "m3_dark_on_surface_variant", "m3_dark_tertiary_container",
        "m3_dark_on_tertiary_container", "m3_dark_surface_container_lowest",
        "m3_dark_surface_container_low", "m3_dark_surface_container",
        "m3_dark_outline", "m3_dark_outline_variant",
    )
    private val LIGHT_KEYS = listOf(
        "m3_light_primary", "m3_light_on_primary", "m3_light_primary_container",
        "m3_light_on_primary_container", "m3_light_secondary",
        "m3_light_secondary_container", "m3_light_on_secondary_container",
        "m3_light_tertiary", "m3_light_background", "m3_light_surface",
        "m3_light_on_surface", "m3_light_surface_variant",
        "m3_light_on_surface_variant", "m3_light_outline", "m3_light_error",
        "m3_light_tertiary_container", "m3_light_on_tertiary_container",
        "m3_light_surface_container_lowest", "m3_light_surface_container_low",
        "m3_light_surface_container", "m3_light_surface_container_high",
        "m3_light_surface_container_highest", "m3_light_outline_variant",
    )

    /** Register the channel on the engine (called from MainActivity). */
    fun register(flutterEngine: FlutterEngine, context: Context) {
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getTokens" -> result.success(tokens(context))
                else -> result.notImplemented()
            }
        }
    }

    /** All token colours as ARGB ints keyed by resource name. */
    fun tokens(context: Context): Map<String, Long> {
        val out = HashMap<String, Long>()
        val res = context.resources
        val packageName = context.packageName
        fun put(name: String) {
            val id = res.getIdentifier(name, "color", packageName)
            if (id != 0) {
                // ARGB Int is negative in Kotlin (0xFF… > Int.MAX); mask it
                // into an unsigned 32-bit Long so Dart receives the exact
                // positive Color.value (e.g. 0xFFAB47BC = 4289377724).
                out[name] = res.getColor(id).toLong() and 0xFFFFFFFFL
            }
        }
        DARK_KEYS.forEach { put(it) }
        LIGHT_KEYS.forEach { put(it) }
        return out
    }
}
