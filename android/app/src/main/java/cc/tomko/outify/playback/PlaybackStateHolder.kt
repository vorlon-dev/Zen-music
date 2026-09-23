package cc.tomko.outify.playback

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow

data class PlaybackState(val playbackSpeed: Float = 1f)

object PlaybackStateHolder {
    private val _state = MutableStateFlow(PlaybackState(playbackSpeed = 1f))
    val state: StateFlow<PlaybackState> = _state
}