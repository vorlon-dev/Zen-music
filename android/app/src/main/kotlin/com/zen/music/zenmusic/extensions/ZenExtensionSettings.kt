package com.zen.music.zenmusic.extensions

import android.content.Context
import dev.brahmkshatriya.echo.common.settings.Settings

/// SharedPreferences-backed Settings for a single extension,
/// scoped by extension id so extensions never collide.
class ZenExtensionSettings(context: Context, extId: String) : Settings {
    private val prefs =
        context.getSharedPreferences("ext_settings_$extId", Context.MODE_PRIVATE)

    override fun getString(key: String): String? = prefs.getString(key, null)

    override fun putString(key: String, value: String?) {
        if (value == null) prefs.edit().remove(key).apply()
        else prefs.edit().putString(key, value).apply()
    }

    override fun getStringSet(key: String): Set<String>? =
        prefs.getStringSet(key, null)

    override fun putStringSet(key: String, value: Set<String>?) {
        if (value == null) prefs.edit().remove(key).apply()
        else prefs.edit().putStringSet(key, value).apply()
    }

    override fun getInt(key: String): Int? =
        if (prefs.contains(key)) prefs.getInt(key, 0) else null

    override fun putInt(key: String, value: Int?) {
        if (value == null) prefs.edit().remove(key).apply()
        else prefs.edit().putInt(key, value).apply()
    }

    override fun getBoolean(key: String): Boolean? =
        if (prefs.contains(key)) prefs.getBoolean(key, false) else null

    override fun putBoolean(key: String, value: Boolean?) {
        if (value == null) prefs.edit().remove(key).apply()
        else prefs.edit().putBoolean(key, value).apply()
    }
}