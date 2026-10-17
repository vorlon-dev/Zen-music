# ─────────────────────────────────────────────
# yt_downloader / ffmpeg_kit_flutter_new ProGuard rules
# ─────────────────────────────────────────────
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

# (Optional but recommended) Standard FFmpegKit rules if you ever use the official package
# -keep class com.arthenica.ffmpegkit.** { *; }

# ─────────────────────────────────────────────
# Flutter / Just Audio / MediaKit rules
# ─────────────────────────────────────────────
# Keep Just Audio and Android Audio Service
-keep class com.ryanheise.just_audio.** { *; }
-keep class com.ryanheise.audioservice.** { *; }

# Keep native DSP / Innertube bridges
-keep class com.zen.music.zenmusic.** { *; }

# Prevent R8 from stripping native C++ methods
-keepclasseswithmembernames class * {
    native <methods>;
}