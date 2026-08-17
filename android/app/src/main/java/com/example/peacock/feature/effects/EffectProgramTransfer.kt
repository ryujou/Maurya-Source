package com.example.peacock.feature.effects

import org.json.JSONArray
import org.json.JSONObject
import java.util.UUID

enum class EffectImportConflictStrategy { COPY, OVERWRITE, SKIP }

data class EffectImportPreview(
    val programs: List<EffectProgram>,
    val errors: List<String>,
    val conflictIds: Set<String>,
)

object EffectProgramCompiler {
    fun compile(program: EffectProgram): CompiledEffect = when (program.sourceKind) {
        EffectSourceKind.BLOCKS -> EffectCompiler.compile(program.workspaceJson)
        EffectSourceKind.SCRIPT -> EffectScriptCompiler.compile(program.scriptSource)
    }

    fun normalise(program: EffectProgram, now: Long = System.currentTimeMillis()): EffectProgram {
        val compiled = compile(program)
        return program.copy(
            astJson = EffectCompiler.canonicalJson(compiled),
            astSha256 = compiled.astSha256,
            blockCount = compiled.blockCount,
            estimatedDurationMs = compiled.estimatedDurationMs,
            updatedAt = now,
            editorSchema = EffectProgramSchemas.EDITOR,
            programSchema = EffectProgramSchemas.PROGRAM,
        )
    }
}

object EffectProgramTransfer {
    const val MAX_FILE_BYTES = 2 * 1024 * 1024
    private const val kindSingle = "maurya-effect"
    private const val kindBundle = "maurya-effect-bundle"

    fun exportSingle(program: EffectProgram): String = JSONObject()
        .put("schema", 1)
        .put("kind", kindSingle)
        .put("exportedBy", exportedBy())
        .put("program", encode(program))
        .toString(2)

    fun exportBundle(programs: List<EffectProgram>): String = JSONObject()
        .put("schema", 1)
        .put("kind", kindBundle)
        .put("exportedBy", exportedBy())
        .put("programs", JSONArray().apply { programs.forEach { put(encode(it)) } })
        .toString(2)

    fun preview(text: String, existingIds: Set<String>): EffectImportPreview {
        require(text.toByteArray().size <= MAX_FILE_BYTES) {
            "导入文件不能超过2 MiB / インポートファイルは2 MiB以下にしてください"
        }
        val root = JSONObject(text)
        require(root.optInt("schema", 0) == 1) {
            "不支持的导入文件版本 / 対応していないファイルバージョンです"
        }
        val rawPrograms = when (root.optString("kind")) {
            kindSingle -> JSONArray().put(root.getJSONObject("program"))
            kindBundle -> root.getJSONArray("programs")
            else -> error("不是Maurya灯效程序文件 / Mauryaエフェクトファイルではありません")
        }
        val valid = mutableListOf<EffectProgram>()
        val errors = mutableListOf<String>()
        for (index in 0 until rawPrograms.length()) {
            runCatching {
                val decoded = decode(rawPrograms.getJSONObject(index), recompile = true)
                require(sourceBytes(decoded) <= EffectScriptCompiler.MAX_SOURCE_BYTES) {
                    "源码超过256 KiB / ソースが256 KiBを超えています"
                }
                decoded
            }.onSuccess(valid::add).onFailure {
                errors += "项目${index + 1}：${it.message.orEmpty()}"
            }
        }
        return EffectImportPreview(valid, errors, valid.map(EffectProgram::id).filter(existingIds::contains).toSet())
    }

    fun encode(program: EffectProgram): JSONObject = JSONObject()
        .put("id", program.id)
        .put("nameZh", program.nameZh)
        .put("nameJa", program.nameJa)
        .put("sourceKind", program.sourceKind.name.lowercase())
        .put("workspaceJson", program.workspaceJson)
        .put("scriptSource", program.scriptSource)
        .put("astJson", program.astJson)
        .put("astSha256", program.astSha256)
        .put("blockCount", program.blockCount)
        .put("estimatedDurationMs", program.estimatedDurationMs ?: JSONObject.NULL)
        .put("createdAt", program.createdAt)
        .put("updatedAt", program.updatedAt)
        .put("editorSchema", program.editorSchema)
        .put("programSchema", program.programSchema)

    fun decode(objectValue: JSONObject, recompile: Boolean = false): EffectProgram {
        val kind = when (objectValue.optString("sourceKind", "blocks").lowercase()) {
            "script" -> EffectSourceKind.SCRIPT
            else -> EffectSourceKind.BLOCKS
        }
        val now = System.currentTimeMillis()
        val decoded = EffectProgram(
            id = objectValue.optString("id").ifBlank { UUID.randomUUID().toString() },
            nameZh = objectValue.optString("nameZh", "导入灯效").take(64),
            nameJa = objectValue.optString("nameJa", "インポートエフェクト").take(64),
            workspaceJson = objectValue.optString("workspaceJson", ""),
            astJson = objectValue.optString("astJson", ""),
            astSha256 = objectValue.optString("astSha256", ""),
            blockCount = objectValue.optInt("blockCount", 0),
            estimatedDurationMs = if (objectValue.isNull("estimatedDurationMs")) null
                else objectValue.optLong("estimatedDurationMs"),
            createdAt = objectValue.optLong("createdAt", now),
            updatedAt = objectValue.optLong("updatedAt", now),
            editorSchema = objectValue.optInt("editorSchema", if (kind == EffectSourceKind.BLOCKS) 1 else 1),
            programSchema = objectValue.optInt("programSchema", 1),
            sourceKind = kind,
            scriptSource = objectValue.optString("scriptSource", ""),
        )
        require(decoded.nameZh.isNotBlank() || decoded.nameJa.isNotBlank()) {
            "程序名称不能为空 / プログラム名を入力してください"
        }
        require(
            if (kind == EffectSourceKind.BLOCKS) decoded.workspaceJson.isNotBlank()
            else decoded.scriptSource.isNotBlank(),
        ) { "程序源码为空 / プログラムソースが空です" }
        return if (recompile) EffectProgramCompiler.normalise(decoded) else decoded
    }

    private fun sourceBytes(program: EffectProgram) = when (program.sourceKind) {
        EffectSourceKind.BLOCKS -> program.workspaceJson.toByteArray().size
        EffectSourceKind.SCRIPT -> program.scriptSource.toByteArray().size
    }

    private fun exportedBy() = JSONObject()
        .put("appVersion", "4.2.0")
        .put("programSchema", EffectProgramSchemas.PROGRAM)
}
