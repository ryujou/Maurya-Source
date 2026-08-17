package com.example.peacock.feature.effects

import com.example.peacock.feature.runtime.GroupState
import java.util.ArrayDeque
import kotlin.math.max
import kotlin.math.min
import kotlin.math.floor
import kotlin.math.pow
import kotlin.math.roundToInt
import kotlin.math.roundToLong

class EffectRuntimeException(message: String) : IllegalStateException(message)

class EffectInterpreter(
    private val compiled: CompiledEffect,
    initial: List<GroupState>,
) {
    private sealed interface RuntimeItem {
        data class Execute(val statement: EffectOp) : RuntimeItem
        data class RepeatLoop(
            val statement: EffectOp.Repeat,
            val iteration: Int,
            val limit: Int?,
            val loopId: String,
        ) : RuntimeItem
        data class ForLoop(
            val statement: EffectOp.For,
            val current: Double,
            val end: Double,
            val step: Double,
            val iteration: Int,
            val loopId: String,
        ) : RuntimeItem
        data class WhileLoop(
            val statement: EffectOp.While,
            val loopId: String,
        ) : RuntimeItem
        data class Boundary(val loopId: String) : RuntimeItem
    }

    private data class ActiveWait(val endMs: Long)
    private data class ActiveFade(
        val targetIndices: List<Int>,
        val startStates: List<GroupState>,
        val colour: EffectColour,
        val startMs: Long,
        val endMs: Long,
        val pixelMode: Boolean,
    )

    private val originalGroups = initial.map { it.copy(innerMode = 1) }
    private var groups = originalGroups.map(GroupState::copy).toMutableList()
    private val originalPixels = originalGroups.flatMap { group ->
        List(EffectGeometry.PIXELS_PER_GROUP) { group.copy(innerMode = 1, innerParam = 0) }
    }
    private var pixels = originalPixels.map(GroupState::copy).toMutableList()
    private val variables = mutableMapOf<String, EffectValue>()
    private val stack = ArrayDeque<RuntimeItem>()
    private var activeWait: ActiveWait? = null
    private var activeFade: ActiveFade? = null
    private var logicalTimeMs = 0L
    private var lastElapsedMs = -1L
    private var finished = false
    private var zeroTimeInstructions = 0
    private var loopSerial = 0L
    private var runtimeSnapshot = EffectRuntimeSnapshot.EMPTY
    private var algorithmState = EffectAlgorithmState(compiled.randomSeed)
    private var functionCallDepth = 0

    val isInfinite: Boolean = compiled.estimatedDurationMs == null
    val durationMs: Long? = compiled.estimatedDurationMs

    init {
        reset()
    }

    fun frameAt(
        elapsedMs: Long,
        snapshot: EffectRuntimeSnapshot = EffectRuntimeSnapshot.EMPTY,
    ): EffectFrame {
        val elapsed = elapsedMs.coerceAtLeast(0L)
        if (elapsed < lastElapsedMs) reset()
        runtimeSnapshot = snapshot
        lastElapsedMs = elapsed
        advanceTo(elapsed)
        val progress = durationMs?.takeIf { it > 0L }
            ?.let { (elapsed.toFloat() / it).coerceIn(0f, 1f) }
        return EffectFrame(
            groups = groups.map(GroupState::copy),
            pixels = if (compiled.requiresPixelEffect) pixels.map(::toRgb) else null,
            finished = finished,
            waiting = activeWait != null,
            progress = progress,
        )
    }

    private fun reset() {
        groups = originalGroups.map(GroupState::copy).toMutableList()
        pixels = originalPixels.map(GroupState::copy).toMutableList()
        variables.clear()
        compiled.variables.forEach { (id, type) ->
            variables[id] = defaultValue(type)
        }
        algorithmState = EffectAlgorithmState(compiled.randomSeed)
        functionCallDepth = 0
        stack.clear()
        pushSequence(compiled.operations)
        activeWait = null
        activeFade = null
        logicalTimeMs = 0L
        lastElapsedMs = -1L
        finished = false
        zeroTimeInstructions = 0
        loopSerial = 0L
    }

    private fun advanceTo(targetMs: Long) {
        while (!finished) {
            activeWait?.let { wait ->
                if (targetMs < wait.endMs) return
                logicalTimeMs = wait.endMs
                activeWait = null
                zeroTimeInstructions = 0
            }
            activeFade?.let { fade ->
                val duration = (fade.endMs - fade.startMs).coerceAtLeast(1L)
                val progress = ((targetMs - fade.startMs).toFloat() / duration).coerceIn(0f, 1f)
                applyFade(fade, progress)
                if (targetMs < fade.endMs) return
                logicalTimeMs = fade.endMs
                activeFade = null
                zeroTimeInstructions = 0
            }

            val item = stack.pollLast()
            if (item == null) {
                finished = true
                return
            }
            zeroTimeInstructions++
            if (zeroTimeInstructions > MAX_ZERO_TIME_INSTRUCTIONS) {
                throw EffectRuntimeException("循环连续执行超过${MAX_ZERO_TIME_INSTRUCTIONS}条无等待指令 / 待機なし命令が多すぎます")
            }
            when (item) {
                is RuntimeItem.Execute -> execute(item.statement)
                is RuntimeItem.RepeatLoop -> executeRepeat(item)
                is RuntimeItem.ForLoop -> executeFor(item)
                is RuntimeItem.WhileLoop -> executeWhile(item)
                is RuntimeItem.Boundary -> Unit
            }
        }
    }

    private fun execute(statement: EffectOp) {
        when (statement) {
            is EffectOp.SetHsv -> {
                val h = wrap(number(statement.h).roundToInt())
                val s = number(statement.s).roundToInt().coerceIn(0, 255)
                val v = number(statement.v).roundToInt().coerceIn(0, 255)
                mutate(statement.target) { it.copy(hue = h, sat = s, value = v) }
            }
            is EffectOp.SetColour -> {
                val colour = colour(statement.colour)
                mutate(statement.target) {
                    it.copy(hue = colour.hue, sat = colour.saturation, value = colour.value)
                }
            }
            is EffectOp.FadeHsv -> beginFade(
                statement.target,
                EffectColour(
                    wrap(number(statement.h).roundToInt()),
                    number(statement.s).roundToInt().coerceIn(0, 255),
                    number(statement.v).roundToInt().coerceIn(0, 255),
                ),
                duration(statement.durationMs),
            )
            is EffectOp.FadeColour -> beginFade(
                statement.target, colour(statement.colour), duration(statement.durationMs),
            )
            is EffectOp.AdjustHsv -> {
                val dh = number(statement.dh).roundToInt()
                val ds = number(statement.ds).roundToInt()
                val dv = number(statement.dv).roundToInt()
                mutate(statement.target) {
                    it.copy(
                        hue = wrap(it.hue + dh),
                        sat = (it.sat + ds).coerceIn(0, 255),
                        value = (it.value + dv).coerceIn(0, 255),
                    )
                }
            }
            is EffectOp.SetMode -> {
                if (compiled.requiresPixelEffect) {
                    throw runtime(statement.blockId, "逐灯程序不能使用硬件组内模式 / ピクセルプログラムではハードウェアモードを使用できません")
                }
                val requested = number(statement.mode).roundToInt()
                val mode = requested.takeIf { it == 1 || it == 3 } ?: 1
                val param = number(statement.param).roundToInt().coerceIn(0, 255)
                mutate(statement.target) { it.copy(innerMode = mode, innerParam = param) }
            }
            is EffectOp.Wait -> {
                activeWait = ActiveWait(logicalTimeMs + duration(statement.durationMs))
            }
            is EffectOp.SetVariable -> {
                val expected = compiled.variables[statement.id]
                    ?: throw runtime(statement.blockId, "变量不存在 / 変数が見つかりません")
                val value = evaluate(statement.value)
                if (value.type() != expected) throw runtime(statement.blockId, "变量类型错误 / 変数の型が一致しません")
                variables[statement.id] = value
            }
            is EffectOp.ChangeVariable -> {
                val current = variables[statement.id] as? EffectValue.Number
                    ?: throw runtime(statement.blockId, "数值变量不存在 / 数値変数が見つかりません")
                variables[statement.id] = EffectValue.Number(finite(current.value + number(statement.delta), statement.blockId))
            }
            is EffectOp.SetListItem -> {
                val list = variables[statement.id] as? EffectValue.ListValue
                    ?: throw runtime(statement.blockId, "列表不存在 / リストが見つかりません")
                val index = number(statement.index).floorToInt()
                if (index !in list.values.indices) {
                    throw runtime(statement.blockId, "列表索引越界 / リストの範囲外です")
                }
                val value = evaluate(statement.value)
                if (value.type() != list.elementType) {
                    throw runtime(statement.blockId, "列表元素类型错误 / リスト要素の型が一致しません")
                }
                list.values[index] = value
            }
            is EffectOp.SeedRandom -> algorithmState.random.reseed(number(statement.seed).roundToLong())
            is EffectOp.CallFunction -> {
                val function = compiled.functions[statement.name]
                    ?: throw runtime(statement.blockId, "函数不存在 / 関数が見つかりません")
                if (function.returnType != null) {
                    throw runtime(statement.blockId, "有返回值函数不能作为流程调用 / 戻り値関数は文として呼び出せません")
                }
                bindFunctionArguments(function, statement.arguments, statement.blockId)
                pushSequence(function.operations)
            }
            is EffectOp.If -> pushSequence(if (boolean(statement.condition)) statement.thenBody else statement.elseBody)
            is EffectOp.Repeat -> {
                val limit = statement.count?.let {
                    number(it).roundToInt().coerceIn(0, MAX_FINITE_ITERATIONS)
                }
                stack.addLast(RuntimeItem.RepeatLoop(statement, 0, limit, nextLoopId(statement.blockId)))
            }
            is EffectOp.For -> {
                val from = number(statement.from)
                val to = number(statement.to)
                val step = number(statement.step)
                if (step == 0.0) throw runtime(statement.blockId, "for循环步长不能为0 / forの増分は0にできません")
                stack.addLast(RuntimeItem.ForLoop(statement, from, to, step, 0, nextLoopId(statement.blockId)))
            }
            is EffectOp.While -> stack.addLast(RuntimeItem.WhileLoop(statement, nextLoopId(statement.blockId)))
            is EffectOp.Break -> breakLoop(statement.blockId)
            is EffectOp.Continue -> continueLoop(statement.blockId)
            is EffectOp.End -> {
                stack.clear()
                activeWait = null
                activeFade = null
                finished = true
            }
        }
    }

    private fun executeRepeat(loop: RuntimeItem.RepeatLoop) {
        if (loop.limit != null && loop.iteration >= loop.limit) return
        val nextIteration = if (loop.iteration == Int.MAX_VALUE) 0 else loop.iteration + 1
        stack.addLast(loop.copy(iteration = nextIteration))
        stack.addLast(RuntimeItem.Boundary(loop.loopId))
        pushSequence(loop.statement.body)
    }

    private fun executeFor(loop: RuntimeItem.ForLoop) {
        val inRange = if (loop.step > 0) loop.current <= loop.end else loop.current >= loop.end
        if (!inRange) return
        if (loop.iteration >= MAX_FINITE_ITERATIONS) {
            throw runtime(loop.statement.blockId, "for循环超过${MAX_FINITE_ITERATIONS}次 / forの回数が上限を超えました")
        }
        variables[loop.statement.variableId] = EffectValue.Number(loop.current)
        stack.addLast(loop.copy(current = finite(loop.current + loop.step, loop.statement.blockId), iteration = loop.iteration + 1))
        stack.addLast(RuntimeItem.Boundary(loop.loopId))
        pushSequence(loop.statement.body)
    }

    private fun executeWhile(loop: RuntimeItem.WhileLoop) {
        if (!boolean(loop.statement.condition)) return
        stack.addLast(loop)
        stack.addLast(RuntimeItem.Boundary(loop.loopId))
        pushSequence(loop.statement.body)
    }

    private fun breakLoop(blockId: String) {
        val boundary = discardToBoundary()
            ?: throw runtime(blockId, "跳出循环不在循环内部 / breakはループ内だけで使用できます")
        val continuation = stack.peekLast()
        if (continuation.loopIdOrNull() == boundary.loopId) stack.removeLast()
    }

    private fun continueLoop(blockId: String) {
        if (discardToBoundary() == null) {
            throw runtime(blockId, "继续下一轮不在循环内部 / continueはループ内だけで使用できます")
        }
    }

    private fun discardToBoundary(): RuntimeItem.Boundary? {
        while (stack.isNotEmpty()) {
            val item = stack.removeLast()
            if (item is RuntimeItem.Boundary) return item
        }
        return null
    }

    private fun RuntimeItem?.loopIdOrNull() = when (this) {
        is RuntimeItem.RepeatLoop -> loopId
        is RuntimeItem.ForLoop -> loopId
        is RuntimeItem.WhileLoop -> loopId
        else -> null
    }

    private fun beginFade(target: EffectTargetRef, targetColour: EffectColour, durationMs: Long) {
        val pixelMode = compiled.requiresPixelEffect
        activeFade = ActiveFade(
            targetIndices = resolveTarget(target),
            startStates = (if (pixelMode) pixels else groups).map(GroupState::copy),
            colour = targetColour,
            startMs = logicalTimeMs,
            endMs = logicalTimeMs + durationMs,
            pixelMode = pixelMode,
        )
    }

    private fun applyFade(fade: ActiveFade, progress: Float) {
        fun transformed(index: Int): GroupState {
            val start = fade.startStates[index]
            val hueDelta = ((fade.colour.hue - start.hue + 540) % 360) - 180
            return start.copy(
                hue = wrap(start.hue + (hueDelta * progress).roundToInt()),
                sat = lerp(start.sat, fade.colour.saturation, progress),
                value = lerp(start.value, fade.colour.value, progress),
            )
        }
        fade.targetIndices.forEach { index ->
            if (fade.pixelMode) pixels[index] = transformed(index)
            else groups[index] = transformed(index)
        }
        if (fade.pixelMode) syncGroupPreview()
    }

    private fun evaluate(expression: EffectExpression): EffectValue = when (expression) {
        is EffectExpression.NumberLiteral -> EffectValue.Number(finite(expression.value))
        is EffectExpression.BooleanLiteral -> EffectValue.Boolean(expression.value)
        is EffectExpression.ColourLiteral -> EffectValue.Colour(expression.value.normalised())
        is EffectExpression.Variable -> variables[expression.id]
            ?: throw EffectRuntimeException("变量不存在 / 変数が見つかりません")
        EffectExpression.ElapsedMs -> EffectValue.Number(logicalTimeMs.toDouble())
        is EffectExpression.GroupValue -> {
            val group = groups[expression.group.coerceIn(0, groups.lastIndex)]
            EffectValue.Number(when (expression.property) {
                EffectGroupProperty.HUE -> group.hue.toDouble()
                EffectGroupProperty.SATURATION -> group.sat.toDouble()
                EffectGroupProperty.VALUE -> group.value.toDouble()
                EffectGroupProperty.MODE -> group.innerMode.toDouble()
            })
        }
        is EffectExpression.DynamicGroupValue -> {
            val index = number(expression.oneBasedIndex).roundToInt()
            if (index !in 1..7) throw EffectRuntimeException("灯组编号必须为1到7 / グループ番号は1から7です")
            val group = groups[index - 1]
            EffectValue.Number(when (expression.property) {
                EffectGroupProperty.HUE -> group.hue.toDouble()
                EffectGroupProperty.SATURATION -> group.sat.toDouble()
                EffectGroupProperty.VALUE -> group.value.toDouble()
                EffectGroupProperty.MODE -> group.innerMode.toDouble()
            })
        }
        is EffectExpression.Arithmetic -> {
            val left = number(expression.left)
            val right = number(expression.right)
            val value = when (expression.operator) {
                ArithmeticOperator.ADD -> left + right
                ArithmeticOperator.SUBTRACT -> left - right
                ArithmeticOperator.MULTIPLY -> left * right
                ArithmeticOperator.DIVIDE -> if (right == 0.0) throw EffectRuntimeException("除数不能为0 / 0で割ることはできません") else left / right
                ArithmeticOperator.MODULO -> if (right == 0.0) throw EffectRuntimeException("除数不能为0 / 0で割ることはできません") else left % right
                ArithmeticOperator.POWER -> left.pow(right)
                ArithmeticOperator.MIN -> min(left, right)
                ArithmeticOperator.MAX -> max(left, right)
            }
            EffectValue.Number(finite(value))
        }
        is EffectExpression.Clamp -> {
            val value = number(expression.value)
            val first = number(expression.low)
            val second = number(expression.high)
            EffectValue.Number(value.coerceIn(min(first, second), max(first, second)))
        }
        is EffectExpression.Comparison -> {
            val left = evaluate(expression.left)
            val right = evaluate(expression.right)
            val result = when (expression.operator) {
                ComparisonOperator.EQ -> left == right
                ComparisonOperator.NEQ -> left != right
                ComparisonOperator.LT -> (left as EffectValue.Number).value < (right as EffectValue.Number).value
                ComparisonOperator.LTE -> (left as EffectValue.Number).value <= (right as EffectValue.Number).value
                ComparisonOperator.GT -> (left as EffectValue.Number).value > (right as EffectValue.Number).value
                ComparisonOperator.GTE -> (left as EffectValue.Number).value >= (right as EffectValue.Number).value
            }
            EffectValue.Boolean(result)
        }
        is EffectExpression.Logic -> {
            val left = boolean(expression.left)
            val result = when (expression.operator) {
                LogicOperator.AND -> left && boolean(expression.right)
                LogicOperator.OR -> left || boolean(expression.right)
            }
            EffectValue.Boolean(result)
        }
        is EffectExpression.Not -> EffectValue.Boolean(!boolean(expression.value))
        is EffectExpression.ColourFromHsv -> EffectValue.Colour(
            EffectColour(
                wrap(number(expression.hue).roundToInt()),
                number(expression.saturation).roundToInt().coerceIn(0, 255),
                number(expression.value).roundToInt().coerceIn(0, 255),
            ),
        )
        is EffectExpression.TargetLiteral -> EffectValue.Target(expression.target)
        is EffectExpression.TargetFromIndex -> {
            val index = number(expression.oneBasedIndex).roundToInt()
            if (index !in 1..7) throw EffectRuntimeException("灯组编号必须为1到7 / グループ番号は1から7です")
            EffectValue.Target(EffectTarget.entries[index])
        }
        is EffectExpression.RuntimeInput -> runtimeSnapshot[expression.key]
        is EffectExpression.Builtin -> evaluateBuiltin(expression)
        is EffectExpression.ListLiteral -> {
            if (expression.elements.size > MAX_LIST_SIZE) {
                throw EffectRuntimeException(
                    "列表不能超过${EffectGeometry.PIXEL_COUNT}项 / " +
                        "リストは${EffectGeometry.PIXEL_COUNT}項目までです",
                )
            }
            val elementType = elementType(expression.type)
            val values = expression.elements.map(::evaluate).toMutableList()
            if (values.any { it.type() != elementType }) {
                throw EffectRuntimeException("列表元素类型错误 / リスト要素の型が一致しません")
            }
            EffectValue.ListValue(elementType, values)
        }
        is EffectExpression.ListGet -> {
            val list = evaluate(expression.list) as? EffectValue.ListValue
                ?: throw EffectRuntimeException("需要列表 / リストが必要です")
            val index = number(expression.index).floorToInt()
            list.values.getOrNull(index)
                ?: throw EffectRuntimeException("列表索引越界 / リストの範囲外です")
        }
        is EffectExpression.FunctionCall -> evaluateFunction(expression)
    }

    private fun evaluateFunction(expression: EffectExpression.FunctionCall): EffectValue {
        val function = compiled.functions[expression.name]
            ?: throw runtime(expression.nodeId, "函数不存在 / 関数が見つかりません")
        val resultExpression = function.returnExpression
            ?: throw runtime(expression.nodeId, "流程函数没有返回值 / 手続き関数に戻り値はありません")
        if (++functionCallDepth > MAX_FUNCTION_CALL_DEPTH) {
            functionCallDepth--
            throw runtime(expression.nodeId, "函数调用超过8层 / 関数呼び出しが8階層を超えました")
        }
        val saved = function.localVariableIds.associateWith { variables[it] }
        return try {
            bindFunctionArguments(function, expression.arguments, expression.nodeId)
            function.operations.forEach { operation ->
                when (operation) {
                    is EffectOp.SetVariable -> variables[operation.id] = evaluate(operation.value)
                    is EffectOp.ChangeVariable -> {
                        val current = variables[operation.id] as? EffectValue.Number
                            ?: throw runtime(operation.blockId, "数值局部变量不存在 / 数値ローカル変数がありません")
                        variables[operation.id] = EffectValue.Number(
                            finite(current.value + number(operation.delta), operation.blockId),
                        )
                    }
                    is EffectOp.SetListItem -> {
                        val list = variables[operation.id] as? EffectValue.ListValue
                            ?: throw runtime(operation.blockId, "列表局部变量不存在 / リスト変数がありません")
                        val index = number(operation.index).floorToInt()
                        if (index !in list.values.indices) {
                            throw runtime(operation.blockId, "列表索引越界 / リストの範囲外です")
                        }
                        list.values[index] = evaluate(operation.value)
                    }
                    else -> throw runtime(
                        operation.blockId,
                        "有返回值函数只能包含局部计算 / 戻り値関数にはローカル計算だけを記述できます",
                    )
                }
            }
            val result = evaluate(resultExpression)
            if (result.type() != function.returnType) {
                throw runtime(expression.nodeId, "函数返回值类型错误 / 関数の戻り値型が一致しません")
            }
            result
        } finally {
            saved.forEach { (id, value) ->
                if (value == null) variables.remove(id) else variables[id] = value
            }
            functionCallDepth--
        }
    }

    private fun bindFunctionArguments(
        function: EffectFunctionDefinition,
        arguments: List<EffectExpression>,
        sourceId: String,
    ) {
        if (arguments.size != function.parameters.size) {
            throw runtime(sourceId, "函数参数数量错误 / 関数の引数数が正しくありません")
        }
        val values = arguments.map(::evaluate)
        function.parameters.zip(values).forEach { (parameter, value) ->
            if (value.type() != parameter.type) {
                throw runtime(sourceId, "函数参数类型错误 / 関数の引数型が一致しません")
            }
            variables[parameter.variableId] = value.deepCopy()
        }
    }

    private fun evaluateBuiltin(expression: EffectExpression.Builtin): EffectValue {
        val id = expression.nodeId.ifBlank { "${expression.function}:${expression.hashCode()}" }
        val function = expression.function
        if (function == BuiltinFunction.RANDOM) {
            val low = number(expression.arguments[0])
            val high = number(expression.arguments[1])
            return EffectValue.Number(EffectMath.lerp(low, high, algorithmState.random.nextDouble()))
        }
        if (function == BuiltinFunction.RANDOM_COLOUR) {
            return EffectValue.Colour(
                EffectColour(
                    (algorithmState.random.nextDouble() * 360.0).toInt().mod(360),
                    (180 + algorithmState.random.nextDouble() * 75.0).toInt().coerceIn(0, 255),
                    (200 + algorithmState.random.nextDouble() * 55.0).toInt().coerceIn(0, 255),
                ),
            )
        }
        if (function in setOf(
                BuiltinFunction.RGB,
                BuiltinFunction.MIX_RGB,
                BuiltinFunction.MIX_HSV,
                BuiltinFunction.COMPLEMENT,
                BuiltinFunction.ROTATE_HUE,
                BuiltinFunction.ADJUST_SATURATION,
                BuiltinFunction.ADJUST_VALUE,
                BuiltinFunction.PALETTE_COLOUR,
            )
        ) {
            return EffectValue.Colour(evaluateColourBuiltin(function, expression.arguments))
        }
        if (function in setOf(
                BuiltinFunction.RED,
                BuiltinFunction.GREEN,
                BuiltinFunction.BLUE,
                BuiltinFunction.HUE,
                BuiltinFunction.SATURATION,
                BuiltinFunction.VALUE,
            )
        ) {
            val colour = colour(expression.arguments[0])
            val value = when (function) {
                BuiltinFunction.HUE -> colour.hue.toDouble()
                BuiltinFunction.SATURATION -> colour.saturation.toDouble()
                BuiltinFunction.VALUE -> colour.value.toDouble()
                else -> {
                    val rgb = EffectMath.hsvToRgb(colour)
                    rgb[when (function) {
                        BuiltinFunction.RED -> 0
                        BuiltinFunction.GREEN -> 1
                        else -> 2
                    }].toDouble()
                }
            }
            return EffectValue.Number(value)
        }
        if (function == BuiltinFunction.LIST_LENGTH) {
            val list = evaluate(expression.arguments[0]) as? EffectValue.ListValue
                ?: throw EffectRuntimeException("需要列表 / リストが必要です")
            return EffectValue.Number(list.values.size.toDouble())
        }
        if (function in setOf(
                BuiltinFunction.MIRROR,
                BuiltinFunction.ROTATE_PATTERN,
                BuiltinFunction.CENTER_SPREAD,
                BuiltinFunction.CENTER_CONTRACT,
            )
        ) {
            return evaluateListPattern(function, expression.arguments)
        }
        if (function == BuiltinFunction.CHASE || function == BuiltinFunction.WAVE_PATTERN) {
            return evaluateGeneratedPattern(function, expression.arguments)
        }
        if (function in setOf(
                BuiltinFunction.SMOOTH,
                BuiltinFunction.HYSTERESIS,
                BuiltinFunction.PEAK_HOLD,
                BuiltinFunction.DEBOUNCE,
                BuiltinFunction.RISING_EDGE,
                BuiltinFunction.FALLING_EDGE,
            )
        ) {
            return evaluateStateful(function, expression.arguments, id)
        }
        val args = expression.arguments.map(::number)
        val value = when (function) {
            BuiltinFunction.RANDOM,
            BuiltinFunction.RANDOM_COLOUR,
            -> error("handled above")
            else -> EffectMath.number(function, args, logicalTimeMs)
        }
        return EffectValue.Number(finite(value))
    }

    private fun evaluateColourBuiltin(
        function: BuiltinFunction,
        arguments: List<EffectExpression>,
    ): EffectColour = when (function) {
        BuiltinFunction.RGB -> EffectMath.rgbToHsv(
            number(arguments[0]).roundToInt(),
            number(arguments[1]).roundToInt(),
            number(arguments[2]).roundToInt(),
        )
        BuiltinFunction.MIX_RGB -> EffectMath.mixRgb(
            colour(arguments[0]), colour(arguments[1]), number(arguments[2]),
        )
        BuiltinFunction.MIX_HSV -> EffectMath.mixHsv(
            colour(arguments[0]), colour(arguments[1]), number(arguments[2]),
        )
        BuiltinFunction.COMPLEMENT -> colour(arguments[0]).let {
            it.copy(hue = wrap(it.hue + 180))
        }
        BuiltinFunction.ROTATE_HUE -> colour(arguments[0]).let {
            it.copy(hue = wrap(it.hue + number(arguments[1]).roundToInt()))
        }
        BuiltinFunction.ADJUST_SATURATION -> colour(arguments[0]).let {
            it.copy(saturation = (it.saturation + number(arguments[1]).roundToInt()).coerceIn(0, 255))
        }
        BuiltinFunction.ADJUST_VALUE -> colour(arguments[0]).let {
            it.copy(value = (it.value + number(arguments[1]).roundToInt()).coerceIn(0, 255))
        }
        BuiltinFunction.PALETTE_COLOUR -> {
            val palette = evaluate(arguments[0]) as? EffectValue.ListValue
                ?: throw EffectRuntimeException("需要颜色列表 / 色リストが必要です")
            if (palette.elementType != EffectValueType.COLOUR || palette.values.isEmpty()) {
                throw EffectRuntimeException("调色板不能为空 / パレットを空にはできません")
            }
            val position = number(arguments[1]).coerceIn(0.0, 1.0) * (palette.values.size - 1)
            val first = floor(position).toInt()
            val second = (first + 1).coerceAtMost(palette.values.lastIndex)
            EffectMath.mixRgb(
                (palette.values[first] as EffectValue.Colour).value,
                (palette.values[second] as EffectValue.Colour).value,
                position - first,
            )
        }
        else -> error("$function is not a colour builtin")
    }

    private fun evaluateListPattern(
        function: BuiltinFunction,
        arguments: List<EffectExpression>,
    ): EffectValue.ListValue {
        val source = evaluate(arguments[0]) as? EffectValue.ListValue
            ?: throw EffectRuntimeException("需要列表 / リストが必要です")
        val values = source.values.toMutableList()
        val result = when (function) {
            BuiltinFunction.MIRROR -> List(values.size) { index ->
                values[min(index, values.lastIndex - index)]
            }
            BuiltinFunction.ROTATE_PATTERN -> {
                if (values.isEmpty()) emptyList() else {
                    val shift = number(arguments[1]).roundToInt().mod(values.size)
                    List(values.size) { values[(it - shift).mod(values.size)] }
                }
            }
            BuiltinFunction.CENTER_SPREAD -> reorderSeven(values, listOf(3, 2, 4, 1, 5, 0, 6))
            BuiltinFunction.CENTER_CONTRACT -> reorderSeven(values, listOf(0, 6, 1, 5, 2, 4, 3))
            else -> values
        }
        return EffectValue.ListValue(source.elementType, result.toMutableList())
    }

    private fun evaluateGeneratedPattern(
        function: BuiltinFunction,
        arguments: List<EffectExpression>,
    ): EffectValue.ListValue {
        val values = when (function) {
            BuiltinFunction.CHASE -> {
                val progress = number(arguments[0]).mod(1.0)
                val active = floor(progress * 7.0).toInt().coerceIn(0, 6)
                MutableList<EffectValue>(7) { EffectValue.Number(if (it == active) 1.0 else 0.0) }
            }
            else -> {
                val progress = number(arguments[0])
                MutableList<EffectValue>(7) { index ->
                    val phase = index / 7.0
                    EffectValue.Number((kotlin.math.sin((progress + phase) * Math.PI * 2.0) + 1.0) / 2.0)
                }
            }
        }
        return EffectValue.ListValue(EffectValueType.NUMBER, values)
    }

    private fun evaluateStateful(
        function: BuiltinFunction,
        arguments: List<EffectExpression>,
        id: String,
    ): EffectValue {
        val input = when (function) {
            BuiltinFunction.DEBOUNCE,
            BuiltinFunction.RISING_EDGE,
            BuiltinFunction.FALLING_EDGE,
            -> boolean(arguments[0]).let { if (it) 1.0 else 0.0 }
            else -> number(arguments[0])
        }
        val previous = algorithmState.numbers[id] ?: input
        val previousTime = algorithmState.timestamps[id] ?: logicalTimeMs
        val delta = (logicalTimeMs - previousTime).coerceAtLeast(0L)
        algorithmState.timestamps[id] = logicalTimeMs
        return when (function) {
            BuiltinFunction.SMOOTH -> {
                val attack = number(arguments[1]).coerceAtLeast(1.0)
                val release = arguments.getOrNull(2)?.let(::number)?.coerceAtLeast(1.0) ?: attack
                val tau = if (input > previous) attack else release
                val alpha = 1.0 - kotlin.math.exp(-delta / tau)
                EffectValue.Number((previous + (input - previous) * alpha).also {
                    algorithmState.numbers[id] = it
                })
            }
            BuiltinFunction.HYSTERESIS -> {
                val low = number(arguments[1])
                val high = number(arguments[2])
                val old = algorithmState.booleans[id] ?: false
                val next = if (old) input > min(low, high) else input >= max(low, high)
                algorithmState.booleans[id] = next
                EffectValue.Boolean(next)
            }
            BuiltinFunction.PEAK_HOLD -> {
                val holdMs = number(arguments[1]).coerceAtLeast(0.0).toLong()
                val decayMs = number(arguments[2]).coerceAtLeast(1.0)
                val peakAt = algorithmState.timestamps["$id:peak"] ?: logicalTimeMs
                val output = if (input >= previous) {
                    algorithmState.timestamps["$id:peak"] = logicalTimeMs
                    input
                } else if (logicalTimeMs - peakAt <= holdMs) {
                    previous
                } else {
                    (previous - delta / decayMs).coerceAtLeast(input)
                }
                algorithmState.numbers[id] = output
                EffectValue.Number(output)
            }
            BuiltinFunction.DEBOUNCE -> {
                val desired = input > 0.5
                val stable = algorithmState.booleans[id] ?: desired
                val changedAt = algorithmState.timestamps["$id:changed"] ?: logicalTimeMs
                if (desired != stable) {
                    if (logicalTimeMs - changedAt >= number(arguments[1]).coerceAtLeast(0.0)) {
                        algorithmState.booleans[id] = desired
                    }
                } else {
                    algorithmState.timestamps["$id:changed"] = logicalTimeMs
                }
                EffectValue.Boolean(algorithmState.booleans[id] ?: desired)
            }
            BuiltinFunction.RISING_EDGE,
            BuiltinFunction.FALLING_EDGE,
            -> {
                val current = input > 0.5
                val old = algorithmState.booleans.put(id, current) ?: current
                EffectValue.Boolean(if (function == BuiltinFunction.RISING_EDGE) !old && current else old && !current)
            }
            else -> error("unsupported stateful function")
        }
    }

    private fun number(expression: EffectExpression) =
        (evaluate(expression) as? EffectValue.Number)?.value
            ?: throw EffectRuntimeException("需要数值 / 数値が必要です")

    private fun boolean(expression: EffectExpression) =
        (evaluate(expression) as? EffectValue.Boolean)?.value
            ?: throw EffectRuntimeException("需要布尔值 / 真偽値が必要です")

    private fun colour(expression: EffectExpression) =
        (evaluate(expression) as? EffectValue.Colour)?.value?.normalised()
            ?: throw EffectRuntimeException("需要颜色 / 色が必要です")

    private fun duration(expression: EffectExpression) =
        number(expression).roundToLong().coerceIn(MIN_DURATION_MS, MAX_DURATION_MS)

    private fun pushSequence(operations: List<EffectOp>) {
        for (index in operations.indices.reversed()) stack.addLast(RuntimeItem.Execute(operations[index]))
    }

    private fun mutate(target: EffectTargetRef, transform: (GroupState) -> GroupState) {
        if (compiled.requiresPixelEffect) {
            resolveTarget(target).forEach { index -> pixels[index] = transform(pixels[index]) }
            syncGroupPreview()
        } else {
            resolveTarget(target).forEach { index -> groups[index] = transform(groups[index]) }
        }
    }

    private fun resolveTarget(target: EffectTargetRef): List<Int> = when (target) {
        EffectTargetRef.All, EffectTargetRef.AllPixels ->
            if (compiled.requiresPixelEffect) pixels.indices.toList() else groups.indices.toList()
        is EffectTargetRef.Group -> {
            val index = number(target.oneBasedIndex).roundToInt()
            if (index !in 1..EffectGeometry.GROUP_COUNT) {
                throw EffectRuntimeException("灯组编号必须为1到7 / グループ番号は1から7です")
            }
            if (compiled.requiresPixelEffect) {
                val start = (index - 1) * EffectGeometry.PIXELS_PER_GROUP
                (start until start + EffectGeometry.PIXELS_PER_GROUP).toList()
            }
            else listOf(index - 1)
        }
        is EffectTargetRef.Pixel -> {
            checkPixelMode()
            val group = number(target.oneBasedGroup).roundToInt()
            val pixel = number(target.oneBasedPixel).roundToInt()
            if (group !in 1..EffectGeometry.GROUP_COUNT ||
                pixel !in 1..EffectGeometry.PIXELS_PER_GROUP
            ) {
                throw EffectRuntimeException("灯组必须为1到7且灯珠必须为1到6 / グループは1～7、ピクセルは1～6です")
            }
            listOf((group - 1) * EffectGeometry.PIXELS_PER_GROUP + pixel - 1)
        }
        is EffectTargetRef.PixelAt -> {
            checkPixelMode()
            val index = number(target.oneBasedIndex).roundToInt()
            if (index !in 1..EffectGeometry.PIXEL_COUNT) {
                throw EffectRuntimeException("全局灯珠编号必须为1到42 / ピクセル番号は1～42です")
            }
            listOf(index - 1)
        }
        is EffectTargetRef.Value -> when (val value = evaluate(target.expression)) {
            is EffectValue.Target -> if (value.value == EffectTarget.ALL) {
                if (compiled.requiresPixelEffect) pixels.indices.toList() else groups.indices.toList()
            } else {
                val group = value.value.ordinal
                if (compiled.requiresPixelEffect) {
                    val start = (group - 1) * EffectGeometry.PIXELS_PER_GROUP
                    (start until start + EffectGeometry.PIXELS_PER_GROUP).toList()
                }
                else listOf(group - 1)
            }
            else -> throw EffectRuntimeException("目标类型错误 / 対象型が一致しません")
        }
    }

    private fun checkPixelMode() {
        if (!compiled.requiresPixelEffect) {
            throw EffectRuntimeException("该目标需要逐灯模式 / この対象にはピクセルモードが必要です")
        }
    }

    private fun syncGroupPreview() {
        repeat(EffectGeometry.GROUP_COUNT) { groupIndex ->
            val source = pixels[groupIndex * EffectGeometry.PIXELS_PER_GROUP]
            groups[groupIndex] = groups[groupIndex].copy(
                hue = source.hue,
                sat = source.sat,
                value = source.value,
                innerMode = 1,
                innerParam = 0,
            )
        }
    }

    private fun toRgb(state: GroupState): EffectRgb {
        val hue = wrap(state.hue).toDouble()
        val saturation = state.sat.coerceIn(0, 255) / 255.0
        val value = state.value.coerceIn(0, 255) / 255.0
        val chroma = value * saturation
        val segment = hue / 60.0
        val x = chroma * (1.0 - kotlin.math.abs(segment % 2.0 - 1.0))
        val (r1, g1, b1) = when (segment.toInt().coerceIn(0, 5)) {
            0 -> Triple(chroma, x, 0.0)
            1 -> Triple(x, chroma, 0.0)
            2 -> Triple(0.0, chroma, x)
            3 -> Triple(0.0, x, chroma)
            4 -> Triple(x, 0.0, chroma)
            else -> Triple(chroma, 0.0, x)
        }
        val m = value - chroma
        return EffectRgb(
            ((r1 + m) * 255.0).roundToInt().coerceIn(0, 255),
            ((g1 + m) * 255.0).roundToInt().coerceIn(0, 255),
            ((b1 + m) * 255.0).roundToInt().coerceIn(0, 255),
        )
    }

    private fun EffectValue.type() = when (this) {
        is EffectValue.Number -> EffectValueType.NUMBER
        is EffectValue.Boolean -> EffectValueType.BOOLEAN
        is EffectValue.Colour -> EffectValueType.COLOUR
        is EffectValue.Target -> EffectValueType.TARGET
        is EffectValue.ListValue -> listType(elementType)
    }

    private fun EffectValue.deepCopy(): EffectValue = when (this) {
        is EffectValue.ListValue -> copy(values = values.map { it.deepCopy() }.toMutableList())
        else -> this
    }

    private fun EffectColour.normalised() = EffectColour(
        wrap(hue), saturation.coerceIn(0, 255), value.coerceIn(0, 255),
    )

    private fun finite(value: Double, blockId: String = ""): Double {
        if (!value.isFinite()) throw runtime(blockId, "数值溢出或无效 / 数値が無効です")
        return value
    }

    private fun runtime(blockId: String, message: String) =
        EffectRuntimeException(if (blockId.isBlank()) message else "[$blockId] $message")

    private fun nextLoopId(blockId: String) = "$blockId:${loopSerial++}"
    private fun wrap(value: Int) = ((value % 360) + 360) % 360
    private fun lerp(start: Int, end: Int, progress: Float) =
        (start + (end - start) * progress).roundToInt().coerceIn(0, 255)

    private companion object {
        const val MAX_ZERO_TIME_INSTRUCTIONS = 1000
        const val MAX_FINITE_ITERATIONS = 1000
        const val MIN_DURATION_MS = 50L
        const val MAX_DURATION_MS = 600_000L
        const val MAX_LIST_SIZE = EffectGeometry.PIXEL_COUNT
        const val MAX_FUNCTION_CALL_DEPTH = 8
    }

    private fun Double.floorToInt() = floor(this).toInt()

    private fun defaultValue(type: EffectValueType): EffectValue = when (type) {
        EffectValueType.NUMBER -> EffectValue.Number(0.0)
        EffectValueType.BOOLEAN -> EffectValue.Boolean(false)
        EffectValueType.COLOUR -> EffectValue.Colour(EffectColour(0, 0, 255))
        EffectValueType.TARGET -> EffectValue.Target(EffectTarget.ALL)
        EffectValueType.NUMBER_LIST -> EffectValue.ListValue(EffectValueType.NUMBER, mutableListOf())
        EffectValueType.BOOLEAN_LIST -> EffectValue.ListValue(EffectValueType.BOOLEAN, mutableListOf())
        EffectValueType.COLOUR_LIST -> EffectValue.ListValue(EffectValueType.COLOUR, mutableListOf())
        EffectValueType.TARGET_LIST -> EffectValue.ListValue(EffectValueType.TARGET, mutableListOf())
    }

    private fun elementType(type: EffectValueType): EffectValueType = when (type) {
        EffectValueType.NUMBER_LIST -> EffectValueType.NUMBER
        EffectValueType.BOOLEAN_LIST -> EffectValueType.BOOLEAN
        EffectValueType.COLOUR_LIST -> EffectValueType.COLOUR
        EffectValueType.TARGET_LIST -> EffectValueType.TARGET
        else -> throw EffectRuntimeException("需要列表类型 / リスト型が必要です")
    }

    private fun listType(elementType: EffectValueType): EffectValueType = when (elementType) {
        EffectValueType.NUMBER -> EffectValueType.NUMBER_LIST
        EffectValueType.BOOLEAN -> EffectValueType.BOOLEAN_LIST
        EffectValueType.COLOUR -> EffectValueType.COLOUR_LIST
        EffectValueType.TARGET -> EffectValueType.TARGET_LIST
        else -> throw EffectRuntimeException("不支持嵌套列表 / ネストしたリストは使用できません")
    }

    private fun reorderSeven(values: List<EffectValue>, order: List<Int>): List<EffectValue> {
        if (values.size != 7) throw EffectRuntimeException("图案需要7项列表 / パターンには7項目のリストが必要です")
        return order.map(values::get)
    }
}
