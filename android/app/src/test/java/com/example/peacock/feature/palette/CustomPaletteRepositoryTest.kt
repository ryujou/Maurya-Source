package com.example.peacock.feature.palette

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class CustomPaletteRepositoryTest {
    @Test
    fun validatesExtendedWebPDimensions() {
        val header = ByteArray(32)
        "RIFF".toByteArray().copyInto(header, 0)
        "WEBP".toByteArray().copyInto(header, 8)
        "VP8X".toByteArray().copyInto(header, 12)
        header[24] = 95
        header[27] = 95
        assertTrue(CustomPaletteRepository.isWebP96(header))
        header[24] = 96
        assertFalse(CustomPaletteRepository.isWebP96(header))
    }

    @Test
    fun sha256IsStable() {
        assertTrue(CustomPaletteRepository.sha256("Maurya".toByteArray()).matches(Regex("[0-9a-f]{64}")))
        assertTrue(CustomPaletteRepository.sha256("Maurya".toByteArray()) ==
            CustomPaletteRepository.sha256("Maurya".toByteArray()))
    }
}
