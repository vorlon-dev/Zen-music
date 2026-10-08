plugins {
  id("com.android.library")
  id("org.jetbrains.kotlin.android")
  id("org.jetbrains.kotlin.plugin.serialization")
}

android {
  namespace = "com.music.innertube"
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
  implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.9.0")

  // Same ktor pin set as the app module — one version across the classpath.
  implementation("io.ktor:ktor-client-core:3.1.3")
  implementation("io.ktor:ktor-client-okhttp:3.1.3")
  implementation("io.ktor:ktor-client-content-negotiation:3.1.3")
  implementation("io.ktor:ktor-serialization-kotlinx-json:3.1.3")
  implementation("io.ktor:ktor-client-encoding:3.1.3")

  // Signature/throttling decipher + po-token provider interfaces used by
  // NewPipe.kt and PoTokenGenerator.kt. Version flagged as unverified against
  // the source project's version catalog; bump if the compile names a missing
  // symbol.
  implementation("com.github.teamnewpipe:NewPipeExtractor:v0.26.4") {
    exclude(group = "com.google.protobuf", module = "protobuf-java")
  }
  implementation("com.github.TeamNewPipe:nanojson:c7a6c1c08d16b6d5ecded34758e6415e07be2166")

  coreLibraryDesugaring("com.android.tools:desugar_jdk_libs_nio:2.1.5")
  testImplementation("junit:junit:4.13.2")
}