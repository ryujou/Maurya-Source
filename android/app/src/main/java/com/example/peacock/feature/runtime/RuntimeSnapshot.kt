package com.example.peacock.feature.runtime

data class GlobalState(
    val sceneMode: Int = 1,
    val sceneParam: Int = 80,
    val globalBrightness: Int = 255,
    val gainR: Int = 255,
    val gainG: Int = 176,
    val gainB: Int = 240,
    val deviceAddr: Int = 1,
    val saveState: Int = 0,
)

data class GroupState(
    val innerMode: Int = 1,
    val hue: Int = 30,
    val sat: Int = 255,
    val value: Int = 255,
    val innerParam: Int = 255,
)

data class DiagnosticsState(
    val rxCount: Int = 0,
    val rxOverflow: Int = 0,
    val txDrop: Int = 0,
    val parseError: Int = 0,
    val tempCx100: Int = 0,
    val vddaMv: Int = 0,
)

data class RuntimeSnapshot(
    val global: GlobalState = GlobalState(),
    val groups: List<GroupState> = List(7) { GroupState() },
    val diagnostics: DiagnosticsState = DiagnosticsState(),
)
