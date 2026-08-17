package com.example.peacock.feature.ota

import com.example.peacock.protocol.ModbusCodec
import org.junit.Assert.assertEquals
import org.junit.Test

class OtaProtocolTest {
    @Test
    fun prepareRequestUsesFirmwareNonceTlv() {
        val nonce = ByteArray(16) { it.toByte() }
        val frame = OtaProtocol.prepareRequest(1, nonce)

        assertEquals(1, frame[0].toInt() and 0xff)
        assertEquals(0x41, frame[1].toInt() and 0xff)
        assertEquals(19, frame[2].toInt() and 0xff)
        assertEquals(OtaProtocol.commandPrepare, frame[3].toInt() and 0xff)
        assertEquals(0x01, frame[4].toInt() and 0xff)
        assertEquals(16, frame[5].toInt() and 0xff)
        assertEquals(nonce.toList(), frame.copyOfRange(6, 22).toList())
        assertEquals(true, ModbusCodec.validateCrc(frame))
    }

    @Test
    fun parsesGetInfoTlvResponse() {
        val payload = byteArrayOf(
            1, 0,
            1, 1, 1,
            2, 1, 2,
            3, 2, 'j'.code.toByte(), 'a'.code.toByte(),
            4, 1, 1,
            5, 1, 15,
            6, 4, 151.toByte(), 0, 0, 0,
            7, 5, '1'.code.toByte(), '.'.code.toByte(), '5'.code.toByte(), '.'.code.toByte(), '1'.code.toByte(),
        )
        val info = OtaProtocol.parseInfo(ModbusCodec.buildVendor(1, payload))
        assertEquals(1, info.protocolVersion)
        assertEquals(2, info.layoutVersion)
        assertEquals("ja", info.variant)
        assertEquals("1.5.1", info.firmwareVersion)
        assertEquals(151, info.secureVersion)
    }

    @Test
    fun parsesPrepareResponse() {
        val bssid = byteArrayOf(0x10, 0x20, 0x30, 0x40, 0x50, 0x60)
        val token = ByteArray(16) { it.toByte() }
        val ssid = "Maurya-493C".toByteArray()
        val payload = byteArrayOf(2, 0, 0x10, ssid.size.toByte()) + ssid +
            byteArrayOf(0x11, 6) + bssid +
            byteArrayOf(0x12, 16) + token +
            byteArrayOf(0x13, 4, 0x2c, 0x01, 0, 0)
        val session = OtaProtocol.parseWifiSession(ModbusCodec.buildVendor(1, payload))
        assertEquals("Maurya-493C", session.ssid)
        assertEquals("10:20:30:40:50:60", session.bssid)
        assertEquals(300, session.timeoutSeconds)
        assertEquals("000102030405060708090a0b0c0d0e0f", session.tokenHex)
    }

    @Test
    fun buildsBoundedBleOtaFrames() {
        val begin = OtaProtocol.bleBeginRequest(1, 987_136, "00".repeat(32))
        assertEquals(38, begin[2].toInt() and 0xff)
        assertEquals(OtaProtocol.commandBleBegin, begin[3].toInt() and 0xff)
        assertEquals(43, begin.size)
        assertEquals(true, ModbusCodec.validateCrc(begin))

        val data = OtaProtocol.bleDataRequest(
            1,
            0,
            ByteArray(OtaProtocol.bleChunkBytes) { it.toByte() },
        )
        assertEquals(128, data.size)
        assertEquals(true, ModbusCodec.validateCrc(data))
    }

    @Test
    fun parsesBleAckAndVerificationStatus() {
        val ackPayload = byteArrayOf(
            OtaProtocol.commandBleData.toByte(), 0,
            0x20, 4, 0xea.toByte(), 0, 0, 0,
        )
        assertEquals(
            234,
            OtaProtocol.parseBleDataAck(ModbusCodec.buildVendor(1, ackPayload)),
        )

        val statusPayload = byteArrayOf(
            OtaProtocol.commandBleStatus.toByte(), 0,
            0x21, 1, OtaProtocol.stateVerified.toByte(),
            0x22, 4, 0, 0x10, 0, 0,
            0x23, 4, 0, 0x10, 0, 0,
            0x24, 4, 0, 0, 0, 0,
        )
        val status = OtaProtocol.parseBleStatus(
            ModbusCodec.buildVendor(1, statusPayload),
        )
        assertEquals(OtaProtocol.stateVerified, status.state)
        assertEquals(4096, status.receivedBytes)
        assertEquals(4096, status.expectedBytes)
        assertEquals(0, status.errorCode)
    }
}
