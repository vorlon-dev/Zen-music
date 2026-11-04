// ZenMusic · vorlon-dev
//
// zen-kit: the Kotlin library behind ZenMusic.
//   - ZenApi        data from your self-hosted backend (search, playlists)
//   - ZenKit        one-call setup: backend URL + on-device playback
//   - on-device     PO-token bridge and stream resolver (moved here from
//                   the app module; packages are unchanged)

plugins {
  id("com.android.library")
  id("org.jetbrains.kotlin.android")
}

android {
  namespace = "dev.vorlon.zenkit"
  compileSdk = 37

  defaultConfig { minSdk = 24 }

  compileOptions {
    isCoreLibraryDesugaringEnabled = true
    sourceCompatibility = JavaVersion.VERSION_17
    targetCompatibility = JavaVersion.VERSION_17
  }
}

kotlin {
  compilerOptions {
    jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
  }
}

dependencies {
  // Raw InnerTube player API + stream decipher (vendored module).
  implementation(project(":innertube"))

  implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.10.2")
  implementation("com.squareup.okhttp3:okhttp:5.1.0")

  coreLibraryDesugaring("com.android.tools:desugar_jdk_libs_nio:2.1.5")

  // org.json is built into Android but stubbed in local unit tests.
  testImplementation("org.json:json:20240303")
  testImplementation("junit:junit:4.13.2")
  testImplementation(kotlin("test"))
}
