// ZenMusic · vorlon-dev

package com.zen.music.zenmusic

import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import java.io.BufferedReader
import java.io.InputStreamReader

/**
 * Streams this app's own logcat output to Dart over "zen/diag_logs".
 * Android permits an app to read its OWN log lines at runtime (its PID
 * only) — this is the mechanism log-viewer apps use, no permission
 * needed. Lines are parsed from `logcat -v brief` format and shipped as
 * {level, tag, message} maps. Dart prints arrive here too (as the
 * flutter tag) but the Dart side filters those, since it already
 * captured them in-zone — no duplicates.
 */
object DiagnosticsLogCapture {
    @Volatile private var process: Process? = null
    @Volatile private var thread: Thread? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    fun register(flutterEngine: FlutterEngine) {
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "zen/diag_logs")
            .setStreamHandler(object : EventChannel.StreamHandler {
                @Volatile private var sink: EventChannel.EventSink? = null

                override fun onListen(args: Any?, events: EventChannel.EventSink?) {
                    stop()
                    sink = events
                    val pid = android.os.Process.myPid()
                    thread = Thread {
                        try {
                            val proc = ProcessBuilder(
                                "logcat", "-v", "brief", "--pid=$pid",
                            ).redirectErrorStream(true).start()
                            process = proc
                            val reader = BufferedReader(InputStreamReader(proc.inputStream))
                            while (true) {
                                val line = reader.readLine() ?: break
                                val parsed = parseBrief(line) ?: continue
                                // Skip Dart-print lines: the zone capture in
                                // Dart already stores them (no duplicates).
                                if (parsed.second == "flutter") continue
                                val s = sink
                                if (s != null) {
                                    mainHandler.post {
                                        s.success(
                                            mapOf(
                                                "level" to parsed.first,
                                                "tag" to parsed.second,
                                                "message" to parsed.third,
                                            )
                                        )
                                    }
                                }
                            }
                        } catch (_: Throwable) {
                            // logcat blocked/unavailable on some OEMs: the
                            // stream just ends; Dart keeps its zone logs.
                        }
                    }.apply {
                        isDaemon = true
                        name = "DiagLogcat"
                        start()
                    }
                }

                override fun onCancel(args: Any?) {
                    sink = null
                    stop()
                }
            })
    }

    private fun stop() {
        try {
            process?.destroy()
        } catch (_: Throwable) {}
        process = null
        thread?.interrupt()
        thread = null
    }

    /// brief format: "I/tag( 1234): message" (space in parens varies).
    private fun parseBrief(line: String): Triple<String, String, String>? {
        if (line.length < 8) return null
        val level = line[0]
        if (level !in "VDIWEF") return null
        val slash = line.indexOf('/')
        if (slash != 1) return null
        val open = line.indexOf('(', slash)
        val close = line.indexOf(')', open)
        if (open <= slash || close <= open) return null
        val sep = line.indexOf(": ", close)
        if (sep <= close) return null
        val tag = line.substring(slash + 1, open).trim()
        val msg = line.substring(sep + 2)
        if (tag.isEmpty()) return null
        return Triple(level.toString(), tag, msg)
    }
}
