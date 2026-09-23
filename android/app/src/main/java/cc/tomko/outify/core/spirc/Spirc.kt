package cc.tomko.outify.core.spirc

import cc.tomko.outify.playback.model.Bitrate

interface SpircInitializationCallback {
    fun initialized()
    fun failed()
}

interface SpircBufferCallback {
    fun started()
    fun stopped()
}

interface SpircDeviceCallback {
    fun becameActive()
    fun becameInactive()
    fun volumeChanged(volume: Int)
}

object Spirc {
    @JvmStatic
    external fun initializeSpirc(
        callback: SpircInitializationCallback,
        gapless: Boolean,
        normalisation: Boolean,
        bitrateSpeed: Int = Bitrate.KBPS320.getSpeed(),
        crossfadeMillis: Int = 5_000,
        deviceName: String = "ZenMusic"
    ): Boolean

    @JvmStatic
    external fun shutdown()

    @JvmStatic
    external fun unregisterBufferCallback()

    @JvmStatic
    external fun unregisterDeviceCallback()

    @JvmStatic
    external fun bufferCallback(callback: SpircBufferCallback): Boolean

    @JvmStatic
    external fun deviceCallback(callback: SpircDeviceCallback): Boolean

    @JvmStatic
    external fun load(context: String? = null, playingTrackUri: String? = null): Boolean

    @JvmStatic
    external fun localLoad(uri: String): Boolean

    @JvmStatic
    external fun shuffleLoad(uri: String? = null): Boolean

    @JvmStatic
    external fun addToQueue(spotifyUri: String?): Boolean

    @JvmStatic
    external fun setQueue(uris: Array<String>, playingTrackUri: String?): Boolean

    @JvmStatic
    external fun activate(): Boolean

    @JvmStatic
    external fun transfer(): Boolean

    @JvmStatic
    external fun setVolume(volume: Int): Boolean

    @JvmStatic
    external fun seekTo(positionMs: Long): Boolean

    @JvmStatic
    external fun shuffle(enabled: Boolean): Boolean

    @JvmStatic
    external fun repeat(repeat: Boolean, repeatTrack: Boolean): Boolean

    @JvmStatic
    external fun playerPlay(): Boolean

    @JvmStatic
    external fun playerPause(): Boolean

    @JvmStatic
    external fun playerPlayPause(): Boolean

    @JvmStatic
    external fun playerNext(): Boolean

    @JvmStatic
    external fun playerPrevious(): Boolean

    @JvmStatic
    external fun previousTracks(): String

    @JvmStatic
    external fun nextTracks(): String
}