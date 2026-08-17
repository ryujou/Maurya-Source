package com.example.peacock.feature.share

import android.content.Context
import android.graphics.Bitmap
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import com.example.peacock.feature.effects.EffectInterpreter
import com.example.peacock.feature.effects.EffectProgram
import com.example.peacock.feature.effects.EffectProgramCompiler
import com.example.peacock.feature.effects.EffectProgramRepository
import com.example.peacock.feature.effects.EffectRgb
import com.example.peacock.feature.palette.CustomPaletteEntry
import com.example.peacock.feature.palette.CustomPaletteRepository
import com.example.peacock.feature.runtime.GroupState
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.util.UUID

enum class ShareSection { CREATE, IMPORT }

data class ShareUiState(
    val section: ShareSection = ShareSection.CREATE,
    val busy: Boolean = false,
    val created: CreatedShare? = null,
    val qrBitmap: Bitmap? = null,
    val pending: PendingShareImport? = null,
    val previewGroups: List<GroupState> = List(7) { GroupState() },
    val previewPixels: List<EffectRgb>? = null,
    val alreadyImported: Boolean = false,
    val status: String = "",
    val error: String = "",
)

class ShareViewModel(
    private val shareRepository: ShareRepository,
    private val effectRepository: EffectProgramRepository,
    private val paletteRepository: CustomPaletteRepository,
) : ViewModel() {
    private val mutableState = MutableStateFlow(ShareUiState())
    val state = mutableState.asStateFlow()
    private var operation: Job? = null

    fun show(section: ShareSection) {
        mutableState.value = mutableState.value.copy(section = section, error = "", status = "")
    }

    fun create(program: EffectProgram) = create { ShareEnvelopeCodec.forEffect(program) }

    fun create(entry: CustomPaletteEntry) = create { ShareEnvelopeCodec.forPalette(entry) }

    private fun create(envelopeProvider: () -> ShareEnvelope) {
        mutableState.value = mutableState.value.copy(created = null, qrBitmap = null)
        launchOperation {
            val envelope = envelopeProvider()
            require(ShareModeration.check(envelope) is ShareModeration.Result.Accepted) {
                "名称或源码可能包含不支持分享的敏感文本；服务器会执行最终审核"
            }
            val created = shareRepository.create(envelope)
            val qr = ShareQr.create(created.shareUrl)
            mutableState.value.copy(
                created = created,
                qrBitmap = qr,
                status = "临时分享已创建，7天后自动失效",
            )
        }
    }

    fun load(rawToken: String) {
        launchOperation {
            val pending = shareRepository.fetchForPreview(rawToken)
            val frame = pending.effect?.let { effect ->
                val compiled = EffectProgramCompiler.compile(effect)
                EffectInterpreter(compiled, List(7) { GroupState() }).frameAt(0)
            }
            mutableState.value.copy(
                section = ShareSection.IMPORT,
                pending = pending,
                previewGroups = frame?.groups ?: List(7) { GroupState() },
                previewPixels = frame?.pixels,
                alreadyImported = shareRepository.wasImported(pending.token),
                status = "已完成校验和本地编译，请确认后导入",
            )
        }
    }

    fun confirmImport() {
        val pending = mutableState.value.pending ?: return
        if (shareRepository.wasImported(pending.token)) {
            mutableState.value = mutableState.value.copy(
                alreadyImported = true,
                error = "该分享码已导入过，为避免重复不会再次创建副本",
            )
            return
        }
        launchOperation {
            val localId = when (pending.envelope.kind) {
                ShareKind.EFFECT -> {
                    val source = requireNotNull(pending.effect)
                    val existing = effectRepository.load()
                    val now = System.currentTimeMillis()
                    val copy = EffectProgramCompiler.normalise(
                        source.copy(
                            id = UUID.randomUUID().toString(),
                            nameZh = copyName(source.nameZh, existing.map { it.nameZh }.toSet(), " 副本", 64),
                            nameJa = copyName(source.nameJa, existing.map { it.nameJa }.toSet(), " コピー", 64),
                            createdAt = now,
                            updatedAt = now,
                        ),
                    )
                    effectRepository.upsert(copy)
                    copy.id
                }
                ShareKind.PALETTE -> {
                    val payload = pending.envelope.payload
                    val existing = paletteRepository.state.value.entries
                    paletteRepository.save(
                        existingId = null,
                        expectedRevision = 0,
                        nameZh = copyName(
                            pending.envelope.displayName.zh,
                            existing.map { it.nameZh }.toSet(),
                            " 副本",
                            32,
                        ),
                        nameJa = copyName(
                            pending.envelope.displayName.ja,
                            existing.map { it.nameJa }.toSet(),
                            " コピー",
                            32,
                        ),
                        hex = payload.getString("hex"),
                        avatarWebP = requireNotNull(pending.paletteAvatar),
                    ).id
                }
            }
            shareRepository.markImported(pending.token, localId)
            mutableState.value.copy(
                alreadyImported = true,
                status = "已创建本地副本；不会自动播放或连接设备",
            )
        }
    }

    fun dismissError() {
        mutableState.value = mutableState.value.copy(error = "")
    }

    private fun launchOperation(block: suspend () -> ShareUiState) {
        operation?.cancel()
        operation = viewModelScope.launch {
            mutableState.value = mutableState.value.copy(busy = true, error = "", status = "")
            runCatching { withContext(Dispatchers.IO) { block() } }
                .onSuccess { mutableState.value = it.copy(busy = false) }
                .onFailure { error ->
                    if (error is kotlinx.coroutines.CancellationException) return@onFailure
                    mutableState.value = mutableState.value.copy(
                        busy = false,
                        error = error.message ?: "分享操作失败",
                    )
                }
        }
    }

    private fun copyName(original: String, existing: Set<String>, suffix: String, limit: Int): String {
        if (original.isBlank() || original !in existing) return original
        var number = 1
        while (true) {
            val resolvedSuffix = if (number == 1) suffix else "$suffix $number"
            val available = (limit - resolvedSuffix.codePointCount(0, resolvedSuffix.length)).coerceAtLeast(0)
            val count = original.codePointCount(0, original.length).coerceAtMost(available)
            val end = original.offsetByCodePoints(0, count)
            val candidate = original.substring(0, end).trimEnd() + resolvedSuffix
            if (candidate !in existing) return candidate
            number++
        }
    }

    class Factory(context: Context) : ViewModelProvider.Factory {
        private val appContext = context.applicationContext
        override fun <T : ViewModel> create(modelClass: Class<T>): T {
            require(modelClass.isAssignableFrom(ShareViewModel::class.java))
            @Suppress("UNCHECKED_CAST")
            return ShareViewModel(
                ShareRepository(appContext),
                EffectProgramRepository(appContext),
                CustomPaletteRepository(appContext),
            ) as T
        }
    }
}
