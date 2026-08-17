package com.example.peacock.feature.runtime

import com.example.peacock.ble.BleManager
import com.example.peacock.protocol.ModbusCodec
import com.example.peacock.protocol.ReadHoldingResponse
import com.example.peacock.protocol.RegisterMap

class RuntimeRepository(
    private val bleManager: BleManager,
) {
    companion object {
        private val MAX_READ_REG_COUNT = RuntimeTransportBatcher.maxReadRegistersPerRequest
    }

    suspend fun refreshSnapshot(deviceAddr: Int): RuntimeSnapshot {
        val globalValues = readHolding(deviceAddr, 0x0000, RegisterMap.CONFIG_REG_COUNT)
        val groupValues = readHolding(deviceAddr, RegisterMap.GROUP_BASE, RegisterMap.GROUP_REG_COUNT)
        return RuntimeMapper.mapSnapshot(globalValues, groupValues)
    }

    suspend fun refreshTelemetry(
        deviceAddr: Int,
        current: DiagnosticsState = DiagnosticsState(),
    ): DiagnosticsState {
        val values = readHolding(deviceAddr, RegisterMap.TEMP_C_X100, 2)
        return current.copy(
            tempCx100 = toSigned16(values[0]),
            vddaMv = values[1],
        )
    }

    suspend fun applyScene(deviceAddr: Int, scene: GlobalState) {
        writeMultiple(
            deviceAddr,
            RegisterMap.SCENE_MODE,
            RuntimePayloads.scenePayload(scene),
        )
    }

    suspend fun applyGlobal(deviceAddr: Int, global: GlobalState) {
        writeMultiple(
            deviceAddr,
            RegisterMap.LED_GLOBAL_BRI,
            RuntimePayloads.globalLedPayload(global),
        )
    }

    suspend fun applyGroup(deviceAddr: Int, index: Int, group: GroupState) {
        val startReg = RegisterMap.GROUP_BASE + index * RegisterMap.GROUP_STRIDE
        writeMultiple(
            deviceAddr,
            startReg,
            RuntimePayloads.groupPayload(group),
        )
    }

    suspend fun applyGroups(deviceAddr: Int, groups: List<GroupState>) {
        RuntimeTransportBatcher.buildGroupWriteBatches(groups).forEach { batch ->
            writeMultiple(deviceAddr, batch.startRegister, batch.values)
        }
    }

    suspend fun clearDiagnostics(deviceAddr: Int) {
        bleManager.transceive(
            ModbusCodec.buildWriteSingle(deviceAddr, RegisterMap.UART_PARSE_ERROR, RegisterMap.DIAG_CLEAR_KEY)
        )
    }

    private suspend fun readHolding(deviceAddr: Int, startReg: Int, count: Int): List<Int> {
        require(count > 0) { "count must be > 0" }
        val values = ArrayList<Int>(count)
        var currentStart = startReg
        var remaining = count

        while (remaining > 0) {
            val chunkCount = minOf(remaining, MAX_READ_REG_COUNT)
            val response = bleManager.transceive(
                ModbusCodec.buildReadHolding(deviceAddr, currentStart, chunkCount)
            )
            values += (ModbusCodec.parseResponse(response) as ReadHoldingResponse).values
            currentStart += chunkCount
            remaining -= chunkCount
        }

        return values
    }

    private suspend fun writeMultiple(deviceAddr: Int, startReg: Int, values: List<Int>) {
        require(values.size <= RegisterMap.MAX_BULK_REG_COUNT) {
            "register count must be <= ${RegisterMap.MAX_BULK_REG_COUNT}"
        }
        bleManager.transceive(ModbusCodec.buildWriteMultiple(deviceAddr, startReg, values))
    }

    private fun toSigned16(value: Int): Int = if (value and 0x8000 != 0) value - 0x10000 else value
}
