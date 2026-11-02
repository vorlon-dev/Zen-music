package com.zen.music.zenmusic.launcher

import android.app.Activity
import android.content.ComponentName
import android.content.pm.PackageManager
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * ZenMusic — launcher icon switcher (SP-77).
 *
 * Each logo slot is an <activity-alias> in AndroidManifest.xml pointing at
 * MainActivity with its own mipmap icon. Switching = enable the chosen
 * alias, disable every other one (PackageManager component-enabled state,
 * DONT_KILL_APP). The activity itself never carries the MAIN/LAUNCHER
 * intent-filter, so exactly one launcher entry exists at any time and the
 * audio engine / notification targets are never disturbed.
 *
 * Slot ids MUST match lib/desktop/services/launcher_icon.dart:
 *   default, zen_logo_1 .. zen_logo_9
 */
object ZenLauncherIcon {

    private const val CHANNEL = "zen/launcher_icon"
    private const val PKG = "com.zen.music.zenmusic"

    val slots = listOf(
        "default",
        "zen_logo_1", "zen_logo_2", "zen_logo_3", "zen_logo_4", "zen_logo_5",
        "zen_logo_6", "zen_logo_7", "zen_logo_8", "zen_logo_9"
    )

    /** .ZenLauncherDefault / .ZenLauncher1 / .ZenLauncher2 ... */
    private fun aliasClass(slot: String): String = when (slot) {
        "default" -> "$PKG.ZenLauncherDefault"
        else -> "$PKG.ZenLauncher" + slot.removePrefix("zen_logo_")
    }

    fun register(flutterEngine: FlutterEngine, activity: Activity) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "slots" -> result.success(slots)
                    "current" -> result.success(current(activity))
                    "set" -> {
                        val slot = call.argument<String>("slot")
                        if (slot == null || slot !in slots) {
                            result.success(false)
                        } else {
                            result.success(runCatching { set(activity, slot) }
                                .getOrDefault(false))
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /** The currently enabled alias slot ("default" when none is enabled). */
    fun current(activity: Activity): String {
        val pm = activity.packageManager
        for (slot in slots) {
            val name = ComponentName(PKG, aliasClass(slot))
            val state = pm.getComponentEnabledSetting(name)
            val enabled =
                state == PackageManager.COMPONENT_ENABLED_STATE_ENABLED
            if (enabled) return slot
        }
        return "default"
    }

    /**
     * Enables [slot]'s alias and disables every OTHER DECLARED alias.
     *
     * SP-82: this used to be all-or-nothing (`slots.all { aliasDeclared }`
     * or fail) — an install whose manifest shipped only part of the alias
     * set (e.g. the app updated over an older build, or a future slot
     * added) could then never switch ANY logo, which reads exactly like
     * the user report "logo are not applying". Switching now works among
     * whatever aliases this APK actually declares; the requested slot
     * must be one of them. Undeclared aliases are skipped untouched.
     */
    private fun set(activity: Activity, slot: String): Boolean {
        val pm = activity.packageManager
        val declared = slots.filter { aliasDeclared(pm, it) }
        if (slot !in declared) return false
        for (s in declared) {
            val name = ComponentName(PKG, aliasClass(s))
            val target =
                if (s == slot) PackageManager.COMPONENT_ENABLED_STATE_ENABLED
                else PackageManager.COMPONENT_ENABLED_STATE_DISABLED
            pm.setComponentEnabledSetting(
                name,
                target,
                PackageManager.DONT_KILL_APP
            )
        }
        return true
    }

    /** True when the manifest on this install declares the alias. */
    private fun aliasDeclared(pm: PackageManager, slot: String): Boolean =
        try {
            pm.getActivityInfo(ComponentName(PKG, aliasClass(slot)), 0)
            true
        } catch (_: Exception) {
            false
        }
}
