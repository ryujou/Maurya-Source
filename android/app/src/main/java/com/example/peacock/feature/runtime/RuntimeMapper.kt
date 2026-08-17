package com.example.peacock.feature.runtime

import com.example.peacock.protocol.RegisterMap

object RuntimeMapper {
    fun mapSnapshot(globalValues: List<Int>, groupValues: List<Int>): RuntimeSnapshot {
        require(globalValues.size >= RegisterMap.CONFIG_REG_COUNT) { "global register count mismatch" }
        require(groupValues.size >= RegisterMap.GROUP_REG_COUNT) { "group register count mismatch" }

        val groups = List(RegisterMap.GROUP_COUNT) { index ->
            val base = index * RegisterMap.GROUP_STRIDE
            GroupState(
                innerMode = groupValues[base],
                hue = groupValues[base + 1],
                sat = groupValues[base + 2],
                value = groupValues[base + 3],
                innerParam = groupValues[base + 4],
            )
        }

        return RuntimeSnapshot(
            global = GlobalState(
                sceneMode = globalValues[0],
                sceneParam = globalValues[1],
                globalBrightness = globalValues[2],
                gainR = globalValues[3],
                gainG = globalValues[4],
                gainB = globalValues[5],
                saveState = globalValues[10],
                deviceAddr = globalValues[11],
            ),
            groups = groups,
            diagnostics = DiagnosticsState(
                rxCount = globalValues[12],
                rxOverflow = globalValues[13],
                txDrop = globalValues[14],
                parseError = globalValues[15],
                tempCx100 = toSigned16(globalValues[16]),
                vddaMv = globalValues[17],
            ),
        )
    }

    private fun toSigned16(value: Int): Int = if (value and 0x8000 != 0) value - 0x10000 else value
}
