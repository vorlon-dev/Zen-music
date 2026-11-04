# zen-api-client

Kotlin client for the ZenMusic API ([docs](../docs/API.md)). Plain Kotlin; works on Android and on the JVM. No Dart.

## Add it to your project

Copy `src/main/kotlin/dev/vorlon/zenapi/ZenApi.kt` into your app, **or** include this folder as a module:

```kotlin
// settings.gradle.kts
include(":zen-api-client")
project(":zen-api-client").projectDir = file("path/to/Zen-music/zen-api-client")

// app/build.gradle.kts
dependencies { implementation(project(":zen-api-client")) }
```

On Android, `org.json` is built in. On a plain JVM add `org.json:json:20240303`.

## Use it

```kotlin
val api = ZenApi(baseUrl = "https://my-zen-music.pages.dev", apiKey = "YOUR_KEY")

val songs = api.searchSongs(Source.YTM, "arijit")      // Source.JIO, Source.YTM, Source.YT
val albums = api.searchCollections("arijit", "album")   // JioSaavn only
val list = api.playlist(Source.YT, "PLxxxxxxxx")
val one = api.song("jioSongId")                         // JioSaavn only

when (val p = songs.first().playback) {
  is Playback.Direct -> startAudio(p.url)             // JioSaavn direct link
  is Playback.YouTube -> startYoutube(p.videoId)      // official YouTube player
}
```

All calls block, so call them from a background thread or coroutine (`withContext(Dispatchers.IO)`). Errors throw `ZenApiException` (with the HTTP status).

Self-hosting guide: [docs/SELF_HOSTING.md](../docs/SELF_HOSTING.md).

## Tests

`./gradlew test` inside this folder (needs a Gradle wrapper or a local Gradle). The tests start a local fake server; no internet needed.
