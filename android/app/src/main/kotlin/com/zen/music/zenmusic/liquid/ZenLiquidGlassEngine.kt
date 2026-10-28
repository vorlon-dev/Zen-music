package com.zen.music.zenmusic.liquid

// SP-54: Liquid Glass — Kotlin-side theme engine.
//
// This is the Android half of the liquid glass theme. The UI of the glass
// layer is drawn 100% natively in Kotlin (LiquidGlassBackdropView +
// LiquidGlassSurfaceView) because native rendering stays smooth on low-end
// phones. This object is the bridge brain:
//   • registers the `zenmusic/liquid_glass` MethodChannel,
//   • stores the current theme state (enabled / dark / accent),
//   • computes a device performance tier (low / mid / high) once at boot
//     from ActivityManager signals so the renderers can degrade cheaply.
//
// Tier policy (smoothness on low-end mobile is a hard requirement):
//   low  → isLowRamDevice == true, OR API < 28, OR small heap class.
//          Renderers go static: no animator, no platform-view panels —
//          Dart falls back to a plain translucent frost instead.
//   mid  → everything else: gradient glass, animator at ~40 fps.
//   high → API ≥ 33 and large heap: full animation at native vsync.

import android.app.Activity
import android.app.ActivityManager
import android.os.Build
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

object ZenLiquidGlassEngine {

    /** Platform-view type — must match kZenGlassViewType in Dart. */
    const val VIEW_TYPE = "zen_liquid_glass"

    /** MethodChannel name — must match LiquidGlassBridge in Dart. */
    const val CHANNEL = "zenmusic/liquid_glass"

    @Volatile var enabled: Boolean = false
        private set
    @Volatile var dark: Boolean = true
        private set
    @Volatile var accentArgb: Int = 0xFF7C8CF8.toInt()
        private set
    @Volatile var tier: String = "mid"
        private set

    /** Bumped on every theme change so live views can cheaply detect it. */
    @Volatile var revision: Int = 0
        private set

    private val listeners = mutableListOf<() -> Unit>()
    private var channel: MethodChannel? = null

    /** Called from MainActivity.configureFlutterEngine. */
    fun register(flutterEngine: FlutterEngine, activity: Activity) {
        computeTier(activity)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "setTheme" -> {
                        enabled = call.argument<Boolean>("enabled") ?: false
                        dark = call.argument<Boolean>("dark") ?: true
                        // Accent is a 32-bit ARGB int from Dart — values above
                        // Int.MAX_VALUE arrive as java.lang.Long, so read it
                        // as Number rather than argument<Int>().
                        val accent =
                            (call.arguments as? Map<*, *>)?.get("accent") as? Number
                        if (accent != null && accent.toInt() != 0) accentArgb = accent.toInt()
                        bump()
                        result.success(null)
                    }
                    "getProfile" -> result.success(
                        mapOf(
                            "tier" to tier,
                            "api" to Build.VERSION.SDK_INT,
                        )
                    )
                    else -> result.notImplemented()
                }
            }
        }
    }

    /**
     * Device performance tier, computed once — no per-frame work.
     * Only OS signals: low-RAM flag, heap class (memoryClass) and API level.
     */
    fun computeTier(activity: Activity) {
        val am = activity.getSystemService(Activity.ACTIVITY_SERVICE) as? ActivityManager
        val lowRam = am?.isLowRamDevice == true
        val memClass = am?.memoryClass ?: 96
        tier = when {
            lowRam || Build.VERSION.SDK_INT < 28 || memClass <= 128 -> "low"
            Build.VERSION.SDK_INT >= 33 && memClass >= 256 -> "high"
            else -> "mid"
        }
    }

    fun addListener(listener: () -> Unit) {
        synchronized(listeners) { listeners.add(listener) }
    }

    fun removeListener(listener: () -> Unit) {
        synchronized(listeners) { listeners.remove(listener) }
    }

    private fun bump() {
        synchronized(listeners) {
            revision++
            // Copy-out to avoid notifying under the lock while a view draws.
            val snapshot = listeners.toList()
            snapshot.forEach { it() }
        }
    }
}
