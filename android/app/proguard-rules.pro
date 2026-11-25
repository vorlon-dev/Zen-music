# ZenMusic · vorlon-dev
#
# R8 rules for release builds.
#
# MODE: shrink-only. R8 removes unused classes, methods and resources (this is
# what makes the APK smaller) but never renames or rewrites anything, because
# native code (JNI), Dart (method channels) and reflection reach many
# Java/Kotlin classes BY NAME.
#
# To shrink further later (test every feature first!): delete the two lines in
# section 0 and add narrower -keep rules for what breaks.

# ── 0. Mode ──────────────────────────────────────────────────────────────
# AGP 9 only ships proguard-android-optimize.txt, so these two lines are what
# keep R8 in shrink-only mode.
-dontobfuscate
-dontoptimize

# Generic signatures, annotations and inner-class info (reflection, Kotlin
# serialization, Ktor).
-keepattributes Signature, InnerClasses, EnclosingMethod, *Annotation*

# ── 1. App code (called from native code and method channels) ────────────
-keep class com.zen.music.zenmusic.** { *; }

# JNI bindings anywhere must keep their native methods.
-keepclasseswithmembernames class * {
    native <methods>;
}

# ── 2. Flutter ───────────────────────────────────────────────────────────
-keep class io.flutter.** { *; }
-dontwarn io.flutter.embedding.**

# ── 3. Audio / video plugins ─────────────────────────────────────────────
-keep class com.ryanheise.just_audio.** { *; }
-keep class com.ryanheise.audioservice.** { *; }
-keep class com.ryanheise.audio_session.** { *; }

# media_kit (libmpv bridge) and Dart JNI
-keep class com.alexmercerind.** { *; }
-keep class com.github.dart_lang.jni.** { *; }

# FFmpegKit (native callbacks use these exact names)
-keep class com.arthenica.ffmpegkit.** { *; }
-keep class com.arthemica.ffmpegkit.** { *; }
-keep class com.antonkarpenko.ffmpegkit.FFmpegKitConfig {
    native <methods>;
    void log(long, int, byte[]);
    void statistics(long, int, float, float, long, double, double, double);
    int safOpen(int);
    int safClose(int);
}
-keep class com.antonkarpenko.ffmpegkit.AbiDetect {
    native <methods>;
}

# ONNX Runtime (offline AI remix analyzer): native code calls back by name.
-keep class ai.onnxruntime.** { *; }

# InAppWebView
-keep class com.pichillilorenzo.flutter_inappwebview_android.** { *; }

# ── 4. Innertube / extractor ─────────────────────────────────────────────
-keep class com.music.innertube.** { *; }

# ── 5. Kotlin serialization ──────────────────────────────────────────────
-dontnote kotlinx.serialization.AnnotationsKt
-keepclassmembers class kotlinx.serialization.json.** {
    *** Companion;
}
-keepclasseswithmembers class kotlinx.serialization.json.** {
    kotlinx.serialization.KSerializer serializer(...);
}
-keep,includedescriptorclasses class com.zen.music.zenmusic.**$$serializer { *; }
-keepclassmembers class com.zen.music.zenmusic.** {
    *** Companion;
}
-keepclasseswithmembers class com.zen.music.zenmusic.** {
    kotlinx.serialization.KSerializer serializer(...);
}

# ── 6. Ktor / OkHttp networking ──────────────────────────────────────────
# Ktor discovers its engine through ServiceLoader (META-INF/services).
-keep class io.ktor.** { *; }
-dontwarn io.ktor.**
-dontwarn org.slf4j.**
-dontwarn okhttp3.internal.Util
-dontwarn okhttp3.internal.platform.**
-dontwarn org.conscrypt.**
-dontwarn org.bouncycastle.**
-dontwarn org.openjsse.**

# ── 7. Classes referenced by libraries but not shipped (silences R8) ─────
-dontwarn java.beans.**
-dontwarn javax.annotation.**
-dontwarn javax.lang.model.**
-dontwarn org.mozilla.javascript.**
-dontwarn com.pichillilorenzo.flutter_inappwebview_android.**
-dontwarn com.google.android.play.core.**
-dontwarn com.google.errorprone.annotations.**
-dontwarn org.checkerframework.**
