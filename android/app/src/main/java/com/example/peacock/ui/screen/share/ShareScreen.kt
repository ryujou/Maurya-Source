package com.example.peacock.ui.screen.share

import android.Manifest
import android.content.pm.PackageManager
import android.graphics.BitmapFactory
import android.widget.Toast
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ElevatedCard
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat
import com.example.peacock.R
import com.example.peacock.feature.effects.EffectProgram
import com.example.peacock.feature.palette.CustomPaletteEntry
import com.example.peacock.feature.share.ShareKind
import com.example.peacock.feature.share.ShareQr
import com.example.peacock.feature.share.ShareQrScanner
import com.example.peacock.feature.share.ShareRepository
import com.example.peacock.feature.share.ShareSection
import com.example.peacock.feature.share.ShareViewModel
import com.example.peacock.ui.collectAsStateCompat
import com.example.peacock.ui.screen.effects.SevenRaySimulator

@Composable
fun ShareScreen(
    viewModel: ShareViewModel,
    effectPrograms: List<EffectProgram>,
    paletteEntries: List<CustomPaletteEntry>,
    initialToken: String? = null,
    onInitialTokenConsumed: () -> Unit = {},
    onBack: () -> Unit = {},
    modifier: Modifier = Modifier,
) {
    val state by viewModel.state.collectAsStateCompat()
    val context = LocalContext.current
    var code by rememberSaveable { mutableStateOf(initialToken.orEmpty()) }
    var scanning by rememberSaveable { mutableStateOf(false) }
    val cameraPermission = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission(),
    ) { granted ->
        scanning = granted
        if (!granted) Toast.makeText(context, "需要相机权限才能扫码", Toast.LENGTH_SHORT).show()
    }

    LaunchedEffect(initialToken) {
        if (!initialToken.isNullOrBlank()) {
            code = initialToken
            viewModel.load(initialToken)
            onInitialTokenConsumed()
        }
    }

    if (scanning) {
        AlertDialog(
            onDismissRequest = { scanning = false },
            title = { Text("扫描 Maurya 分享二维码") },
            text = {
                ShareQrScanner(
                    onResult = { value ->
                        scanning = false
                        code = value
                        viewModel.load(value)
                    },
                    onError = { message ->
                        scanning = false
                        Toast.makeText(context, message, Toast.LENGTH_SHORT).show()
                    },
                    modifier = Modifier.fillMaxWidth().height(360.dp),
                )
            },
            confirmButton = { TextButton(onClick = { scanning = false }) { Text("取消") } },
        )
    }

    Column(
        modifier = modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(stringResource(R.string.temporary_share), style = MaterialTheme.typography.headlineSmall)
            TextButton(onClick = onBack) { Text("返回") }
        }
        Text("单个灯效或应援色，匿名保存7天。服务端审核结果为准。")
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            SectionButton("创建分享", state.section == ShareSection.CREATE) {
                viewModel.show(ShareSection.CREATE)
            }
            SectionButton("导入分享", state.section == ShareSection.IMPORT) {
                viewModel.show(ShareSection.IMPORT)
            }
        }

        if (state.error.isNotBlank()) {
            ElevatedCard(Modifier.fillMaxWidth()) {
                Row(
                    Modifier.fillMaxWidth().padding(12.dp),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text(state.error, color = MaterialTheme.colorScheme.error, modifier = Modifier.weight(1f))
                    TextButton(onClick = viewModel::dismissError) { Text("关闭") }
                }
            }
        }
        if (state.status.isNotBlank()) Text(state.status, color = MaterialTheme.colorScheme.primary)
        if (state.busy) Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
            CircularProgressIndicator()
        }

        when (state.section) {
            ShareSection.CREATE -> CreateShareContent(
                effectPrograms,
                paletteEntries,
                viewModel,
                state.busy,
            )
            ShareSection.IMPORT -> ImportShareContent(
                code = code,
                onCodeChange = { code = it },
                onLoad = { viewModel.load(code) },
                onScan = {
                    if (ContextCompat.checkSelfPermission(context, Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED) {
                        scanning = true
                    } else cameraPermission.launch(Manifest.permission.CAMERA)
                },
                viewModel = viewModel,
                busy = state.busy,
            )
        }

        if (state.section == ShareSection.CREATE) state.created?.let { created ->
            ElevatedCard(Modifier.fillMaxWidth()) {
                Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Text("分享码 ${ShareRepository.shortCode(created.token)}")
                    Text("有效期至 ${created.expiresAt}", style = MaterialTheme.typography.bodySmall)
                    state.qrBitmap?.let { bitmap ->
                        Image(
                            bitmap.asImageBitmap(),
                            contentDescription = "Maurya分享二维码",
                            modifier = Modifier.fillMaxWidth().aspectRatio(1f)
                                .background(androidx.compose.ui.graphics.Color.White),
                        )
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            OutlinedButton(onClick = {
                                runCatching { ShareQr.save(context, bitmap) }
                                    .onSuccess { Toast.makeText(context, "二维码已保存", Toast.LENGTH_SHORT).show() }
                                    .onFailure { Toast.makeText(context, it.message, Toast.LENGTH_SHORT).show() }
                            }) { Text("保存图片") }
                            Button(onClick = {
                                runCatching { ShareQr.share(context, bitmap) }
                                    .onFailure { Toast.makeText(context, it.message, Toast.LENGTH_SHORT).show() }
                            }) { Text("系统分享") }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun SectionButton(label: String, selected: Boolean, action: () -> Unit) {
    if (selected) Button(onClick = action) { Text(label) }
    else OutlinedButton(onClick = action) { Text(label) }
}

@Composable
private fun CreateShareContent(
    effects: List<EffectProgram>,
    palettes: List<CustomPaletteEntry>,
    viewModel: ShareViewModel,
    busy: Boolean,
) {
    Text("选择一个灯效", style = MaterialTheme.typography.titleMedium)
    effects.forEach { program ->
        ShareItem(program.nameZh.ifBlank { program.nameJa }, "灯效", busy) { viewModel.create(program) }
    }
    Text("选择一个自定义应援色", style = MaterialTheme.typography.titleMedium)
    palettes.forEach { entry ->
        ShareItem(entry.nameZh.ifBlank { entry.nameJa }, entry.hex, busy) { viewModel.create(entry) }
    }
    if (effects.isEmpty() && palettes.isEmpty()) Text("暂无可分享内容")
}

@Composable
private fun ShareItem(name: String, detail: String, busy: Boolean, action: () -> Unit) {
    ElevatedCard(Modifier.fillMaxWidth()) {
        Row(
            Modifier.fillMaxWidth().padding(12.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Column(Modifier.weight(1f)) {
                Text(name, style = MaterialTheme.typography.titleSmall)
                Text(detail, style = MaterialTheme.typography.bodySmall)
            }
            Button(onClick = action, enabled = !busy) { Text("生成二维码") }
        }
    }
}

@Composable
private fun ImportShareContent(
    code: String,
    onCodeChange: (String) -> Unit,
    onLoad: () -> Unit,
    onScan: () -> Unit,
    viewModel: ShareViewModel,
    busy: Boolean,
) {
    val state by viewModel.state.collectAsStateCompat()
    OutlinedTextField(
        value = code,
        onValueChange = onCodeChange,
        label = { Text("10位分享码或链接") },
        singleLine = true,
        modifier = Modifier.fillMaxWidth(),
    )
    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        Button(onClick = onLoad, enabled = code.isNotBlank() && !busy) { Text("校验并预览") }
        OutlinedButton(onClick = onScan, enabled = !busy) { Text("扫码") }
    }
    state.pending?.let { pending ->
        ElevatedCard(Modifier.fillMaxWidth()) {
            Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(
                    pending.envelope.displayName.zh.ifBlank { pending.envelope.displayName.ja },
                    style = MaterialTheme.typography.titleMedium,
                )
                Text(if (pending.envelope.kind == ShareKind.EFFECT) "灯效" else "应援色")
                if (pending.envelope.kind == ShareKind.EFFECT) {
                    Text("已在本机完成结构校验与编译；导入后仍需手动选择播放。")
                    SevenRaySimulator(
                        groups = state.previewGroups,
                        pixels = state.previewPixels,
                        modifier = Modifier.fillMaxWidth().height(240.dp),
                    )
                } else {
                    val bitmap = remember(pending) {
                        BitmapFactory.decodeByteArray(
                            pending.paletteAvatar,
                            0,
                            pending.paletteAvatar?.size ?: 0,
                        )
                    }
                    bitmap?.let {
                        Image(it.asImageBitmap(), "应援色头像", Modifier.size(96.dp))
                    }
                    Text(pending.envelope.payload.getString("hex"))
                }
                Button(
                    onClick = viewModel::confirmImport,
                    enabled = !busy && !state.alreadyImported,
                ) { Text(if (state.alreadyImported) "已导入" else "确认创建本地副本") }
            }
        }
    }
}
