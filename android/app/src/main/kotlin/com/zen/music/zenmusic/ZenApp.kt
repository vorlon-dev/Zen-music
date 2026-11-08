// ZenMusic · vorlon-dev

package com.zen.music.zenmusic

import android.app.Application
import android.content.pm.ApplicationInfo
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
        // Application.onCreate runs on the main thread BEFORE the first frame
        // (it measured 2.7 s on a Redmi 9-class phone). Touching
        // ZenInnertubeResolver loads the innertube/ktor/okhttp/serialization
        // classes and reads SharedPreferences — none of that needs the main
        // thread, so do it on a worker.
        val app = applicationContext
        Thread({
            val debuggable =
                (app.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0
            ZenInnertubeResolver.debugLogs = debuggable
            ZenInnertubeResolver.init(app)
        }, "zen-init").start()
    }
}
