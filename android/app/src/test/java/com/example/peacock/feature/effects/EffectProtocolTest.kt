package com.example.peacock.feature.effects

import com.example.peacock.feature.runtime.GroupState
import com.example.peacock.protocol.ModbusCodec
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class EffectProtocolTest {
    @Test
    fun frameCarriesAtomicSevenGroups() {
        val groups = List(7) { i ->
            GroupState(
                innerMode = when (i) {
                    2 -> 2
                    3 -> 4
                    else -> 1
                },
                hue = i * 50,
                sat = 255,
                value = 200,
                innerParam = 100 + i,
            )
        }
        val request = EffectProtocol.frameRequest(1, 0x12345678, 0x3456, groups)
        assertEquals(54, request.size)
        assertEquals(49, request[2].toInt() and 255)
        assertTrue(ModbusCodec.validateCrc(request))
    }
}
