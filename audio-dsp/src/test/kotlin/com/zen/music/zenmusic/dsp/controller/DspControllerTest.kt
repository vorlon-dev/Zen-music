package com.zen.music.zenmusic.dsp.controller

import com.zen.music.zenmusic.dsp.core.models.FilterType
import com.zen.music.zenmusic.dsp.core.models.ParametricEQBand
import com.zen.music.zenmusic.dsp.core.models.SavedEQProfile
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class DspControllerTest {

  private fun profile() = SavedEQProfile(
    id = "t1",
    name = "Test profile",
    bands = listOf(ParametricEQBand(1000.0, 4.0, 0.7, FilterType.PK)),
    preamp = -2.0,
    isCustom = true,
  )

  @Test
  fun `createProcessors registers the trio and release removes it`() {
    val c = DspControllerImpl()
    val p = c.createProcessors()
    assertEquals(3, c.getAudioProcessors().size)
    c.releaseProcessors(p)
    assertTrue(c.getAudioProcessors().isEmpty())
  }

  @Test
  fun `applyProfile with no processors stores state and succeeds`() {
    val c = DspControllerImpl()
    val r = c.applyProfile(profile())
    assertTrue(r.isSuccess)
    assertTrue(c.isEnabled.value)
    assertEquals("t1", c.activeProfile.value?.id)
  }

  @Test
  fun `late-added processor receives the pending profile`() {
    val c = DspControllerImpl()
    c.applyProfile(profile())
    val p = c.createProcessors()
    assertTrue("pending profile must apply on registration", p.equalizer.isEnabled())
    c.releaseProcessors(p)
  }

  @Test
  fun `disable clears state and future processors start disabled`() {
    val c = DspControllerImpl()
    c.applyProfile(profile())
    c.disable()
    assertFalse(c.isEnabled.value)
    assertNull(c.activeProfile.value)
    val p = c.createProcessors()
    assertFalse(p.equalizer.isEnabled())
    c.releaseProcessors(p)
  }

  @Test
  fun `stereo width clamps and reaches new processors`() {
    val c = DspControllerImpl()
    c.setStereoWidth(5f)
    assertEquals(2f, c.stereoWidth.value, 0.001f)
    val p = c.createProcessors()
    assertEquals(2f, p.stereoWidener.width, 0.001f)
    c.releaseProcessors(p)
  }
}