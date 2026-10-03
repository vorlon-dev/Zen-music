package com.zen.music.zenmusic

import android.app.Application
import com.zen.music.zenmusic.innertubex.InnerTubeXResolver

/// Application-level init: starts the InnerTubeX warm-up at process
/// creation — earlier than MainActivity.configureFlutterEngine, so
/// the cipher/visitor bootstrap is paid before the Flutter engine and
/// first UI frame (Echo parity: its resolver also inits in Application).
/// NOTE: no Flutter/Activity access here — native-only init.
class ZenApp : Application() {
    override fun onCreate() {
        super.onCreate()
        InnerTubeXResolver.init(applicationContext)
    }
}