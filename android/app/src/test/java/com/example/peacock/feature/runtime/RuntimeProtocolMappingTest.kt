package com.example.peacock.feature.runtime

import com.example.peacock.protocol.RegisterMap
import org.junit.Assert.assertEquals
import org.junit.Test

class RuntimeProtocolMappingTest {
    @Test
    fun `mapSnapshot maps full global and group registers`() {
        val globalValues = MutableList(RegisterMap.CONFIG_REG_COUNT) { 0 }
        globalValues[0] = 4
        globalValues[1] = 100
        globalValues[2] = 220
        globalValues[3] = 255
        globalValues[4] = 176
        globalValues[5] = 240
        globalValues[10] = 1
        globalValues[11] = 7
        globalValues[12] = 11
        globalValues[13] = 12
        globalValues[14] = 13
        globalValues[15] = 14
        globalValues[16] = 0xFE0C
        globalValues[17] = 3300

        val groupValues = mutableListOf<Int>()
        repeat(RegisterMap.GROUP_COUNT) { index ->
            groupValues += listOf(index + 1, index * 30, 200 + index, 150 + index, 100 + index)
        }

        val snapshot = RuntimeMapper.mapSnapshot(globalValues, groupValues)

        assertEquals(4, snapshot.global.sceneMode)
        assertEquals(100, snapshot.global.sceneParam)
        assertEquals(220, snapshot.global.globalBrightness)
        assertEquals(255, snapshot.global.gainR)
        assertEquals(176, snapshot.global.gainG)
        assertEquals(240, snapshot.global.gainB)
        assertEquals(7, snapshot.global.deviceAddr)
        assertEquals(1, snapshot.global.saveState)
        assertEquals(-500, snapshot.diagnostics.tempCx100)
        assertEquals(3300, snapshot.diagnostics.vddaMv)
        assertEquals(7, snapshot.groups.size)
        assertEquals(1, snapshot.groups.first().innerMode)
        assertEquals(180, snapshot.groups.last().hue)
        assertEquals(206, snapshot.groups.last().sat)
        assertEquals(156, snapshot.groups.last().value)
        assertEquals(106, snapshot.groups.last().innerParam)
    }

    @Test
    fun `allGroupsPayload flattens all 35 registers in order`() {
        val groups = List(RegisterMap.GROUP_COUNT) { index ->
            GroupState(
                innerMode = (index % 4) + 1,
                hue = index,
                sat = 10 + index,
                value = 20 + index,
                innerParam = 30 + index,
            )
        }

        val payload = RuntimePayloads.allGroupsPayload(groups)

        assertEquals(RegisterMap.GROUP_REG_COUNT, payload.size)
        assertEquals(listOf(1, 0, 10, 20, 30), payload.take(5))
        assertEquals(listOf(3, 6, 16, 26, 36), payload.takeLast(5))
    }

    @Test
    fun `groupWriteBatches keep all seven groups in one BLE-safe write`() {
        val groups = List(RegisterMap.GROUP_COUNT) { index ->
            GroupState(
                innerMode = 1,
                hue = index * 10,
                sat = 200,
                value = 255,
                innerParam = 100 + index,
            )
        }

        val batches = RuntimeTransportBatcher.buildGroupWriteBatches(groups)

        assertEquals(61, RuntimeTransportBatcher.maxReadRegistersPerRequest)
        assertEquals(1, batches.size)
        assertEquals(RegisterMap.GROUP_BASE, batches[0].startRegister)
        assertEquals(RegisterMap.GROUP_REG_COUNT, batches[0].values.size)
    }
}
