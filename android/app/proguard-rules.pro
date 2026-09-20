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