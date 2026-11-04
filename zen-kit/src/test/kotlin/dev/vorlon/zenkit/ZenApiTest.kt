// ZenMusic · vorlon-dev

package dev.vorlon.zenkit

import com.sun.net.httpserver.HttpServer
import java.net.InetSocketAddress
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertTrue

class ZenApiTest {
  private fun server(handler: (path: String, key: String?) -> Pair<Int, String>): HttpServer {
    val s = HttpServer.create(InetSocketAddress("127.0.0.1", 0), 0)
    s.createContext("/") { ex ->
      val (code, body) = handler(ex.requestURI.toString(), ex.requestHeaders.getFirst("x-api-key"))
      val bytes = body.toByteArray()
      ex.sendResponseHeaders(code, bytes.size.toLong())
      ex.responseBody.use { it.write(bytes) }
    }
    s.start()
    return s
  }

  private fun url(s: HttpServer) = "http://127.0.0.1:${s.address.port}"

  @Test
  fun parsesJioAndYoutubeSongs() {
    val s = server { _, _ ->
      200 to """{"ok":true,"data":{"results":[
        {"id":"j1","source":"jio","title":"A","artist":"X","album":"Alb","image":"i","duration":200,
         "playback":{"type":"direct","url":"https://c/320","streams":[{"quality":"320kbps","url":"https://c/320"}]}},
        {"id":"v1","source":"ytm","title":"B","artist":"Y","album":"","image":"","duration":0,
         "playback":{"type":"youtube","videoId":"v1","embedUrl":"https://www.youtube.com/embed/v1"}}]}}"""
    }
    try {
      val songs = ZenApi(url(s)).searchSongs(Source.JIO, "hello")
      assertEquals(2, songs.size)
      val direct = songs[0].playback as Playback.Direct
      assertEquals("https://c/320", direct.url)
      assertEquals(1, direct.streams.size)
      assertEquals(Source.YTM, songs[1].source)
      assertTrue(songs[1].playback is Playback.YouTube)
    } finally {
      s.stop(0)
    }
  }

  @Test
  fun sendsApiKeyAndReportsErrors() {
    val s = server { _, key ->
      if (key == "secret") 200 to """{"ok":true,"data":{"results":[]}}"""
      else 401 to """{"ok":false,"error":"Missing or invalid API key"}"""
    }
    try {
      assertEquals(0, ZenApi(url(s), "secret").searchSongs(Source.JIO, "a").size)
      val e = assertFailsWith<ZenApiException> { ZenApi(url(s)).searchSongs(Source.JIO, "a") }
      assertEquals(401, e.status)
      assertEquals("Missing or invalid API key", e.message)
    } finally {
      s.stop(0)
    }
  }
}
