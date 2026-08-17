package com.example.peacock.ui.screen.detail

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.ElevatedCard
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Slider
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import com.example.peacock.R
import com.example.peacock.feature.runtime.GroupState
import com.example.peacock.ui.component.ColorPreview
import com.example.peacock.ui.component.QuickModeSelector
import com.example.peacock.ui.i18n.innerModeLabel
import com.example.peacock.util.ColorUtils

@Composable
fun GroupEditorCard(
    title: String,
    group: GroupState,
    onGroupChange: (GroupState) -> Unit,
    onApply: () -> Unit,
    applyLabel: String,
    modifier: Modifier = Modifier,
    eyebrow: String? = null,
    enabled: Boolean = true,
    testPrefix: String = "group",
) {
    ElevatedCard(modifier = modifier.fillMaxWidth()) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            eyebrow?.let {
                Text(it, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.secondary)
            }
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
            ) {
                Text(title, style = MaterialTheme.typography.titleLarge)
                ColorPreview(
                    color = run {
                        val rgb = ColorUtils.hsvToRgb(group.hue, group.sat, group.value)
                        androidx.compose.ui.graphics.Color(
                            android.graphics.Color.rgb(rgb.first, rgb.second, rgb.third),
                        )
                    },
                )
            }

            val selectedMode = group.innerMode.takeIf { it == 1 || it == 3 } ?: 1
            QuickModeSelector(
                options = listOf(
                    1 to stringResource(R.string.group_mode_steady),
                    3 to stringResource(R.string.group_mode_strobe),
                ),
                selectedValue = selectedMode,
                onSelect = { onGroupChange(group.copy(innerMode = it)) },
                enabled = enabled,
                testPrefix = "$testPrefix-mode",
            )
            Text(stringResource(R.string.group_current_mode, innerModeLabel(group.innerMode)))

            RangeSliderField("Hue", group.hue, 0..359, enabled, "$testPrefix-hue") {
                onGroupChange(group.copy(hue = it))
            }
            RangeSliderField("Saturation", group.sat, 0..255, enabled, "$testPrefix-saturation") {
                onGroupChange(group.copy(sat = it))
            }
            RangeSliderField(stringResource(R.string.value_label), group.value, 0..255, enabled, "$testPrefix-value") {
                onGroupChange(group.copy(value = it))
            }
            if (group.innerMode == 3) {
                RangeSliderField(
                    stringResource(R.string.strobe_speed_label),
                    group.innerParam,
                    0..255,
                    enabled,
                    "$testPrefix-strobe-speed",
                ) {
                    onGroupChange(group.copy(innerParam = it))
                }
                Text(
                    stringResource(
                        R.string.strobe_period_hint,
                        strobePeriodMs(group.innerParam),
                    ),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }

            Button(
                onClick = onApply,
                enabled = enabled,
                modifier = Modifier.fillMaxWidth().testTag("$testPrefix-apply"),
            ) {
                Text(applyLabel)
            }
        }
    }
}

@Composable
private fun RangeSliderField(
    label: String,
    value: Int,
    range: IntRange,
    enabled: Boolean,
    testTag: String,
    onValueChange: (Int) -> Unit,
) {
    Text("$label · $value")
    Slider(
        value = value.toFloat(),
        onValueChange = { onValueChange(it.toInt().coerceIn(range)) },
        valueRange = range.first.toFloat()..range.last.toFloat(),
        enabled = enabled,
        modifier = Modifier.testTag(testTag),
    )
}

internal fun strobePeriodMs(speed: Int): Int = 30 + ((255 - speed.coerceIn(0, 255)) * 220) / 255
