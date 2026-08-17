package com.example.peacock.feature.effects

import android.content.Context
import android.Manifest
import android.content.pm.PackageManager
import android.net.Uri
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import com.example.peacock.ble.BleManager
import com.example.peacock.feature.runtime.GroupState
import com.example.peacock.feature.ota.OtaProtocol
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import java.io.ByteArrayOutputStream
import java.io.InputStream
import java.util.UUID

private val defaultVirtualInputs = RuntimeInputKey.entries.associateWith { key ->
    when (key) {
        RuntimeInputKey.SENSOR_MOTION -> 0.25
        RuntimeInputKey.SENSOR_LIGHT -> 300.0
        RuntimeInputKey.SENSOR_PRESSURE -> 1013.25
        RuntimeInputKey.AUDIO_LEVEL,
        RuntimeInputKey.AUDIO_BASS -> 0.4
        RuntimeInputKey.AUDIO_MID -> 0.3
        RuntimeInputKey.AUDIO_TREBLE -> 0.2
        RuntimeInputKey.AUDIO_BPM -> 120.0
        else -> 0.0
    }
}

data class EffectUiState(
    val programs: List<EffectProgram> = emptyList(),
    val editing: EffectProgram? = null,
    val editorError: String = "",
    val editorIssue: EffectCompileIssue? = null,
    val isPlaying: Boolean = false,
    val isPaused: Boolean = false,
    val playingName: String = "",
    val preview: List<GroupState> = List(7){ GroupState() },
    val previewPixels: List<EffectRgb>? = null,
    val progress: Float? = null,
    val status: String = "",
    val firmwareVersion: String = "",
    val importPreview: EffectImportPreview? = null,
    val transferStatus: String = "",
    val runtimeSnapshot: EffectRuntimeSnapshot = EffectRuntimeSnapshot.EMPTY,
    val virtualInputsEnabled: Boolean = false,
    val virtualInputs: Map<RuntimeInputKey, Double> = defaultVirtualInputs,
)

class EffectViewModel(
    private val repository: EffectProgramRepository,
    private val ble: BleManager,
    private val context: Context,
) : ViewModel() {
    private val _state=MutableStateFlow(EffectUiState(programs=repository.load()))
    val state=_state.asStateFlow()
    private var playJob:Job?=null
    private var activeSessionId:Long?=null
    private var activeAddress:Int=1
    private val sensorHub = EffectSensorHub(context)
    init {
        viewModelScope.launch { EffectPlaybackBus.stop.collect { stop(activeAddress) } }
    }

    fun edit(program:EffectProgram){ _state.value=_state.value.copy(editing=program,editorError="",editorIssue=null) }
    fun create(
        kind: EffectSourceKind = EffectSourceKind.BLOCKS,
        nameZh: String,
        nameJa: String,
    ){
        val now=System.currentTimeMillis()
        val (resolvedZh, resolvedJa) = normaliseNames(nameZh, nameJa)
        val workspace="""{"blocks":{"languageVersion":0,"blocks":[{"type":"maurya_start","id":"${UUID.randomUUID()}"}]}}"""
        val script = if(kind == EffectSourceKind.SCRIPT) EffectScriptCompiler.template(resolvedZh) else ""
        _state.value=_state.value.copy(
            editing=EffectProgram(
                UUID.randomUUID().toString(),resolvedZh,resolvedJa,workspace,"","",
                1,0,now,now,editorSchema=EffectProgramSchemas.EDITOR,
                programSchema=EffectProgramSchemas.PROGRAM,
                sourceKind=kind,scriptSource=script,
            ),
            editorError="",
            editorIssue=null,
        )
    }

    fun rename(program: EffectProgram, nameZh: String, nameJa: String) {
        val (resolvedZh, resolvedJa) = normaliseNames(nameZh, nameJa)
        val changed = program.copy(
            nameZh = resolvedZh,
            nameJa = resolvedJa,
            updatedAt = System.currentTimeMillis(),
        )
        _state.value = _state.value.copy(
            programs = repository.upsert(changed),
            editing = _state.value.editing?.let {
                if (it.id == changed.id) changed else it
            },
            transferStatus = "名称已更新 / 名前を変更しました",
        )
    }
    fun closeEditor(){ _state.value=_state.value.copy(editing=null,editorError="",editorIssue=null) }
    fun requiresMicrophone(program: EffectProgram): Boolean =
        !_state.value.virtualInputsEnabled && runCatching {
        EffectProgramCompiler.compile(program).requiredInputs.any { it.name.startsWith("AUDIO_") }
    }.getOrDefault(false)

    fun reportInputError(message: String) {
        _state.value = _state.value.copy(status = message)
    }
    fun setVirtualInputsEnabled(enabled: Boolean) {
        _state.value = _state.value.copy(virtualInputsEnabled = enabled)
    }

    fun setVirtualInput(key: RuntimeInputKey, value: Double) {
        _state.value = _state.value.copy(
            virtualInputs = _state.value.virtualInputs + (key to value),
        )
    }

    fun zeroAttitude() = sensorHub.zeroAttitude()

    fun setAudioSensitivity(value: Double) = sensorHub.setAudioSensitivity(value)
    fun save(source:String):Boolean = runCatching {
        val current=requireNotNull(_state.value.editing)
        val changed = when(current.sourceKind) {
            EffectSourceKind.BLOCKS -> current.copy(workspaceJson=source)
            EffectSourceKind.SCRIPT -> current.copy(scriptSource=source)
        }
        val saved=EffectProgramCompiler.normalise(changed)
        _state.value=_state.value.copy(
            programs=repository.upsert(saved),editing=saved,editorError="",editorIssue=null,
        )
    }.onFailure(::showCompileFailure).isSuccess

    fun duplicate(program:EffectProgram) {
        val copy=program.copy(id=UUID.randomUUID().toString(),nameZh="${program.nameZh} 副本",nameJa="${program.nameJa} コピー",
            createdAt=System.currentTimeMillis(),updatedAt=System.currentTimeMillis())
        _state.value=_state.value.copy(programs=repository.upsert(copy))
    }
    fun duplicateAsScript(program:EffectProgram) {
        runCatching {
            val compiled=EffectProgramCompiler.compile(program)
            val now=System.currentTimeMillis()
            val copyNameZh="${program.nameZh} 代码版"
            val copyNameJa="${program.nameJa} コード版"
            val source=EffectScriptFormatter.fromCompiled(copyNameZh,compiled)
            val copy=EffectProgramCompiler.normalise(
                program.copy(
                    id=UUID.randomUUID().toString(),
                    nameZh=copyNameZh,
                    nameJa=copyNameJa,
                    workspaceJson="",
                    scriptSource=source,
                    sourceKind=EffectSourceKind.SCRIPT,
                    createdAt=now,
                    updatedAt=now,
                    editorSchema=EffectProgramSchemas.EDITOR,
                    programSchema=EffectProgramSchemas.PROGRAM,
                ),
            )
            _state.value=_state.value.copy(
                programs=repository.upsert(copy),
                editing=copy,
                editorError="",
                editorIssue=null,
                transferStatus="已复制并打开代码程序 / コード版を作成して開きました",
            )
        }.onFailure {
            showCompileFailure(it)
            _state.value=_state.value.copy(
                transferStatus="复制为代码失败：${it.message.orEmpty()} / コード化に失敗しました",
            )
        }
    }
    fun delete(program:EffectProgram){ _state.value=_state.value.copy(programs=repository.delete(program.id)) }

    fun preview(source:String, initial:List<GroupState>) {
        runCatching {
            val current=requireNotNull(_state.value.editing)
            val changed=if(current.sourceKind==EffectSourceKind.BLOCKS) current.copy(workspaceJson=source)
                else current.copy(scriptSource=source)
            EffectInterpreter(EffectProgramCompiler.compile(changed),initial).frameAt(1500)
        }.onSuccess {
            _state.value=_state.value.copy(
                preview=it.groups,
                previewPixels=it.pixels,
                editorError="",
                editorIssue=null,
            )
        }
            .onFailure(::showCompileFailure)
    }

    fun play(program:EffectProgram, initial:List<GroupState>, address:Int) {
        stop(address)
        val compiled=runCatching { EffectProgramCompiler.compile(program) }.getOrElse {
            showCompileFailure(it)
            _state.value=_state.value.copy(status=it.message.orEmpty())
            return
        }
        _state.value=_state.value.copy(
            isPlaying=true,
            isPaused=false,
            playingName=program.nameZh,
            status="正在建立RAM临时会话",
        )
        playJob=viewModelScope.launch {
            runCatching {
                val virtualMode = _state.value.virtualInputsEnabled
                val microphoneRequired =
                    !virtualMode && compiled.requiredInputs.any { it.name.startsWith("AUDIO_") }
                val microphoneGranted = context.checkSelfPermission(Manifest.permission.RECORD_AUDIO) ==
                    PackageManager.PERMISSION_GRANTED
                if (microphoneRequired && !microphoneGranted) {
                    error("此程序需要麦克风权限 / このプログラムにはマイク権限が必要です")
                }
                val missingInputs = if (virtualMode) emptySet()
                    else sensorHub.start(compiled.requiredInputs, microphoneGranted)
                if (missingInputs.isNotEmpty()) {
                    error("手机缺少输入：${missingInputs.joinToString { it.displayName() }}")
                }
                val deviceInfo=OtaProtocol.parseInfo(
                    ble.transceive(OtaProtocol.getInfoRequest(address)),
                )
                _state.value=_state.value.copy(firmwareVersion=deviceInfo.firmwareVersion)
                check(deviceInfo.capabilities and EffectProtocol.capabilityVolatileEffect != 0) {
                    "当前固件${deviceInfo.firmwareVersion}不支持临时灯效，请更新到1.7.1或更高版本"
                }
                if (compiled.requiresPixelEffect) {
                    check(deviceInfo.capabilities and EffectProtocol.capabilityPixelEffect != 0) {
                        "逐灯程序需要固件v1.8.0 / ピクセルプログラムにはファームウェアv1.8.0が必要です"
                    }
                }
                val interpreter=EffectInterpreter(compiled,initial)
                var sessionId=EffectProtocol.parseBegin(ble.transceive(EffectProtocol.beginRequest(address)))
                activeSessionId=sessionId
                activeAddress=address
                var sequence=0
                val started=android.os.SystemClock.elapsedRealtime()
                var lastHeartbeat=started
                var lastSentGroups:List<GroupState>?=null
                var lastSentPixels:List<EffectRgb>?=null
                var nextFrameAt=started
                var pausedDuration=0L
                var pausedAt:Long?=null
                _state.value=_state.value.copy(status="RAM临时播放 · 不写Flash")
                EffectPlaybackService.start(context, program.nameZh, usesMicrophone = microphoneRequired)
                while(true) {
                    if(_state.value.isPaused) {
                        if(pausedAt==null) pausedAt=android.os.SystemClock.elapsedRealtime()
                        val now=android.os.SystemClock.elapsedRealtime()
                        if(now-lastHeartbeat>=1000) {
                            EffectProtocol.parseAck(ble.transceive(EffectProtocol.heartbeatRequest(address,sessionId)),EffectProtocol.heartbeatCommand())
                            lastHeartbeat=now
                        }
                        delay(100)
                        continue
                    }
                    pausedAt?.let {
                        pausedDuration+=android.os.SystemClock.elapsedRealtime()-it
                        pausedAt=null
                    }
                    if(!ble.session.value.isReady) {
                        _state.value=_state.value.copy(status="BLE断开，正在自动重连")
                        val reconnectStarted=android.os.SystemClock.elapsedRealtime()
                        if(!ble.reconnectUntilReady(30_000)) error("BLE重连超时")
                        sessionId=EffectProtocol.parseBegin(ble.transceive(EffectProtocol.beginRequest(address)))
                        activeSessionId=sessionId
                        pausedDuration+=android.os.SystemClock.elapsedRealtime()-reconnectStarted
                    }
                    val now=android.os.SystemClock.elapsedRealtime()
                    val snapshot = if (virtualMode) virtualSnapshot(now) else sensorHub.snapshot()
                    _state.value = _state.value.copy(runtimeSnapshot = snapshot)
                    val staleInputs = compiled.requiredInputs.filterTo(linkedSetOf()) {
                        snapshot.isStale(it, now)
                    }
                    if (staleInputs.isNotEmpty() && now - started > 1_000L) {
                        error("输入超过1秒未更新：${staleInputs.joinToString { it.displayName() }}")
                    }
                    val frame=interpreter.frameAt(now-started-pausedDuration, snapshot)
                    _state.value=_state.value.copy(
                        preview=frame.groups,
                        previewPixels=frame.pixels,
                        progress=frame.progress,
                    )
                    if (compiled.requiresPixelEffect && frame.pixels != null &&
                        frame.pixels != lastSentPixels
                    ) {
                        sequence=(sequence+1) and 0xffff
                        EffectProtocol.parseAck(
                            ble.transceive(
                                EffectProtocol.pixelFrameRequest(
                                    address, sessionId, sequence, frame.pixels,
                                ),
                            ),
                            EffectProtocol.pixelFrameCommand(),
                        )
                        lastSentPixels=frame.pixels
                        lastHeartbeat=android.os.SystemClock.elapsedRealtime()
                    } else if(!compiled.requiresPixelEffect && frame.groups!=lastSentGroups) {
                        sequence=(sequence+1) and 0xffff
                        EffectProtocol.parseAck(ble.transceive(EffectProtocol.frameRequest(address,sessionId,sequence,frame.groups)),EffectProtocol.frameCommand())
                        lastSentGroups=frame.groups
                        lastHeartbeat=android.os.SystemClock.elapsedRealtime()
                    } else if(now-lastHeartbeat>=1000) {
                        EffectProtocol.parseAck(ble.transceive(EffectProtocol.heartbeatRequest(address,sessionId)),EffectProtocol.heartbeatCommand())
                        lastHeartbeat=android.os.SystemClock.elapsedRealtime()
                    }
                    if(frame.finished) break
                    val frameInterval = if (compiled.requiresPixelEffect) {
                        PIXEL_FRAME_INTERVAL_MS
                    } else {
                        GROUP_FRAME_INTERVAL_MS
                    }
                    nextFrameAt+=frameInterval
                    val afterSend=android.os.SystemClock.elapsedRealtime()
                    if(nextFrameAt<afterSend-frameInterval) nextFrameAt=afterSend
                    delay((nextFrameAt-afterSend).coerceAtLeast(0L))
                }
                runCatching { EffectProtocol.parseAck(ble.transceive(EffectProtocol.endRequest(address,sessionId)),EffectProtocol.endCommand()) }
            }.onFailure {
                val message=when(it) {
                    is EffectCommandRejectedException ->
                        "${it.message}；请确认固件为1.7.1，并停止其他控制操作后重试"
                    else -> it.message.orEmpty()
                }
                _state.value=_state.value.copy(status=message)
            }
            _state.value=_state.value.copy(isPlaying=false,isPaused=false,playingName="",progress=null)
            activeSessionId=null
            sensorHub.stop()
            EffectPlaybackService.stop(context)
        }
    }

    fun stop(address:Int) {
        playJob?.cancel(); playJob=null
        val sessionId=activeSessionId
        activeSessionId=null
        if(sessionId!=null) viewModelScope.launch {
            runCatching { EffectProtocol.parseAck(ble.transceive(EffectProtocol.endRequest(activeAddress,sessionId)),EffectProtocol.endCommand()) }
        }
        _state.value=_state.value.copy(isPlaying=false,isPaused=false,playingName="",progress=null,status="已停止，设备恢复已保存配置")
        sensorHub.stop()
        EffectPlaybackService.stop(context)
    }

    fun togglePause() {
        if(!_state.value.isPlaying) return
        val paused=!_state.value.isPaused
        _state.value=_state.value.copy(isPaused=paused,status=if(paused)"已暂停 · RAM会话保持中" else "RAM临时播放 · 不写Flash")
    }

    fun exportProgram(uri:Uri, program:EffectProgram?) {
        runCatching {
            val text=if(program==null) repository.exportAll() else repository.exportProgram(program.id)
            context.contentResolver.openOutputStream(uri,"wt")!!.bufferedWriter(Charsets.UTF_8).use { it.write(text) }
        }.onSuccess {
            _state.value=_state.value.copy(transferStatus="导出成功 / エクスポートしました")
        }.onFailure {
            _state.value=_state.value.copy(transferStatus=it.message.orEmpty())
        }
    }

    fun previewImport(uri:Uri) {
        runCatching {
            val bytes=context.contentResolver.openInputStream(uri)!!.use {
                readLimited(it,EffectProgramTransfer.MAX_FILE_BYTES+1)
            }
            require(bytes.size<=EffectProgramTransfer.MAX_FILE_BYTES) {
                "导入文件不能超过2 MiB / インポートファイルは2 MiB以下にしてください"
            }
            repository.previewImport(bytes.toString(Charsets.UTF_8))
        }.onSuccess {
            _state.value=_state.value.copy(importPreview=it,transferStatus="")
        }.onFailure {
            _state.value=_state.value.copy(importPreview=null,transferStatus=it.message.orEmpty())
        }
    }

    fun applyImport(strategy:EffectImportConflictStrategy) {
        val preview=_state.value.importPreview ?: return
        runCatching { repository.applyImport(preview,strategy) }
            .onSuccess {
                _state.value=_state.value.copy(
                    programs=it,importPreview=null,
                    transferStatus="导入成功 / インポートしました",
                )
            }
            .onFailure {
                _state.value=_state.value.copy(transferStatus=it.message.orEmpty())
            }
    }

    fun closeImportPreview(){ _state.value=_state.value.copy(importPreview=null) }

    private fun showCompileFailure(error:Throwable) {
        val compile=error as? EffectCompileException
        _state.value=_state.value.copy(
            editorError=error.message.orEmpty(),
            editorIssue=compile?.diagnostics?.firstOrNull(),
        )
    }

    private fun readLimited(input:InputStream,limit:Int):ByteArray {
        val output=ByteArrayOutputStream(minOf(limit,32*1024))
        val buffer=ByteArray(8*1024)
        while(output.size()<limit) {
            val read=input.read(buffer,0,minOf(buffer.size,limit-output.size()))
            if(read<0) break
            output.write(buffer,0,read)
        }
        return output.toByteArray()
    }

    private fun normaliseNames(nameZh: String, nameJa: String): Pair<String, String> {
        val zh = nameZh.trim().take(64)
        val ja = nameJa.trim().take(64)
        require(zh.isNotBlank() || ja.isNotBlank()) {
            "请至少填写一个名称 / 名前を1つ以上入力してください"
        }
        return (zh.ifBlank { ja }) to (ja.ifBlank { zh })
    }

    private fun RuntimeInputKey.displayName(): String = name
        .removePrefix("SENSOR_")
        .removePrefix("AUDIO_")
        .lowercase()

    class Factory(context:Context,private val ble:BleManager):ViewModelProvider.Factory {
        private val appContext=context.applicationContext
        private val repository=EffectProgramRepository(appContext)
        @Suppress("UNCHECKED_CAST")
        override fun <T:ViewModel> create(modelClass:Class<T>):T=EffectViewModel(repository,ble,appContext) as T
    }

    private companion object {
        const val GROUP_FRAME_INTERVAL_MS=100L
        const val PIXEL_FRAME_INTERVAL_MS=50L
    }

    private fun virtualSnapshot(nowMs: Long): EffectRuntimeSnapshot {
        val values = _state.value.virtualInputs.mapValues { (key, value) ->
            if (key == RuntimeInputKey.AUDIO_BEAT) EffectValue.Boolean(value >= 0.5)
            else EffectValue.Number(value)
        }
        return EffectRuntimeSnapshot(nowMs, values, values.keys, values.keys.associateWith { nowMs })
    }

    override fun onCleared() {
        sensorHub.stop()
        super.onCleared()
    }
}
