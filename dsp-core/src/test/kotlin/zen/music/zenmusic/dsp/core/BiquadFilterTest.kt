package com.zen.music.zenmusic.dsp.core

import com.zen.music.zenmusic.dsp.core.models.FilterType
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.abs
import kotlin.math.pow

class BiquadFilterTest {

  @Test
  fun `zero-gain peaking filter is unity at every frequency`() {
    val filter = BiquadFilter(44100, 1000.0, 0.0, 0.70, FilterType.PK)
    for (f in listOf(20.0, 100.0, 1000.0, 5000.0, 15000.0)) {
      assertTrue("unity expected at $f Hz", abs(filter.magnitudeAt(f) - 1.0) < 1e-9)
    }
  }

  @Test
  fun `peaking filter reaches design gain at center frequency`() {
    val filter = BiquadFilter(44100, 1000.0, 6.0, 0.70, FilterType.PK)
    val expected = 10.0.pow(6.0 / 20.0) // +6 dB in amplitude
    assertTrue(
      "expected $expected at center, got ${filter.magnitudeAt(1000.0)}",
      abs(filter.magnitudeAt(1000.0) - expected) < 1e-6,
    )
  }

  @Test
  fun `peaking filter leaves distant frequencies near unity`() {
    val filter = BiquadFilter(44100, 1000.0, 6.0, 0.70, FilterType.PK)
    val mag = filter.magnitudeAt(100.0)
    assertTrue("expected near-unity at 100 Hz, got $mag", abs(mag - 1.0) < 0.05)
  }

  @Test
  fun `processSample passes DC through with unity gain`() {
    val filter = BiquadFilter(44100, 1000.0, 0.0, 0.70, FilterType.PK)
    var y = 0.0
    repeat(64) { y = filter.processSample(0.5) }
    assertTrue(abs(y - 0.5) < 1e-9)
  }
}