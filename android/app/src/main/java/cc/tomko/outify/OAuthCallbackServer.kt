package cc.tomko.outify

import java.io.BufferedReader
import java.io.InputStreamReader
import java.net.ServerSocket

class OAuthCallbackServer(
    private val port: Int,
    private val onCode: (code: String, state: String) -> Unit,
) {
    @Volatile private var running = false
    private var socket: ServerSocket? = null

    fun start() {
        running = true
        Thread {
            try {
                socket = ServerSocket(port)
                socket?.soTimeout = 120_000 // wait up to 2 min for the login
                while (running) {
                    val client = socket?.accept() ?: break
                    handleClient(client)
                    break // one login per server lifetime
                }
            } catch (e: Exception) {
                if (running) e.printStackTrace()
            } finally {
                stop()
            }
        }.apply { isDaemon = true; start() }
    }

    private fun handleClient(client: java.net.Socket) {
        client.use { c ->
            c.soTimeout = 10_000
            val reader = BufferedReader(
                InputStreamReader(c.getInputStream(), Charsets.UTF_8)
            )
            val requestLine = reader.readLine() ?: return
            // "GET /login?code=...&state=... HTTP/1.1"
            val uri = requestLine.split(" ").getOrNull(1) ?: return
            val code = uri.substringAfter("code=", "").substringBefore("&")
            val state = uri.substringAfter("state=", "").substringBefore("&")

            val body = "<html><body style='font-family:sans-serif'>" +
                    "<h2>Login complete ✔</h2>" +
                    "<p>You can close this page and return to ZenMusic.</p></body></html>"
            val response = "HTTP/1.1 200 OK\r\n" +
                    "Content-Type: text/html; charset=utf-8\r\n" +
                    "Content-Length: ${body.length}\r\nConnection: close\r\n\r\n$body"
            c.getOutputStream().write(response.toByteArray(Charsets.UTF_8))
            c.getOutputStream().flush()

            if (code.isNotEmpty()) onCode(code, state)
        }
    }

    fun stop() {
        running = false
        try { socket?.close() } catch (_: Exception) {}
        socket = null
    }
}