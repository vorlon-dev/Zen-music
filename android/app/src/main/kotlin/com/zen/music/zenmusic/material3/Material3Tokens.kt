package com.zen.music.zenmusic.material3

import android.content.Context
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * SP-58: Material 3 theme — NATIVE token provider.
 *
 * The "Material 3" UI theme's palette lives in
 * res/values/material3_tokens.xml (extracted 1:1 from PixelMusic's
 * ui/theme/Color.kt). This object reads those resources and serves them
 * to Flutter over the `zen/material3_tokens` channel once at boot; the
 * Dart side (lib/desktop/material3/m3_bridge.dart) then builds the
 * ColorScheme from the native values. Failure-soft by design: if
 * anything goes wrong the Dart-side fallback palette (identical values)
 * is used, and this class is never invoked again.
 *
 * Note: PixelMusic's UI itself is Jetpack Compose (its screens are
 * Kotlin, not XML layouts) — the design SYSTEM is what gets adopted
 * here: tokens native in res/, rendering via Flutter's Material 3
 * widgets, which implement the same spec.
 */
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
        // SP-61: full surface-container ladder + outlines so the player's
        // lyrics / queue / quality-sheet surfaces resolve natively on
        // Android too (they consume these roles via the M3 ColorScheme).
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
        // SP-61: remaining container roles for full native coverage.
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
