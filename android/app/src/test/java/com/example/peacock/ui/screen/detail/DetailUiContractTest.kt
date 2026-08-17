package com.example.peacock.ui.screen.detail

import org.junit.Assert.assertEquals
import org.junit.Test

class DetailUiContractTest {
    @Test
    fun detailTabs_matchWebInformationArchitecture() {
        assertEquals(
            listOf(DetailTab.CONSOLE, DetailTab.CHARACTERS, DetailTab.HELP, DetailTab.EFFECTS),
            DetailTab.entries,
        )
    }

    @Test
    fun strobePeriod_matchesFirmwareUiRange() {
        assertEquals(250, strobePeriodMs(0))
        assertEquals(139, strobePeriodMs(128))
        assertEquals(30, strobePeriodMs(255))
        assertEquals(250, strobePeriodMs(-1))
        assertEquals(30, strobePeriodMs(256))
    }
}
