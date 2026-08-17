package com.example.peacock.feature.effects

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.util.UUID

class EffectProgramRepository(context: Context) {
    private val file = File(context.filesDir, "effect_programs.json")
    private val preferences = context.getSharedPreferences("effect_program_repository", Context.MODE_PRIVATE)

    @Synchronized
    fun load(): List<EffectProgram> {
        if (!file.exists()) return examples().also {
            saveAll(it)
            markBundledExamplesInstalled()
        }
        return runCatching {
            val array = JSONArray(file.readText())
            val decoded = (0 until array.length()).map { decode(array.getJSONObject(it)) }
            installBundledExamples(migratePrograms(decoded))
        }.getOrElse { examples().also(::saveAll) }
    }

    @Synchronized
    fun upsert(program: EffectProgram): List<EffectProgram> {
        val next = load().toMutableList()
        val index = next.indexOfFirst { it.id == program.id }
        if (index >= 0) next[index] = program else {
            require(next.size < 50) { "最多保存50个灯效程序" }
            next += program
        }
        saveAll(next)
        return next
    }

    @Synchronized
    fun delete(id: String): List<EffectProgram> =
        load().filterNot { it.id == id }.also(::saveAll)

    @Synchronized
    fun exportProgram(id: String): String {
        val program = load().firstOrNull { it.id == id }
            ?: error("找不到灯效程序 / エフェクトプログラムが見つかりません")
        return EffectProgramTransfer.exportSingle(program)
    }

    @Synchronized
    fun exportAll(): String = EffectProgramTransfer.exportBundle(load())

    @Synchronized
    fun previewImport(text: String): EffectImportPreview =
        EffectProgramTransfer.preview(text, load().map(EffectProgram::id).toSet())

    @Synchronized
    fun applyImport(
        preview: EffectImportPreview,
        strategy: EffectImportConflictStrategy,
    ): List<EffectProgram> {
        val current = load().toMutableList()
        preview.programs.forEach { imported ->
            val existing = current.indexOfFirst { it.id == imported.id }
            when {
                existing < 0 -> current += imported
                strategy == EffectImportConflictStrategy.SKIP -> Unit
                strategy == EffectImportConflictStrategy.OVERWRITE -> current[existing] = imported
                else -> current += imported.copy(
                    id = UUID.randomUUID().toString(),
                    nameZh = "${imported.nameZh} 副本",
                    nameJa = "${imported.nameJa} コピー",
                    createdAt = System.currentTimeMillis(),
                    updatedAt = System.currentTimeMillis(),
                )
            }
        }
        require(current.size <= 50) {
            "导入后会超过50个程序 / インポート後に50件を超えます"
        }
        saveAll(current)
        return current
    }

    private fun saveAll(programs: List<EffectProgram>) {
        val temp = File(file.parentFile, "${file.name}.tmp")
        temp.writeText(JSONArray().apply { programs.forEach { put(encode(it)) } }.toString())
        if (!temp.renameTo(file)) {
            file.writeText(temp.readText())
            temp.delete()
        }
    }

    private fun examples(): List<EffectProgram> {
        val now = System.currentTimeMillis()
        return listOf(
            example(
                "example-rgb", "红→绿→蓝", "赤→緑→青",
                chain(
                    block("maurya_start"),
                    block("maurya_set_color", mapOf("TARGET" to "ALL", "COLOR" to "#ff0000")),
                    block("maurya_wait", mapOf("DURATION" to 500, "UNIT" to "MS")),
                    block("maurya_fade", mapOf("TARGET" to "ALL", "COLOR" to "#00ff00", "DURATION" to 1500)),
                    block("maurya_fade", mapOf("TARGET" to "ALL", "COLOR" to "#0000ff", "DURATION" to 1500)),
                ), now,
            ),
            example(
                "example-rainbow", "无限彩虹", "無限レインボー",
                chain(
                    block("maurya_start"),
                    loop(block("maurya_adjust_hsv", mapOf("TARGET" to "ALL", "H" to 2, "S" to 0, "V" to 0)),
                        block("maurya_wait", mapOf("DURATION" to 50, "UNIT" to "MS"))),
                ), now,
            ),
            scriptExample(
                "example-nebula-prism",
                "星云棱镜·42灯独立",
                "ネビュラプリズム・42灯独立",
                BuiltinEffectSources.NEBULA_PRISM,
                now,
            ),
        )
    }

    private fun example(id:String, zh:String, ja:String, workspace:String, now:Long):EffectProgram {
        val compiled=EffectCompiler.compile(workspace)
        return EffectProgram(id,zh,ja,workspace,EffectCompiler.canonicalJson(compiled),compiled.astSha256,
            compiled.blockCount,compiled.estimatedDurationMs,now,now,
            editorSchema=EffectProgramSchemas.EDITOR,
            programSchema=EffectProgramSchemas.PROGRAM)
    }

    private fun scriptExample(id: String, zh: String, ja: String, source: String, now: Long): EffectProgram =
        EffectProgramCompiler.normalise(
            EffectProgram(
                id = id,
                nameZh = zh,
                nameJa = ja,
                workspaceJson = "",
                astJson = "",
                astSha256 = "",
                blockCount = 0,
                estimatedDurationMs = null,
                createdAt = now,
                updatedAt = now,
                editorSchema = EffectProgramSchemas.EDITOR,
                programSchema = EffectProgramSchemas.PROGRAM,
                sourceKind = EffectSourceKind.SCRIPT,
                scriptSource = source,
            ),
            now,
        )

    private fun installBundledExamples(programs: List<EffectProgram>): List<EffectProgram> {
        if (preferences.getInt(BUNDLED_EXAMPLES_VERSION_KEY, 0) >= BUNDLED_EXAMPLES_VERSION) {
            return programs
        }
        val existingIds = programs.mapTo(mutableSetOf(), EffectProgram::id)
        val additions = examples().filter { it.id in BUNDLED_ADDITION_IDS && it.id !in existingIds }
        val next = if (programs.size + additions.size <= 50) programs + additions else programs
        if (next !== programs) saveAll(next)
        markBundledExamplesInstalled()
        return next
    }

    private fun markBundledExamplesInstalled() {
        preferences.edit().putInt(BUNDLED_EXAMPLES_VERSION_KEY, BUNDLED_EXAMPLES_VERSION).apply()
    }

    private fun migratePrograms(programs: List<EffectProgram>): List<EffectProgram> {
        val replacements = examples().associateBy { it.id }
        var changed = false
        val migrated = programs.map { program ->
            val replacement = replacements[program.id]
            if (replacement != null && program.programSchema < 3) {
                changed = true
                replacement.copy(createdAt = program.createdAt)
            } else if (
                program.programSchema < EffectProgramSchemas.PROGRAM ||
                program.editorSchema < EffectProgramSchemas.EDITOR
            ) {
                runCatching {
                    changed = true
                    EffectProgramCompiler.normalise(program)
                }.getOrDefault(program)
            } else {
                program
            }
        }
        if (changed) saveAll(migrated)
        return migrated
    }

    private fun chain(vararg blocks:JSONObject):String {
        for(i in 0 until blocks.lastIndex) blocks[i].put("next",JSONObject().put("block",blocks[i+1]))
        return JSONObject().put("blocks",JSONObject().put("languageVersion",0).put("blocks",JSONArray().put(blocks[0]))).toString()
    }
    private fun block(type:String, fields:Map<String,Any> = emptyMap())=JSONObject().put("type",type).put("id",UUID.randomUUID().toString())
        .also { if(fields.isNotEmpty()) it.put("fields",JSONObject(fields)) }
    private fun loop(vararg body:JSONObject):JSONObject {
        for(i in 0 until body.lastIndex) body[i].put("next",JSONObject().put("block",body[i+1]))
        return block("maurya_forever").put("inputs",JSONObject().put("DO",JSONObject().put("block",body[0])))
    }

    private fun encode(p:EffectProgram)=EffectProgramTransfer.encode(p)
    private fun decode(o:JSONObject)=EffectProgramTransfer.decode(o)

    private companion object {
        const val BUNDLED_EXAMPLES_VERSION_KEY = "bundled_examples_version"
        const val BUNDLED_EXAMPLES_VERSION = 1
        val BUNDLED_ADDITION_IDS = setOf("example-nebula-prism")
    }
}
