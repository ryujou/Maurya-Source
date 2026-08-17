package com.example.peacock.feature.effects

import com.example.peacock.feature.runtime.GroupState

enum class EffectTarget { ALL, GROUP_1, GROUP_2, GROUP_3, GROUP_4, GROUP_5, GROUP_6, GROUP_7 }
enum class EffectValueType {
    NUMBER,
    BOOLEAN,
    COLOUR,
    TARGET,
    NUMBER_LIST,
    BOOLEAN_LIST,
    COLOUR_LIST,
    TARGET_LIST,
}
enum class EffectGroupProperty { HUE, SATURATION, VALUE, MODE }
enum class ArithmeticOperator { ADD, SUBTRACT, MULTIPLY, DIVIDE, MODULO, POWER, MIN, MAX }
enum class ComparisonOperator { EQ, NEQ, LT, LTE, GT, GTE }
enum class LogicOperator { AND, OR }
enum class EffectSourceKind { BLOCKS, SCRIPT }
enum class RuntimeInputKey {
    SENSOR_ACCEL_X,
    SENSOR_ACCEL_Y,
    SENSOR_ACCEL_Z,
    SENSOR_MOTION,
    SENSOR_SHAKE,
    SENSOR_GYRO_X,
    SENSOR_GYRO_Y,
    SENSOR_GYRO_Z,
    SENSOR_PITCH,
    SENSOR_ROLL,
    SENSOR_YAW,
    SENSOR_LIGHT,
    SENSOR_NEAR,
    SENSOR_HEADING,
    SENSOR_PRESSURE,
    AUDIO_LEVEL,
    AUDIO_PEAK,
    AUDIO_BASS,
    AUDIO_MID,
    AUDIO_TREBLE,
    AUDIO_BEAT,
    AUDIO_BPM,
}

enum class BuiltinFunction {
    ABS,
    MIN,
    MAX,
    CLAMP,
    POWER,
    ROUND,
    FLOOR,
    CEIL,
    SQRT,
    LOG,
    SIN,
    COS,
    RADIANS,
    DEGREES,
    MAP,
    LERP,
    SMOOTHSTEP,
    SMOOTHERSTEP,
    EASE_IN,
    EASE_OUT,
    EASE_IN_OUT,
    SINE_WAVE,
    TRIANGLE_WAVE,
    SAW_WAVE,
    SQUARE_WAVE,
    RANDOM,
    NOISE_1D,
    FBM_NOISE,
    SMOOTH,
    DEADZONE,
    HYSTERESIS,
    PEAK_HOLD,
    DEBOUNCE,
    RISING_EDGE,
    FALLING_EDGE,
    RGB,
    RED,
    GREEN,
    BLUE,
    HUE,
    SATURATION,
    VALUE,
    MIX_RGB,
    MIX_HSV,
    COMPLEMENT,
    ROTATE_HUE,
    ADJUST_SATURATION,
    ADJUST_VALUE,
    PALETTE_COLOUR,
    RANDOM_COLOUR,
    CYCLE,
    BEAT_PHASE,
    BAR_PHASE,
    LIST_LENGTH,
    MIRROR,
    ROTATE_PATTERN,
    CENTER_SPREAD,
    CENTER_CONTRACT,
    CHASE,
    WAVE_PATTERN,
}

data class EffectCompileIssue(
    val code: String,
    val messageZh: String,
    val messageJa: String,
    val sourceId: String = "",
    val quickFixWaitMs: Long? = null,
    val sourceStart: Int? = null,
    val sourceEnd: Int? = null,
) {
    val combinedMessage: String get() = "$messageZh / $messageJa"
}

data class EffectColour(val hue: Int, val saturation: Int, val value: Int)

sealed interface EffectValue {
    data class Number(val value: Double) : EffectValue
    data class Boolean(val value: kotlin.Boolean) : EffectValue
    data class Colour(val value: EffectColour) : EffectValue
    data class Target(val value: EffectTarget) : EffectValue
    data class ListValue(
        val elementType: EffectValueType,
        val values: MutableList<EffectValue>,
    ) : EffectValue
}

sealed interface EffectTargetRef {
    data object All : EffectTargetRef
    data object AllPixels : EffectTargetRef
    data class Group(val oneBasedIndex: EffectExpression) : EffectTargetRef
    data class Pixel(
        val oneBasedGroup: EffectExpression,
        val oneBasedPixel: EffectExpression,
    ) : EffectTargetRef
    data class PixelAt(val oneBasedIndex: EffectExpression) : EffectTargetRef
    data class Value(val expression: EffectExpression) : EffectTargetRef

    companion object {
        fun static(target: EffectTarget): EffectTargetRef =
            if (target == EffectTarget.ALL) All
            else Group(EffectExpression.NumberLiteral(target.ordinal.toDouble()))
    }
}

sealed interface EffectExpression {
    val type: EffectValueType

    data class NumberLiteral(val value: Double) : EffectExpression {
        override val type = EffectValueType.NUMBER
    }

    data class BooleanLiteral(val value: Boolean) : EffectExpression {
        override val type = EffectValueType.BOOLEAN
    }

    data class ColourLiteral(val value: EffectColour) : EffectExpression {
        override val type = EffectValueType.COLOUR
    }

    data class Variable(val id: String, override val type: EffectValueType) : EffectExpression
    data object ElapsedMs : EffectExpression {
        override val type = EffectValueType.NUMBER
    }

    data class GroupValue(
        val group: Int,
        val property: EffectGroupProperty,
    ) : EffectExpression {
        override val type = EffectValueType.NUMBER
    }

    data class DynamicGroupValue(
        val oneBasedIndex: EffectExpression,
        val property: EffectGroupProperty,
    ) : EffectExpression {
        override val type = EffectValueType.NUMBER
    }

    data class Arithmetic(
        val operator: ArithmeticOperator,
        val left: EffectExpression,
        val right: EffectExpression,
    ) : EffectExpression {
        override val type = EffectValueType.NUMBER
    }

    data class Clamp(
        val value: EffectExpression,
        val low: EffectExpression,
        val high: EffectExpression,
    ) : EffectExpression {
        override val type = EffectValueType.NUMBER
    }

    data class Comparison(
        val operator: ComparisonOperator,
        val left: EffectExpression,
        val right: EffectExpression,
    ) : EffectExpression {
        override val type = EffectValueType.BOOLEAN
    }

    data class Logic(
        val operator: LogicOperator,
        val left: EffectExpression,
        val right: EffectExpression,
    ) : EffectExpression {
        override val type = EffectValueType.BOOLEAN
    }

    data class Not(val value: EffectExpression) : EffectExpression {
        override val type = EffectValueType.BOOLEAN
    }

    data class ColourFromHsv(
        val hue: EffectExpression,
        val saturation: EffectExpression,
        val value: EffectExpression,
    ) : EffectExpression {
        override val type = EffectValueType.COLOUR
    }

    data class TargetLiteral(val target: EffectTarget) : EffectExpression {
        override val type = EffectValueType.TARGET
    }

    data class TargetFromIndex(val oneBasedIndex: EffectExpression) : EffectExpression {
        override val type = EffectValueType.TARGET
    }

    data class RuntimeInput(
        val key: RuntimeInputKey,
        override val type: EffectValueType =
            if (key == RuntimeInputKey.AUDIO_BEAT) EffectValueType.BOOLEAN else EffectValueType.NUMBER,
    ) : EffectExpression

    data class Builtin(
        val function: BuiltinFunction,
        val arguments: List<EffectExpression>,
        override val type: EffectValueType,
        val nodeId: String = "",
    ) : EffectExpression

    data class ListLiteral(
        val elements: List<EffectExpression>,
        override val type: EffectValueType,
    ) : EffectExpression

    data class ListGet(
        val list: EffectExpression,
        val index: EffectExpression,
        override val type: EffectValueType,
    ) : EffectExpression

    data class FunctionCall(
        val name: String,
        val arguments: List<EffectExpression>,
        override val type: EffectValueType,
        val nodeId: String = "",
    ) : EffectExpression
}

data class EffectFunctionParameter(
    val name: String,
    val variableId: String,
    val type: EffectValueType,
)

data class EffectFunctionDefinition(
    val name: String,
    val parameters: List<EffectFunctionParameter>,
    val returnType: EffectValueType?,
    val operations: List<EffectOp>,
    val returnExpression: EffectExpression? = null,
    val localVariableIds: Set<String> = emptySet(),
)

sealed interface EffectOp {
    val blockId: String

    data class SetHsv(
        val target: EffectTargetRef,
        val h: EffectExpression,
        val s: EffectExpression,
        val v: EffectExpression,
        override val blockId: String = "",
    ) : EffectOp {
        constructor(target: EffectTarget, h: Int, s: Int, v: Int, blockId: String = "") :
            this(EffectTargetRef.static(target), EffectExpression.NumberLiteral(h.toDouble()),
                EffectExpression.NumberLiteral(s.toDouble()), EffectExpression.NumberLiteral(v.toDouble()), blockId)
        constructor(
            target: EffectTarget,
            h: EffectExpression,
            s: EffectExpression,
            v: EffectExpression,
            blockId: String = "",
        ) : this(EffectTargetRef.static(target), h, s, v, blockId)
    }

    data class SetColour(
        val target: EffectTargetRef,
        val colour: EffectExpression,
        override val blockId: String = "",
    ) : EffectOp {
        constructor(target: EffectTarget, colour: EffectExpression, blockId: String = "") :
            this(EffectTargetRef.static(target), colour, blockId)
    }

    data class FadeHsv(
        val target: EffectTargetRef,
        val h: EffectExpression,
        val s: EffectExpression,
        val v: EffectExpression,
        val durationMs: EffectExpression,
        override val blockId: String = "",
    ) : EffectOp {
        constructor(target: EffectTarget, h: Int, s: Int, v: Int, durationMs: Long, blockId: String = "") :
            this(EffectTargetRef.static(target), EffectExpression.NumberLiteral(h.toDouble()), EffectExpression.NumberLiteral(s.toDouble()),
                EffectExpression.NumberLiteral(v.toDouble()), EffectExpression.NumberLiteral(durationMs.toDouble()), blockId)
        constructor(
            target: EffectTarget,
            h: EffectExpression,
            s: EffectExpression,
            v: EffectExpression,
            durationMs: EffectExpression,
            blockId: String = "",
        ) : this(EffectTargetRef.static(target), h, s, v, durationMs, blockId)
    }

    data class FadeColour(
        val target: EffectTargetRef,
        val colour: EffectExpression,
        val durationMs: EffectExpression,
        override val blockId: String = "",
    ) : EffectOp {
        constructor(
            target: EffectTarget,
            colour: EffectExpression,
            durationMs: EffectExpression,
            blockId: String = "",
        ) : this(EffectTargetRef.static(target), colour, durationMs, blockId)
    }

    data class AdjustHsv(
        val target: EffectTargetRef,
        val dh: EffectExpression,
        val ds: EffectExpression,
        val dv: EffectExpression,
        override val blockId: String = "",
    ) : EffectOp {
        constructor(target: EffectTarget, dh: Int, ds: Int, dv: Int, blockId: String = "") :
            this(EffectTargetRef.static(target), EffectExpression.NumberLiteral(dh.toDouble()),
                EffectExpression.NumberLiteral(ds.toDouble()), EffectExpression.NumberLiteral(dv.toDouble()), blockId)
        constructor(
            target: EffectTarget,
            dh: EffectExpression,
            ds: EffectExpression,
            dv: EffectExpression,
            blockId: String = "",
        ) : this(EffectTargetRef.static(target), dh, ds, dv, blockId)
    }

    data class SetMode(
        val target: EffectTargetRef,
        val mode: EffectExpression,
        val param: EffectExpression,
        override val blockId: String = "",
    ) : EffectOp {
        constructor(target: EffectTarget, mode: Int, param: Int, blockId: String = "") :
            this(EffectTargetRef.static(target), EffectExpression.NumberLiteral(mode.toDouble()),
                EffectExpression.NumberLiteral(param.toDouble()), blockId)
        constructor(
            target: EffectTarget,
            mode: EffectExpression,
            param: EffectExpression,
            blockId: String = "",
        ) : this(EffectTargetRef.static(target), mode, param, blockId)
    }

    data class Wait(
        val durationMs: EffectExpression,
        override val blockId: String = "",
    ) : EffectOp {
        constructor(durationMs: Long, blockId: String = "") :
            this(EffectExpression.NumberLiteral(durationMs.toDouble()), blockId)
    }

    data class SetVariable(
        val id: String,
        val value: EffectExpression,
        override val blockId: String = "",
    ) : EffectOp

    data class ChangeVariable(
        val id: String,
        val delta: EffectExpression,
        override val blockId: String = "",
    ) : EffectOp

    data class SetListItem(
        val id: String,
        val index: EffectExpression,
        val value: EffectExpression,
        override val blockId: String = "",
    ) : EffectOp

    data class SeedRandom(
        val seed: EffectExpression,
        override val blockId: String = "",
    ) : EffectOp

    data class CallFunction(
        val name: String,
        val arguments: List<EffectExpression>,
        override val blockId: String = "",
    ) : EffectOp

    data class If(
        val condition: EffectExpression,
        val thenBody: List<EffectOp>,
        val elseBody: List<EffectOp>,
        override val blockId: String = "",
    ) : EffectOp

    data class Repeat(
        val count: EffectExpression?,
        val body: List<EffectOp>,
        override val blockId: String = "",
    ) : EffectOp

    data class For(
        val variableId: String,
        val from: EffectExpression,
        val to: EffectExpression,
        val step: EffectExpression,
        val body: List<EffectOp>,
        override val blockId: String = "",
    ) : EffectOp

    data class While(
        val condition: EffectExpression,
        val body: List<EffectOp>,
        override val blockId: String = "",
    ) : EffectOp

    data class Break(override val blockId: String = "") : EffectOp
    data class Continue(override val blockId: String = "") : EffectOp
    data class End(override val blockId: String = "") : EffectOp
}

data class CompiledEffect(
    val operations: List<EffectOp>,
    val blockCount: Int,
    val estimatedDurationMs: Long?,
    val astSha256: String,
    val variables: Map<String, EffectValueType> = emptyMap(),
    val requiredInputs: Set<RuntimeInputKey> = emptySet(),
    val randomSeed: Long = 0L,
    val functions: Map<String, EffectFunctionDefinition> = emptyMap(),
    val requiresPixelEffect: Boolean = false,
)

data class EffectProgram(
    val id: String,
    val nameZh: String,
    val nameJa: String,
    val workspaceJson: String,
    val astJson: String,
    val astSha256: String,
    val blockCount: Int,
    val estimatedDurationMs: Long?,
    val createdAt: Long,
    val updatedAt: Long,
    val editorSchema: Int = EffectProgramSchemas.EDITOR,
    val programSchema: Int = EffectProgramSchemas.PROGRAM,
    val sourceKind: EffectSourceKind = EffectSourceKind.BLOCKS,
    val scriptSource: String = "",
)

data class EffectFrame(
    val groups: List<GroupState>,
    val pixels: List<EffectRgb>? = null,
    val finished: Boolean,
    val waiting: Boolean,
    val progress: Float?,
)

data class EffectRgb(val red: Int, val green: Int, val blue: Int) {
    init {
        require(red in 0..255 && green in 0..255 && blue in 0..255)
    }
}
object EffectProgramSchemas {
    const val EDITOR = 4
    const val PROGRAM = 6
}
