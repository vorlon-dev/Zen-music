package com.zen.music.zenmusic.dsp.audio

import androidx.media3.common.C
import androidx.media3.common.audio.AudioProcessor
import com.zen.music.zenmusic.dsp.core.models.FilterType
import com.zen.music.zenmusic.dsp.core.models.ParametricEQ
import com.zen.music.zenmusic.dsp.core.models.ParametricEQBand
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

class CustomEqualizerAudioProcessorTest {

  private val stereoPcm =
    AudioProcessor.AudioFormat(44100, 2, C.ENCODING_PCM_16BIT)

  private val eq = ParametricEQ(
    preamp = -3.0,
    bands = listOf(ParametricEQBand(1000.0, 4.0, 0.7, FilterType.PK)),
  )

  @Test
  fun `profile applied before configure is stored pending`() {
    val p = CustomEqualizerAudioProcessor()
    p.applyProfile(eq)
    assertFalse("not configured yet — must stay pending", p.isEnabled())
  }

  @Test
  fun `pending profile activates on configure`() {
    val p = CustomEqualizerAudioProcessor()
    p.applyProfile(eq)
    p.configure(stereoPcm)
    assertTrue(p.isEnabled())
  }

  @Test
  fun `disable clears the profile`() {
    val p = CustomEqualizerAudioProcessor()
    p.applyProfile(eq)
    p.configure(stereoPcm)
    assertTrue(p.isEnabled())
    p.disable()
    assertFalse(p.isEnabled())
  }

  @Test
  fun `configure rejects multichannel formats`() {
    val p = CustomEqualizerAudioProcessor()
    try {
      p.configure(AudioProcessor.AudioFormat(48000, 6, C.ENCODING_PCM_16BIT))
      fail("expected UnhandledAudioFormatException")
    } catch (_: AudioProcessor.UnhandledAudioFormatException) {
      // expected
    }
  }
}