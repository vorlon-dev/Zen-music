allprojects {
    repositories {
        google()
        mavenCentral()
        // Required for yt_extractor to resolve NewPipeExtractor
        maven { url = uri("https://jitpack.io") }
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}

// ─────────────────────────────────────────────
// Force Java 17 + Kotlin 17 on every plugin.
// Must be registered BEFORE evaluationDependsOn(":app").
// ─────────────────────────────────────────────
subprojects {
    afterEvaluate {
        extensions.findByType(com.android.build.gradle.BaseExtension::class.java)?.apply {
            compileOptions {
                sourceCompatibility = JavaVersion.VERSION_17
                targetCompatibility = JavaVersion.VERSION_17
            }
        }
    }
    tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
        compilerOptions {
            jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
        }
    }
}
subprojects {
    afterEvaluate {
        if (name == "flutter_discord_rpc") {
            extensions.findByType(com.android.build.gradle.BaseExtension::class.java)?.apply {
                compileSdkVersion(37)
            }
        }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

// ─────────────────────────────────────────────
// SP-44 (rev 3) — Android: skip cargokit (Rust) native builds.
//
// flutter_discord_rpc 1.1.0 (Discord Rich Presence — a desktop-only
// feature) declares Android in its plugin pubspec, so every Android
// build tries to compile its Rust library through the vendored cargokit
// gradle script. That script calls Project.exec(), an API Gradle 9.0
// removed (this project ships Gradle 9.3.1 / AGP 9.1.0), and every
// Android build died on:
//   ':flutter_discord_rpc:cargokitCargoBuild...'
//   "Could not find method exec() for arguments [...]"
// Discord presence cannot work on a phone — it talks to the desktop
// Discord client over a local IPC pipe — so the library is dead weight
// in an APK. DiscordPresenceBridge.init() also returns before touching
// the plugin on Android (non-desktop platforms no-op by design), so
// nothing ever loads a missing .so. Windows/Linux builds are untouched:
// they go through cargokit's CMake path, not this gradle script.
//
// rev 3: rev 1 (tasks.whenTaskAdded { task -> ... }) and rev 2
// (tasks.withType<Task>().configureEach { task -> ... }) both fail to
// compile under Gradle 9.3.1's Kotlin DSL — its lambda/overload
// inference rejects an explicitly named lambda parameter in both
// shapes. rev 3 avoids lambda inference entirely: a fully typed
// anonymous object implementing org.gradle.api.Action, registered via
// tasks.all(...) — the same "run for every task as it is added"
// semantics as whenTaskAdded, valid on every Gradle version. Delete
// this block only if a future cargokit plugin must build natively on
// Android.
// ─────────────────────────────────────────────
subprojects {
    tasks.all(object : org.gradle.api.Action<org.gradle.api.Task> {
        override fun execute(task: org.gradle.api.Task) {
            if (task.name.startsWith("cargokitCargoBuild")) {
                task.setEnabled(false)
            }
        }
    })
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}