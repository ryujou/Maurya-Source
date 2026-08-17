package com.example.peacock.ble

object BleWriteChunker {
    private const val ATT_HEADER_SIZE = 3
    private const val DEFAULT_WRITE_PAYLOAD_SIZE = 20

    fun chunkPayload(payload: ByteArray, negotiatedMtu: Int): List<ByteArray> {
        if (payload.isEmpty()) return emptyList()

        val chunkSize = (negotiatedMtu - ATT_HEADER_SIZE).coerceAtLeast(DEFAULT_WRITE_PAYLOAD_SIZE)
        if (payload.size <= chunkSize) return listOf(payload)

        val chunks = ArrayList<ByteArray>((payload.size + chunkSize - 1) / chunkSize)
        var offset = 0
        while (offset < payload.size) {
            val end = minOf(offset + chunkSize, payload.size)
            chunks += payload.copyOfRange(offset, end)
            offset = end
        }
        return chunks
    }
}
