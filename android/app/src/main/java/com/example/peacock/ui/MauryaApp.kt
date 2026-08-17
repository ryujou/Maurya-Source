package com.example.peacock.ui

import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalContext
import com.example.peacock.BuildConfig
import com.example.peacock.R
import com.example.peacock.ble.BleDeviceItem
import com.example.peacock.ble.BleManager
import com.example.peacock.feature.palette.CharacterRepository
import com.example.peacock.feature.palette.ColorApplyUseCase
import com.example.peacock.feature.palette.CustomPaletteRepository
import com.example.peacock.feature.palette.CustomPaletteViewModel
import com.example.peacock.feature.palette.PaletteHierarchyUiState
import com.example.peacock.feature.ota.OtaCoordinator
import com.example.peacock.feature.ota.OtaViewModel
import com.example.peacock.feature.effects.EffectViewModel
import com.example.peacock.feature.runtime.DiagnosticsState
import com.example.peacock.feature.runtime.GlobalState
import com.example.peacock.feature.runtime.GroupState
import com.example.peacock.feature.runtime.RuntimeRepository
import com.example.peacock.protocol.RegisterMap
import com.example.peacock.ui.i18n.AppLanguage
import com.example.peacock.ui.i18n.AppLanguageManager
import com.example.peacock.ui.navigation.AppScreen
import com.example.peacock.ui.screen.detail.DetailScreen
import com.example.peacock.ui.screen.detail.DetailTab
import com.example.peacock.ui.screen.scan.ScanScreen
import com.example.peacock.ui.screen.share.ShareScreen
import com.example.peacock.feature.share.ShareViewModel
import com.example.peacock.util.PermissionUtils
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import androidx.lifecycle.viewmodel.compose.viewModel

@Composable
fun MauryaApp(
    requestPermissions: (Array<String>) -> Unit,
    incomingShareToken: String? = null,
    onShareTokenConsumed: () -> Unit = {},
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val bleManager = remember { BleManager(context) }
    val repository = remember { RuntimeRepository(bleManager) }
    val customPaletteFactory = remember(context) {
        CustomPaletteViewModel.Factory(CustomPaletteRepository(context.applicationContext))
    }
    val customPaletteViewModel: CustomPaletteViewModel = viewModel(factory = customPaletteFactory)
    val otaFactory = remember(context, bleManager) {
        OtaViewModel.Factory(OtaCoordinator(context.applicationContext, bleManager))
    }
    val otaViewModel: OtaViewModel = viewModel(factory = otaFactory)
    val effectFactory = remember(context, bleManager) { EffectViewModel.Factory(context, bleManager) }
    val effectViewModel: EffectViewModel = viewModel(factory = effectFactory)
    val shareFactory = remember(context) { ShareViewModel.Factory(context.applicationContext) }
    val shareViewModel: ShareViewModel = viewModel(factory = shareFactory)
    val effectState by effectViewModel.state.collectAsStateCompat()
    val otaState by otaViewModel.state.collectAsStateCompat()
    val session by bleManager.session.collectAsStateCompat()
    val scanResults by bleManager.scanResults.collectAsStateCompat()
    val customPaletteState by customPaletteViewModel.state.collectAsStateCompat()

    val debugUiEnabled = BuildConfig.DEBUG

    var screen by remember {
        mutableStateOf(if (incomingShareToken != null) AppScreen.SHARE else AppScreen.SCAN)
    }
    var shareReturnScreen by remember { mutableStateOf(AppScreen.SCAN) }
    var debugMode by remember { mutableStateOf(false) }
    var demoMode by remember { mutableStateOf(false) }
    var filterFfe0 by remember { mutableStateOf(true) }
    var detailTab by remember { mutableStateOf(DetailTab.CONSOLE) }
    var statusMessage by remember { mutableStateOf("") }
    var isDeviceActionInProgress by remember { mutableStateOf(false) }
    var appLanguage by remember { mutableStateOf(AppLanguageManager.loadSelection(context)) }
    var globalState by remember {
        mutableStateOf(GlobalState(deviceAddr = RegisterMap.DEVICE_ADDR_DEFAULT))
    }
    var groups by remember { mutableStateOf(List(RegisterMap.GROUP_COUNT) { GroupState() }) }
    var diagnostics by remember { mutableStateOf(DiagnosticsState()) }

    LaunchedEffect(incomingShareToken) {
        if (incomingShareToken != null) {
            if (screen != AppScreen.SHARE) shareReturnScreen = screen
            screen = AppScreen.SHARE
        }
    }

    val effectiveDebugMode = debugUiEnabled && debugMode
    val paletteHierarchy = remember(context) {
        CharacterRepository.loadCatalog(context)
            .let(CharacterRepository::buildHierarchy)
            .takeIf { it != PaletteHierarchyUiState.Empty }
            ?: PaletteHierarchyUiState.Empty
    }

    DisposableEffect(screen) {
        if (screen != AppScreen.SHARE && !PermissionUtils.hasBlePermissions(context)) {
            requestPermissions(PermissionUtils.blePermissions)
        }
        onDispose { }
    }

    DisposableEffect(Unit) {
        onDispose { bleManager.close() }
    }

    LaunchedEffect(session.isReady, session.selectedDevice?.address) {
        if (session.isReady && session.selectedDevice != null) {
            demoMode = false
            otaViewModel.refreshInstalledVersion(globalState.deviceAddr)
            runCatching { repository.refreshSnapshot(globalState.deviceAddr) }
                .onSuccess { snapshot ->
                    globalState = snapshot.global
                    groups = snapshot.groups
                    diagnostics = snapshot.diagnostics
                    statusMessage = context.getString(R.string.status_refreshed)
                }
                .onFailure {
                    statusMessage = context.getString(
                        R.string.status_action_failed,
                        context.getString(R.string.status_refreshed),
                        it.message.orEmpty(),
                    )
                }
        }
    }

    LaunchedEffect(
        session.isReady,
        session.selectedDevice?.address,
        demoMode,
        isDeviceActionInProgress,
        effectState.isPlaying,
    ) {
        if (!session.isReady || session.selectedDevice == null || demoMode ||
            isDeviceActionInProgress || effectState.isPlaying) {
            return@LaunchedEffect
        }

        while (true) {
            delay(1_000)
            runCatching {
                repository.refreshTelemetry(globalState.deviceAddr, diagnostics)
            }.onSuccess { telemetry ->
                diagnostics = telemetry
            }
        }
    }

    fun setAppLanguage(selection: AppLanguage) {
        appLanguage = selection
        AppLanguageManager.applySelection(
            context = context,
            selection = selection,
            allowManualOverride = true,
        )
    }

    fun launchDeviceAction(
        successMessage: String,
        demoMessage: String = successMessage,
        block: suspend () -> Unit,
    ) {
        if (demoMode) {
            statusMessage = demoMessage
            return
        }
        if (isDeviceActionInProgress) {
            return
        }
        scope.launch {
            effectViewModel.stop(globalState.deviceAddr)
            isDeviceActionInProgress = true
            try {
                runCatching { block() }
                    .onSuccess { statusMessage = successMessage }
                    .onFailure {
                        statusMessage = context.getString(
                            R.string.status_action_failed,
                            successMessage,
                            it.message.orEmpty(),
                        )
                    }
            } finally {
                isDeviceActionInProgress = false
            }
        }
    }

    Scaffold(containerColor = MaterialTheme.colorScheme.background) { innerPadding ->
        when (screen) {
            AppScreen.SCAN -> ScanScreen(
                innerPadding = innerPadding,
                status = session.connectionText,
                list = scanResults,
                filterFfe0 = filterFfe0,
                debugMode = effectiveDebugMode,
                showDebugControls = debugUiEnabled,
                appLanguage = appLanguage,
                onDebugModeChange = { debugMode = it },
                onAppLanguageChange = ::setAppLanguage,
                onFilterChange = { filterFfe0 = it },
                onStartScan = {
                    if (!PermissionUtils.hasBlePermissions(context)) {
                        requestPermissions(PermissionUtils.blePermissions)
                        statusMessage = context.getString(R.string.status_grant_ble_permission)
                    } else {
                        bleManager.startScan(filterFfe0)
                    }
                },
                onStopScan = { bleManager.stopScan() },
                onClickItem = { item: BleDeviceItem ->
                    demoMode = false
                    screen = AppScreen.DETAIL
                    statusMessage = context.getString(R.string.status_connecting, item.name)
                    bleManager.connect(item)
                },
                onOpenDemo = {
                    demoMode = true
                    screen = AppScreen.DETAIL
                    detailTab = DetailTab.CONSOLE
                    globalState = GlobalState(
                        sceneMode = 4,
                        sceneParam = 100,
                        globalBrightness = 255,
                        gainR = 255,
                        gainG = 176,
                        gainB = 240,
                        deviceAddr = 1,
                        saveState = 0,
                    )
                    groups = List(RegisterMap.GROUP_COUNT) { index ->
                        GroupState(
                            innerMode = if (index % 2 == 0) 1 else 3,
                            hue = (index * 45) % 360,
                            sat = 255,
                            value = 255,
                            innerParam = 120 + index * 10,
                        )
                    }
                    diagnostics = DiagnosticsState(
                        rxCount = 12,
                        rxOverflow = 0,
                        txDrop = 0,
                        parseError = 0,
                        tempCx100 = 2534,
                        vddaMv = 3300,
                    )
                    statusMessage = context.getString(R.string.status_demo_enter)
                },
                onOpenShare = {
                    shareReturnScreen = AppScreen.SCAN
                    screen = AppScreen.SHARE
                },
            )

            AppScreen.DETAIL -> DetailScreen(
                innerPadding = innerPadding,
                global = globalState,
                groups = groups,
                diagnostics = diagnostics,
                connectionStatus = if (demoMode) context.getString(R.string.demo_mode) else session.connectionText,
                isActionInProgress = isDeviceActionInProgress,
                debugMode = effectiveDebugMode,
                showDebugControls = debugUiEnabled,
                appLanguage = appLanguage,
                detailTab = detailTab,
                statusMessage = statusMessage,
                paletteHierarchy = paletteHierarchy,
                customPaletteViewModel = customPaletteViewModel,
                otaState = otaState,
                effectViewModel = effectViewModel,
                bleReady = session.isReady,
                onDebugModeChange = { debugMode = it },
                onAppLanguageChange = ::setAppLanguage,
                onDetailTabChange = { detailTab = it },
                onBack = {
                    demoMode = false
                    bleManager.disconnect()
                    screen = AppScreen.SCAN
                },
                onOpenShare = {
                    shareReturnScreen = AppScreen.DETAIL
                    screen = AppScreen.SHARE
                },
                onReconnect = { bleManager.reconnect() },
                onDisconnect = { bleManager.disconnect() },
                onRefresh = {
                    launchDeviceAction(
                        successMessage = context.getString(R.string.status_refreshed),
                        demoMessage = context.getString(R.string.status_demo_refreshed),
                    ) {
                        val snapshot = repository.refreshSnapshot(globalState.deviceAddr)
                        globalState = snapshot.global
                        groups = snapshot.groups
                        diagnostics = snapshot.diagnostics
                    }
                },
                onSceneModeChange = {
                    globalState = globalState.copy(sceneMode = it.coerceIn(1, 4))
                },
                onSceneParamChange = {
                    globalState = globalState.copy(sceneParam = it.coerceIn(0, 255))
                },
                onApplyScene = {
                    launchDeviceAction(
                        successMessage = context.getString(R.string.status_scene_applied),
                        demoMessage = context.getString(R.string.status_demo_scene_applied),
                    ) {
                        repository.applyScene(globalState.deviceAddr, globalState)
                    }
                },
                onGlobalChange = { globalState = it },
                onApplyGlobal = {
                    launchDeviceAction(
                        successMessage = context.getString(R.string.status_global_applied),
                        demoMessage = context.getString(R.string.status_demo_global_applied),
                    ) {
                        repository.applyGlobal(globalState.deviceAddr, globalState)
                    }
                },
                onAllGroupsChange = { template ->
                    groups = List(RegisterMap.GROUP_COUNT) { template }
                },
                onApplyAllGroups = {
                    launchDeviceAction(
                        successMessage = context.getString(R.string.status_group_applied),
                        demoMessage = context.getString(R.string.status_demo_group_applied),
                    ) {
                        repository.applyGroups(globalState.deviceAddr, groups)
                    }
                },
                onGroupChange = { index, group ->
                    groups = groups.toMutableList().also { next -> next[index] = group }
                },
                onApplyGroup = { index ->
                    launchDeviceAction(
                        successMessage = context.getString(R.string.status_one_group_applied, index + 1),
                        demoMessage = context.getString(R.string.status_demo_one_group_applied, index + 1),
                    ) {
                        repository.applyGroup(globalState.deviceAddr, index, groups[index])
                    }
                },
                onClearDiagnostics = {
                    launchDeviceAction(
                        successMessage = context.getString(R.string.status_diag_cleared),
                        demoMessage = context.getString(R.string.status_demo_diag),
                    ) {
                        repository.clearDiagnostics(globalState.deviceAddr)
                        val snapshot = repository.refreshSnapshot(globalState.deviceAddr)
                        globalState = snapshot.global
                        groups = snapshot.groups
                        diagnostics = snapshot.diagnostics
                    }
                },
                onPickPaletteColor = { hex ->
                    val nextGroups = ColorApplyUseCase.applyHexToAllGroups(groups, hex)
                    groups = nextGroups
                    launchDeviceAction(
                        successMessage = context.getString(R.string.status_palette_applied),
                        demoMessage = context.getString(R.string.status_demo_palette_applied),
                    ) {
                        repository.applyGroups(globalState.deviceAddr, nextGroups)
                    }
                },
                onStartOta = {
                    effectViewModel.stop(globalState.deviceAddr)
                    otaViewModel.start(globalState.deviceAddr)
                },
                onCancelOta = { otaViewModel.cancel(globalState.deviceAddr) },
            )

            AppScreen.SHARE -> ShareScreen(
                viewModel = shareViewModel,
                effectPrograms = effectState.programs,
                paletteEntries = customPaletteState.entries,
                initialToken = incomingShareToken,
                onInitialTokenConsumed = onShareTokenConsumed,
                onBack = { screen = shareReturnScreen },
                modifier = androidx.compose.ui.Modifier.padding(innerPadding),
            )
        }
    }
}
