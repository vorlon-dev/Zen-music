plugins {
  id("org.jetbrains.kotlin.jvm")
  id("org.jetbrains.kotlin.plugin.serialization")
}

kotlin {
  // Aligned with the app module (JVM 17). The original module asked
  // for 21, which requires a JDK 21 toolchain this project does not
  // configure — and the DSP code uses no post-17 APIs.
  jvmToolchain(17)
}

dependencies {
  // Same serialization runtime as the app module — mixing versions
  // on one classpath is a proven runtime hazard (ktor regression).
  implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.9.0")
  testImplementation("junit:junit:4.13.2")
}