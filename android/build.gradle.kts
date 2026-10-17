allprojects {
    repositories {
        google()
        mavenCentral()
        // ▼▼▼ ADD THIS LINE ▼▼▼
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

subprojects {
    project.evaluationDependsOn(":app")
}

// ─────────────────────────────────────────────
// ✅ Force JVM 17 consistency across ALL subprojects.
// ─────────────────────────────────────────────
subprojects {
    tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
        compilerOptions {
            jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
        }
    }

    tasks.withType<JavaCompile>().configureEach {
        sourceCompatibility = JavaVersion.VERSION_17.toString()
        targetCompatibility = JavaVersion.VERSION_17.toString()
    }
}

// ─────────────────────────────────────────────
// ✅ FIX for flutter_inappwebview_android ProGuard error
// AGP 9.0+ no longer accepts the legacy 'proguard-android.txt'.
// This forces the plugin to use the optimized file instead.
// ─────────────────────────────────────────────
subprojects {
    afterEvaluate {
        if (name == "flutter_inappwebview_android") {
            val androidExt = extensions.findByName("android") as? com.android.build.gradle.BaseExtension
            androidExt?.buildTypes?.getByName("release")?.apply {
                // Override the legacy proguard file with the new optimized one
                proguardFiles(
                    androidExt.getDefaultProguardFile("proguard-android-optimize.txt"),
                    "proguard-rules.pro"
                )
                // Optional fallback: If it still fails, you can uncomment the line below:
                // isMinifyEnabled = false
            }
        }
    }
}

gradle.projectsEvaluated {
    val flutterJsProject = subprojects.find { it.name == "flutter_js" }
    flutterJsProject?.tasks?.withType<JavaCompile>()?.configureEach {
        sourceCompatibility = JavaVersion.VERSION_17.toString()
        targetCompatibility = JavaVersion.VERSION_17.toString()
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}