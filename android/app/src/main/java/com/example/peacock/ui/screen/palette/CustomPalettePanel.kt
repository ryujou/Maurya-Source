package com.example.peacock.ui.screen.palette

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Color as AndroidColor
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.gestures.detectTransformGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ElevatedCard
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Slider
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import coil.compose.AsyncImage
import com.example.peacock.feature.palette.AvatarTransform
import com.example.peacock.feature.palette.CustomAvatarProcessor
import com.example.peacock.feature.palette.CustomPaletteEntry
import com.example.peacock.feature.palette.CustomPaletteViewModel
import com.example.peacock.ui.collectAsStateCompat
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.time.LocalDate

private data class EditorState(
    val existing: CustomPaletteEntry? = null,
    val bitmap: Bitmap? = null,
    val transform: AvatarTransform = AvatarTransform(),
    val nameZh: String = "",
    val nameJa: String = "",
    val hex: String = "#66CCFF",
    val candidates: List<String> = emptyList(),
)

@Composable
fun CustomPalettePanel(
    viewModel: CustomPaletteViewModel,
    useJapanese: Boolean,
    onApplyColor: (String) -> Unit,
    modifier: Modifier = Modifier,
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val state by viewModel.state.collectAsStateCompat()
    var editor by remember { mutableStateOf<EditorState?>(null) }
    var query by remember { mutableStateOf("") }
    var message by remember { mutableStateOf("") }
    var importBytes by remember { mutableStateOf<ByteArray?>(null) }
    var deleteTarget by remember { mutableStateOf<CustomPaletteEntry?>(null) }

    val photoPicker = rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()) { uri ->
        if (uri != null) scope.launch {
            runCatching { withContext(Dispatchers.IO) { CustomAvatarProcessor.decode(context.contentResolver, uri) } }
                .onSuccess { bitmap ->
                    val crop = CustomAvatarProcessor.crop(bitmap, AvatarTransform())
                    editor = editor?.copy(bitmap = bitmap, transform = AvatarTransform(),
                        candidates = CustomAvatarProcessor.candidateColors(crop))
                    crop.recycle()
                }.onFailure { message = it.message.orEmpty() }
        }
    }
    val exportLauncher = rememberLauncherForActivityResult(ActivityResultContracts.CreateDocument("application/json")) { uri ->
        if (uri != null) scope.launch {
            runCatching { viewModel.exportBackup() }.onSuccess { bytes ->
                context.contentResolver.openOutputStream(uri)?.use { it.write(bytes) }
                message = if (useJapanese) "バックアップを書き出しました" else "备份已导出"
            }.onFailure { message = it.message.orEmpty() }
        }
    }
    val importLauncher = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        if (uri != null) scope.launch {
            importBytes = runCatching { withContext(Dispatchers.IO) {
                context.contentResolver.openInputStream(uri)?.use { it.readBytes() } ?: error("empty file")
            } }.onFailure { message = it.message.orEmpty() }.getOrNull()
        }
    }

    val filtered = state.entries.filter { entry ->
        query.isBlank() || listOf(entry.nameZh, entry.nameJa, entry.hex).any { it.contains(query, true) }
    }
    Column(modifier = modifier, verticalArrangement = Arrangement.spacedBy(12.dp)) {
        ElevatedCard(Modifier.fillMaxWidth()) {
            Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Text(if (useJapanese) "マイ応援カラー" else "我的应援色", style = MaterialTheme.typography.titleLarge)
                Text(
                    if (useJapanese) "この端末に保存されます。バックアップでWeb版と手動移行できます。"
                    else "保存在当前手机，可通过通用备份与Web版手动迁移。",
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                Text("${state.entries.size}/${state.limit} · ${"%.1f".format(state.usedBytes / 1024.0)} KiB")
                Button(
                    onClick = { editor = EditorState() },
                    enabled = state.entries.size < state.limit,
                    modifier = Modifier.fillMaxWidth().testTag("custom-palette-add"),
                ) { Text(if (useJapanese) "応援カラーを追加" else "新增应援色") }
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    OutlinedButton(onClick = {
                        exportLauncher.launch("maurya-colors-${LocalDate.now()}.maurya-colors.json")
                    }, modifier = Modifier.weight(1f)) { Text(if (useJapanese) "書き出す" else "导出") }
                    OutlinedButton(onClick = { importLauncher.launch(arrayOf("application/json", "text/json")) },
                        modifier = Modifier.weight(1f)) { Text(if (useJapanese) "読み込む" else "导入") }
                }
                OutlinedTextField(query, { query = it }, label = { Text(if (useJapanese) "検索" else "搜索") },
                    singleLine = true, modifier = Modifier.fillMaxWidth())
                if (message.isNotBlank()) Text(message, color = MaterialTheme.colorScheme.secondary)
            }
        }

        if (filtered.isEmpty()) {
            Text(if (useJapanese) "マイ応援カラーはまだありません" else "还没有自定义应援色",
                modifier = Modifier.padding(18.dp))
        } else {
            Column(verticalArrangement = Arrangement.spacedBy(9.dp)) {
                filtered.forEach { entry ->
                    CustomEntryCard(entry, useJapanese, onApplyColor,
                        onEdit = {
                            val bitmap = BitmapFactory.decodeFile(entry.avatarPath)
                            editor = EditorState(entry, bitmap, AvatarTransform(), entry.nameZh, entry.nameJa, entry.hex)
                        }, onDelete = { deleteTarget = entry })
                }
            }
        }
    }

    editor?.let { value ->
        CustomEditorDialog(value, useJapanese,
            onChange = { editor = it },
            onChoosePhoto = { photoPicker.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)) },
            onDismiss = { value.bitmap?.recycle(); editor = null },
            onSave = { applyAfter ->
                val bitmap = value.bitmap
                if (bitmap == null) { message = if (useJapanese) "画像を選択してください" else "请选择图片"; return@CustomEditorDialog }
                scope.launch {
                    val result = runCatching { withContext(Dispatchers.Default) {
                        val crop = CustomAvatarProcessor.crop(bitmap, value.transform)
                        CustomAvatarProcessor.compress(crop).also { crop.recycle() }
                    } }
                    result.onSuccess { bytes ->
                        viewModel.save(value.existing?.id, value.existing?.revision ?: 0,
                            value.nameZh, value.nameJa, normalizeHex(value.hex) ?: value.hex, bytes) { saved ->
                            saved.onSuccess {
                                editor = null
                                message = if (useJapanese) "保存しました" else "保存成功"
                                if (applyAfter) onApplyColor(it.hex)
                            }.onFailure { message = it.message.orEmpty() }
                        }
                    }.onFailure { message = it.message.orEmpty() }
                }
            })
    }

    importBytes?.let { bytes ->
        AlertDialog(onDismissRequest = { importBytes = null },
            title = { Text(if (useJapanese) "重複するデータ" else "导入冲突") },
            text = { Text(if (useJapanese) "同じIDは既存データを保持します。上書きも選択できます。" else "默认保留同ID现有条目，也可选择覆盖。") },
            confirmButton = { TextButton(onClick = {
                scope.launch { runCatching { viewModel.importBackup(bytes, true) }
                    .onSuccess { message = if (useJapanese) "${it}件読み込みました" else "已导入${it}项" }
                    .onFailure { message = it.message.orEmpty() }; importBytes = null }
            }) { Text(if (useJapanese) "上書き" else "覆盖") } },
            dismissButton = { TextButton(onClick = {
                scope.launch { runCatching { viewModel.importBackup(bytes, false) }
                    .onSuccess { message = if (useJapanese) "${it}件読み込みました" else "已导入${it}项" }
                    .onFailure { message = it.message.orEmpty() }; importBytes = null }
            }) { Text(if (useJapanese) "既存を保持" else "保留现有") } })
    }
    deleteTarget?.let { entry ->
        AlertDialog(onDismissRequest = { deleteTarget = null }, title = { Text(if (useJapanese) "削除しますか？" else "确认删除？") },
            confirmButton = { TextButton(onClick = { viewModel.delete(entry) { it.onFailure { error -> message = error.message.orEmpty() } }; deleteTarget = null }) { Text(if (useJapanese) "削除" else "删除") } },
            dismissButton = { TextButton(onClick = { deleteTarget = null }) { Text(if (useJapanese) "キャンセル" else "取消") } })
    }
}

@Composable
private fun CustomEntryCard(entry: CustomPaletteEntry, useJapanese: Boolean, onApply: (String) -> Unit,
                            onEdit: () -> Unit, onDelete: () -> Unit) {
    ElevatedCard(Modifier.fillMaxWidth()) {
        Row(Modifier.padding(11.dp), verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(11.dp)) {
            AsyncImage(entry.avatarPath, entry.displayName(useJapanese), Modifier.size(58.dp).clip(CircleShape), contentScale = ContentScale.Crop)
            Column(Modifier.weight(1f).clickable { onApply(entry.hex) }) {
                Text(entry.displayName(useJapanese), maxLines = 1, overflow = TextOverflow.Ellipsis, fontWeight = FontWeight.SemiBold)
                Text(entry.hex, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            Column {
                TextButton(onClick = onEdit) { Text(if (useJapanese) "編集" else "编辑") }
                TextButton(onClick = onDelete) { Text(if (useJapanese) "削除" else "删除") }
            }
        }
    }
}

@Composable
private fun CustomEditorDialog(state: EditorState, useJapanese: Boolean, onChange: (EditorState) -> Unit,
                               onChoosePhoto: () -> Unit, onDismiss: () -> Unit, onSave: (Boolean) -> Unit) {
    var hsv by remember(state.hex) { mutableStateOf(hexToHsv(state.hex)) }
    val contentMaxHeight = (LocalConfiguration.current.screenHeightDp * 0.56f).dp
    AlertDialog(modifier = Modifier.imePadding().testTag("custom-palette-editor"), onDismissRequest = onDismiss,
        title = { Text(if (state.existing == null) (if (useJapanese) "応援カラーを追加" else "新增应援色") else (if (useJapanese) "応援カラーを編集" else "编辑应援色")) },
        text = {
            LazyColumn(
                modifier = Modifier.heightIn(max = contentMaxHeight),
                verticalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                item {
                    CropPreview(state.bitmap, state.transform) { zoom, panX, panY ->
                        onChange(state.copy(transform = state.transform.copy(
                            zoom = (state.transform.zoom * zoom).coerceIn(1f, 6f),
                            panX = state.transform.panX + panX,
                            panY = state.transform.panY + panY)))
                    }
                }
                item { Button(onClick = onChoosePhoto, modifier = Modifier.fillMaxWidth()) { Text(if (useJapanese) "画像を選択" else "选择图片") } }
                item { Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    OutlinedButton(onClick = { onChange(state.copy(transform = state.transform.copy(rotation = (state.transform.rotation + 90) % 360))) }, Modifier.weight(1f)) { Text("90°") }
                    OutlinedButton(onClick = { onChange(state.copy(transform = AvatarTransform())) }, Modifier.weight(1f)) { Text(if (useJapanese) "リセット" else "重置") }
                } }
                item { OutlinedTextField(state.nameZh, { onChange(state.copy(nameZh = it.take(32))) }, label = { Text(if (useJapanese) "中国語名" else "中文名称") }, singleLine = true) }
                item { OutlinedTextField(state.nameJa, { onChange(state.copy(nameJa = it.take(32))) }, label = { Text(if (useJapanese) "日本語名" else "日文名称") }, singleLine = true) }
                if (state.bitmap != null) item {
                    OutlinedButton(onClick = {
                        val crop = CustomAvatarProcessor.crop(state.bitmap, state.transform)
                        val colors = CustomAvatarProcessor.candidateColors(crop); crop.recycle()
                        onChange(state.copy(candidates = colors, hex = colors.firstOrNull() ?: state.hex))
                    }, Modifier.fillMaxWidth()) { Text(if (useJapanese) "現在の切り抜きから色を抽出" else "从当前裁剪提取颜色") }
                }
                if (state.candidates.isNotEmpty()) item { Row(horizontalArrangement = Arrangement.spacedBy(9.dp)) {
                    state.candidates.forEach { hex -> Box(Modifier.size(39.dp).clip(CircleShape).background(Color(AndroidColor.parseColor(hex))).border(2.dp, Color.White, CircleShape).clickable { onChange(state.copy(hex = hex)) }) }
                } }
                item { HsvColorPad(hsv) { next -> hsv = next; onChange(state.copy(hex = hsvToHex(next))) } }
                item { Text("Hue ${hsv[0].toInt()}"); Slider(hsv[0], { hsv = floatArrayOf(it, hsv[1], hsv[2]); onChange(state.copy(hex = hsvToHex(hsv))) }, valueRange = 0f..359f) }
                item { OutlinedTextField(state.hex, { value -> normalizeHex(value)?.let { onChange(state.copy(hex = it)); hsv = hexToHsv(it) } }, label = { Text("HEX") }, singleLine = true) }
            }
        },
        confirmButton = {
            Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Button(onClick = { onSave(true) }, modifier = Modifier.fillMaxWidth()) {
                    Text(if (useJapanese) "保存して適用" else "保存并应用")
                }
                OutlinedButton(onClick = { onSave(false) }, modifier = Modifier.fillMaxWidth()) {
                    Text(if (useJapanese) "保存のみ" else "仅保存")
                }
                TextButton(onClick = onDismiss, modifier = Modifier.fillMaxWidth()) {
                    Text(if (useJapanese) "キャンセル" else "取消")
                }
            }
        })
}

@Composable
private fun CropPreview(bitmap: Bitmap?, transform: AvatarTransform, onGesture: (Float, Float, Float) -> Unit) {
    Box(Modifier.fillMaxWidth().aspectRatio(1f).clip(RoundedCornerShape(16.dp)).background(Color(0xFF090B12))
        .pointerInput(bitmap) { detectTransformGestures { _, pan, zoom, _ -> onGesture(zoom, pan.x, pan.y) } }, contentAlignment = Alignment.Center) {
        if (bitmap != null) Image(bitmap.asImageBitmap(), null, Modifier.fillMaxWidth().graphicsLayer {
            scaleX = transform.zoom; scaleY = transform.zoom; translationX = transform.panX; translationY = transform.panY; rotationZ = transform.rotation.toFloat()
        }, contentScale = ContentScale.Crop)
        else Text("96×96")
        Box(Modifier.matchParentSize().padding(12.dp).border(3.dp, Color.White, CircleShape))
    }
}

@Composable
private fun HsvColorPad(hsv: FloatArray, onChange: (FloatArray) -> Unit) {
    val hueColor = Color.hsv(hsv[0], 1f, 1f)
    Canvas(Modifier.fillMaxWidth().height(120.dp).clip(RoundedCornerShape(10.dp))
        .background(Brush.verticalGradient(listOf(Color.Transparent, Color.Black)))
        .pointerInput(hsv[0]) { detectTapGestures { point ->
            onChange(floatArrayOf(hsv[0], (point.x / size.width).coerceIn(0f, 1f), (1f - point.y / size.height).coerceIn(0f, 1f)))
        } }) {
        drawRect(Brush.horizontalGradient(listOf(Color.White, hueColor)))
        drawRect(Brush.verticalGradient(listOf(Color.Transparent, Color.Black)))
        drawCircle(Color.White, 6.dp.toPx(), center = androidx.compose.ui.geometry.Offset(hsv[1] * size.width, (1f - hsv[2]) * size.height))
    }
}

private fun normalizeHex(value: String): String? = value.trim().uppercase().let { if (Regex("#[0-9A-F]{6}").matches(it)) it else null }
private fun hexToHsv(hex: String): FloatArray = FloatArray(3).also { AndroidColor.colorToHSV(runCatching { AndroidColor.parseColor(hex) }.getOrDefault(AndroidColor.CYAN), it) }
private fun hsvToHex(hsv: FloatArray): String = String.format("#%06X", 0xFFFFFF and AndroidColor.HSVToColor(hsv))
