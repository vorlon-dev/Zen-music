package com.zen.music.zenmusic.dsp.core.parser

import com.zen.music.zenmusic.dsp.core.models.FilterType
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class ParametricEQParserTest {

    private val autoEqText = """
      Notes: AutoEq preset for testing
      Preamp: -3.5 dB
      Filter 1: ON PK Fc 1000 Hz Gain 3.0 dB Q 0.70
      Filter 2: ON LSC Fc 105 Hz Gain 2.0 dB Q 0.70
      Filter 3: ON HSC Fc 8000 Hz Gain -2.5 dB Q 0.70
  """.trimIndent()

    @Test
    fun `parses preamp bands and metadata`() {
        val eq = ParametricEQParser.parseText(autoEqText)
        assertEquals(-3.5, eq.preamp, 1e-9)
        assertEquals(3, eq.bands.size)
        assertEquals(FilterType.PK, eq.bands[0].filterType)
        assertEquals(1000.0, eq.bands[0].frequency, 1e-9)
        assertEquals(3.0, eq.bands[0].gain, 1e-9)
        assertEquals(0.70, eq.bands[0].q, 1e-9)
        assertEquals(FilterType.LSC, eq.bands[1].filterType)
        assertEquals(FilterType.HSC, eq.bands[2].filterType)
        assertEquals("AutoEq preset for testing", eq.metadata["Notes"])
    }

    @Test
    fun `skips OFF filter lines`() {
        val text = "Preamp: 0 dB\nFilter 1: OFF PK Fc 500 Hz Gain 3 dB Q 1.0\n"
        val eq = ParametricEQParser.parseText(text)
        assertEquals(0, eq.bands.size)
    }

    @Test
    fun `validate accepts a sane profile`() {
        val eq = ParametricEQParser.parseText(autoEqText)
        assertTrue(ParametricEQParser.validate(eq).isEmpty())
    }

    @Test
    fun `validate rejects empty band list`() {
        val eq = ParametricEQParser.parseText("Preamp: 0 dB\n")
        assertTrue(ParametricEQParser.validate(eq).isNotEmpty())
    }

    @Test
    fun `file format round-trip keeps values`() {
        val eq = ParametricEQParser.parseText(autoEqText)
        val reparsed = ParametricEQParser.parseText(ParametricEQParser.toFileFormat(eq))
        assertEquals(eq.bands.size, reparsed.bands.size)
        assertEquals(eq.bands[0].frequency, reparsed.bands[0].frequency, 1e-9)
        assertEquals(eq.bands[2].gain, reparsed.bands[2].gain, 1e-9)
    }
}