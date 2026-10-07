package com.zen.music.zenmusic.dsp.audio

import androidx.media3.common.C
import androidx.media3.common.audio.AudioProcessor
import java.nio.ByteBuffer
import java.nio.ByteOrder
import org.junit.Assert.assertEquals
import org.junit.Test

class StereoWidenerAudioProcessorTest {

  @Test
  fun `width clamps to the 1..2 range`() {
    val p = StereoWidenerAudioProcessor()
    p.width = 5f
    assertEquals(2f, p.width, 0.001f)
    p.width = 0.2f
    assertEquals(1f, p.width, 0.001f)
  }

  @Test
  fun `mid-side widening scales the side component`() {
    val p = StereoWidenerAudioProcessor()
    p.width = 2f
    p.configure(AudioProcessor.AudioFormat(44100, 2, C.ENCODING_PCM_16BIT))

    // Hard-panned pair: mid = 0, side = (L - R)/2 = 1000 → at width 2
    // the recombined frame is (+2000, -2000).
    val input = ByteBuffer
      .allocateDirect(4)
      .order(ByteOrder.nativeOrder())
    input.putShort(1000).putShort(-1000)
    input.flip()

    p.queueInput(input)
    val out = p.getOutput()
    assertEquals(4, out.remaining())
    assertEquals(2000, out.short.toInt())
    assertEquals(-2000, out.short.toInt())
  }

  @Test
  fun `mono input passes through unchanged`() {
    val p = StereoWidenerAudioProcessor()
    p.width = 2f
    p.configure(AudioProcessor.AudioFormat(44100, 1, C.ENCODING_PCM_16BIT))

    val input = ByteBuffer
      .allocateDirect(2)
      .order(ByteOrder.nativeOrder())
    input.putShort(1234)
    input.flip()

    p.queueInput(input)
    val out = p.getOutput()
    assertEquals(2, out.remaining())
    assertEquals(1234, out.short.toInt())
  }
}