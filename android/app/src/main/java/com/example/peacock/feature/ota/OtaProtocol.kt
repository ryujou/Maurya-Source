package com.example.peacock.feature.ota

import com.example.peacock.protocol.ModbusCodec

data class OtaDeviceInfo(
    val protocolVersion: Int,
    val layoutVersion: Int,
    val firmwareVersion: String,
    val variant: String,
    val assetPackVersion: Int,
    val capabilities: Int,
    val secureVersion: Int,
)

data class OtaWifiSession(
    val ssid: String,
    val bssid: String,
    val tokenHex: String,
    val timeoutSeconds: Int,
)

data class OtaBleStatus(
    val state: Int,
    val receivedBytes: Int,
    val expectedBytes: Int,
    val errorCode: Int,
)

object OtaProtocol {
    const val layoutVersion = 2
    const val capabilityBleOta = 0x10
    // v1.6.0 receivers accept complete vendor frames up to 128 bytes.
    // A BLE_DATA frame adds 10 bytes (address/function/length, command,
    // offset and CRC), leaving 118 bytes for firmware data.
    const val bleChunkBytes = 118
    const val commandGetInfo = 1
    const val commandPrepare = 2
    const val commandCancel = 3
    const val commandBleBegin = 0x10
    const val commandBleData = 0x11
    const val commandBleStatus = 0x12
    const val commandBleCommit = 0x14
    const val commandBleCancel = 0x15
    const val stateVerified = 3
    const val stateFailed = 5

    private const val tlvProtocol = 1
    private const val tlvLayout = 2
    private const val tlvVariant = 3
    private const val tlvAssetPack = 4
    private const val tlvCapabilities = 5
    private const val tlvSecureVersion = 6
    private const val tlvVersion = 7
    private const val tlvNonce = 1
    private const val tlvSsid = 16
    private const val tlvBssid = 17
    private const val tlvToken = 18
    private const val tlvTimeout = 19

    fun getInfoRequest(address: Int) =
        ModbusCodec.buildVendor(address, byteArrayOf(commandGetInfo.toByte()))

    fun prepareRequest(address: Int, nonce: ByteArray): ByteArray {
        require(nonce.size == 16)
        return ModbusCodec.buildVendor(
            address,
            byteArrayOf(commandPrepare.toByte(), tlvNonce.toByte(), nonce.size.toByte()) + nonce,
        )
    }

    fun cancelRequest(address: Int) =
        ModbusCodec.buildVendor(address, byteArrayOf(commandCancel.toByte()))

    fun bleBeginRequest(address: Int, size: Long, sha256: String): ByteArray {
        require(size in 1..0xffffffffL)
        val hash = sha256.chunked(2).map { it.toInt(16).toByte() }.toByteArray()
        require(hash.size == 32)
        return ModbusCodec.buildVendor(
            address,
            byteArrayOf(commandBleBegin.toByte()) +
                u32(size.toInt()) +
                byteArrayOf(layoutVersion.toByte()) +
                hash,
        )
    }

    fun bleDataRequest(address: Int, offset: Int, data: ByteArray): ByteArray {
        require(data.isNotEmpty() && data.size <= bleChunkBytes)
        return ModbusCodec.buildVendor(
            address,
            byteArrayOf(commandBleData.toByte()) + u32(offset) + data,
        )
    }

    fun bleStatusRequest(address: Int) =
        ModbusCodec.buildVendor(address, byteArrayOf(commandBleStatus.toByte()))

    fun bleCommitRequest(address: Int) =
        ModbusCodec.buildVendor(address, byteArrayOf(commandBleCommit.toByte()))

    fun bleCancelRequest(address: Int) =
        ModbusCodec.buildVendor(address, byteArrayOf(commandBleCancel.toByte()))

    fun parseBleBegin(frame: ByteArray) {
        responsePayload(frame, commandBleBegin)
    }

    fun parseBleDataAck(frame: ByteArray): Int =
        parseTlv(responsePayload(frame, commandBleData)).u32(0x20)

    fun parseBleStatus(frame: ByteArray): OtaBleStatus {
        val tlv = parseTlv(responsePayload(frame, commandBleStatus))
        return OtaBleStatus(
            state = tlv.u8(0x21),
            receivedBytes = tlv.u32(0x22),
            expectedBytes = tlv.u32(0x23),
            errorCode = tlv.u32(0x24),
        )
    }

    fun parseBleCommit(frame: ByteArray) {
        responsePayload(frame, commandBleCommit)
    }

    fun parseBleCancel(frame: ByteArray) {
        responsePayload(frame, commandBleCancel)
    }

    fun parseInfo(frame: ByteArray): OtaDeviceInfo {
        val payload = responsePayload(frame, commandGetInfo)
        val tlv = parseTlv(payload)
        return OtaDeviceInfo(
            protocolVersion = tlv.u8(tlvProtocol),
            layoutVersion = tlv.u8(tlvLayout),
            firmwareVersion = tlv.text(tlvVersion),
            variant = tlv.text(tlvVariant),
            assetPackVersion = tlv.u8(tlvAssetPack),
            capabilities = tlv.u8(tlvCapabilities),
            secureVersion = tlv.u32(tlvSecureVersion),
        )
    }

    fun parseWifiSession(frame: ByteArray): OtaWifiSession {
        val payload = responsePayload(frame, commandPrepare)
        val tlv = parseTlv(payload)
        val bssid = tlv.required(tlvBssid)
        require(bssid.size == 6) { "invalid BSSID" }
        val token = tlv.required(tlvToken)
        require(token.size == 16) { "invalid OTA token" }
        return OtaWifiSession(
            ssid = tlv.text(tlvSsid),
            bssid = bssid.joinToString(":") { "%02X".format(it.toInt() and 0xff) },
            tokenHex = token.joinToString("") { "%02x".format(it.toInt() and 0xff) },
            timeoutSeconds = tlv.u32(tlvTimeout),
        )
    }

    private fun responsePayload(frame: ByteArray, command: Int): ByteArray {
        require(ModbusCodec.validateCrc(frame)) { "OTA response CRC mismatch" }
        require(frame.size >= 7 && (frame[1].toInt() and 0xff) == 0x41)
        require(frame.size == 5 + (frame[2].toInt() and 0xff)) { "OTA response length mismatch" }
        val payload = frame.copyOfRange(3, frame.size - 2)
        require((payload[0].toInt() and 0xff) == command) { "OTA command mismatch" }
        require((payload[1].toInt() and 0xff) == 0) { "OTA device rejected command" }
        return payload.copyOfRange(2, payload.size)
    }

    private fun parseTlv(payload: ByteArray): Map<Int, ByteArray> {
        val result = linkedMapOf<Int, ByteArray>()
        var offset = 0
        while (offset < payload.size) {
            require(offset + 2 <= payload.size) { "truncated OTA TLV" }
            val type = payload[offset].toInt() and 0xff
            val length = payload[offset + 1].toInt() and 0xff
            offset += 2
            require(offset + length <= payload.size) { "truncated OTA TLV value" }
            result[type] = payload.copyOfRange(offset, offset + length)
            offset += length
        }
        return result
    }

    private fun Map<Int, ByteArray>.required(type: Int) =
        get(type) ?: error("missing OTA TLV $type")

    private fun Map<Int, ByteArray>.text(type: Int) =
        required(type).toString(Charsets.UTF_8)

    private fun Map<Int, ByteArray>.u8(type: Int) =
        required(type).also { require(it.size == 1) }[0].toInt() and 0xff

    private fun Map<Int, ByteArray>.u16(type: Int): Int {
        val data = required(type)
        require(data.size == 2)
        return (data[0].toInt() and 0xff) or ((data[1].toInt() and 0xff) shl 8)
    }

    private fun Map<Int, ByteArray>.u32(type: Int): Int {
        val data = required(type)
        require(data.size == 4)
        return data.foldIndexed(0) { index, value, byte ->
            value or ((byte.toInt() and 0xff) shl (index * 8))
        }
    }

    private fun u32(value: Int) = byteArrayOf(
        value.toByte(),
        (value ushr 8).toByte(),
        (value ushr 16).toByte(),
        (value ushr 24).toByte(),
    )
}
