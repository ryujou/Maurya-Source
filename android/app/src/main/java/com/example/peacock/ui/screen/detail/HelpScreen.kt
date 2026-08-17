package com.example.peacock.ui.screen.detail

import androidx.annotation.StringRes
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.material3.ElevatedCard
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import com.example.peacock.BuildConfig
import com.example.peacock.R

private data class HelpSection(
    val eyebrow: String,
    @param:StringRes val title: Int,
    @param:StringRes val items: List<Int>,
    @param:StringRes val codeSample: Int? = null,
)

private val helpSections = listOf(
    HelpSection(
        eyebrow = "QUICK START",
        title = R.string.help_quick_start_title,
        items = listOf(
            R.string.help_quick_start_1,
            R.string.help_quick_start_2,
            R.string.help_quick_start_3,
        ),
    ),
    HelpSection(
        eyebrow = "BUTTONS & LED",
        title = R.string.help_buttons_title,
        items = listOf(
            R.string.help_buttons_1,
            R.string.help_buttons_2,
            R.string.help_buttons_3,
        ),
    ),
    HelpSection(
        eyebrow = "CONTROL",
        title = R.string.help_control_title,
        items = listOf(
            R.string.help_control_1,
            R.string.help_control_2,
            R.string.help_control_3,
            R.string.help_control_4,
        ),
    ),
    HelpSection(
        eyebrow = "SUPPORT COLOR",
        title = R.string.help_palette_title,
        items = listOf(
            R.string.help_palette_1,
            R.string.help_palette_2,
            R.string.help_palette_3,
        ),
    ),
    HelpSection(
        eyebrow = "BLOCK PROGRAMMING",
        title = R.string.help_blocks_title,
        items = listOf(
            R.string.help_blocks_1,
            R.string.help_blocks_2,
            R.string.help_blocks_3,
            R.string.help_blocks_4,
            R.string.help_blocks_5,
        ),
    ),
    HelpSection(
        eyebrow = "MAURYA SCRIPT",
        title = R.string.help_script_title,
        items = listOf(
            R.string.help_script_1,
            R.string.help_script_2,
            R.string.help_script_3,
            R.string.help_script_4,
            R.string.help_script_5,
            R.string.help_script_6,
        ),
        codeSample = R.string.help_script_example,
    ),
    HelpSection(
        eyebrow = "ALGORITHMS",
        title = R.string.help_algorithms_title,
        items = listOf(
            R.string.help_algorithms_1,
            R.string.help_algorithms_2,
            R.string.help_algorithms_3,
            R.string.help_algorithms_4,
            R.string.help_algorithms_5,
        ),
    ),
    HelpSection(
        eyebrow = "SENSORS & AUDIO",
        title = R.string.help_sensors_title,
        items = listOf(
            R.string.help_sensors_1,
            R.string.help_sensors_2,
            R.string.help_sensors_3,
            R.string.help_sensors_4,
        ),
    ),
    HelpSection(
        eyebrow = "NETWORK",
        title = R.string.help_network_title,
        items = listOf(
            R.string.help_network_1,
            R.string.help_network_2,
            R.string.help_network_3,
        ),
    ),
    HelpSection(
        eyebrow = "RECOVERY",
        title = R.string.help_recovery_title,
        items = listOf(
            R.string.help_recovery_1,
            R.string.help_recovery_2,
            R.string.help_recovery_3,
        ),
    ),
)

@Composable
fun HelpScreen(
    modifier: Modifier = Modifier,
    leadingContent: @Composable () -> Unit = {},
) {
    LazyColumn(
        modifier = modifier.fillMaxSize().testTag("help-page"),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        item(key = "leading-content") {
            leadingContent()
        }

        item {
            ElevatedCard(modifier = Modifier.fillMaxWidth().testTag("help-hero")) {
                Row(
                    modifier = Modifier.padding(18.dp),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Column(
                        modifier = Modifier.weight(1f),
                        verticalArrangement = Arrangement.spacedBy(4.dp),
                    ) {
                        Text(
                            text = "OFFLINE GUIDE",
                            style = MaterialTheme.typography.labelMedium,
                            color = MaterialTheme.colorScheme.secondary,
                            fontWeight = FontWeight.Bold,
                        )
                        Text(stringResource(R.string.help_title), style = MaterialTheme.typography.headlineSmall)
                        Text(
                            stringResource(R.string.help_intro),
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                    Surface(
                        color = MaterialTheme.colorScheme.secondaryContainer,
                        shape = MaterialTheme.shapes.large,
                    ) {
                        Text(
                            text = "v${BuildConfig.VERSION_NAME}",
                            modifier = Modifier.padding(horizontal = 12.dp, vertical = 8.dp),
                            color = MaterialTheme.colorScheme.onSecondaryContainer,
                            fontWeight = FontWeight.Bold,
                        )
                    }
                }
            }
        }

        itemsIndexed(helpSections) { index, section ->
            ElevatedCard(modifier = Modifier.fillMaxWidth().testTag("help-section-${index + 1}")) {
                Row(
                    modifier = Modifier.padding(16.dp),
                    horizontalArrangement = Arrangement.spacedBy(14.dp),
                    verticalAlignment = Alignment.Top,
                ) {
                    Surface(
                        color = MaterialTheme.colorScheme.primaryContainer,
                        shape = MaterialTheme.shapes.medium,
                    ) {
                        Text(
                            text = (index + 1).toString().padStart(2, '0'),
                            modifier = Modifier.padding(horizontal = 10.dp, vertical = 8.dp),
                            color = MaterialTheme.colorScheme.onPrimaryContainer,
                            fontWeight = FontWeight.Black,
                        )
                    }
                    Column(
                        modifier = Modifier.weight(1f),
                        verticalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        Text(
                            text = section.eyebrow,
                            style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.secondary,
                            fontWeight = FontWeight.Bold,
                        )
                        Text(stringResource(section.title), style = MaterialTheme.typography.titleLarge)
                        section.items.forEach { item ->
                            Text(
                                text = "• ${stringResource(item)}",
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                                style = MaterialTheme.typography.bodyMedium,
                            )
                        }
                        section.codeSample?.let { codeSample ->
                            Surface(
                                modifier = Modifier.fillMaxWidth().testTag("help-script-example"),
                                color = MaterialTheme.colorScheme.surfaceVariant,
                                shape = MaterialTheme.shapes.medium,
                            ) {
                                Text(
                                    text = stringResource(codeSample),
                                    modifier = Modifier.padding(12.dp),
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                    style = MaterialTheme.typography.bodySmall,
                                    fontFamily = FontFamily.Monospace,
                                )
                            }
                        }
                    }
                }
            }
        }

        item {
            Surface(
                modifier = Modifier.fillMaxWidth(),
                color = MaterialTheme.colorScheme.tertiary.copy(alpha = 0.12f),
                shape = MaterialTheme.shapes.large,
            ) {
                Column(modifier = Modifier.padding(16.dp)) {
                    Text(
                        stringResource(R.string.help_offline_title),
                        color = MaterialTheme.colorScheme.tertiary,
                        fontWeight = FontWeight.Bold,
                    )
                    Text(
                        stringResource(R.string.help_offline_body),
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
        }
    }
}
