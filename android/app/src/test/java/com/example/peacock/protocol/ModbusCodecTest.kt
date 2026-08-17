package com.example.peacock.protocol

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Test

class ModbusCodecTest {
    @Test
    fun `buildWriteMultiple encodes 35-register payload`() {
        val values = (1..35).toList()

        val frame = ModbusCodec.buildWriteMultiple(
            deviceAddr = 0x01,
            startReg = RegisterMap.GROUP_BASE,
            values = values,
        )

        assertEquals(1, frame[0].toInt() and 0xFF)
        assertEquals(0x10, frame[1].toInt() and 0xFF)
        assertEquals(0x00, frame[2].toInt() and 0xFF)
        assertEquals(0x20, frame[3].toInt() and 0xFF)
        assertEquals(0x00, frame[4].toInt() and 0xFF)
        assertEquals(35, frame[5].toInt() and 0xFF)
        assertEquals(70, frame[6].toInt() and 0xFF)
        assertArrayEquals(byteArrayOf(0x00, 0x01, 0x00, 0x02), frame.sliceArray(7..10))
    }

    @Test
    fun `parseResponse decodes exception frame`() {
        val payload = byteArrayOf(0x01, 0x83.toByte(), 0x03)
        val crc = ModbusCodec.crc16Modbus(payload)
        val frame = payload + byteArrayOf((crc and 0xFF).toByte(), ((crc ushr 8) and 0xFF).toByte())

        val response = ModbusCodec.parseResponse(frame) as ExceptionResponse

        assertEquals(0x83, response.function)
        assertEquals(0x03, response.code)
        assertEquals("Illegal value", response.message)
    }
}
