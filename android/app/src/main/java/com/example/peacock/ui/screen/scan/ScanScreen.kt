package com.example.peacock.ui.screen.scan

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Button
import androidx.compose.material3.ElevatedCard
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.example.peacock.R
import com.example.peacock.ble.BleDeviceItem
import com.example.peacock.ui.component.DebugControlPanel
import com.example.peacock.ui.i18n.AppLanguage

@Composable
fun ScanScreen(
    innerPadding: PaddingValues,
    status: String,
    list: List<BleDeviceItem>,
    filterFfe0: Boolean,
    debugMode: Boolean,
    showDebugControls: Boolean,
    appLanguage: AppLanguage,
    onDebugModeChange: (Boolean) -> Unit,
    onAppLanguageChange: (AppLanguage) -> Unit,
    onFilterChange: (Boolean) -> Unit,
    onStartScan: () -> Unit,
    onStopScan: () -> Unit,
    onClickItem: (BleDeviceItem) -> Unit,
    onOpenDemo: () -> Unit,
    onOpenShare: () -> Unit,
) {
    Column(
        modifier = Modifier
            .padding(innerPadding)
            .padding(16.dp)
            .fillMaxSize(),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.Top,
        ) {
            Column {
                Text(stringResource(R.string.app_name), style = MaterialTheme.typography.titleLarge)
                Text(
                    stringResource(R.string.brand_subtitle),
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.secondary,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }

            DebugControlPanel(
                debugMode = debugMode,
                appLanguage = appLanguage,
                showDebugToggle = showDebugControls,
                showLanguageSelector = true,
                onDebugModeChange = onDebugModeChange,
                onAppLanguageChange = onAppLanguageChange,
            )
        }

        ElevatedCard {
            Column(
                modifier = Modifier.padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                Button(onClick = onStartScan, modifier = Modifier.fillMaxWidth()) {
                    Text(stringResource(R.string.scan_start))
                }
                OutlinedButton(onClick = onStopScan, modifier = Modifier.fillMaxWidth()) {
                    Text(stringResource(R.string.scan_stop))
                }
                OutlinedButton(onClick = onOpenShare, modifier = Modifier.fillMaxWidth()) {
                    Text(stringResource(R.string.temporary_share))
                }

                if (debugMode) {
                    Text(
                        text = status,
                        maxLines = 2,
                        overflow = TextOverflow.Ellipsis,
                    )
                    Text(stringResource(R.string.devices_found, list.size))
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Text(stringResource(R.string.show_only_ffe0))
                        Switch(
                            checked = filterFfe0,
                            onCheckedChange = onFilterChange,
                        )
                    }
                    OutlinedButton(
                        onClick = onOpenDemo,
                        modifier = Modifier.fillMaxWidth().testTag("open-demo"),
                    ) {
                        Text(stringResource(R.string.open_demo_page))
                    }
                }
            }
        }

        ElevatedCard {
            Column(Modifier.padding(vertical = 4.dp)) {
                if (list.isEmpty()) {
                    Text(
                        text = stringResource(R.string.device_empty),
                        modifier = Modifier
                            .padding(16.dp)
                            .fillMaxWidth(),
                    )
                }

                LazyColumn(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    items(list) { item ->
                        ListItem(
                            headlineContent = {
                                Text(
                                    text = item.name,
                                    maxLines = 1,
                                    overflow = TextOverflow.Ellipsis,
                                )
                            },
                            supportingContent = {
                                if (debugMode) {
                                    Text(
                                        text = stringResource(R.string.device_rssi, item.address, item.rssi),
                                        maxLines = 1,
                                        overflow = TextOverflow.Ellipsis,
                                    )
                                }
                            },
                            modifier = Modifier
                                .fillMaxWidth()
                                .clickable { onClickItem(item) },
                        )
                        HorizontalDivider()
                    }
                }
            }
        }
    }
}
