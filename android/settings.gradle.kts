pluginManagement {
    val flutterSdkPath = run {
        val properties = java.util.Properties()
        file("local.properties").inputStream().use { properties.load(it) }
        val flutterSdkPath = properties.getProperty("flutter.sdk")
        require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
        flutterSdkPath
    }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "9.1.0" apply false
    id("org.jetbrains.kotlin.android") version "2.4.0" apply false
    id("org.jetbrains.kotlin.plugin.serialization") version "2.4.0" apply false
    // JVM library plugin for the :dsp-core module. Same kotlin-gradle-plugin
    // artifact/version as kotlin.android above — one JAR, two plugin ids.
    id("org.jetbrains.kotlin.jvm") version "2.4.0" apply false
}

include(":app")
include(":dsp-core")
project(":dsp-core").projectDir = file("../dsp-core")
include(":audio-dsp")
project(":audio-dsp").projectDir = file("../audio-dsp")
include(":innertube")
project(":innertube").projectDir = file("../innertube")