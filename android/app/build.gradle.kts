plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.serialization")
}

android {
    namespace = "com.zen.music.zenmusic"
    // Override: receive_sharing_intent's latest release was built
    // against SDK 37; Flutter's default lags at 36. Explicit override
    // keeps the plugin happy regardless of Flutter's pinned value.
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        applicationId = "com.zen.music.zenmusic"
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    // Parametric EQ DSP: preset parsing, validation, biquad math +
    // magnitude response (zen/dsp channel).
    implementation(project(":dsp-core"))

    // Parametric-EQ audio processors + controller (state bridging now,
    // audio-pipeline injection in the forked-just_audio round).
    implementation(project(":audio-dsp"))

    // Tier-0 stream extraction — vendored raw player API module
    // (direct-URL clients: ANDROID_VR 1.65.10 / VISIONOS), served
    // through ZenInnertubeResolver on the legacy 'zen/innertubex'
    // channel. Replaced the innertubex JitPack artifact (removed).
    implementation(project(":innertube"))

    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.9.0")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.10.2")
    implementation("com.squareup.okhttp3:okhttp:5.1.0")

    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs_nio:2.1.5")

    // media3 — one version across the set. exoplayer brings
    // datasource/extractor transitively (ZenVideoPlayerView uses
    // DefaultHttpDataSource + ProgressiveMediaSource/MergingMediaSource);
    // media3-ui is NOT needed — the player renders into a TextureView.
    implementation("androidx.media3:media3-common:1.4.1")
    implementation("androidx.media3:media3-exoplayer:1.4.1")

    // ktor — one version across the classpath. The :innertube module
    // declares identical pins of its own; these stay explicit at app
    // level so no future transitive can pull a different ktor
    // (2.x mixes produced runtime NoClassDefFoundError:
    // ContentNegotiation).
    implementation("io.ktor:ktor-client-core:3.1.3")
    implementation("io.ktor:ktor-client-okhttp:3.1.3")
    implementation("io.ktor:ktor-client-content-negotiation:3.1.3")
    implementation("io.ktor:ktor-serialization-kotlinx-json:3.1.3")
    implementation("com.jakewharton.timber:timber:5.0.1")

    flutter {
        source = "../.."
    }
}