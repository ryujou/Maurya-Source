package com.example.peacock.ui.screen.detail

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
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
import com.example.peacock.feature.runtime.GlobalState

@Composable
fun GlobalLedCard(
    global: GlobalState,
    enabled: Boolean = true,
    onGlobalChange: (GlobalState) -> Unit,
    onApply: () -> Unit,
    modifier: Modifier = Modifier,
) {
    ElevatedCard(modifier = modifier.fillMaxWidth()) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Text("MASTER", style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.secondary)
            Text(stringResource(R.string.global_lighting_title), style = MaterialTheme.typography.titleLarge)
            SliderField(stringResource(R.string.global_brightness), global.globalBrightness, enabled, "global-brightness") {
                onGlobalChange(global.copy(globalBrightness = it))
            }
            SliderField(stringResource(R.string.gain_r), global.gainR, enabled, "global-gain-r") {
                onGlobalChange(global.copy(gainR = it))
            }
            SliderField(stringResource(R.string.gain_g), global.gainG, enabled, "global-gain-g") {
                onGlobalChange(global.copy(gainG = it))
            }
            SliderField(stringResource(R.string.gain_b), global.gainB, enabled, "global-gain-b") {
                onGlobalChange(global.copy(gainB = it))
            }
            Button(
                onClick = onApply,
                enabled = enabled,
                modifier = Modifier.fillMaxWidth().testTag("apply-global"),
            ) {
                Text(stringResource(R.string.apply))
            }
        }
    }
}

@Composable
private fun SliderField(
    label: String,
    value: Int,
    enabled: Boolean,
    testTag: String,
    onValueChange: (Int) -> Unit,
) {
    Text("$label · $value")
    Slider(
        value = value.toFloat(),
        onValueChange = { onValueChange(it.toInt().coerceIn(0, 255)) },
        valueRange = 0f..255f,
        enabled = enabled,
        modifier = Modifier.testTag(testTag),
    )
}
