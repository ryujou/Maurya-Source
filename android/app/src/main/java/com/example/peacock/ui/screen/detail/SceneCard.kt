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
import com.example.peacock.ui.component.QuickModeSelector
import com.example.peacock.ui.i18n.sceneModeLabel

@Composable
fun SceneCard(
    global: GlobalState,
    enabled: Boolean = true,
    onSceneModeChange: (Int) -> Unit,
    onSceneParamChange: (Int) -> Unit,
    onApply: () -> Unit,
    modifier: Modifier = Modifier,
) {
    ElevatedCard(modifier = modifier.fillMaxWidth().testTag("scene-card")) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Text("SCENE", style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.secondary)
            Text(stringResource(R.string.scene_title), style = MaterialTheme.typography.titleLarge)
            QuickModeSelector(
                options = listOf(
                    1 to stringResource(R.string.scene_mode_static),
                    2 to stringResource(R.string.scene_mode_left),
                    3 to stringResource(R.string.scene_mode_right),
                    4 to stringResource(R.string.scene_mode_pingpong),
                ),
                selectedValue = global.sceneMode.coerceIn(1, 4),
                onSelect = onSceneModeChange,
                enabled = enabled,
                testPrefix = "scene-mode",
            )
            Text(stringResource(R.string.scene_current_mode, sceneModeLabel(global.sceneMode)))
            Text(stringResource(R.string.scene_speed, global.sceneParam))
            Slider(
                value = global.sceneParam.toFloat(),
                onValueChange = { onSceneParamChange(it.toInt().coerceIn(0, 255)) },
                valueRange = 0f..255f,
                enabled = enabled,
                modifier = Modifier.testTag("scene-speed"),
            )
            Button(
                onClick = onApply,
                enabled = enabled,
                modifier = Modifier.fillMaxWidth().testTag("apply-scene"),
            ) {
                Text(stringResource(R.string.apply))
            }
        }
    }
}
