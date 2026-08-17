package com.example.peacock.feature.runtime

import com.example.peacock.protocol.RegisterMap

object RuntimeTransportBatcher {
    private const val BLE_TRANSPORT_MAX_FRAME_LEN = 128
    private const val READ_RESPONSE_OVERHEAD = 5
    private const val WRITE_MULTIPLE_REQUEST_OVERHEAD = 9

    val maxReadRegistersPerRequest: Int =
        (BLE_TRANSPORT_MAX_FRAME_LEN - READ_RESPONSE_OVERHEAD) / 2

    private val maxWriteRegistersPerRequest: Int =
        (BLE_TRANSPORT_MAX_FRAME_LEN - WRITE_MULTIPLE_REQUEST_OVERHEAD) / 2

    private val maxGroupsPerWriteBatch: Int =
        (maxWriteRegistersPerRequest / RegisterMap.GROUP_STRIDE).coerceAtLeast(1)

    data class GroupWriteBatch(
        val startRegister: Int,
        val values: List<Int>,
    )

    fun buildGroupWriteBatches(groups: List<GroupState>): List<GroupWriteBatch> {
        require(groups.size == RegisterMap.GROUP_COUNT) {
            "group count must be ${RegisterMap.GROUP_COUNT}"
        }

        return groups
            .chunked(maxGroupsPerWriteBatch)
            .mapIndexed { batchIndex, batchGroups ->
                val startGroupIndex = batchIndex * maxGroupsPerWriteBatch
                GroupWriteBatch(
                    startRegister = RegisterMap.GROUP_BASE + startGroupIndex * RegisterMap.GROUP_STRIDE,
                    values = buildList(batchGroups.size * RegisterMap.GROUP_STRIDE) {
                        batchGroups.forEach { addAll(RuntimePayloads.groupPayload(it)) }
                    },
                )
            }
    }
}
