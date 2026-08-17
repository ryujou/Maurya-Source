package com.example.peacock.feature.effects

import org.json.JSONArray
import org.json.JSONObject
import java.security.MessageDigest
import kotlin.math.abs
import kotlin.math.floor
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow

class EffectCompileException(
    val issues: List<String>,
    val diagnostics: List<EffectCompileIssue> = emptyList(),
) : IllegalArgumentException(issues.joinToString("\n"))

object EffectCompiler {
    private const val maxBlocks = 300
    private const val maxControlDepth = 6
    private const val maxVariables = 16

    private data class VariableInfo(val id: String, val name: String, val type: EffectValueType)

    fun compile(workspaceJson: String): CompiledEffect {
        val root = JSONObject(workspaceJson)
        val top = root.optJSONObject("blocks")?.optJSONArray("blocks") ?: JSONArray()
        val issues = mutableListOf<String>()
        val allCount = countBlocks(top)
        if (allCount > maxBlocks) issues += "积木数量不能超过 $maxBlocks / ブロックは最大${maxBlocks}個です"

        val variables = readVariables(root, issues)
        if (variables.size > maxVariables) issues += "变量不能超过 $maxVariables 个 / 変数は最大${maxVariables}個です"

        val starts = (0 until top.length()).mapNotNull { top.optJSONObject(it) }
            .filter { it.optString("type") == "maurya_start" }
        val functionBlocks = (0 until top.length()).mapNotNull { top.optJSONObject(it) }
            .filter { it.optString("type") == "maurya_function_def" }
        if (starts.size != 1) issues += "必须有且只有一个“开始播放”积木 / 「再生開始」は1個必要です"
        if (top.length() != 1 + functionBlocks.size || starts.size != 1) {
            issues += "存在未连接到开始积木或函数定义的孤立积木 / 未接続ブロックがあります"
        }
        if (issues.isNotEmpty()) throw EffectCompileException(issues)

        val functions = linkedMapOf<String, EffectFunctionDefinition>()
        functionBlocks.forEach { block ->
            val name = block.optJSONObject("fields")?.optString("NAME").orEmpty().trim()
            if (name.isBlank()) {
                issues += "函数名不能为空 / 関数名を入力してください"
            } else if (functions.containsKey(name)) {
                issues += "函数$name 重复 / 関数$name が重複しています"
            } else {
                functions[name] = EffectFunctionDefinition(
                    name = name,
                    parameters = emptyList(),
                    returnType = null,
                    operations = parseChain(
                        inputBlock(block, "BODY"),
                        1,
                        0,
                        variables,
                        issues,
                    ),
                )
            }
        }
        val operations = parseChain(next(starts.single()), 0, 0, variables, issues)
        if (operations.isEmpty()) issues += "开始积木后没有可执行内容 / 実行するブロックがありません"
        validateBlocklyFunctions(operations, functions, issues)
        if (issues.isNotEmpty()) throw EffectCompileException(issues)
        return compileOperations(
            operations,
            allCount,
            variables.mapValues { it.value.type },
            functions,
        )
    }

    fun canonicalJson(compiled: CompiledEffect): String = canonicalProgram(
        compiled.operations,
        compiled.functions,
    ).toString()

    fun compileOperations(
        operations: List<EffectOp>,
        nodeCount: Int,
        variables: Map<String, EffectValueType> = emptyMap(),
        functions: Map<String, EffectFunctionDefinition> = emptyMap(),
    ): CompiledEffect {
        val issues = mutableListOf<String>()
        val diagnostics = mutableListOf<EffectCompileIssue>()
        if (nodeCount > maxBlocks) {
            issues += "程序步骤不能超过 $maxBlocks / プログラムは最大${maxBlocks}ステップです"
        }
        if (variables.size > maxVariables) {
            issues += "变量不能超过 $maxVariables 个 / 変数は最大${maxVariables}個です"
        }
        val allOperations = operations + functions.values.flatMap { it.operations }
        val requiresPixelEffect = allOperations.any(::containsPixelTarget)
        allOperations.forEach { validateConstantPixelTargets(it, issues) }
        if (requiresPixelEffect && allOperations.any(::containsModeOperation)) {
            issues += "逐灯程序不能使用硬件组内模式，请用等待、波形和颜色帧实现闪烁 / ピクセルプログラムではハードウェアモードを使用できません"
        }
        validateReachability(operations, issues)
        validateObservableStates(operations, diagnostics)
        issues += diagnostics.map(EffectCompileIssue::combinedMessage)
        if (issues.isNotEmpty()) throw EffectCompileException(issues, diagnostics)

        val astJson = canonicalProgram(operations, functions).toString()
        val hash = sha256(astJson)
        return CompiledEffect(
            operations = operations,
            blockCount = nodeCount,
            estimatedDurationMs = duration(operations),
            astSha256 = hash,
            variables = variables,
            requiredInputs = collectRuntimeInputs(allOperations).toMutableSet().apply {
                functions.values.mapNotNull { it.returnExpression }.forEach { expression ->
                    addAll(collectRuntimeInputs(listOf(EffectOp.SetVariable("__return", expression))))
                }
            },
            randomSeed = hash.take(16).toULong(16).toLong(),
            functions = functions,
            requiresPixelEffect = requiresPixelEffect,
        )
    }

    private fun containsPixelTarget(op: EffectOp): Boolean {
        fun pixel(target: EffectTargetRef) = target is EffectTargetRef.AllPixels ||
            target is EffectTargetRef.Pixel || target is EffectTargetRef.PixelAt
        return when (op) {
            is EffectOp.SetHsv -> pixel(op.target)
            is EffectOp.SetColour -> pixel(op.target)
            is EffectOp.FadeHsv -> pixel(op.target)
            is EffectOp.FadeColour -> pixel(op.target)
            is EffectOp.AdjustHsv -> pixel(op.target)
            is EffectOp.SetMode -> pixel(op.target)
            is EffectOp.If -> op.thenBody.any(::containsPixelTarget) || op.elseBody.any(::containsPixelTarget)
            is EffectOp.Repeat -> op.body.any(::containsPixelTarget)
            is EffectOp.For -> op.body.any(::containsPixelTarget)
            is EffectOp.While -> op.body.any(::containsPixelTarget)
            else -> false
        }
    }

    private fun containsModeOperation(op: EffectOp): Boolean = when (op) {
        is EffectOp.SetMode -> true
        is EffectOp.If -> op.thenBody.any(::containsModeOperation) || op.elseBody.any(::containsModeOperation)
        is EffectOp.Repeat -> op.body.any(::containsModeOperation)
        is EffectOp.For -> op.body.any(::containsModeOperation)
        is EffectOp.While -> op.body.any(::containsModeOperation)
        else -> false
    }

    private fun validateConstantPixelTargets(op: EffectOp, issues: MutableList<String>) {
        fun validateNumber(
            expression: EffectExpression,
            range: IntRange,
            labelZh: String,
            labelJa: String,
        ) {
            val value = (expression as? EffectExpression.NumberLiteral)?.value ?: return
            if (!value.isFinite() || value % 1.0 != 0.0 || value.toInt() !in range) {
                issues += "${labelZh}必须为${range.first}到${range.last}的整数 / " +
                    "${labelJa}は${range.first}から${range.last}の整数で指定してください"
            }
        }
        fun validateTarget(target: EffectTargetRef) {
            when (target) {
                is EffectTargetRef.Pixel -> {
                    validateNumber(target.oneBasedGroup, 1..7, "逐灯灯组编号", "ピクセルのグループ番号")
                    validateNumber(
                        target.oneBasedPixel,
                        1..EffectGeometry.PIXELS_PER_GROUP,
                        "组内灯珠编号",
                        "グループ内ピクセル番号",
                    )
                }
                is EffectTargetRef.PixelAt ->
                    validateNumber(
                        target.oneBasedIndex,
                        1..EffectGeometry.PIXEL_COUNT,
                        "全局灯珠编号",
                        "通しピクセル番号",
                    )
                else -> Unit
            }
        }
        when (op) {
            is EffectOp.SetHsv -> validateTarget(op.target)
            is EffectOp.SetColour -> validateTarget(op.target)
            is EffectOp.FadeHsv -> validateTarget(op.target)
            is EffectOp.FadeColour -> validateTarget(op.target)
            is EffectOp.AdjustHsv -> validateTarget(op.target)
            is EffectOp.SetMode -> validateTarget(op.target)
            is EffectOp.If -> {
                op.thenBody.forEach { validateConstantPixelTargets(it, issues) }
                op.elseBody.forEach { validateConstantPixelTargets(it, issues) }
            }
            is EffectOp.Repeat -> op.body.forEach { validateConstantPixelTargets(it, issues) }
            is EffectOp.For -> op.body.forEach { validateConstantPixelTargets(it, issues) }
            is EffectOp.While -> op.body.forEach { validateConstantPixelTargets(it, issues) }
            else -> Unit
        }
    }

    private fun collectRuntimeInputs(operations: List<EffectOp>): Set<RuntimeInputKey> {
        val result = linkedSetOf<RuntimeInputKey>()
        fun expression(value: EffectExpression) {
            when (value) {
                is EffectExpression.RuntimeInput -> result += value.key
                is EffectExpression.Arithmetic -> {
                    expression(value.left)
                    expression(value.right)
                }
                is EffectExpression.Clamp -> {
                    expression(value.value)
                    expression(value.low)
                    expression(value.high)
                }
                is EffectExpression.Comparison -> {
                    expression(value.left)
                    expression(value.right)
                }
                is EffectExpression.Logic -> {
                    expression(value.left)
                    expression(value.right)
                }
                is EffectExpression.Not -> expression(value.value)
                is EffectExpression.ColourFromHsv -> {
                    expression(value.hue)
                    expression(value.saturation)
                    expression(value.value)
                }
                is EffectExpression.DynamicGroupValue -> expression(value.oneBasedIndex)
                is EffectExpression.TargetFromIndex -> expression(value.oneBasedIndex)
                is EffectExpression.Builtin -> value.arguments.forEach(::expression)
                is EffectExpression.ListLiteral -> value.elements.forEach(::expression)
                is EffectExpression.ListGet -> {
                    expression(value.list)
                    expression(value.index)
                }
                is EffectExpression.FunctionCall -> value.arguments.forEach(::expression)
                is EffectExpression.NumberLiteral,
                is EffectExpression.BooleanLiteral,
                is EffectExpression.ColourLiteral,
                is EffectExpression.Variable,
                EffectExpression.ElapsedMs,
                is EffectExpression.GroupValue,
                is EffectExpression.TargetLiteral,
                -> Unit
            }
        }
        fun target(value: EffectTargetRef) {
            when (value) {
                EffectTargetRef.All, EffectTargetRef.AllPixels -> Unit
                is EffectTargetRef.Group -> expression(value.oneBasedIndex)
                is EffectTargetRef.Pixel -> {
                    expression(value.oneBasedGroup)
                    expression(value.oneBasedPixel)
                }
                is EffectTargetRef.PixelAt -> expression(value.oneBasedIndex)
                is EffectTargetRef.Value -> expression(value.expression)
            }
        }
        fun visit(items: List<EffectOp>) {
            items.forEach { op ->
                when (op) {
                    is EffectOp.SetHsv -> {
                        target(op.target); expression(op.h); expression(op.s); expression(op.v)
                    }
                    is EffectOp.SetColour -> {
                        target(op.target); expression(op.colour)
                    }
                    is EffectOp.FadeHsv -> {
                        target(op.target); expression(op.h); expression(op.s); expression(op.v); expression(op.durationMs)
                    }
                    is EffectOp.FadeColour -> {
                        target(op.target); expression(op.colour); expression(op.durationMs)
                    }
                    is EffectOp.AdjustHsv -> {
                        target(op.target); expression(op.dh); expression(op.ds); expression(op.dv)
                    }
                    is EffectOp.SetMode -> {
                        target(op.target); expression(op.mode); expression(op.param)
                    }
                    is EffectOp.Wait -> expression(op.durationMs)
                    is EffectOp.SetVariable -> expression(op.value)
                    is EffectOp.ChangeVariable -> expression(op.delta)
                    is EffectOp.SetListItem -> {
                        expression(op.index); expression(op.value)
                    }
                    is EffectOp.SeedRandom -> expression(op.seed)
                    is EffectOp.CallFunction -> op.arguments.forEach(::expression)
                    is EffectOp.If -> {
                        expression(op.condition); visit(op.thenBody); visit(op.elseBody)
                    }
                    is EffectOp.Repeat -> {
                        op.count?.let(::expression); visit(op.body)
                    }
                    is EffectOp.For -> {
                        expression(op.from); expression(op.to); expression(op.step); visit(op.body)
                    }
                    is EffectOp.While -> {
                        expression(op.condition); visit(op.body)
                    }
                    is EffectOp.Break,
                    is EffectOp.Continue,
                    is EffectOp.End,
                    -> Unit
                }
            }
        }
        visit(operations)
        return result
    }

    private fun readVariables(root: JSONObject, issues: MutableList<String>): Map<String, VariableInfo> {
        val result = linkedMapOf<String, VariableInfo>()
        val array = root.optJSONArray("variables") ?: JSONArray()
        for (index in 0 until array.length()) {
            val item = array.optJSONObject(index) ?: continue
            val id = item.optString("id")
            val name = item.optString("name", id)
            val type = when (item.optString("type")) {
                "Number" -> EffectValueType.NUMBER
                "Boolean" -> EffectValueType.BOOLEAN
                "Colour" -> EffectValueType.COLOUR
                else -> null
            }
            if (id.isBlank() || type == null) {
                issues += "变量定义无效：$name / 変数定義が無効です"
            } else if (result.put(id, VariableInfo(id, name, type)) != null) {
                issues += "变量ID重复：$name / 変数IDが重複しています"
            }
        }
        return result
    }

    private fun parseChain(
        first: JSONObject?,
        depth: Int,
        loopDepth: Int,
        variables: Map<String, VariableInfo>,
        issues: MutableList<String>,
    ): List<EffectOp> {
        val result = mutableListOf<EffectOp>()
        var block = first
        while (block != null) {
            val id = block.optString("id")
            val fields = block.optJSONObject("fields") ?: JSONObject()
            val target = target(fields.optString("TARGET", "ALL"), id, issues)
            when (block.optString("type")) {
                "maurya_set_all_pixels_color_value" -> result += EffectOp.SetColour(
                    EffectTargetRef.AllPixels,
                    expression(block, "COLOR", EffectValueType.COLOUR, variables, issues),
                    id,
                )
                "maurya_set_all_pixels_hsv_value" -> result += EffectOp.SetHsv(
                    EffectTargetRef.AllPixels,
                    expression(block, "H", EffectValueType.NUMBER, variables, issues),
                    expression(block, "S", EffectValueType.NUMBER, variables, issues),
                    expression(block, "V", EffectValueType.NUMBER, variables, issues),
                    id,
                )
                "maurya_set_pixel_color_value" -> result += EffectOp.SetColour(
                    EffectTargetRef.Pixel(
                        expression(block, "GROUP", EffectValueType.NUMBER, variables, issues),
                        expression(block, "PIXEL", EffectValueType.NUMBER, variables, issues),
                    ),
                    expression(block, "COLOR", EffectValueType.COLOUR, variables, issues),
                    id,
                )
                "maurya_set_pixel_hsv_value" -> result += EffectOp.SetHsv(
                    EffectTargetRef.Pixel(
                        expression(block, "GROUP", EffectValueType.NUMBER, variables, issues),
                        expression(block, "PIXEL", EffectValueType.NUMBER, variables, issues),
                    ),
                    expression(block, "H", EffectValueType.NUMBER, variables, issues),
                    expression(block, "S", EffectValueType.NUMBER, variables, issues),
                    expression(block, "V", EffectValueType.NUMBER, variables, issues),
                    id,
                )
                "maurya_set_pixel_at_color_value" -> result += EffectOp.SetColour(
                    EffectTargetRef.PixelAt(
                        expression(block, "INDEX", EffectValueType.NUMBER, variables, issues),
                    ),
                    expression(block, "COLOR", EffectValueType.COLOUR, variables, issues),
                    id,
                )
                "maurya_set_pixel_at_hsv_value" -> result += EffectOp.SetHsv(
                    EffectTargetRef.PixelAt(
                        expression(block, "INDEX", EffectValueType.NUMBER, variables, issues),
                    ),
                    expression(block, "H", EffectValueType.NUMBER, variables, issues),
                    expression(block, "S", EffectValueType.NUMBER, variables, issues),
                    expression(block, "V", EffectValueType.NUMBER, variables, issues),
                    id,
                )
                "maurya_apply_pixel_colour_list" -> {
                    val colours = expression(
                        block, "LIST", EffectValueType.COLOUR_LIST, variables, issues,
                    )
                    val length = EffectExpression.Builtin(
                        BuiltinFunction.LIST_LENGTH,
                        listOf(colours),
                        EffectValueType.NUMBER,
                        "$id:length",
                    )
                    repeat(EffectGeometry.PIXEL_COUNT) { index ->
                        result += EffectOp.SetColour(
                            EffectTargetRef.PixelAt(
                                EffectExpression.NumberLiteral((index + 1).toDouble()),
                            ),
                            EffectExpression.ListGet(
                                colours,
                                EffectExpression.Arithmetic(
                                    ArithmeticOperator.MODULO,
                                    EffectExpression.NumberLiteral(index.toDouble()),
                                    length,
                                ),
                                EffectValueType.COLOUR,
                            ),
                            "$id:$index",
                        )
                    }
                }
                "maurya_set_color" -> {
                    val hsv = hexToHsv(fields.optString("COLOR", "#FFFFFF"))
                    result += EffectOp.SetHsv(
                        target,
                        EffectExpression.NumberLiteral(hsv.hue.toDouble()),
                        EffectExpression.NumberLiteral(hsv.saturation.toDouble()),
                        EffectExpression.NumberLiteral(hsv.value.toDouble()),
                        id,
                    )
                }
                "maurya_set_color_value" -> result += EffectOp.SetColour(
                    target, expression(block, "COLOR", EffectValueType.COLOUR, variables, issues), id,
                )
                "maurya_fade" -> {
                    val hsv = hexToHsv(fields.optString("COLOR", "#FFFFFF"))
                    result += EffectOp.FadeHsv(
                        target,
                        EffectExpression.NumberLiteral(hsv.hue.toDouble()),
                        EffectExpression.NumberLiteral(hsv.saturation.toDouble()),
                        EffectExpression.NumberLiteral(hsv.value.toDouble()),
                        EffectExpression.NumberLiteral(
                            fields.optLong("DURATION", 1000L).coerceAtLeast(100L).toDouble(),
                        ),
                        id,
                    )
                }
                "maurya_fade_value" -> result += EffectOp.FadeColour(
                    target,
                    expression(block, "COLOR", EffectValueType.COLOUR, variables, issues),
                    expression(block, "DURATION", EffectValueType.NUMBER, variables, issues),
                    id,
                )
                "maurya_set_hsv" -> result += EffectOp.SetHsv(
                    target,
                    EffectExpression.NumberLiteral(wrapHue(fields.optInt("H")).toDouble()),
                    EffectExpression.NumberLiteral(fields.optInt("S").coerceIn(0, 255).toDouble()),
                    EffectExpression.NumberLiteral(fields.optInt("V").coerceIn(0, 255).toDouble()),
                    id,
                )
                "maurya_set_hsv_value" -> result += EffectOp.SetHsv(
                    target,
                    expression(block, "H", EffectValueType.NUMBER, variables, issues),
                    expression(block, "S", EffectValueType.NUMBER, variables, issues),
                    expression(block, "V", EffectValueType.NUMBER, variables, issues),
                    id,
                )
                "maurya_adjust_hsv" -> result += EffectOp.AdjustHsv(
                    target,
                    EffectExpression.NumberLiteral(fields.optInt("H").coerceIn(-359, 359).toDouble()),
                    EffectExpression.NumberLiteral(fields.optInt("S").coerceIn(-255, 255).toDouble()),
                    EffectExpression.NumberLiteral(fields.optInt("V").coerceIn(-255, 255).toDouble()),
                    id,
                )
                "maurya_adjust_hsv_value" -> result += EffectOp.AdjustHsv(
                    target,
                    expression(block, "H", EffectValueType.NUMBER, variables, issues),
                    expression(block, "S", EffectValueType.NUMBER, variables, issues),
                    expression(block, "V", EffectValueType.NUMBER, variables, issues),
                    id,
                )
                "maurya_mode" -> result += EffectOp.SetMode(
                    target,
                    EffectExpression.NumberLiteral(fields.optInt("MODE", 1).toDouble()),
                    EffectExpression.NumberLiteral(fields.optInt("PARAM", 128).toDouble()),
                    id,
                )
                "maurya_wait" -> {
                    var millis = fields.optLong("DURATION", 1000L)
                    if (fields.optString("UNIT") == "SEC") millis *= 1000L
                    result += EffectOp.Wait(millis.coerceIn(50L, 600_000L), id)
                }
                "maurya_wait_value" -> {
                    var value = expression(block, "DURATION", EffectValueType.NUMBER, variables, issues)
                    if (fields.optString("UNIT") == "SEC") {
                        value = EffectExpression.Arithmetic(
                            ArithmeticOperator.MULTIPLY, value, EffectExpression.NumberLiteral(1000.0),
                        )
                    }
                    result += EffectOp.Wait(value, id)
                }
                "maurya_seed_random" -> result += EffectOp.SeedRandom(
                    expression(block, "SEED", EffectValueType.NUMBER, variables, issues),
                    id,
                )
                "maurya_function_call" -> result += EffectOp.CallFunction(
                    fields.optString("NAME").trim(),
                    emptyList(),
                    id,
                )
                "maurya_apply_colour_list" -> {
                    val colours = expression(
                        block, "LIST", EffectValueType.COLOUR_LIST, variables, issues,
                    )
                    repeat(7) { index ->
                        result += EffectOp.SetColour(
                            EffectTarget.entries[index + 1],
                            EffectExpression.ListGet(
                                colours,
                                EffectExpression.NumberLiteral(index.toDouble()),
                                EffectValueType.COLOUR,
                            ),
                            "$id:$index",
                        )
                    }
                }
                "maurya_var_set_number", "maurya_var_set_boolean", "maurya_var_set_colour" -> {
                    val expected = when (block.optString("type")) {
                        "maurya_var_set_number" -> EffectValueType.NUMBER
                        "maurya_var_set_boolean" -> EffectValueType.BOOLEAN
                        else -> EffectValueType.COLOUR
                    }
                    val variableId = variableId(fields, expected, variables, id, issues)
                    result += EffectOp.SetVariable(
                        variableId, expression(block, "VALUE", expected, variables, issues), id,
                    )
                }
                "maurya_var_change_number" -> {
                    val variableId = variableId(fields, EffectValueType.NUMBER, variables, id, issues)
                    result += EffectOp.ChangeVariable(
                        variableId, expression(block, "VALUE", EffectValueType.NUMBER, variables, issues), id,
                    )
                }
                "maurya_if", "maurya_if_else" -> {
                    checkDepth(depth, id, issues)
                    result += EffectOp.If(
                        expression(block, "IF", EffectValueType.BOOLEAN, variables, issues),
                        parseChain(inputBlock(block, "DO"), depth + 1, loopDepth, variables, issues),
                        parseChain(inputBlock(block, "ELSE"), depth + 1, loopDepth, variables, issues),
                        id,
                    )
                }
                "maurya_repeat", "maurya_forever" -> {
                    checkDepth(depth, id, issues)
                    val body = parseChain(inputBlock(block, "DO"), depth + 1, loopDepth + 1, variables, issues)
                    if (body.isEmpty()) issues += issue(id, "循环内部不能为空 / ループ内は空にできません")
                    val count = if (block.optString("type") == "maurya_forever") null
                    else EffectExpression.NumberLiteral(fields.optInt("COUNT", 1).coerceIn(1, 1000).toDouble())
                    result += EffectOp.Repeat(count, body, id)
                }
                "maurya_for" -> {
                    checkDepth(depth, id, issues)
                    val variableId = variableId(fields, EffectValueType.NUMBER, variables, id, issues)
                    val step = expression(block, "BY", EffectValueType.NUMBER, variables, issues)
                    if ((step as? EffectExpression.NumberLiteral)?.value == 0.0) {
                        issues += issue(id, "for循环步长不能为0 / forの増分は0にできません")
                    }
                    val body = parseChain(inputBlock(block, "DO"), depth + 1, loopDepth + 1, variables, issues)
                    if (body.isEmpty()) issues += issue(id, "for循环内部不能为空 / for内は空にできません")
                    result += EffectOp.For(
                        variableId,
                        expression(block, "FROM", EffectValueType.NUMBER, variables, issues),
                        expression(block, "TO", EffectValueType.NUMBER, variables, issues),
                        step, body, id,
                    )
                }
                "maurya_while" -> {
                    checkDepth(depth, id, issues)
                    val body = parseChain(inputBlock(block, "DO"), depth + 1, loopDepth + 1, variables, issues)
                    if (body.isEmpty()) issues += issue(id, "while循环内部不能为空 / while内は空にできません")
                    result += EffectOp.While(
                        expression(block, "IF", EffectValueType.BOOLEAN, variables, issues), body, id,
                    )
                }
                "maurya_break" -> if (loopDepth == 0) {
                    issues += issue(id, "跳出循环只能放在循环内部 / breakはループ内だけで使用できます")
                } else result += EffectOp.Break(id)
                "maurya_continue" -> if (loopDepth == 0) {
                    issues += issue(id, "继续下一轮只能放在循环内部 / continueはループ内だけで使用できます")
                } else result += EffectOp.Continue(id)
                "maurya_end" -> {
                    result += EffectOp.End(id)
                    if (next(block) != null) issues += issue(id, "结束程序后的积木不可达 / 終了後のブロックには到達できません")
                    block = null
                    continue
                }
                else -> issues += issue(id, "不支持的积木：${block.optString("type")} / 未対応ブロック")
            }
            block = next(block)
        }
        return result
    }

    private fun validateBlocklyFunctions(
        operations: List<EffectOp>,
        functions: Map<String, EffectFunctionDefinition>,
        issues: MutableList<String>,
    ) {
        fun calls(source: List<EffectOp>): Set<String> {
            val result = linkedSetOf<String>()
            fun visit(items: List<EffectOp>) {
                items.forEach { operation ->
                    when (operation) {
                        is EffectOp.CallFunction -> result += operation.name
                        is EffectOp.If -> {
                            visit(operation.thenBody)
                            visit(operation.elseBody)
                        }
                        is EffectOp.Repeat -> visit(operation.body)
                        is EffectOp.For -> visit(operation.body)
                        is EffectOp.While -> visit(operation.body)
                        else -> Unit
                    }
                }
            }
            visit(source)
            return result
        }

        val allCalls = calls(operations) + functions.values.flatMap { calls(it.operations) }
        allCalls.filterNot(functions::containsKey).forEach { name ->
            issues += "找不到函数$name / 関数$name が見つかりません"
        }
        val graph = functions.mapValues { calls(it.value.operations).filter(functions::containsKey).toSet() }
        val done = mutableSetOf<String>()
        fun visit(name: String, active: MutableSet<String>) {
            if (name in done) return
            if (!active.add(name)) {
                issues += "禁止递归调用函数$name / 関数$name の再帰呼び出しは禁止です"
                return
            }
            graph[name].orEmpty().forEach { visit(it, active) }
            active.remove(name)
            done += name
        }
        functions.keys.forEach { visit(it, mutableSetOf()) }
    }

    private fun expression(
        parent: JSONObject,
        inputName: String,
        expected: EffectValueType,
        variables: Map<String, VariableInfo>,
        issues: MutableList<String>,
    ): EffectExpression {
        val block = inputBlock(parent, inputName)
        if (block == null) {
            issues += issue(parent.optString("id"), "缺少输入：$inputName / 入力がありません")
            return defaultExpression(expected)
        }
        val parsed = parseExpression(block, variables, issues)
        if (parsed.type != expected) {
            issues += issue(block.optString("id"), "输入类型应为$expected，实际为${parsed.type} / 型が一致しません")
            return defaultExpression(expected)
        }
        return parsed
    }

    private fun parseExpression(
        block: JSONObject,
        variables: Map<String, VariableInfo>,
        issues: MutableList<String>,
    ): EffectExpression {
        val id = block.optString("id")
        val fields = block.optJSONObject("fields") ?: JSONObject()
        return when (block.optString("type")) {
            "math_number" -> EffectExpression.NumberLiteral(fields.optDouble("NUM", 0.0))
            "logic_boolean" -> EffectExpression.BooleanLiteral(fields.optString("BOOL", "TRUE") == "TRUE")
            "maurya_colour_literal" -> EffectExpression.ColourLiteral(hexToHsv(fields.optString("COLOR", "#FFFFFF")))
            "maurya_var_get_number" -> EffectExpression.Variable(
                variableId(fields, EffectValueType.NUMBER, variables, id, issues), EffectValueType.NUMBER,
            )
            "maurya_var_get_boolean" -> EffectExpression.Variable(
                variableId(fields, EffectValueType.BOOLEAN, variables, id, issues), EffectValueType.BOOLEAN,
            )
            "maurya_var_get_colour" -> EffectExpression.Variable(
                variableId(fields, EffectValueType.COLOUR, variables, id, issues), EffectValueType.COLOUR,
            )
            "maurya_elapsed" -> EffectExpression.ElapsedMs
            "maurya_group_value" -> EffectExpression.GroupValue(
                fields.optInt("GROUP", 0).coerceIn(0, 6),
                when (fields.optString("PROPERTY", "H")) {
                    "S" -> EffectGroupProperty.SATURATION
                    "V" -> EffectGroupProperty.VALUE
                    "MODE" -> EffectGroupProperty.MODE
                    else -> EffectGroupProperty.HUE
                },
            )
            "maurya_algorithm_unary" -> builtinExpression(
                block, fields, variables, issues,
                listOf("A" to EffectValueType.NUMBER), EffectValueType.NUMBER,
            )
            "maurya_algorithm_binary" -> builtinExpression(
                block, fields, variables, issues,
                listOf("A" to EffectValueType.NUMBER, "B" to EffectValueType.NUMBER),
                EffectValueType.NUMBER,
            )
            "maurya_algorithm_ternary" -> builtinExpression(
                block, fields, variables, issues,
                listOf(
                    "A" to EffectValueType.NUMBER,
                    "B" to EffectValueType.NUMBER,
                    "C" to EffectValueType.NUMBER,
                ),
                EffectValueType.NUMBER,
            )
            "maurya_wave" -> builtinExpression(
                block, fields, variables, issues,
                listOf("PERIOD" to EffectValueType.NUMBER, "PHASE" to EffectValueType.NUMBER),
                EffectValueType.NUMBER,
            )
            "maurya_square_wave" -> EffectExpression.Builtin(
                BuiltinFunction.SQUARE_WAVE,
                listOf(
                    expression(block, "PERIOD", EffectValueType.NUMBER, variables, issues),
                    expression(block, "DUTY", EffectValueType.NUMBER, variables, issues),
                    expression(block, "PHASE", EffectValueType.NUMBER, variables, issues),
                ),
                EffectValueType.NUMBER,
                id,
            )
            "maurya_noise" -> {
                val function = runCatching {
                    BuiltinFunction.valueOf(fields.optString("FUNCTION", "NOISE_1D"))
                }.getOrDefault(BuiltinFunction.NOISE_1D)
                val x = expression(block, "X", EffectValueType.NUMBER, variables, issues)
                val seed = expression(block, "SEED", EffectValueType.NUMBER, variables, issues)
                val arguments = if (function == BuiltinFunction.FBM_NOISE) listOf(
                    x,
                    expression(block, "OCTAVES", EffectValueType.NUMBER, variables, issues),
                    seed,
                ) else listOf(x, seed)
                EffectExpression.Builtin(function, arguments, EffectValueType.NUMBER, id)
            }
            "maurya_random_number" -> EffectExpression.Builtin(
                BuiltinFunction.RANDOM,
                listOf(
                    expression(block, "LOW", EffectValueType.NUMBER, variables, issues),
                    expression(block, "HIGH", EffectValueType.NUMBER, variables, issues),
                ),
                EffectValueType.NUMBER,
                id,
            )
            "maurya_random_colour" -> EffectExpression.Builtin(
                BuiltinFunction.RANDOM_COLOUR,
                emptyList(),
                EffectValueType.COLOUR,
                id,
            )
            "maurya_colour_unary" -> builtinExpression(
                block, fields, variables, issues,
                listOf("COLOUR" to EffectValueType.COLOUR), EffectValueType.COLOUR,
            )
            "maurya_colour_adjust" -> builtinExpression(
                block, fields, variables, issues,
                listOf("COLOUR" to EffectValueType.COLOUR, "AMOUNT" to EffectValueType.NUMBER),
                EffectValueType.COLOUR,
            )
            "maurya_colour_mix" -> builtinExpression(
                block, fields, variables, issues,
                listOf(
                    "A" to EffectValueType.COLOUR,
                    "B" to EffectValueType.COLOUR,
                    "AMOUNT" to EffectValueType.NUMBER,
                ),
                EffectValueType.COLOUR,
            )
            "maurya_runtime_number", "maurya_audio_number" -> EffectExpression.RuntimeInput(
                runCatching { RuntimeInputKey.valueOf(fields.optString("KEY")) }
                    .getOrElse {
                        issues += issue(id, "运行时输入无效 / ランタイム入力が無効です")
                        RuntimeInputKey.SENSOR_MOTION
                    },
            )
            "maurya_audio_beat" -> EffectExpression.RuntimeInput(RuntimeInputKey.AUDIO_BEAT)
            "maurya_time_phase" -> {
                val function = runCatching {
                    BuiltinFunction.valueOf(fields.optString("FUNCTION", "CYCLE"))
                }.getOrDefault(BuiltinFunction.CYCLE)
                val inputs = when (function) {
                    BuiltinFunction.CYCLE,
                    BuiltinFunction.BEAT_PHASE,
                    -> listOf("A")
                    else -> listOf("A", "B", "C")
                }
                EffectExpression.Builtin(
                    function,
                    inputs.map { expression(block, it, EffectValueType.NUMBER, variables, issues) },
                    EffectValueType.NUMBER,
                    id,
                )
            }
            "maurya_colour_list7" -> EffectExpression.ListLiteral(
                (1..7).map {
                    expression(block, "C$it", EffectValueType.COLOUR, variables, issues)
                },
                EffectValueType.COLOUR_LIST,
            )
            "maurya_number_list7" -> EffectExpression.ListLiteral(
                (1..7).map {
                    expression(block, "N$it", EffectValueType.NUMBER, variables, issues)
                },
                EffectValueType.NUMBER_LIST,
            )
            "maurya_colour_list_get" -> EffectExpression.ListGet(
                expression(block, "LIST", EffectValueType.COLOUR_LIST, variables, issues),
                expression(block, "INDEX", EffectValueType.NUMBER, variables, issues),
                EffectValueType.COLOUR,
            )
            "maurya_number_list_get" -> EffectExpression.ListGet(
                expression(block, "LIST", EffectValueType.NUMBER_LIST, variables, issues),
                expression(block, "INDEX", EffectValueType.NUMBER, variables, issues),
                EffectValueType.NUMBER,
            )
            "maurya_list_length" -> {
                val listBlock = inputBlock(block, "LIST")
                val list = listBlock?.let { parseExpression(it, variables, issues) }
                    ?: EffectExpression.ListLiteral(emptyList(), EffectValueType.NUMBER_LIST)
                        .also { issues += issue(id, "缺少列表 / リストがありません") }
                EffectExpression.Builtin(
                    BuiltinFunction.LIST_LENGTH, listOf(list), EffectValueType.NUMBER, id,
                )
            }
            "maurya_pattern" -> builtinExpression(
                block, fields, variables, issues,
                listOf("PROGRESS" to EffectValueType.NUMBER), EffectValueType.NUMBER_LIST,
            )
            "maurya_pattern_list" -> {
                val listBlock = inputBlock(block, "LIST")
                val list = listBlock?.let { parseExpression(it, variables, issues) }
                    ?: EffectExpression.ListLiteral(emptyList(), EffectValueType.NUMBER_LIST)
                        .also { issues += issue(id, "缺少图案列表 / パターンリストがありません") }
                val function = runCatching {
                    BuiltinFunction.valueOf(fields.optString("FUNCTION", "MIRROR"))
                }.getOrDefault(BuiltinFunction.MIRROR)
                val arguments = if (function == BuiltinFunction.ROTATE_PATTERN) {
                    listOf(
                        list,
                        expression(block, "OFFSET", EffectValueType.NUMBER, variables, issues),
                    )
                } else listOf(list)
                EffectExpression.Builtin(function, arguments, list.type, id)
            }
            "math_arithmetic" -> {
                val op = when (fields.optString("OP", "ADD")) {
                    "MINUS" -> ArithmeticOperator.SUBTRACT
                    "MULTIPLY" -> ArithmeticOperator.MULTIPLY
                    "DIVIDE" -> ArithmeticOperator.DIVIDE
                    "POWER" -> ArithmeticOperator.POWER
                    else -> ArithmeticOperator.ADD
                }
                EffectExpression.Arithmetic(
                    op,
                    expression(block, "A", EffectValueType.NUMBER, variables, issues),
                    expression(block, "B", EffectValueType.NUMBER, variables, issues),
                )
            }
            "math_modulo" -> EffectExpression.Arithmetic(
                ArithmeticOperator.MODULO,
                expression(block, "DIVIDEND", EffectValueType.NUMBER, variables, issues),
                expression(block, "DIVISOR", EffectValueType.NUMBER, variables, issues),
            )
            "maurya_minmax" -> EffectExpression.Arithmetic(
                if (fields.optString("OP") == "MAX") ArithmeticOperator.MAX else ArithmeticOperator.MIN,
                expression(block, "A", EffectValueType.NUMBER, variables, issues),
                expression(block, "B", EffectValueType.NUMBER, variables, issues),
            )
            "maurya_clamp" -> EffectExpression.Clamp(
                expression(block, "VALUE", EffectValueType.NUMBER, variables, issues),
                expression(block, "LOW", EffectValueType.NUMBER, variables, issues),
                expression(block, "HIGH", EffectValueType.NUMBER, variables, issues),
            )
            "logic_compare" -> {
                val leftBlock = inputBlock(block, "A")
                val rightBlock = inputBlock(block, "B")
                val left = leftBlock?.let { parseExpression(it, variables, issues) }
                    ?: defaultExpression(EffectValueType.NUMBER)
                val right = rightBlock?.let { parseExpression(it, variables, issues) }
                    ?: defaultExpression(left.type)
                if (left.type != right.type) issues += issue(id, "比较两侧类型不同 / 比較する型が一致しません")
                val op = when (fields.optString("OP", "EQ")) {
                    "NEQ" -> ComparisonOperator.NEQ
                    "LT" -> ComparisonOperator.LT
                    "LTE" -> ComparisonOperator.LTE
                    "GT" -> ComparisonOperator.GT
                    "GTE" -> ComparisonOperator.GTE
                    else -> ComparisonOperator.EQ
                }
                if (op !in listOf(ComparisonOperator.EQ, ComparisonOperator.NEQ) && left.type != EffectValueType.NUMBER) {
                    issues += issue(id, "大小比较只支持数值 / 大小比較は数値のみです")
                }
                EffectExpression.Comparison(op, left, right)
            }
            "logic_operation" -> EffectExpression.Logic(
                if (fields.optString("OP") == "OR") LogicOperator.OR else LogicOperator.AND,
                expression(block, "A", EffectValueType.BOOLEAN, variables, issues),
                expression(block, "B", EffectValueType.BOOLEAN, variables, issues),
            )
            "logic_negate" -> EffectExpression.Not(
                expression(block, "BOOL", EffectValueType.BOOLEAN, variables, issues),
            )
            "maurya_hsv_colour" -> EffectExpression.ColourFromHsv(
                expression(block, "H", EffectValueType.NUMBER, variables, issues),
                expression(block, "S", EffectValueType.NUMBER, variables, issues),
                expression(block, "V", EffectValueType.NUMBER, variables, issues),
            )
            else -> {
                issues += issue(id, "不支持的表达式：${block.optString("type")} / 未対応の式")
                defaultExpression(EffectValueType.NUMBER)
            }
        }
    }

    private fun builtinExpression(
        block: JSONObject,
        fields: JSONObject,
        variables: Map<String, VariableInfo>,
        issues: MutableList<String>,
        inputs: List<Pair<String, EffectValueType>>,
        result: EffectValueType,
    ): EffectExpression {
        val id = block.optString("id")
        val function = runCatching {
            BuiltinFunction.valueOf(fields.optString("FUNCTION"))
        }.getOrElse {
            issues += issue(id, "算法函数无效 / アルゴリズム関数が無効です")
            BuiltinFunction.ABS
        }
        return EffectExpression.Builtin(
            function,
            inputs.map { (name, type) -> expression(block, name, type, variables, issues) },
            result,
            id,
        )
    }

    private fun validateReachability(ops: List<EffectOp>, issues: MutableList<String>) {
        ops.forEachIndexed { index, op ->
            when (op) {
                is EffectOp.Repeat -> {
                    validateReachability(op.body, issues)
                    if (op.count == null && index != ops.lastIndex) {
                        issues += issue(op.blockId, "永久循环后的积木不可达 / 無限ループ後には到達できません")
                    }
                }
                is EffectOp.If -> {
                    validateReachability(op.thenBody, issues)
                    validateReachability(op.elseBody, issues)
                }
                is EffectOp.For -> validateReachability(op.body, issues)
                is EffectOp.While -> validateReachability(op.body, issues)
                else -> Unit
            }
        }
    }

    private data class PendingLightChange(
        val operation: EffectOp,
        val suggestedWaitMs: Long,
    )

    private data class VisibilityState(
        val pending: List<PendingLightChange> = emptyList(),
        val lastWaitMs: Long = 1_000L,
    )

    private fun validateObservableStates(
        operations: List<EffectOp>,
        diagnostics: MutableList<EffectCompileIssue>,
    ) {
        val result = analyseVisibility(operations, VisibilityState(), diagnostics)
        appendInvisibleIssues(result.pending, diagnostics)
    }

    private fun analyseVisibility(
        operations: List<EffectOp>,
        initial: VisibilityState,
        diagnostics: MutableList<EffectCompileIssue>,
    ): VisibilityState {
        var state = initial
        for (operation in operations) {
            state = when (operation) {
                is EffectOp.SetHsv,
                is EffectOp.SetColour,
                is EffectOp.AdjustHsv,
                is EffectOp.SetMode,
                -> VisibilityState(
                    pending = listOf(PendingLightChange(operation, state.lastWaitMs)),
                    lastWaitMs = state.lastWaitMs,
                )
                is EffectOp.Wait -> VisibilityState(
                    pending = emptyList(),
                    lastWaitMs = literal(operation.durationMs)?.toLong()
                        ?.coerceIn(100L, 600_000L) ?: state.lastWaitMs,
                )
                is EffectOp.FadeHsv -> VisibilityState(
                    pending = emptyList(),
                    lastWaitMs = literal(operation.durationMs)?.toLong()
                        ?.coerceIn(100L, 600_000L) ?: state.lastWaitMs,
                )
                is EffectOp.FadeColour -> VisibilityState(
                    pending = emptyList(),
                    lastWaitMs = literal(operation.durationMs)?.toLong()
                        ?.coerceIn(100L, 600_000L) ?: state.lastWaitMs,
                )
                is EffectOp.If -> {
                    val thenState = analyseVisibility(operation.thenBody, state, diagnostics)
                    val elseState = analyseVisibility(operation.elseBody, state, diagnostics)
                    VisibilityState(
                        pending = (thenState.pending + elseState.pending)
                            .distinctBy { it.operation.blockId },
                        lastWaitMs = maxOf(thenState.lastWaitMs, elseState.lastWaitMs),
                    )
                }
                is EffectOp.Repeat -> {
                    val bodyState = analyseVisibility(
                        operation.body,
                        VisibilityState(lastWaitMs = state.lastWaitMs),
                        diagnostics,
                    )
                    appendInvisibleIssues(bodyState.pending, diagnostics)
                    VisibilityState(lastWaitMs = bodyState.lastWaitMs)
                }
                is EffectOp.For -> {
                    val bodyState = analyseVisibility(
                        operation.body,
                        state,
                        diagnostics,
                    )
                    // A finite for loop is commonly used to build one complete seven-group
                    // frame. Preserve its pending mutations so a wait immediately after the
                    // loop makes the assembled frame observable.
                    bodyState
                }
                is EffectOp.While -> {
                    val bodyState = analyseVisibility(
                        operation.body,
                        VisibilityState(lastWaitMs = state.lastWaitMs),
                        diagnostics,
                    )
                    appendInvisibleIssues(bodyState.pending, diagnostics)
                    VisibilityState(lastWaitMs = bodyState.lastWaitMs)
                }
                is EffectOp.End -> {
                    appendInvisibleIssues(state.pending, diagnostics)
                    VisibilityState(lastWaitMs = state.lastWaitMs)
                }
                else -> state
            }
        }
        return state
    }

    private fun appendInvisibleIssues(
        pending: List<PendingLightChange>,
        diagnostics: MutableList<EffectCompileIssue>,
    ) {
        pending.distinctBy { it.operation.blockId }.forEach { change ->
            val source = parseScriptSourceId(change.operation.blockId)
            diagnostics += EffectCompileIssue(
                code = "EFFECT_STATE_NOT_OBSERVABLE",
                messageZh = "该灯光状态持续0 ms，会在显示前被下一轮或程序结束覆盖",
                messageJa = "このライト状態は0 msのため、表示前に次のループまたは終了で上書きされます",
                sourceId = change.operation.blockId,
                quickFixWaitMs = change.suggestedWaitMs.coerceIn(100L, 600_000L),
                sourceStart = source?.first,
                sourceEnd = source?.second,
            )
        }
    }

    private fun parseScriptSourceId(sourceId: String): Pair<Int, Int>? {
        if (!sourceId.startsWith("script:")) return null
        val parts = sourceId.split(':')
        if (parts.size < 3) return null
        val start = parts[1].toIntOrNull() ?: return null
        val end = parts[2].toIntOrNull() ?: return null
        return start to end
    }

    private fun duration(ops: List<EffectOp>): Long? {
        var sum = 0L
        for (op in ops) {
            val value = when (op) {
                is EffectOp.FadeHsv -> literal(op.durationMs)?.toLong() ?: return null
                is EffectOp.FadeColour -> literal(op.durationMs)?.toLong() ?: return null
                is EffectOp.Wait -> literal(op.durationMs)?.toLong() ?: return null
                is EffectOp.Repeat -> {
                    val body = duration(op.body) ?: return null
                    val count = op.count?.let(::literal)?.toLong() ?: return null
                    body * count.coerceIn(0, 1000)
                }
                is EffectOp.If -> {
                    val condition = (op.condition as? EffectExpression.BooleanLiteral)?.value ?: return null
                    duration(if (condition) op.thenBody else op.elseBody) ?: return null
                }
                is EffectOp.For -> {
                    val start = literal(op.from) ?: return null
                    val end = literal(op.to) ?: return null
                    val step = literal(op.step) ?: return null
                    if (step == 0.0) return null
                    val count = if ((step > 0 && start > end) || (step < 0 && start < end)) 0L
                    else (floor(abs((end - start) / step)) + 1).toLong().coerceAtMost(1000)
                    (duration(op.body) ?: return null) * count
                }
                is EffectOp.While -> {
                    if ((op.condition as? EffectExpression.BooleanLiteral)?.value == false) 0L else return null
                }
                else -> 0L
            }
            sum = (sum + value.coerceAtLeast(0L)).coerceAtMost(Long.MAX_VALUE / 2)
        }
        return sum
    }

    private fun literal(expression: EffectExpression): Double? =
        (expression as? EffectExpression.NumberLiteral)?.value

    private fun canonicalOps(ops: List<EffectOp>): JSONArray = JSONArray().apply {
        ops.forEach { op ->
            put(when (op) {
                is EffectOp.SetHsv -> base("set", op).put("target", targetJson(op.target))
                    .put("h", expressionJson(op.h)).put("s", expressionJson(op.s)).put("v", expressionJson(op.v))
                is EffectOp.SetColour -> base("setColour", op).put("target", targetJson(op.target))
                    .put("colour", expressionJson(op.colour))
                is EffectOp.FadeHsv -> base("fade", op).put("target", targetJson(op.target))
                    .put("h", expressionJson(op.h)).put("s", expressionJson(op.s)).put("v", expressionJson(op.v))
                    .put("ms", expressionJson(op.durationMs))
                is EffectOp.FadeColour -> base("fadeColour", op).put("target", targetJson(op.target))
                    .put("colour", expressionJson(op.colour)).put("ms", expressionJson(op.durationMs))
                is EffectOp.AdjustHsv -> base("adjust", op).put("target", targetJson(op.target))
                    .put("dh", expressionJson(op.dh)).put("ds", expressionJson(op.ds)).put("dv", expressionJson(op.dv))
                is EffectOp.SetMode -> base("mode", op).put("target", targetJson(op.target))
                    .put("mode", expressionJson(op.mode)).put("param", expressionJson(op.param))
                is EffectOp.Wait -> base("wait", op).put("ms", expressionJson(op.durationMs))
                is EffectOp.SetVariable -> base("setVariable", op).put("id", op.id).put("value", expressionJson(op.value))
                is EffectOp.ChangeVariable -> base("changeVariable", op).put("id", op.id).put("delta", expressionJson(op.delta))
                is EffectOp.SetListItem -> base("setListItem", op).put("id", op.id)
                    .put("index", expressionJson(op.index)).put("value", expressionJson(op.value))
                is EffectOp.SeedRandom -> base("seedRandom", op).put("seed", expressionJson(op.seed))
                is EffectOp.CallFunction -> base("callFunction", op).put("name", op.name)
                    .put("arguments", JSONArray().apply { op.arguments.forEach { put(expressionJson(it)) } })
                is EffectOp.If -> base("if", op).put("condition", expressionJson(op.condition))
                    .put("then", canonicalOps(op.thenBody)).put("else", canonicalOps(op.elseBody))
                is EffectOp.Repeat -> base("repeat", op)
                    .put("count", op.count?.let(::expressionJson) ?: JSONObject.NULL).put("body", canonicalOps(op.body))
                is EffectOp.For -> base("for", op).put("id", op.variableId)
                    .put("from", expressionJson(op.from)).put("to", expressionJson(op.to)).put("step", expressionJson(op.step))
                    .put("body", canonicalOps(op.body))
                is EffectOp.While -> base("while", op).put("condition", expressionJson(op.condition))
                    .put("body", canonicalOps(op.body))
                is EffectOp.Break -> base("break", op)
                is EffectOp.Continue -> base("continue", op)
                is EffectOp.End -> base("end", op)
            })
        }
    }

    private fun base(name: String, op: EffectOp) = JSONObject().put("op", name).put("blockId", op.blockId)

    private fun targetJson(target: EffectTargetRef): JSONObject = when (target) {
        EffectTargetRef.All -> JSONObject().put("kind", "all")
        EffectTargetRef.AllPixels -> JSONObject().put("kind", "allPixels")
        is EffectTargetRef.Group -> JSONObject().put("kind", "group")
            .put("index", expressionJson(target.oneBasedIndex))
        is EffectTargetRef.Pixel -> JSONObject().put("kind", "pixel")
            .put("group", expressionJson(target.oneBasedGroup))
            .put("pixel", expressionJson(target.oneBasedPixel))
        is EffectTargetRef.PixelAt -> JSONObject().put("kind", "pixelAt")
            .put("index", expressionJson(target.oneBasedIndex))
        is EffectTargetRef.Value -> JSONObject().put("kind", "value")
            .put("expression", expressionJson(target.expression))
    }

    private fun expressionJson(expression: EffectExpression): JSONObject = when (expression) {
        is EffectExpression.NumberLiteral -> JSONObject().put("type", "number").put("value", expression.value)
        is EffectExpression.BooleanLiteral -> JSONObject().put("type", "boolean").put("value", expression.value)
        is EffectExpression.ColourLiteral -> JSONObject().put("type", "colour")
            .put("h", expression.value.hue).put("s", expression.value.saturation).put("v", expression.value.value)
        is EffectExpression.Variable -> JSONObject().put("type", "variable").put("id", expression.id)
            .put("valueType", expression.type.name)
        EffectExpression.ElapsedMs -> JSONObject().put("type", "elapsed")
        is EffectExpression.GroupValue -> JSONObject().put("type", "group").put("group", expression.group)
            .put("property", expression.property.name)
        is EffectExpression.DynamicGroupValue -> JSONObject().put("type", "dynamicGroup")
            .put("index", expressionJson(expression.oneBasedIndex)).put("property", expression.property.name)
        is EffectExpression.Arithmetic -> JSONObject().put("type", "arithmetic").put("op", expression.operator.name)
            .put("left", expressionJson(expression.left)).put("right", expressionJson(expression.right))
        is EffectExpression.Clamp -> JSONObject().put("type", "clamp").put("value", expressionJson(expression.value))
            .put("low", expressionJson(expression.low)).put("high", expressionJson(expression.high))
        is EffectExpression.Comparison -> JSONObject().put("type", "comparison").put("op", expression.operator.name)
            .put("left", expressionJson(expression.left)).put("right", expressionJson(expression.right))
        is EffectExpression.Logic -> JSONObject().put("type", "logic").put("op", expression.operator.name)
            .put("left", expressionJson(expression.left)).put("right", expressionJson(expression.right))
        is EffectExpression.Not -> JSONObject().put("type", "not").put("value", expressionJson(expression.value))
        is EffectExpression.ColourFromHsv -> JSONObject().put("type", "hsv")
            .put("h", expressionJson(expression.hue)).put("s", expressionJson(expression.saturation))
            .put("v", expressionJson(expression.value))
        is EffectExpression.TargetLiteral -> JSONObject().put("type", "target")
            .put("target", expression.target.name)
        is EffectExpression.TargetFromIndex -> JSONObject().put("type", "targetFromIndex")
            .put("index", expressionJson(expression.oneBasedIndex))
        is EffectExpression.RuntimeInput -> JSONObject().put("type", "runtimeInput")
            .put("key", expression.key.name)
        is EffectExpression.Builtin -> JSONObject().put("type", "builtin")
            .put("function", expression.function.name)
            .put("valueType", expression.type.name)
            .put("nodeId", expression.nodeId)
            .put("arguments", JSONArray().apply {
                expression.arguments.forEach { put(expressionJson(it)) }
            })
        is EffectExpression.ListLiteral -> JSONObject().put("type", "list")
            .put("valueType", expression.type.name)
            .put("elements", JSONArray().apply {
                expression.elements.forEach { put(expressionJson(it)) }
            })
        is EffectExpression.ListGet -> JSONObject().put("type", "listGet")
            .put("valueType", expression.type.name)
            .put("list", expressionJson(expression.list))
            .put("index", expressionJson(expression.index))
        is EffectExpression.FunctionCall -> JSONObject().put("type", "functionCall")
            .put("name", expression.name)
            .put("valueType", expression.type.name)
            .put("nodeId", expression.nodeId)
            .put("arguments", JSONArray().apply {
                expression.arguments.forEach { put(expressionJson(it)) }
            })
    }

    private fun canonicalProgram(
        operations: List<EffectOp>,
        functions: Map<String, EffectFunctionDefinition>,
    ): JSONObject = JSONObject()
        .put("operations", canonicalOps(operations))
        .put("functions", JSONArray().apply {
            functions.toSortedMap().values.forEach { function ->
                put(JSONObject()
                    .put("name", function.name)
                    .put("parameters", JSONArray().apply {
                        function.parameters.forEach { parameter ->
                            put(JSONObject()
                                .put("name", parameter.name)
                                .put("variableId", parameter.variableId)
                                .put("type", parameter.type.name))
                        }
                    })
                    .put("returnType", function.returnType?.name ?: JSONObject.NULL)
                    .put("operations", canonicalOps(function.operations))
                    .put("return", function.returnExpression?.let(::expressionJson) ?: JSONObject.NULL))
            }
        })

    private fun countBlocks(array: JSONArray): Int {
        var count = 0
        fun visit(block: JSONObject?) {
            if (block == null) return
            count++
            val inputs = block.optJSONObject("inputs")
            inputs?.keys()?.forEach {
                val input = inputs.optJSONObject(it)
                visit(input?.optJSONObject("block") ?: input?.optJSONObject("shadow"))
            }
            visit(next(block))
        }
        for (index in 0 until array.length()) visit(array.optJSONObject(index))
        return count
    }

    private fun inputBlock(block: JSONObject, name: String): JSONObject? {
        val input = block.optJSONObject("inputs")?.optJSONObject(name) ?: return null
        return input.optJSONObject("block") ?: input.optJSONObject("shadow")
    }

    private fun next(block: JSONObject) = block.optJSONObject("next")?.optJSONObject("block")

    private fun variableId(
        fields: JSONObject,
        expected: EffectValueType,
        variables: Map<String, VariableInfo>,
        blockId: String,
        issues: MutableList<String>,
    ): String {
        val raw = fields.opt("VAR")
        val id = when (raw) {
            is JSONObject -> raw.optString("id")
            null, JSONObject.NULL -> ""
            else -> raw.toString()
        }
        val info = variables[id] ?: variables.values.firstOrNull { it.name == id }
        if (info == null) {
            issues += issue(blockId, "找不到变量：$id / 変数が見つかりません")
            return id
        }
        if (info.type != expected) issues += issue(blockId, "变量${info.name}类型错误 / 変数の型が一致しません")
        return info.id
    }

    private fun target(raw: String, blockId: String, issues: MutableList<String>): EffectTargetRef =
        if (raw == "ALL") EffectTargetRef.All
        else raw.toIntOrNull()?.takeIf { it in 0..6 }?.let {
            EffectTargetRef.Group(EffectExpression.NumberLiteral((it + 1).toDouble()))
        } ?: EffectTargetRef.All.also {
            issues += issue(blockId, "目标灯组无效 / ライトグループが無効です")
        }

    private fun defaultExpression(type: EffectValueType): EffectExpression = when (type) {
        EffectValueType.NUMBER -> EffectExpression.NumberLiteral(0.0)
        EffectValueType.BOOLEAN -> EffectExpression.BooleanLiteral(false)
        EffectValueType.COLOUR -> EffectExpression.ColourLiteral(EffectColour(0, 0, 255))
        EffectValueType.TARGET -> EffectExpression.TargetLiteral(EffectTarget.ALL)
        EffectValueType.NUMBER_LIST -> EffectExpression.ListLiteral(emptyList(), type)
        EffectValueType.BOOLEAN_LIST -> EffectExpression.ListLiteral(emptyList(), type)
        EffectValueType.COLOUR_LIST -> EffectExpression.ListLiteral(emptyList(), type)
        EffectValueType.TARGET_LIST -> EffectExpression.ListLiteral(emptyList(), type)
    }

    private fun checkDepth(depth: Int, blockId: String, issues: MutableList<String>) {
        if (depth >= maxControlDepth) {
            issues += issue(blockId, "控制结构嵌套不能超过 $maxControlDepth 层 / ネストは${maxControlDepth}階層までです")
        }
    }

    private fun issue(blockId: String, message: String) =
        if (blockId.isBlank()) message else "[$blockId] $message"

    private fun wrapHue(value: Int) = ((value % 360) + 360) % 360

    private fun hexToHsv(hex: String): EffectColour {
        val clean = hex.removePrefix("#")
        val rgb = clean.toIntOrNull(16) ?: 0xFFFFFF
        val r = (rgb shr 16 and 255) / 255.0
        val g = (rgb shr 8 and 255) / 255.0
        val b = (rgb and 255) / 255.0
        val high = max(r, max(g, b))
        val low = min(r, min(g, b))
        val delta = high - low
        var hue = when {
            delta == 0.0 -> 0.0
            high == r -> 60.0 * (((g - b) / delta) % 6.0)
            high == g -> 60.0 * ((b - r) / delta + 2.0)
            else -> 60.0 * ((r - g) / delta + 4.0)
        }
        if (hue < 0) hue += 360.0
        return EffectColour(
            hue.toInt().coerceIn(0, 359),
            (if (high == 0.0) 0.0 else delta / high * 255.0).toInt().coerceIn(0, 255),
            (high * 255.0).toInt().coerceIn(0, 255),
        )
    }

    private fun sha256(value: String) = MessageDigest.getInstance("SHA-256")
        .digest(value.toByteArray()).joinToString("") { "%02x".format(it) }
}
