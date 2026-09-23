package cc.tomko.outify.playback.callbacks

interface PlayerEventCallback {
    fun onTrackChange(spotify_uri: String, json: String)
    fun onPositionUpdate(spotify_uri: String, position_ms: Long, json: String)
    fun onPlayingStatus(playing: Boolean)
}