# zen-kit

The Kotlin library behind ZenMusic, in one folder. No Dart.

| Part | What it does | Runs |
|---|---|---|
| `ZenApi` | Search, playlists, albums, song data from **your** backend ([`backend/`](../backend/README.md)) | calls your Cloudflare site |
| `ZenKit.resolveAudioBlocking` | Resolves a YouTube / YouTube Music audio stream | **on the device** |
| PO-token bridge (`potoken/ZenPoTokenBridge.kt`, `assets/po_token.html`) | Mints the PO token on the device in a hidden WebView | **on the device** |
| Stream resolver (`innertubex/ZenInnertubeResolver.kt`) + [`innertube`](../innertube) module | Client selection and signature/throttling solving | **on the device** |

The backend never sees tokens or audio. It only returns metadata (and direct links for JioSaavn).

## Put it in your Android project

1. Copy the folders **`zen-kit/`** and **`innertube/`** from this repository next to your `android/` (or app) folder. (`zen-kit` uses `innertube` for the player API and the solver.)
2. `settings.gradle.kts`:

   ```kotlin
   include(":innertube")
   project(":innertube").projectDir = file("../innertube")
   include(":zen-kit")
   project(":zen-kit").projectDir = file("../zen-kit")
   ```

   Make sure the plugins `org.jetbrains.kotlin.android` and `org.jetbrains.kotlin.plugin.serialization` are declared (see this repository's `android/settings.gradle.kts`).
3. App `build.gradle.kts`: `implementation(project(":zen-kit"))`
4. `MainActivity.kt`: initialise once, with your backend URL:

   ```kotlin
   ZenKit.init(
       activity = this,
       backendUrl = "https://my-zen-music.pages.dev", // see backend/README.md
       apiKey = "YOUR_KEY",                            // or null
       debug = false,
   )
   ```

   In this repository the URL lives in two constants at the top of `MainActivity.kt` (`ZEN_BACKEND_URL`, `ZEN_BACKEND_KEY`).

Nothing else is needed: the PO-token page is bundled in the library's assets, and the token is created on the device when playback needs it. You do not place any token files anywhere.

## Use it

All calls block; use a background thread or `withContext(Dispatchers.IO)`.

```kotlin
// data from your backend
val songs = ZenKit.api.searchSongs(Source.YTM, "arijit")   // Source.JIO / YTM / YT
val list  = ZenKit.api.playlist(Source.YT, "PLxxxxxxxx")
val albums = ZenKit.api.searchCollections("arijit", "album") // JioSaavn only

// play
val song = songs.first()
when (val p = song.playback) {
  is Playback.Direct  -> play(p.url)                               // JioSaavn: direct link
  is Playback.YouTube -> {                                         // YouTube / YTM
    val audio = ZenKit.resolveAudioBlocking(p.videoId)             // on-device
    if (audio != null) play(audio.url, audio.headers)              // pass headers to ExoPlayer
  }
}
```

Alternatively play `Playback.YouTube.embedUrl` with the official YouTube player.

## Status

This module was split out of the app module by moving files; package names are unchanged, so existing imports (`com.zen.music.zenmusic.innertube.ZenInnertubeResolver`, `...potoken.ZenPoTokenBridge`) still work. It has not been compiled by the author of this change; build it before releasing.

Tests: `./gradlew :zen-kit:testDebugUnitTest` (a local fake server; no internet).
