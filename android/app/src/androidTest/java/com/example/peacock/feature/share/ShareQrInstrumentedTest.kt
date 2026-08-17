package com.example.peacock.feature.share

import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class ShareQrInstrumentedTest {
    @Test
    fun temporaryShareQrUsesMemoryBoundedBitmap() {
        val bitmap = ShareQr.create("https://xtbang.top/maurya/s/K8F3Q7D2PX")
        try {
            assertEquals(512, ShareQr.SIZE)
            assertEquals(ShareQr.SIZE, bitmap.width)
            assertEquals(ShareQr.SIZE, bitmap.height)
        } finally {
            bitmap.recycle()
        }
    }
}
