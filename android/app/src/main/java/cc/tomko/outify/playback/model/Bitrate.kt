package cc.tomko.outify.playback.model

enum class Bitrate(val kbps: Int) {
    KBPS96(96),
    KBPS160(160),
    KBPS320(320);

    fun getSpeed(): Int = kbps
}