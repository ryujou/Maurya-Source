package com.example.peacock.ble

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class BleWriteChunkerTest {
    @Test
    fun `chunkPayload splits oversized request by mtu payload size`() {
        val payload = ByteArray(79) { it.toByte() }

        val chunks = BleWriteChunker.chunkPayload(payload, negotiatedMtu = 23)

        assertEquals(listOf(20, 20, 20, 19), chunks.map { it.size })
        assertTrue(chunks.flatMap { it.asIterable() } == payload.toList())
    }

    @Test
    fun `chunkPayload keeps request whole when mtu is large enough`() {
        val payload = ByteArray(79) { it.toByte() }

        val chunks = BleWriteChunker.chunkPayload(payload, negotiatedMtu = 247)

        assertEquals(1, chunks.size)
        assertEquals(79, chunks.single().size)
    }

    @Test
    fun `140 byte pixel frame is one write at mtu 247`() {
        val payload = ByteArray(140) { it.toByte() }

        val chunks = BleWriteChunker.chunkPayload(payload, negotiatedMtu = 247)

        assertEquals(listOf(140), chunks.map { it.size })
        assertEquals(payload.toList(), chunks.single().toList())
    }

    @Test
    fun `140 byte pixel frame is losslessly split at mtu 23`() {
        val payload = ByteArray(140) { it.toByte() }

        val chunks = BleWriteChunker.chunkPayload(payload, negotiatedMtu = 23)

        assertEquals(7, chunks.size)
        assertEquals(List(7) { 20 }, chunks.map { it.size })
        assertEquals(payload.toList(), chunks.flatMap { it.asIterable() })
    }
}
