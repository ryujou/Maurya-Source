package com.example.peacock.feature.runtime

import com.example.peacock.protocol.RegisterMap

object RuntimePayloads {
    fun scenePayload(global: GlobalState): List<Int> = listOf(
        global.sceneMode.coerceIn(1, 4),
        global.sceneParam.coerceIn(0, 255),
    )

    fun globalLedPayload(global: GlobalState): List<Int> = listOf(
        global.globalBrightness.coerceIn(0, 255),
        global.gainR.coerceIn(0, 255),
        global.gainG.coerceIn(0, 255),
        global.gainB.coerceIn(0, 255),
    )

    fun groupPayload(group: GroupState): List<Int> = listOf(
        group.innerMode.coerceIn(1, 4),
        group.hue.coerceIn(0, 359),
        group.sat.coerceIn(0, 255),
        group.value.coerceIn(0, 255),
        group.innerParam.coerceIn(0, 255),
    )

    fun allGroupsPayload(groups: List<GroupState>): List<Int> {
        require(groups.size == RegisterMap.GROUP_COUNT) {
            "group count must be ${RegisterMap.GROUP_COUNT}"
        }
        return buildList(RegisterMap.GROUP_REG_COUNT) {
            groups.forEach { addAll(groupPayload(it)) }
        }
    }
}
