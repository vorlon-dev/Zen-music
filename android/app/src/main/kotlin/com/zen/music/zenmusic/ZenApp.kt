package com.zen.music.zenmusic

import android.app.Application
import com.zen.music.zenmusic.innertube.ZenInnertubeResolver

/// Application-level init: starts the stream-extraction resolver's
/// warm-up at process creation — earlier than
/// MainActivity.configureFlutterEngine, so the visitorData bootstrap
/// is paid before the Flutter engine and first UI frame (Echo parity:
/// its resolver also inits in Application). The old cipher prewarm is
/// gone with InnerTubeX; visitorData persistence is what remains.
/// NOTE: no Flutter/Activity access here — native-only init.
class ZenApp : Application() {
    override fun onCreate() {
        super.onCreate()
        ZenInnertubeResolver.init(applicationContext)
    }
}