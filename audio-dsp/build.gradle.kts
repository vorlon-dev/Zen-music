plugins {
  id("com.android.library")
  id("org.jetbrains.kotlin.android")
}

android {
  namespace = "com.zen.music.zenmusic.dsp.audio"
  // Aligned with the app module (37 — the receive_sharing_intent
  // override comment there applies here too).
  compileSdk = 37

  defaultConfig {
    // MUST be <= the app's minSdk (24) — a library minSdk above the
    // consumer's fails the manifest merger.
    minSdk = 24
  }

  compileOptions {
    sourceCompatibility = JavaVersion.VERSION_17
    targetCompatibility = JavaVersion.VERSION_17
  }
}

kotlin {
  // Project toolchain (17). The original asked 21; no post-17 APIs used.
  jvmToolchain(17)
}

dependencies {
  // Biquad math + EQ models come from :dsp-core.
  api(project(":dsp-core"))

  // The processors implement androidx.media3.common.audio.AudioProcessor —
  // same artifact AND version the app pins (mixed media3 versions on one
  // classpath is the same hazard as the ktor regression).
  api("androidx.media3:media3-common:1.4.1")

  // StateFlow/MutableStateFlow in the DspController API. api() because
  // the controller's public interface exposes StateFlow types. Same
  // version the app pins.
  api("org.jetbrains.kotlinx:kotlinx-coroutines-core:1.10.2")

  implementation("com.jakewharton.timber:timber:5.0.1")

  testImplementation("junit:junit:4.13.2")
}