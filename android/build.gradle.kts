// ZenMusic · vorlon-dev

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
