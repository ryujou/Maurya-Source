package com.example.peacock.ui.screen.detail

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.ElevatedCard
import androidx.compose.material3.Button
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.example.peacock.R
import com.example.peacock.feature.palette.PaletteHierarchyUiState
import com.example.peacock.feature.palette.CustomPaletteViewModel
import com.example.peacock.feature.ota.OtaStage
import com.example.peacock.feature.ota.OtaUiState
import com.example.peacock.feature.effects.EffectViewModel
import com.example.peacock.feature.runtime.DiagnosticsState
import com.example.peacock.feature.runtime.GlobalState
import com.example.peacock.feature.runtime.GroupState
import com.example.peacock.ui.component.DebugControlPanel
import com.example.peacock.ui.component.ModeButton
import com.example.peacock.ui.i18n.AppLanguage
import com.example.peacock.ui.screen.palette.CharacterPaletteScreen
import com.example.peacock.ui.screen.effects.EffectLibraryScreen
import com.example.peacock.util.Formatters

enum class DetailTab {
    CONSOLE,
    CHARACTERS,
    HELP,
    EFFECTS,
}

@Composable
fun DetailScreen(
    innerPadding: PaddingValues,
    global: GlobalState,
    groups: List<GroupState>,
    diagnostics: DiagnosticsState,
    connectionStatus: String,
    isActionInProgress: Boolean,
    debugMode: Boolean,
    showDebugControls: Boolean,
    appLanguage: AppLanguage,
    detailTab: DetailTab,
    statusMessage: String,
    paletteHierarchy: PaletteHierarchyUiState,
    customPaletteViewModel: CustomPaletteViewModel,
    otaState: OtaUiState,
    effectViewModel: EffectViewModel,
    bleReady: Boolean,
    onDebugModeChange: (Boolean) -> Unit,
    onAppLanguageChange: (AppLanguage) -> Unit,
    onDetailTabChange: (DetailTab) -> Unit,
    onBack: () -> Unit,
    onOpenShare: () -> Unit,
    onReconnect: () -> Unit,
    onDisconnect: () -> Unit,
    onRefresh: () -> Unit,
    onSceneModeChange: (Int) -> Unit,
    onSceneParamChange: (Int) -> Unit,
    onApplyScene: () -> Unit,
    onGlobalChange: (GlobalState) -> Unit,
    onApplyGlobal: () -> Unit,
    onAllGroupsChange: (GroupState) -> Unit,
    onApplyAllGroups: () -> Unit,
    onGroupChange: (Int, GroupState) -> Unit,
    onApplyGroup: (Int) -> Unit,
    onClearDiagnostics: () -> Unit,
    onPickPaletteColor: (String) -> Unit,
    onStartOta: () -> Unit,
    onCancelOta: () -> Unit,
) {
    val consoleScrollState = rememberScrollState()
    val allGroupsState = groups.firstOrNull() ?: GroupState()
    var advancedOpen by rememberSaveable { mutableStateOf(false) }

    Column(
        modifier = Modifier
            .padding(innerPadding)
            .padding(horizontal = 16.dp, vertical = 12.dp)
            .fillMaxSize(),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        ElevatedCard(modifier = Modifier.fillMaxWidth()) {
            Column(
                modifier = Modifier.padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Row(
                        modifier = Modifier.weight(1f),
                        horizontalArrangement = Arrangement.spacedBy(12.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Box(
                            modifier = Modifier
                                .size(44.dp)
                                .background(MaterialTheme.colorScheme.primary, CircleShape),
                            contentAlignment = Alignment.Center,
                        ) {
                            Text(
                                text = "M",
                                color = MaterialTheme.colorScheme.onPrimary,
                                style = MaterialTheme.typography.titleLarge,
                                fontWeight = FontWeight.Black,
                            )
                        }
                        Column {
                            Text(stringResource(R.string.app_name), style = MaterialTheme.typography.headlineSmall)
                            Text(
                                text = stringResource(R.string.detail_subtitle),
                                style = MaterialTheme.typography.bodyMedium,
                                color = MaterialTheme.colorScheme.secondary,
                                maxLines = 1,
                                overflow = TextOverflow.Ellipsis,
                            )
                        }
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

                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    StatusBadge(connectionStatus, Modifier.weight(1f))
                    StatusBadge(
                        Formatters.saveStateLabel(androidx.compose.ui.platform.LocalContext.current, global.saveState),
                        Modifier.weight(1f),
                        highlighted = global.saveState != 0,
                    )
                }

                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    OutlinedButton(
                        onClick = onBack,
                        modifier = Modifier.weight(1f).testTag("detail-back"),
                    ) {
                        Text(stringResource(R.string.back))
                    }
                    OutlinedButton(onClick = onReconnect, modifier = Modifier.weight(1f)) {
                        Text(stringResource(R.string.reconnect))
                    }
                    OutlinedButton(onClick = onDisconnect, modifier = Modifier.weight(1f)) {
                        Text(stringResource(R.string.disconnect))
                    }
                }
                OutlinedButton(onClick = onOpenShare, modifier = Modifier.fillMaxWidth()) {
                    Text(stringResource(R.string.temporary_share))
                }
            }
        }

        if (statusMessage.isNotBlank()) {
            Surface(
                modifier = Modifier.fillMaxWidth(),
                color = MaterialTheme.colorScheme.primaryContainer,
                shape = MaterialTheme.shapes.medium,
            ) {
                Text(
                    text = statusMessage,
                    modifier = Modifier.padding(horizontal = 14.dp, vertical = 10.dp),
                    color = MaterialTheme.colorScheme.onPrimaryContainer,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis,
                )
            }
        }

        val detailTabs = listOf(
            Triple(DetailTab.CONSOLE, stringResource(R.string.console), "detail-tab-console"),
            Triple(DetailTab.CHARACTERS, stringResource(R.string.character_palette), "detail-tab-palette"),
            Triple(DetailTab.HELP, stringResource(R.string.help_tab), "detail-tab-help"),
            Triple(
                DetailTab.EFFECTS,
                if (appLanguage == AppLanguage.JA_JP) "エフェクト" else "效果编程",
                "detail-tab-effects",
            ),
        )
        BoxWithConstraints(Modifier.fillMaxWidth()) {
            if (maxWidth < 600.dp) {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    detailTabs.chunked(2).forEach { rowTabs ->
                        Row(
                            Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.spacedBy(8.dp),
                        ) {
                            rowTabs.forEach { (tab, label, tag) ->
                                ModeButton(
                                    text = label,
                                    selected = detailTab == tab,
                                    onClick = { onDetailTabChange(tab) },
                                    modifier = Modifier.weight(1f).testTag(tag),
                                    compact = true,
                                )
                            }
                        }
                    }
                }
            } else {
                Row(
                    Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    detailTabs.forEach { (tab, label, tag) ->
                        ModeButton(
                            text = label,
                            selected = detailTab == tab,
                            onClick = { onDetailTabChange(tab) },
                            modifier = Modifier.weight(1f).testTag(tag),
                            compact = true,
                        )
                    }
                }
            }
        }

        when (detailTab) {
            DetailTab.CHARACTERS -> CharacterPaletteScreen(
                hierarchy = paletteHierarchy,
                customPaletteViewModel = customPaletteViewModel,
                onPickGroupColor = onPickPaletteColor,
                onPickCharacterColor = onPickPaletteColor,
                modifier = Modifier.weight(1f),
            )

            DetailTab.HELP -> HelpScreen(
                modifier = Modifier.weight(1f),
                leadingContent = {
                    OtaUpdateCard(
                        state = otaState,
                        enabled = !isActionInProgress,
                        onStart = onStartOta,
                        onCancel = onCancelOta,
                    )
                },
            )

            DetailTab.EFFECTS -> EffectLibraryScreen(
                viewModel = effectViewModel,
                language = appLanguage,
                groups = groups,
                deviceAddress = global.deviceAddr,
                connected = bleReady,
                modifier = Modifier.weight(1f),
            )

            DetailTab.CONSOLE -> Column(
                modifier = Modifier
                    .weight(1f)
                    .testTag("console-page")
                    .verticalScroll(consoleScrollState),
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                TelemetryCard(
                    global = global,
                    diagnostics = diagnostics,
                    enabled = !isActionInProgress,
                    onRefresh = onRefresh,
                    onClearDiagnostics = onClearDiagnostics,
                )

                SceneCard(
                    global = global,
                    enabled = !isActionInProgress,
                    onSceneModeChange = onSceneModeChange,
                    onSceneParamChange = onSceneParamChange,
                    onApply = onApplyScene,
                )

                GlobalLedCard(
                    global = global,
                    enabled = !isActionInProgress,
                    onGlobalChange = onGlobalChange,
                    onApply = onApplyGlobal,
                    modifier = Modifier.testTag("global-light-card"),
                )

                GroupEditorCard(
                    eyebrow = "7 CHANNELS",
                    title = stringResource(R.string.all_groups_title),
                    group = allGroupsState,
                    enabled = !isActionInProgress,
                    onGroupChange = onAllGroupsChange,
                    onApply = onApplyAllGroups,
                    applyLabel = stringResource(R.string.apply_all_groups),
                    modifier = Modifier.testTag("all-groups-card"),
                    testPrefix = "all-groups",
                )

                ElevatedCard(modifier = Modifier.fillMaxWidth()) {
                    Column(
                        modifier = Modifier.padding(12.dp),
                        verticalArrangement = Arrangement.spacedBy(12.dp),
                    ) {
                        OutlinedButton(
                            onClick = { advancedOpen = !advancedOpen },
                            modifier = Modifier.fillMaxWidth().testTag("advanced-toggle"),
                        ) {
                            Text(
                                stringResource(
                                    if (advancedOpen) R.string.advanced_groups_close else R.string.advanced_groups_open,
                                ),
                            )
                        }
                        AnimatedVisibility(visible = advancedOpen) {
                            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                                groups.forEachIndexed { index, group ->
                                    GroupEditorCard(
                                        eyebrow = stringResource(R.string.group_number, index + 1),
                                        title = stringResource(R.string.group_title, index + 1),
                                        group = group,
                                        enabled = !isActionInProgress,
                                        onGroupChange = { onGroupChange(index, it) },
                                        onApply = { onApplyGroup(index) },
                                        applyLabel = stringResource(R.string.apply_one_group),
                                        modifier = Modifier.testTag("group-card-${index + 1}"),
                                        testPrefix = "group-${index + 1}",
                                    )
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun OtaUpdateCard(
    state: OtaUiState,
    enabled: Boolean,
    onStart: () -> Unit,
    onCancel: () -> Unit,
) {
    val running = state.stage !in setOf(
        OtaStage.IDLE,
        OtaStage.SUCCESS,
        OtaStage.UP_TO_DATE,
        OtaStage.FAILED,
    )
    ElevatedCard(modifier = Modifier.fillMaxWidth().testTag("ota-update-card")) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            Text("FIRMWARE OTA", color = MaterialTheme.colorScheme.secondary)
            Text(stringResource(R.string.ota_title), style = MaterialTheme.typography.titleLarge)
            Text(
                state.message.ifBlank { stringResource(R.string.ota_description) },
                style = MaterialTheme.typography.bodyMedium,
            )
            if (running || state.progress > 0f) {
                LinearProgressIndicator(
                    progress = { state.progress.coerceIn(0f, 1f) },
                    modifier = Modifier.fillMaxWidth(),
                )
            }
            if (state.installedVersion.isNotBlank() && state.availableVersion.isNotBlank()) {
                Text(
                    stringResource(
                        R.string.ota_versions,
                        state.installedVersion,
                        state.availableVersion,
                    ),
                    style = MaterialTheme.typography.labelMedium,
                )
            } else if (state.installedVersion.isNotBlank()) {
                Text(
                    stringResource(R.string.ota_current_version, state.installedVersion),
                    style = MaterialTheme.typography.labelMedium,
                )
            }
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Button(
                    onClick = onStart,
                    enabled = enabled && !running,
                    modifier = Modifier.weight(1f).testTag("ota-start"),
                ) {
                    Text(stringResource(R.string.ota_start))
                }
                OutlinedButton(
                    onClick = onCancel,
                    enabled = state.canCancel,
                    modifier = Modifier.weight(1f).testTag("ota-cancel"),
                ) {
                    Text(stringResource(R.string.ota_cancel))
                }
            }
        }
    }
}

@Composable
private fun StatusBadge(
    text: String,
    modifier: Modifier = Modifier,
    highlighted: Boolean = false,
) {
    Surface(
        modifier = modifier,
        color = if (highlighted) MaterialTheme.colorScheme.secondaryContainer else MaterialTheme.colorScheme.surfaceVariant,
        shape = CircleShape,
    ) {
        Text(
            text = text,
            modifier = Modifier.padding(horizontal = 12.dp, vertical = 8.dp),
            style = MaterialTheme.typography.labelMedium,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
        )
    }
}
