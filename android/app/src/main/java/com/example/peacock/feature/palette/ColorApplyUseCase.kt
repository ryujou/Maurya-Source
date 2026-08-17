package com.example.peacock.feature.palette

import com.example.peacock.feature.runtime.GroupState
import com.example.peacock.util.ColorUtils

object ColorApplyUseCase {
    fun applyHexToAllGroups(groups: List<GroupState>, hex: String): List<GroupState> {
        val rgb = ColorUtils.parseHexColor(hex) ?: return groups
        val hsv = ColorUtils.rgbToHsv(rgb.first, rgb.second, rgb.third)
        return groups.map { group ->
            group.copy(hue = hsv.h, sat = hsv.s, value = hsv.v)
        }
    }
}
