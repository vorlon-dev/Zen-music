plugins {
    id("com.android.library")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "com.zen.music.zenmusic.lossless"
    compileSdk = 37

    defaultConfig {
        minSdk = 24

        externalNativeBuild {
            cmake {
                // STL choice and the 16 KB page-size support flag match the
                // proven reference. The policy floor lets soxr 0.1.3's
                // legacy CMake configure under modern CMake — do not drop it.
                arguments += listOf(
                    "-DANDROID_STL=c++_shared",
                    "-DANDROID_SUPPORT_FLEXIBLE_PAGE_SIZES=ON",
                    "-DCMAKE_POLICY_VERSION_MINIMUM=3.5",
                )
            }
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            // REMOVED: prefab = true (causes script compilation error)
        }
        // Flutter's `profile` build type: without this the :just_audio
        // module's profile compile classpath finds no matching variant
        // of :lossless (assembleProfile fails at dependency resolution).
        create("profile") {
            matchingFallbacks += listOf("release")
            isMinifyEnabled = false
        }
    }

    buildFeatures {
        // Consumes com.google.oboe:oboe's prefab-packaged native library.
        prefab = true
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    externalNativeBuild {
        cmake {
            path = file("cpp/CMakeLists.txt")
            version = "3.22.1"
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    // Media3 audio-processor API for ZenNativePcmAudioProcessor
    // (BaseAudioProcessor / AudioFormat / C). One version line with the app.
    implementation("androidx.media3:media3-common:1.4.1")
    // Low-latency native output; exposes its CMake target through Prefab.
    // Reference-proven pin (1.10, API-compatible with the Oboe 1.8+ baseline).
    implementation("com.google.oboe:oboe:1.10.0")
}