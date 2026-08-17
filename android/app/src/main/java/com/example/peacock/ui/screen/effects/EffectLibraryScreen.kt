package com.example.peacock.ui.screen.effects

import android.annotation.SuppressLint
import android.Manifest
import android.content.pm.PackageManager
import android.graphics.Color
import android.graphics.Rect
import android.net.Uri
import android.view.HapticFeedbackConstants
import android.view.View
import android.view.ViewTreeObserver
import android.webkit.JavascriptInterface
import android.webkit.WebResourceRequest
import android.webkit.WebView
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ElevatedCard
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Slider
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.input.OffsetMapping
import androidx.compose.ui.text.input.TransformedText
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.compose.ui.platform.testTag
import androidx.webkit.WebViewAssetLoader
import androidx.webkit.WebViewClientCompat
import androidx.webkit.WebSettingsCompat
import androidx.webkit.WebViewFeature
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import com.example.peacock.feature.effects.EffectCompileIssue
import com.example.peacock.feature.effects.EffectGeometry
import com.example.peacock.feature.effects.EffectRgb
import com.example.peacock.feature.effects.EffectImportConflictStrategy
import com.example.peacock.feature.effects.EffectProgram
import com.example.peacock.feature.effects.EffectValue
import com.example.peacock.feature.effects.RuntimeInputKey
import com.example.peacock.feature.effects.EffectSourceKind
import com.example.peacock.feature.effects.EffectViewModel
import com.example.peacock.feature.runtime.GroupState
import com.example.peacock.ui.collectAsStateCompat
import com.example.peacock.ui.i18n.AppLanguage
import org.json.JSONArray
import org.json.JSONObject
import kotlin.math.cos
import kotlin.math.roundToInt
import kotlin.math.sin

@Composable
private fun VirtualInputSlider(
    label: String,
    value: Double,
    range: ClosedFloatingPointRange<Float>,
    onChange: (Double) -> Unit,
) {
    Column {
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
            Text(label)
            Text(
                "%.2f".format(value),
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        Slider(
            value = value.toFloat().coerceIn(range.start, range.endInclusive),
            onValueChange = { onChange(it.toDouble()) },
            valueRange = range,
        )
    }
}

private fun RuntimeInputKey.shortName(): String = name
    .removePrefix("SENSOR_")
    .removePrefix("AUDIO_")
    .lowercase()

private fun EffectValue.displayValue(): String = when (this) {
    is EffectValue.Number -> "%.2f".format(value)
    is EffectValue.Boolean -> value.toString()
    is EffectValue.Colour -> "${value.hue}/${value.saturation}/${value.value}"
    is EffectValue.Target -> value.name
    is EffectValue.ListValue -> "[${values.size}]"
}

@Composable
fun EffectLibraryScreen(
    viewModel: EffectViewModel,
    language: AppLanguage,
    groups: List<GroupState>,
    deviceAddress: Int,
    connected: Boolean,
    modifier: Modifier = Modifier,
) {
    val state by viewModel.state.collectAsStateCompat()
    val japanese = language == AppLanguage.JA_JP
    var pendingExport by remember { mutableStateOf<EffectProgram?>(null) }
    var exportingAll by remember { mutableStateOf(false) }
    var pendingCreateKind by remember { mutableStateOf<EffectSourceKind?>(null) }
    var pendingRename by remember { mutableStateOf<EffectProgram?>(null) }
    var pendingMicrophonePlay by remember { mutableStateOf<EffectProgram?>(null) }
    var audioSensitivity by remember { mutableStateOf(1f) }
    val context = LocalContext.current
    val microphonePermission = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission(),
    ) { granted ->
        val program = pendingMicrophonePlay
        pendingMicrophonePlay = null
        if (granted && program != null) {
            viewModel.play(program, groups, deviceAddress)
        } else if (!granted) {
            viewModel.reportInputError(
                if (japanese) "マイク権限がないため再生できません"
                else "未授予麦克风权限，无法播放该程序",
            )
        }
    }
    fun requestPlay(program: EffectProgram) {
        if (viewModel.requiresMicrophone(program) &&
            context.checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED
        ) {
            pendingMicrophonePlay = program
            microphonePermission.launch(Manifest.permission.RECORD_AUDIO)
        } else {
            viewModel.play(program, groups, deviceAddress)
        }
    }
    val exportLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.CreateDocument("application/json"),
    ) { uri: Uri? ->
        uri?.let { viewModel.exportProgram(it, if (exportingAll) null else pendingExport) }
        pendingExport = null
        exportingAll = false
    }
    val importLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.OpenDocument(),
    ) { uri: Uri? -> uri?.let(viewModel::previewImport) }

    Box(modifier.fillMaxSize()) {
        Column(
            Modifier
                .fillMaxSize()
                .padding(bottom = if (state.isPlaying) 116.dp else 0.dp)
                .testTag("effects-page")
                .verticalScroll(rememberScrollState()),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            ElevatedCard(Modifier.fillMaxWidth()) {
            Column(Modifier.padding(18.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                    Column {
                        Text(
                            if (japanese) "エフェクトプログラミング" else "效果编程",
                            style = MaterialTheme.typography.headlineSmall,
                        )
                        Text(
                            if (japanese) "RAM一時制御・Flashへ保存しません" else "RAM临时控制 · 不写Flash",
                            color = MaterialTheme.colorScheme.secondary,
                        )
                    }
                    Box(
                        Modifier.size(12.dp).background(
                            if (connected) androidx.compose.ui.graphics.Color(0xFF7CE6AE)
                            else androidx.compose.ui.graphics.Color.Gray,
                            CircleShape,
                        ),
                    )
                }
                if (state.isPlaying) {
                    Text("${if (japanese) "再生中" else "正在播放"}：${state.playingName}")
                    state.progress?.let {
                        LinearProgressIndicator(progress = { it }, modifier = Modifier.fillMaxWidth())
                    }
                    SevenRaySimulator(
                        state.preview,
                        state.previewPixels,
                        Modifier.fillMaxWidth().height(150.dp),
                    )
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        OutlinedButton(onClick = viewModel::togglePause, modifier = Modifier.weight(1f)) {
                            Text(
                                if (state.isPaused) {
                                    if (japanese) "再開" else "继续"
                                } else if (japanese) "一時停止" else "暂停",
                            )
                        }
                        Button(
                            onClick = { viewModel.stop(deviceAddress) },
                            modifier = Modifier.weight(1f),
                        ) { Text(if (japanese) "停止して復元" else "停止并恢复") }
                    }
                }
                if (state.status.isNotBlank()) {
                    Text(state.status, color = MaterialTheme.colorScheme.primary)
                }
                if (state.firmwareVersion.isNotBlank()) {
                    Text(
                        "${if (japanese) "ファームウェア" else "固件"} ${state.firmwareVersion}",
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        style = MaterialTheme.typography.labelLarge,
                    )
                }
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Button(
                        onClick = { pendingCreateKind = EffectSourceKind.BLOCKS },
                        modifier = Modifier.weight(1f).testTag("effect-new-blocks"),
                    ) { Text(if (japanese) "ブロックで作成" else "新建积木") }
                    Button(
                        onClick = { pendingCreateKind = EffectSourceKind.SCRIPT },
                        modifier = Modifier.weight(1f).testTag("effect-new-script"),
                    ) { Text(if (japanese) "コードで作成" else "新建代码") }
                }
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    OutlinedButton(
                        onClick = { importLauncher.launch(arrayOf("application/json", "text/plain")) },
                        modifier = Modifier.weight(1f).testTag("effect-import"),
                    ) { Text(if (japanese) "インポート" else "导入程序") }
                    OutlinedButton(
                        onClick = {
                            exportingAll = true
                            exportLauncher.launch("Maurya-effects.maurya-effects.json")
                        },
                        modifier = Modifier.weight(1f).testTag("effect-export-all"),
                    ) { Text(if (japanese) "すべて書き出す" else "导出全部") }
                }
                if (state.transferStatus.isNotBlank()) {
                    Text(
                        localizedTransferStatus(state.transferStatus, japanese),
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.testTag("effect-transfer-status"),
                    )
                }
            }
        }
            ElevatedCard(Modifier.fillMaxWidth().testTag("effect-input-monitor")) {
                Column(
                    Modifier.padding(18.dp),
                    verticalArrangement = Arrangement.spacedBy(10.dp),
                ) {
                    Row(
                        Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Column(Modifier.weight(1f)) {
                            Text(
                                if (japanese) "リアルタイム入力" else "实时输入",
                                style = MaterialTheme.typography.titleLarge,
                            )
                            Text(
                                if (state.virtualInputsEnabled) {
                                    if (japanese) "仮想入力モード（実機センサー不要）" else "虚拟输入模式（无需真机传感器）"
                                } else {
                                    if (japanese) "端末センサーとマイクを使用" else "使用手机传感器与麦克风"
                                },
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                        Switch(
                            checked = state.virtualInputsEnabled,
                            onCheckedChange = viewModel::setVirtualInputsEnabled,
                        )
                    }
                    if (state.virtualInputsEnabled) {
                        VirtualInputSlider(
                            if (japanese) "モーション" else "运动强度",
                            state.virtualInputs[RuntimeInputKey.SENSOR_MOTION] ?: 0.0,
                            0f..1f,
                        ) { viewModel.setVirtualInput(RuntimeInputKey.SENSOR_MOTION, it) }
                        VirtualInputSlider(
                            if (japanese) "ロール" else "横滚角",
                            state.virtualInputs[RuntimeInputKey.SENSOR_ROLL] ?: 0.0,
                            -180f..180f,
                        ) { viewModel.setVirtualInput(RuntimeInputKey.SENSOR_ROLL, it) }
                        VirtualInputSlider(
                            if (japanese) "環境光" else "环境光",
                            state.virtualInputs[RuntimeInputKey.SENSOR_LIGHT] ?: 0.0,
                            0f..2_000f,
                        ) { viewModel.setVirtualInput(RuntimeInputKey.SENSOR_LIGHT, it) }
                        VirtualInputSlider(
                            if (japanese) "音量" else "音量",
                            state.virtualInputs[RuntimeInputKey.AUDIO_LEVEL] ?: 0.0,
                            0f..1f,
                        ) { viewModel.setVirtualInput(RuntimeInputKey.AUDIO_LEVEL, it) }
                        VirtualInputSlider(
                            "BPM",
                            state.virtualInputs[RuntimeInputKey.AUDIO_BPM] ?: 120.0,
                            40f..240f,
                        ) { viewModel.setVirtualInput(RuntimeInputKey.AUDIO_BPM, it) }
                    } else {
                        Row(
                            Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.spacedBy(8.dp),
                        ) {
                            OutlinedButton(
                                onClick = viewModel::zeroAttitude,
                                modifier = Modifier.weight(1f),
                            ) { Text(if (japanese) "姿勢をゼロ補正" else "姿态归零") }
                            Text(
                                state.runtimeSnapshot.values.entries.take(3).joinToString("  ") {
                                    "${it.key.shortName()}=${it.value.displayValue()}"
                                }.ifBlank {
                                    if (japanese) "再生時に入力値を表示" else "播放时显示输入值"
                                },
                                modifier = Modifier.weight(1f),
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                                style = MaterialTheme.typography.bodySmall,
                            )
                        }
                        Text(if (japanese) "マイク感度" else "麦克风灵敏度")
                        Slider(
                            value = audioSensitivity,
                            onValueChange = {
                                audioSensitivity = it
                                viewModel.setAudioSensitivity(it.toDouble())
                            },
                            valueRange = 0.25f..4f,
                        )
                    }
                }
            }
            state.programs.forEach { program ->
                ProgramCard(
                    program = program,
                    japanese = japanese,
                    playing = state.isPlaying,
                    onEdit = { viewModel.edit(program) },
                    onPlay = { requestPlay(program) },
                    onCopy = { viewModel.duplicate(program) },
                    onCopyAsScript = { viewModel.duplicateAsScript(program) },
                    onRename = { pendingRename = program },
                    onExport = {
                        pendingExport = program
                        exportingAll = false
                        exportLauncher.launch("${safeFileName(program.nameZh)}.maurya-effect.json")
                    },
                    onDelete = { viewModel.delete(program) },
                )
            }
        }

        if (state.isPlaying) {
            PlaybackDock(
                japanese = japanese,
                programName = state.playingName,
                paused = state.isPaused,
                onTogglePause = viewModel::togglePause,
                onStop = { viewModel.stop(deviceAddress) },
                modifier = Modifier.align(Alignment.BottomCenter),
            )
        }
    }

    pendingCreateKind?.let { kind ->
        ProgramNameDialog(
            japanese = japanese,
            title = when {
                kind == EffectSourceKind.BLOCKS && japanese -> "ブロックプログラム名"
                kind == EffectSourceKind.SCRIPT && japanese -> "コードプログラム名"
                kind == EffectSourceKind.BLOCKS -> "命名积木程序"
                else -> "命名代码程序"
            },
            initialNameZh = "",
            initialNameJa = "",
            confirmTag = "effect-name-create-confirm",
            onDismiss = { pendingCreateKind = null },
            onConfirm = { nameZh, nameJa ->
                viewModel.create(kind, nameZh, nameJa)
                pendingCreateKind = null
            },
        )
    }

    pendingRename?.let { program ->
        ProgramNameDialog(
            japanese = japanese,
            title = if (japanese) "プログラム名を変更" else "重命名程序",
            initialNameZh = program.nameZh,
            initialNameJa = program.nameJa,
            confirmTag = "effect-name-rename-confirm",
            onDismiss = { pendingRename = null },
            onConfirm = { nameZh, nameJa ->
                viewModel.rename(program, nameZh, nameJa)
                pendingRename = null
            },
        )
    }

    state.importPreview?.let { preview ->
        AlertDialog(
            onDismissRequest = viewModel::closeImportPreview,
            title = { Text(if (japanese) "インポート確認" else "导入预览") },
            text = {
                Column(
                    Modifier.heightIn(max = 360.dp).verticalScroll(rememberScrollState()),
                    verticalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    Text("${if (japanese) "有効" else "有效"}：${preview.programs.size}")
                    Text("${if (japanese) "競合" else "ID冲突"}：${preview.conflictIds.size}")
                    if (preview.errors.isNotEmpty()) {
                        Text(preview.errors.joinToString("\n"), color = MaterialTheme.colorScheme.error)
                    }
                    OutlinedButton(
                        onClick = { viewModel.applyImport(EffectImportConflictStrategy.OVERWRITE) },
                        modifier = Modifier.fillMaxWidth(),
                    ) {
                        Text(if (japanese) "競合を上書き" else "覆盖冲突项")
                    }
                    OutlinedButton(
                        onClick = { viewModel.applyImport(EffectImportConflictStrategy.SKIP) },
                        modifier = Modifier.fillMaxWidth(),
                    ) {
                        Text(if (japanese) "競合をスキップ" else "跳过冲突项")
                    }
                }
            },
            confirmButton = {
                TextButton(onClick = { viewModel.applyImport(EffectImportConflictStrategy.COPY) }) {
                    Text(if (japanese) "コピーとして追加" else "作为副本导入")
                }
            },
            dismissButton = {
                TextButton(onClick = viewModel::closeImportPreview) {
                    Text(if (japanese) "キャンセル" else "取消")
                }
            },
        )
    }

    state.editing?.let { program ->
        if (program.sourceKind == EffectSourceKind.BLOCKS) {
            BlockEditorDialog(
                program, language, state.editorError, state.editorIssue,
                state.preview, state.previewPixels,
                onClose = viewModel::closeEditor,
                onSave = viewModel::save,
                onPreview = { viewModel.preview(it, groups) },
                onPlay = {
                    if (viewModel.save(it)) {
                        requestPlay(viewModel.state.value.editing!!)
                    }
                },
            )
        } else {
            ScriptEditorDialog(
                program, language, state.editorError, state.editorIssue,
                state.preview, state.previewPixels,
                onClose = viewModel::closeEditor,
                onSave = viewModel::save,
                onPreview = { viewModel.preview(it, groups) },
                onPlay = {
                    if (viewModel.save(it)) {
                        requestPlay(viewModel.state.value.editing!!)
                    }
                },
            )
        }
    }
}

internal fun localizedTransferStatus(status: String, japanese: Boolean): String {
    val localized = status.split(" / ", limit = 2)
    return if (localized.size == 2) {
        if (japanese) localized[1] else localized[0]
    } else {
        status
    }
}

@Composable
private fun PlaybackDock(
    japanese: Boolean,
    programName: String,
    paused: Boolean,
    onTogglePause: () -> Unit,
    onStop: () -> Unit,
    modifier: Modifier = Modifier,
) {
    ElevatedCard(
        modifier
            .fillMaxWidth()
            .padding(horizontal = 8.dp, vertical = 6.dp)
            .testTag("effect-playback-dock"),
    ) {
        Column(
            Modifier.padding(horizontal = 12.dp, vertical = 10.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Text(
                "${if (japanese) "再生中" else "正在播放"}：$programName",
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                style = MaterialTheme.typography.labelLarge,
            )
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedButton(
                    onClick = onTogglePause,
                    modifier = Modifier.weight(1f).testTag("effect-floating-pause"),
                ) {
                    Text(
                        if (paused) {
                            if (japanese) "再開" else "继续"
                        } else if (japanese) "一時停止" else "暂停",
                    )
                }
                Button(
                    onClick = onStop,
                    modifier = Modifier.weight(1f).testTag("effect-floating-stop"),
                ) {
                    Text(if (japanese) "停止して復元" else "停止并恢复")
                }
            }
        }
    }
}

@Composable
private fun ProgramNameDialog(
    japanese: Boolean,
    title: String,
    initialNameZh: String,
    initialNameJa: String,
    confirmTag: String,
    onDismiss: () -> Unit,
    onConfirm: (String, String) -> Unit,
) {
    var nameZh by remember(initialNameZh) { mutableStateOf(initialNameZh) }
    var nameJa by remember(initialNameJa) { mutableStateOf(initialNameJa) }
    val valid = nameZh.isNotBlank() || nameJa.isNotBlank()
    AlertDialog(
        modifier = Modifier.imePadding().testTag("effect-name-dialog"),
        onDismissRequest = onDismiss,
        title = { Text(title) },
        text = {
            Column(
                Modifier.heightIn(max = 420.dp).verticalScroll(rememberScrollState()),
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                Text(
                    if (japanese) {
                        "中国語名または日本語名を1つ以上入力してください。空欄側には同じ名前を使用します。"
                    } else {
                        "中文名或日文名至少填写一个，空缺的语言会自动使用另一项名称。"
                    },
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                OutlinedTextField(
                    value = nameZh,
                    onValueChange = { nameZh = it.take(64) },
                    modifier = Modifier.fillMaxWidth().testTag("effect-name-zh"),
                    singleLine = true,
                    label = { Text(if (japanese) "中国語名" else "中文名称") },
                )
                OutlinedTextField(
                    value = nameJa,
                    onValueChange = { nameJa = it.take(64) },
                    modifier = Modifier.fillMaxWidth().testTag("effect-name-ja"),
                    singleLine = true,
                    label = { Text(if (japanese) "日本語名" else "日文名称") },
                )
            }
        },
        confirmButton = {
            TextButton(
                onClick = { onConfirm(nameZh, nameJa) },
                enabled = valid,
                modifier = Modifier.testTag(confirmTag),
            ) {
                Text(if (japanese) "決定" else "确定")
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) {
                Text(if (japanese) "キャンセル" else "取消")
            }
        },
    )
}

@Composable
private fun ProgramCard(
    program: EffectProgram,
    japanese: Boolean,
    playing: Boolean,
    onEdit: () -> Unit,
    onPlay: () -> Unit,
    onCopy: () -> Unit,
    onCopyAsScript: () -> Unit,
    onRename: () -> Unit,
    onExport: () -> Unit,
    onDelete: () -> Unit,
) {
    ElevatedCard(Modifier.fillMaxWidth().testTag("effect-program-${program.id}")) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                Text(
                    if (japanese) program.nameJa else program.nameZh,
                    style = MaterialTheme.typography.titleLarge,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.weight(1f),
                )
                Text(
                    if (program.sourceKind == EffectSourceKind.BLOCKS) {
                        if (japanese) "ブロック" else "积木"
                    } else {
                        if (japanese) "コード" else "代码"
                    },
                    color = MaterialTheme.colorScheme.secondary,
                    style = MaterialTheme.typography.labelLarge,
                )
            }
            Text(
                buildString {
                    append("${program.blockCount} ${if (japanese) "ステップ" else "个步骤"} · ")
                    append(
                        program.estimatedDurationMs?.let { "${it / 1000.0}s" } ?: run {
                            val infinite = if (program.sourceKind == EffectSourceKind.BLOCKS) {
                                program.workspaceJson.contains("\"maurya_forever\"")
                            } else program.scriptSource.contains("forever")
                            if (infinite) {
                                if (japanese) "無限ループ" else "无限循环"
                            } else if (japanese) "動的" else "动态"
                        },
                    )
                },
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Button(onClick = onPlay, enabled = !playing, modifier = Modifier.weight(1f)) {
                    Text("▶ ${if (japanese) "再生" else "播放"}")
                }
                OutlinedButton(
                    onClick = onEdit,
                    modifier = Modifier.weight(1f)
                        .testTag("effect-edit-${safeFileName(program.nameZh)}"),
                ) {
                    Text(if (japanese) "編集" else "编辑")
                }
            }
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedButton(onClick = onCopy, modifier = Modifier.weight(1f)) {
                    Text(if (japanese) "複製" else "复制")
                }
                if (program.sourceKind == EffectSourceKind.BLOCKS) {
                    OutlinedButton(onClick = onCopyAsScript, modifier = Modifier.weight(1f)) {
                        Text(if (japanese) "コード化" else "复制为代码")
                    }
                } else {
                    OutlinedButton(onClick = onExport, modifier = Modifier.weight(1f)) {
                        Text(if (japanese) "書き出す" else "导出")
                    }
                }
            }
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedButton(
                    onClick = onRename,
                    modifier = Modifier.weight(1f)
                        .testTag("effect-rename-${safeFileName(program.nameZh)}"),
                ) {
                    Text(if (japanese) "名前変更" else "重命名")
                }
                if (program.sourceKind == EffectSourceKind.BLOCKS) {
                    OutlinedButton(onClick = onExport, modifier = Modifier.weight(1f)) {
                        Text(if (japanese) "書き出す" else "导出")
                    }
                } else {
                    OutlinedButton(onClick = onDelete, modifier = Modifier.weight(1f)) {
                        Text(if (japanese) "削除" else "删除")
                    }
                }
            }
            if (program.sourceKind == EffectSourceKind.BLOCKS) {
                OutlinedButton(onClick = onDelete, modifier = Modifier.fillMaxWidth()) {
                    Text(if (japanese) "削除" else "删除")
                }
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun BlockEditorDialog(
    program: EffectProgram,
    language: AppLanguage,
    error: String,
    issue: EffectCompileIssue?,
    preview: List<GroupState>,
    previewPixels: List<EffectRgb>?,
    onClose: () -> Unit,
    onSave: (String) -> Boolean,
    onPreview: (String) -> Unit,
    onPlay: (String) -> Unit,
) {
    var webView by remember { mutableStateOf<WebView?>(null) }
    var blocks by remember { mutableIntStateOf(program.blockCount) }
    fun withJson(action: (String) -> Unit) {
        evaluateString(webView, "window.MauryaEditor.save()", action)
    }
    EditorScaffold(
        title = if (language == AppLanguage.JA_JP) program.nameJa else program.nameZh,
        subtitle = "$blocks blocks",
        language = language,
        error = error,
        issue = issue,
        preview = preview,
        previewPixels = previewPixels,
        onClose = onClose,
        onUndo = { webView?.evaluateJavascript("MauryaEditor.undo()", null) },
        onRedo = { webView?.evaluateJavascript("MauryaEditor.redo()", null) },
        onFormat = null,
        onSave = { withJson { onSave(it) } },
        onPreview = { withJson(onPreview) },
        onPlay = { withJson(onPlay) },
        onQuickFix = {
            val fix = issue ?: return@EditorScaffold
            val millis = fix.quickFixWaitMs ?: return@EditorScaffold
            webView?.evaluateJavascript(
                "MauryaEditor.insertWaitAfter(${JSONObject.quote(fix.sourceId)},$millis)",
            ) { withJson { onSave(it) } }
        },
        editorTag = "effect-block-editor",
    ) {
        BlockEditorWebView(
            program.workspaceJson,
            language,
            onReady = { webView = it },
            onBlocks = { blocks = it },
            modifier = Modifier.fillMaxSize(),
        )
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ScriptEditorDialog(
    program: EffectProgram,
    language: AppLanguage,
    error: String,
    issue: EffectCompileIssue?,
    preview: List<GroupState>,
    previewPixels: List<EffectRgb>?,
    onClose: () -> Unit,
    onSave: (String) -> Boolean,
    onPreview: (String) -> Unit,
    onPlay: (String) -> Unit,
) {
    var source by remember(program.id) { mutableStateOf(program.scriptSource) }
    var undoStack by remember(program.id) { mutableStateOf(emptyList<String>()) }
    var redoStack by remember(program.id) { mutableStateOf(emptyList<String>()) }
    fun updateSource(next: String, recordUndo: Boolean = true) {
        if (next == source) return
        if (recordUndo) {
            undoStack = (undoStack + source).takeLast(50)
            redoStack = emptyList()
        }
        source = next
    }
    val lines = source.lineSequence().count()
    EditorScaffold(
        title = if (language == AppLanguage.JA_JP) program.nameJa else program.nameZh,
        subtitle = "$lines L · Script",
        language = language,
        error = error,
        issue = issue,
        preview = preview,
        previewPixels = previewPixels,
        onClose = onClose,
        onUndo = {
            undoStack.lastOrNull()?.let { previous ->
                redoStack = (redoStack + source).takeLast(50)
                undoStack = undoStack.dropLast(1)
                source = previous
            }
        },
        onRedo = {
            redoStack.lastOrNull()?.let { next ->
                undoStack = (undoStack + source).takeLast(50)
                redoStack = redoStack.dropLast(1)
                source = next
            }
        },
        onFormat = { updateSource(formatMauryaScript(source)) },
        onSave = { onSave(source) },
        onPreview = { onPreview(source) },
        onPlay = { onPlay(source) },
        onQuickFix = {
            val fix = issue ?: return@EditorScaffold
            val offset = fix.sourceEnd ?: return@EditorScaffold
            val millis = fix.quickFixWaitMs ?: return@EditorScaffold
            val fixed = insertScriptWait(source, offset, millis)
            updateSource(fixed)
            onSave(fixed)
        },
        editorTag = "effect-script-editor",
    ) {
        NativeScriptEditor(
            source = source,
            issue = issue,
            onSourceChange = ::updateSource,
            modifier = Modifier.fillMaxSize(),
        )
    }
}

@Composable
private fun NativeScriptEditor(
    source: String,
    issue: EffectCompileIssue?,
    onSourceChange: (String) -> Unit,
    modifier: Modifier = Modifier,
) {
    val scroll = rememberScrollState()
    Box(
        modifier
            .background(androidx.compose.ui.graphics.Color(0xFF070912.toInt()))
            .border(
                1.dp,
                androidx.compose.ui.graphics.Color(0xFF252B42.toInt()),
                RoundedCornerShape(8.dp),
            )
            .padding(12.dp)
            .testTag("effect-script-native-editor"),
    ) {
        BasicTextField(
            value = source,
            onValueChange = onSourceChange,
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(scroll)
                .testTag("effect-script-source"),
            textStyle = TextStyle(
                color = androidx.compose.ui.graphics.Color(0xFFF5F6FF.toInt()),
                fontFamily = FontFamily.Monospace,
                fontSize = 16.sp,
                lineHeight = 23.sp,
            ),
            cursorBrush = SolidColor(androidx.compose.ui.graphics.Color(0xFFB8C5FF.toInt())),
            visualTransformation = remember(issue) { MauryaScriptVisualTransformation(issue) },
        )
    }
}

private class MauryaScriptVisualTransformation(
    private val issue: EffectCompileIssue?,
) : VisualTransformation {
    override fun filter(text: AnnotatedString): TransformedText {
        val styled = AnnotatedString.Builder(text)
        val source = text.text
        Regex(
            """\b(effect|forever|repeat|for|while|if|else|break|continue|wait|fade|var|true|false|all|group|mode|color|hsv|set|add|STROBE|STATIC)\b""",
        ).findAll(source).forEach {
            styled.addStyle(
                SpanStyle(color = androidx.compose.ui.graphics.Color(0xFFB8C5FF.toInt())),
                it.range.first,
                it.range.last + 1,
            )
        }
        Regex("\"(?:\\\\.|[^\"\\\\])*\"").findAll(source).forEach {
            styled.addStyle(
                SpanStyle(color = androidx.compose.ui.graphics.Color(0xFF7CE6AE.toInt())),
                it.range.first,
                it.range.last + 1,
            )
        }
        Regex("""\b\d+(?:\.\d+)?(?:ms|s)?\b""").findAll(source).forEach {
            styled.addStyle(
                SpanStyle(color = androidx.compose.ui.graphics.Color(0xFFC8AA70.toInt())),
                it.range.first,
                it.range.last + 1,
            )
        }
        Regex("""//[^\n]*""").findAll(source).forEach {
            styled.addStyle(
                SpanStyle(color = androidx.compose.ui.graphics.Color(0xFF7E859E.toInt())),
                it.range.first,
                it.range.last + 1,
            )
        }
        val start = issue?.sourceStart
        val end = issue?.sourceEnd
        if (start != null && end != null && start in 0..source.length && end in start..source.length) {
            styled.addStyle(
                SpanStyle(
                    color = androidx.compose.ui.graphics.Color(0xFFFFB4AB.toInt()),
                    background = androidx.compose.ui.graphics.Color(0x553F1010),
                ),
                start,
                end,
            )
        }
        return TransformedText(styled.toAnnotatedString(), OffsetMapping.Identity)
    }
}

private fun formatMauryaScript(source: String): String {
    var indent = 0
    return source.lineSequence().joinToString("\n") { raw ->
        val line = raw.trim()
        if (line.startsWith("}")) indent = (indent - 1).coerceAtLeast(0)
        val formatted = "    ".repeat(indent) + line
        if (line.endsWith("{")) indent++
        formatted
    }.trimEnd() + "\n"
}

private fun insertScriptWait(source: String, offset: Int, millis: Long): String {
    val safeOffset = offset.coerceIn(0, source.length)
    val lineStart = source.lastIndexOf('\n', (safeOffset - 1).coerceAtLeast(0))
        .let { if (it < 0) 0 else it + 1 }
    val indent = source.substring(lineStart, safeOffset)
        .takeWhile { it == ' ' || it == '\t' }
    val insertion = "\n${indent}wait(${millis}ms);"
    return source.substring(0, safeOffset) + insertion + source.substring(safeOffset)
}

internal fun localizedEditorError(
    language: AppLanguage,
    fallback: String,
    issue: EffectCompileIssue?,
): String = when {
    issue == null -> fallback
    language == AppLanguage.JA_JP -> issue.messageJa
    else -> issue.messageZh
}

private data class EditorSystemInsets(
    val left: androidx.compose.ui.unit.Dp,
    val right: androidx.compose.ui.unit.Dp,
    val bottom: androidx.compose.ui.unit.Dp,
)

@Composable
private fun rememberEditorSystemInsets(): EditorSystemInsets {
    val view = LocalView.current
    val density = LocalDensity.current
    var leftPx by remember(view) { mutableIntStateOf(0) }
    var rightPx by remember(view) { mutableIntStateOf(0) }
    var bottomPx by remember(view) { mutableIntStateOf(0) }

    DisposableEffect(view) {
        val visibleFrame = Rect()
        val location = IntArray(2)

        fun update() {
            if (!view.isAttachedToWindow || view.width <= 0 || view.height <= 0) return
            val rootInsets = ViewCompat.getRootWindowInsets(view)
            val navigation = rootInsets
                ?.getInsetsIgnoringVisibility(WindowInsetsCompat.Type.navigationBars())
            val ime = if (rootInsets?.isVisible(WindowInsetsCompat.Type.ime()) == true) {
                rootInsets.getInsets(WindowInsetsCompat.Type.ime())
            } else {
                null
            }

            view.getWindowVisibleDisplayFrame(visibleFrame)
            view.getLocationOnScreen(location)
            val viewBottom = location[1] + view.height
            val visibleBottomGap = if (!visibleFrame.isEmpty) {
                (viewBottom - visibleFrame.bottom).coerceAtLeast(0)
            } else {
                0
            }

            val newLeft = maxOf(navigation?.left ?: 0, ime?.left ?: 0)
            val newRight = maxOf(navigation?.right ?: 0, ime?.right ?: 0)
            val newBottom = maxOf(
                navigation?.bottom ?: 0,
                ime?.bottom ?: 0,
                visibleBottomGap,
            )
            if (newLeft != leftPx) leftPx = newLeft
            if (newRight != rightPx) rightPx = newRight
            if (newBottom != bottomPx) bottomPx = newBottom
        }

        val listener = ViewTreeObserver.OnGlobalLayoutListener(::update)
        view.viewTreeObserver.addOnGlobalLayoutListener(listener)
        view.post(::update)
        ViewCompat.requestApplyInsets(view)
        onDispose {
            if (view.viewTreeObserver.isAlive) {
                view.viewTreeObserver.removeOnGlobalLayoutListener(listener)
            }
        }
    }

    return with(density) {
        EditorSystemInsets(leftPx.toDp(), rightPx.toDp(), bottomPx.toDp())
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun EditorScaffold(
    title: String,
    subtitle: String,
    language: AppLanguage,
    error: String,
    issue: EffectCompileIssue?,
    preview: List<GroupState>,
    previewPixels: List<EffectRgb>?,
    onClose: () -> Unit,
    onUndo: () -> Unit,
    onRedo: () -> Unit,
    onFormat: (() -> Unit)?,
    onSave: () -> Unit,
    onPreview: () -> Unit,
    onPlay: () -> Unit,
    onQuickFix: () -> Unit,
    editorTag: String,
    content: @Composable () -> Unit,
) {
    val japanese = language == AppLanguage.JA_JP
    val configuration = LocalConfiguration.current
    val compactTopBar = configuration.screenWidthDp <= 360
    val compactHeight = configuration.screenHeightDp <= 620 ||
        configuration.screenWidthDp > configuration.screenHeightDp
    val visibleError = localizedEditorError(language, error, issue)
    Dialog(
        onDismissRequest = onClose,
        properties = DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false),
    ) {
        val systemInsets = rememberEditorSystemInsets()
        Scaffold(
            modifier = Modifier.fillMaxSize().testTag(editorTag),
            contentWindowInsets = WindowInsets(0, 0, 0, 0),
            topBar = {
                TopAppBar(
                    title = {
                        Column {
                            Text(title, maxLines = 1, overflow = TextOverflow.Ellipsis)
                            Text(
                                subtitle,
                                maxLines = 1,
                                overflow = TextOverflow.Ellipsis,
                                style = MaterialTheme.typography.labelSmall,
                            )
                        }
                    },
                    navigationIcon = {
                        IconButton(
                            onClick = onClose,
                            modifier = Modifier.size(36.dp).testTag("effect-editor-close"),
                        ) { Text("‹") }
                    },
                    actions = {
                        IconButton(
                            onClick = onUndo,
                            modifier = Modifier.size(36.dp).testTag("effect-editor-undo"),
                        ) { Text("↶") }
                        IconButton(
                            onClick = onRedo,
                            modifier = Modifier.size(36.dp).testTag("effect-editor-redo"),
                        ) { Text("↷") }
                        onFormat?.let { action ->
                            TextButton(
                                onClick = action,
                                modifier = Modifier.size(if (compactTopBar) 40.dp else 48.dp, 40.dp),
                                contentPadding = PaddingValues(0.dp),
                            ) {
                                Text(
                                    if (compactTopBar) "整" else if (japanese) "整形" else "格式",
                                    style = MaterialTheme.typography.labelMedium,
                                )
                            }
                        }
                        TextButton(
                            onClick = onSave,
                            modifier = Modifier
                                .size(if (compactTopBar) 40.dp else 48.dp, 40.dp)
                                .testTag("effect-editor-save"),
                            contentPadding = PaddingValues(0.dp),
                        ) {
                            Text(
                                if (compactTopBar) "存" else "保存",
                                style = MaterialTheme.typography.labelMedium,
                            )
                        }
                    },
                )
            },
            bottomBar = {
                Surface(color = MaterialTheme.colorScheme.surface) {
                    Row(
                        Modifier.fillMaxWidth()
                            .padding(
                                start = 12.dp + systemInsets.left,
                                top = 8.dp,
                                end = 12.dp + systemInsets.right,
                                bottom = 8.dp + systemInsets.bottom,
                            ),
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        OutlinedButton(
                            onClick = onPreview,
                            modifier = Modifier.weight(1f)
                                .heightIn(min = 48.dp)
                                .testTag("effect-editor-preview"),
                        ) {
                            Text(if (japanese) "プレビュー" else "预览")
                        }
                        Button(
                            onClick = onPlay,
                            modifier = Modifier.weight(1f)
                                .heightIn(min = 48.dp)
                                .testTag("effect-editor-play"),
                        ) {
                            Text(if (japanese) "再生" else "播放")
                        }
                    }
                }
            },
        ) { padding ->
            Column(Modifier.padding(padding).fillMaxSize()) {
                SevenRaySimulator(
                    preview,
                    previewPixels,
                    Modifier.fillMaxWidth().height(if (compactHeight) 60.dp else 84.dp),
                )
                Box(Modifier.weight(1f).fillMaxWidth()) { content() }
                if (visibleError.isNotBlank()) {
                    Column(
                        Modifier.fillMaxWidth()
                            .background(MaterialTheme.colorScheme.errorContainer)
                            .heightIn(max = if (compactHeight) 88.dp else 128.dp)
                            .verticalScroll(rememberScrollState())
                            .padding(8.dp)
                            .testTag("effect-editor-error"),
                    ) {
                        Text(visibleError, color = MaterialTheme.colorScheme.onErrorContainer)
                        if (issue?.quickFixWaitMs != null) {
                            TextButton(onClick = onQuickFix) {
                                Text(
                                    if (japanese) {
                                        "${issue.quickFixWaitMs} msの待機を追加"
                                    } else "一键补入${issue.quickFixWaitMs} ms等待",
                                )
                            }
                        }
                    }
                }
            }
        }
    }
}

@SuppressLint("SetJavaScriptEnabled")
@Composable
private fun BlockEditorWebView(
    workspace: String,
    language: AppLanguage,
    onReady: (WebView) -> Unit,
    onBlocks: (Int) -> Unit,
    modifier: Modifier,
) {
    EditorWebView(
        page = "index.html",
        language = language,
        initial = workspace,
        loadFunction = "MauryaEditor.load",
        readyExpression = "typeof window.MauryaEditor",
        bridge = {
            object {
                @JavascriptInterface fun onWorkspaceChanged(json: String, count: Int) {
                    it.post { onBlocks(count) }
                }
                @JavascriptInterface fun onSaveRequested(json: String) = Unit
                @JavascriptInterface fun onRunRequested(json: String) = Unit
                @JavascriptInterface fun onHaptic(kind: String) {
                    it.post { it.performHapticFeedback(HapticFeedbackConstants.CLOCK_TICK) }
                }
            }
        },
        onReady = onReady,
        modifier = modifier,
    )
}

@SuppressLint("SetJavaScriptEnabled")
@Composable
private fun ScriptEditorWebView(
    source: String,
    language: AppLanguage,
    onReady: (WebView) -> Unit,
    onLines: (Int) -> Unit,
    modifier: Modifier,
) {
    EditorWebView(
        page = "script.html",
        language = language,
        initial = source,
        loadFunction = "MauryaScriptEditor.load",
        readyExpression = "typeof window.MauryaScriptEditor",
        bridge = {
            object {
                @JavascriptInterface fun onSourceChanged(value: String, lines: Int) {
                    it.post { onLines(lines) }
                }
                @JavascriptInterface fun onHaptic(kind: String) {
                    it.post { it.performHapticFeedback(HapticFeedbackConstants.CLOCK_TICK) }
                }
            }
        },
        onReady = onReady,
        modifier = modifier,
    )
}

@SuppressLint("SetJavaScriptEnabled", "JavascriptInterface")
@Composable
private fun EditorWebView(
    page: String,
    language: AppLanguage,
    initial: String,
    loadFunction: String,
    readyExpression: String,
    bridge: (WebView) -> Any,
    onReady: (WebView) -> Unit,
    modifier: Modifier,
) {
    var created by remember { mutableStateOf<WebView?>(null) }
    val context = androidx.compose.ui.platform.LocalContext.current
    val loader = remember(context) {
        WebViewAssetLoader.Builder()
            .addPathHandler("/assets/", WebViewAssetLoader.AssetsPathHandler(context))
            .build()
    }
    AndroidView(
        factory = { context ->
            WebView(context).apply {
                created = this
                setLayerType(android.view.View.LAYER_TYPE_HARDWARE, null)
                setBackgroundColor(Color.TRANSPARENT)
                isFocusable = true
                isFocusableInTouchMode = true
                settings.javaScriptEnabled = true
                settings.allowFileAccess = false
                settings.allowContentAccess = false
                settings.domStorageEnabled = false
                settings.cacheMode = android.webkit.WebSettings.LOAD_NO_CACHE
                settings.mixedContentMode = android.webkit.WebSettings.MIXED_CONTENT_NEVER_ALLOW
                settings.textZoom = 100
                if (WebViewFeature.isFeatureSupported(WebViewFeature.ALGORITHMIC_DARKENING)) {
                    WebSettingsCompat.setAlgorithmicDarkeningAllowed(settings, false)
                }
                clearCache(true)
                addJavascriptInterface(bridge(this), "MauryaBridge")
                webViewClient = object : WebViewClientCompat() {
                    override fun shouldInterceptRequest(view: WebView, request: WebResourceRequest) =
                        loader.shouldInterceptRequest(request.url)

                    override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest) =
                        request.url.host != "appassets.androidplatform.net"

                    override fun onPageFinished(view: WebView, url: String) {
                        fun awaitEditor(attempt: Int = 0) {
                            view.evaluateJavascript(readyExpression) { type ->
                                if (type == "\"object\"") {
                                    view.evaluateJavascript(
                                        "$loadFunction(${JSONObject.quote(initial)})",
                                    ) {
                                        onReady(view)
                                    }
                                } else if (attempt < 40) {
                                    view.postDelayed({ awaitEditor(attempt + 1) }, 50)
                                }
                            }
                        }
                        awaitEditor()
                    }
                }
                loadUrl(
                    "https://appassets.androidplatform.net/assets/effect-editor/$page" +
                        "?v=409&lang=${if (language == AppLanguage.JA_JP) "ja" else "zh"}",
                )
            }
        },
        modifier = modifier,
    )
    DisposableEffect(Unit) { onDispose { created?.destroy() } }
}

private fun evaluateString(webView: WebView?, expression: String, action: (String) -> Unit) {
    webView?.evaluateJavascript(expression) { encoded ->
        runCatching { JSONArray("[$encoded]").getString(0) }.onSuccess(action)
    }
}

private fun safeFileName(value: String) =
    value.replace(Regex("[\\\\/:*?\"<>|]"), "_").ifBlank { "Maurya-effect" }

@Composable
fun SevenRaySimulator(
    groups: List<GroupState>,
    pixels: List<EffectRgb>? = null,
    modifier: Modifier = Modifier,
) {
    Canvas(modifier) {
        val center = Offset(size.width / 2, size.height * .88f)
        val length = size.minDimension * .62f
        groups.take(7).forEachIndexed { index, group ->
            val angle = Math.toRadians((-165 + index * 25).toDouble())
            val end = Offset(
                center.x + (cos(angle) * length).toFloat(),
                center.y + (sin(angle) * length).toFloat(),
            )
            val groupColor = androidx.compose.ui.graphics.Color(
                android.graphics.Color.HSVToColor(
                    floatArrayOf(group.hue.toFloat(), group.sat / 255f, group.value / 255f),
                ),
            )
            if (pixels?.size == EffectGeometry.PIXEL_COUNT) {
                repeat(EffectGeometry.PIXELS_PER_GROUP) { pixelIndex ->
                    val startRatio = pixelIndex / EffectGeometry.PIXELS_PER_GROUP.toFloat() + .015f
                    val endRatio =
                        (pixelIndex + 1) / EffectGeometry.PIXELS_PER_GROUP.toFloat() - .015f
                    val start = Offset(
                        center.x + (end.x - center.x) * startRatio,
                        center.y + (end.y - center.y) * startRatio,
                    )
                    val segmentEnd = Offset(
                        center.x + (end.x - center.x) * endRatio,
                        center.y + (end.y - center.y) * endRatio,
                    )
                    val pixel = pixels[index * EffectGeometry.PIXELS_PER_GROUP + pixelIndex]
                    val color = androidx.compose.ui.graphics.Color(
                        pixel.red, pixel.green, pixel.blue,
                    )
                    drawLine(
                        androidx.compose.ui.graphics.Color(0x44C8AA70),
                        start, segmentEnd, 18.dp.toPx(), StrokeCap.Round,
                    )
                    drawLine(color, start, segmentEnd, 10.dp.toPx(), StrokeCap.Round)
                }
            } else {
                drawLine(
                    androidx.compose.ui.graphics.Color(0x44C8AA70),
                    center, end, 22.dp.toPx(), StrokeCap.Round,
                )
                drawLine(groupColor, center, end, 13.dp.toPx(), StrokeCap.Round)
            }
        }
        drawCircle(androidx.compose.ui.graphics.Color(0xFF10131E), 22.dp.toPx(), center)
        drawCircle(
            androidx.compose.ui.graphics.Color(0xFFC8AA70),
            22.dp.toPx(),
            center,
            style = Stroke(2.dp.toPx()),
        )
    }
}
