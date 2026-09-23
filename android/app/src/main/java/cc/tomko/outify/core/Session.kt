package cc.tomko.outify.core

interface SessionCallback {
    fun onInitialized()
    fun onShutdown()
    fun onAutoRestart()
}

class Session {
    external fun initializeSession(callback: SessionCallback)
    external fun shutdown(): Boolean
    external fun unregisterSessionCallback()
}