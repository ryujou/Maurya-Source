package com.example.peacock.protocol

object ModbusCodec {
    fun buildReadHolding(deviceAddr: Int, startReg: Int, count: Int): ByteArray {
        val payload = byteArrayOf(
            deviceAddr.toByte(),
            0x03,
            ((startReg ushr 8) and 0xFF).toByte(),
            (startReg and 0xFF).toByte(),
            ((count ushr 8) and 0xFF).toByte(),
            (count and 0xFF).toByte(),
        )
        return appendCrc(payload)
    }

    fun buildWriteSingle(deviceAddr: Int, reg: Int, value: Int): ByteArray {
        val payload = byteArrayOf(
            deviceAddr.toByte(),
            0x06,
            ((reg ushr 8) and 0xFF).toByte(),
            (reg and 0xFF).toByte(),
            ((value ushr 8) and 0xFF).toByte(),
            (value and 0xFF).toByte(),
        )
        return appendCrc(payload)
    }

    fun buildWriteMultiple(deviceAddr: Int, startReg: Int, values: List<Int>): ByteArray {
        require(values.isNotEmpty()) { "values must not be empty" }
        val count = values.size
        val payload = ByteArray(7 + count * 2)
        payload[0] = deviceAddr.toByte()
        payload[1] = 0x10
        payload[2] = ((startReg ushr 8) and 0xFF).toByte()
        payload[3] = (startReg and 0xFF).toByte()
        payload[4] = ((count ushr 8) and 0xFF).toByte()
        payload[5] = (count and 0xFF).toByte()
        payload[6] = (count * 2).toByte()
        values.forEachIndexed { index, value ->
            val offset = 7 + index * 2
            payload[offset] = ((value ushr 8) and 0xFF).toByte()
            payload[offset + 1] = (value and 0xFF).toByte()
        }
        return appendCrc(payload)
    }

    fun buildVendor(deviceAddr: Int, payload: ByteArray): ByteArray {
        require(payload.size <= 239) { "vendor payload too large" }
        return appendCrc(
            byteArrayOf(deviceAddr.toByte(), 0x41, payload.size.toByte()) + payload,
        )
    }

    fun crc16Modbus(data: ByteArray, len: Int = data.size): Int {
        var crc = 0xFFFF
        for (i in 0 until len) {
            crc = crc xor (data[i].toInt() and 0xFF)
            repeat(8) {
                crc = if ((crc and 1) != 0) {
                    (crc ushr 1) xor 0xA001
                } else {
                    crc ushr 1
                }
            }
        }
        return crc and 0xFFFF
    }

    fun validateCrc(frame: ByteArray): Boolean {
        if (frame.size < 4) return false
        val expected = crc16Modbus(frame, frame.size - 2)
        val actual = (frame[frame.size - 2].toInt() and 0xFF) or
            ((frame[frame.size - 1].toInt() and 0xFF) shl 8)
        return expected == actual
    }

    fun expectedResponseLength(buffer: ByteArray): Int? {
        if (buffer.size < 2) return null
        val function = buffer[1].toInt() and 0xFF
        return when {
            function == 0x03 -> {
                if (buffer.size < 3) null else 5 + (buffer[2].toInt() and 0xFF)
            }
            function == 0x06 || function == 0x10 -> 8
            function == 0x41 -> {
                if (buffer.size < 3) null else 5 + (buffer[2].toInt() and 0xFF)
            }
            (function and 0x80) != 0 -> 5
            else -> null
        }
    }

    fun parseResponse(frame: ByteArray): ProtocolResponse {
        require(validateCrc(frame)) { "CRC mismatch" }
        val function = frame[1].toInt() and 0xFF
        if ((function and 0x80) != 0) {
            val code = frame[2].toInt() and 0xFF
            return ExceptionResponse(function, code, exceptionMessage(code))
        }
        return when (function) {
            0x03 -> {
                val byteCount = frame[2].toInt() and 0xFF
                require(frame.size == byteCount + 5) { "length mismatch" }
                val values = buildList {
                    var offset = 3
                    while (offset < 3 + byteCount) {
                        add(
                            ((frame[offset].toInt() and 0xFF) shl 8) or
                                (frame[offset + 1].toInt() and 0xFF)
                        )
                        offset += 2
                    }
                }
                ReadHoldingResponse(values)
            }
            0x06, 0x10 -> {
                val startReg = ((frame[2].toInt() and 0xFF) shl 8) or (frame[3].toInt() and 0xFF)
                val valueOrCount = ((frame[4].toInt() and 0xFF) shl 8) or (frame[5].toInt() and 0xFF)
                WriteAckResponse(function, startReg, valueOrCount)
            }
            else -> error("unsupported function 0x${function.toString(16)}")
        }
    }

    private fun appendCrc(payload: ByteArray): ByteArray {
        val crc = crc16Modbus(payload)
        return payload + byteArrayOf((crc and 0xFF).toByte(), ((crc ushr 8) and 0xFF).toByte())
    }

    private fun exceptionMessage(code: Int): String = when (code) {
        0x02 -> "Illegal address"
        0x03 -> "Illegal value"
        else -> "Modbus exception 0x${code.toString(16)}"
    }
}
