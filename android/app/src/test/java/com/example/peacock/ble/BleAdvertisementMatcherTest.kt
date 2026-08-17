package com.example.peacock.ble

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.UUID

class BleAdvertisementMatcherTest {
    @Test
    fun acceptsMauryaNameWhenPhoneOmitsAdvertisedService() {
        assertTrue(
            BleAdvertisementMatcher.matches(
                filterMaurya = true,
                name = "Maurya-2601",
                advertisedServices = emptyList(),
            ),
        )
    }

    @Test
    fun acceptsLegacyFfe0Peripheral() {
        assertTrue(
            BleAdvertisementMatcher.matches(
                filterMaurya = true,
                name = null,
                advertisedServices = listOf(UUID_FFE0),
            ),
        )
    }

    @Test
    fun rejectsUnrelatedPeripheralWhileFilterIsEnabled() {
        assertFalse(
            BleAdvertisementMatcher.matches(
                filterMaurya = true,
                name = "midea",
                advertisedServices = listOf(UUID.randomUUID()),
            ),
        )
    }

    @Test
    fun acceptsAllPeripheralsWhenFilterIsDisabled() {
        assertTrue(
            BleAdvertisementMatcher.matches(
                filterMaurya = false,
                name = "midea",
                advertisedServices = emptyList(),
            ),
        )
    }
}
