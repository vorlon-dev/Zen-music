// ZenMusic · vorlon-dev
//
// Kotlin client for the ZenMusic API. Plain Kotlin/JVM (works on Android too).
// Not part of the app's Gradle build: copy `src/main/kotlin` into your
// project, or include this folder as a module in your own settings.gradle.kts.

plugins {
  id("org.jetbrains.kotlin.jvm") version "2.4.0"
}

repositories { mavenCentral() }

dependencies {
  // Android already ships org.json; on plain JVM add it yourself.
  compileOnly("org.json:json:20240303")
  testImplementation("org.json:json:20240303")
  testImplementation(kotlin("test"))
}

kotlin { jvmToolchain(17) }

tasks.test { useJUnitPlatform() }
