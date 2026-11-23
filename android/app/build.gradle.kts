// ZenMusic · vorlon-dev

plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.serialization")
    // SP72: native Echo-style mobile UI (Jetpack Compose).
    id("org.jetbrains.kotlin.plugin.compose")
}

android {
    namespace = "com.zen.music.zenmusic"
    // Pinned above Flutter's default so every plugin compiles against the
    // same (newest) SDK level.
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    packaging {
        jniLibs {
            // Store native libraries compressed inside the APK. This makes
            // the downloaded APK much smaller (libmpv, libflutter and libapp
            // are ~34 MB uncompressed); the system extracts them at install.
            useLegacyPackaging = true
        }
        resources {
            // libsoxr ships AL/LGPL META-INF metadata that breaks
            // duplicate-resource merging.
            excludes += "/META-INF/{AL2.0,LGPL2.1}"
        }
    }

    defaultConfig {
        applicationId = "com.zen.music.zenmusic"
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildFeatures {
        // SP72: the phone UI is native Compose (Echo-style) rendered on top
        // of the headless Flutter engine.
        compose = true
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
            // R8 code/resource shrinking: unused classes and resources are
            // stripped from the APK (see proguard-rules.pro — shrink-only
            // mode, no obfuscation/optimization).
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                // AGP 9 removed proguard-android.txt (it hard-codes
                // -dontoptimize). The optimize variant is now required;
                // proguard-rules.pro still pins -dontoptimize + -dontobfuscate,
                // so R8 keeps the exact same shrink-only pass as before.
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
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
    implementation(project(":lossless"))
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

    // ── SP72: native mobile UI stack (Echo-style Compose) ────────────────
    // The Compose BOM pins every androidx.compose artifact to one tested
    // set; only the BOM version is upgraded.
    implementation(platform("androidx.compose:compose-bom:2025.06.01"))
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.ui:ui-graphics")
    implementation("androidx.compose.foundation:foundation")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.material:material-icons-core")
    implementation("androidx.activity:activity-compose:1.10.1")
    // ComposeView needs the ViewTree owners installed on it (hosted inside
    // a FlutterActivity) — the -ktx artifacts ship the setViewTree* helpers.
    implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.8.7")
    implementation("androidx.lifecycle:lifecycle-viewmodel-ktx:2.8.7")
    implementation("androidx.savedstate:savedstate-ktx:1.2.1")
    // Album-art palette extraction → dynamic accent color (Echo-style).
    implementation("androidx.palette:palette-ktx:1.0.0")
    // Async artwork images (Coil 3 — matches the OkHttp 5 already pinned).
    implementation("io.coil-kt.coil3:coil-compose:3.2.0")
    implementation("io.coil-kt.coil3:coil-network-okhttp:3.2.0")

    flutter {
        source = "../.."
    }
}
