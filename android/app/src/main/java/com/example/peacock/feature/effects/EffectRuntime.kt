package com.example.peacock.feature.effects

import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.ceil
import kotlin.math.cos
import kotlin.math.exp
import kotlin.math.floor
import kotlin.math.ln
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.round
import kotlin.math.sin
import kotlin.math.sqrt

data class EffectRuntimeSnapshot(
    val capturedAtMs: Long,
    val values: Map<RuntimeInputKey, EffectValue>,
    val available: Set<RuntimeInputKey> = values.keys,
    val updatedAtMs: Map<RuntimeInputKey, Long> = values.keys.associateWith { capturedAtMs },
) {
    operator fun get(key: RuntimeInputKey): EffectValue =
        values[key] ?: if (key == RuntimeInputKey.AUDIO_BEAT) {
            EffectValue.Boolean(false)
        } else {
            EffectValue.Number(0.0)
        }

    fun isStale(key: RuntimeInputKey, nowMs: Long, timeoutMs: Long = 1_000L): Boolean =
        key !in available || nowMs - (updatedAtMs[key] ?: 0L) > timeoutMs

    companion object {
        val EMPTY = EffectRuntimeSnapshot(0L, emptyMap(), emptySet())
    }
}

interface EffectInputProvider {
    fun snapshot(): EffectRuntimeSnapshot
    fun availableInputs(): Set<RuntimeInputKey>
}

internal class EffectAlgorithmState(seed: Long) {
    val random = DeterministicRandom(seed)
    val numbers = mutableMapOf<String, Double>()
    val booleans = mutableMapOf<String, Boolean>()
    val timestamps = mutableMapOf<String, Long>()
}

internal class DeterministicRandom(seed: Long) {
    private var state = if (seed == 0L) 0x6a09e667f3bcc909L else seed

    fun reseed(seed: Long) {
        state = if (seed == 0L) 0x6a09e667f3bcc909L else seed
    }

    fun nextDouble(): Double {
        var value = state
        value = value xor (value shl 13)
        value = value xor (value ushr 7)
        value = value xor (value shl 17)
        state = value
        return ((value ushr 11).toDouble() / (1L shl 53).toDouble()).coerceIn(0.0, 1.0)
    }
}

internal object EffectMath {
    fun number(function: BuiltinFunction, args: List<Double>, elapsedMs: Long): Double = when (function) {
        BuiltinFunction.ABS -> abs(args[0])
        BuiltinFunction.MIN -> min(args[0], args[1])
        BuiltinFunction.MAX -> max(args[0], args[1])
        BuiltinFunction.CLAMP -> args[0].coerceIn(min(args[1], args[2]), max(args[1], args[2]))
        BuiltinFunction.POWER -> args[0].pow(args[1])
        BuiltinFunction.ROUND -> round(args[0])
        BuiltinFunction.FLOOR -> floor(args[0])
        BuiltinFunction.CEIL -> ceil(args[0])
        BuiltinFunction.SQRT -> sqrt(args[0].also {
            if (it < 0.0) throw EffectRuntimeException("sqrt参数不能为负数 / sqrtの引数は0以上です")
        })
        BuiltinFunction.LOG -> ln(args[0].also {
            if (it <= 0.0) throw EffectRuntimeException("log参数必须大于0 / logの引数は0より大きい必要があります")
        })
        BuiltinFunction.SIN -> sin(args[0])
        BuiltinFunction.COS -> cos(args[0])
        BuiltinFunction.RADIANS -> args[0] * PI / 180.0
        BuiltinFunction.DEGREES -> args[0] * 180.0 / PI
        BuiltinFunction.MAP -> {
            val span = args[2] - args[1]
            if (span == 0.0) args[3]
            else args[3] + (args[0] - args[1]) / span * (args[4] - args[3])
        }
        BuiltinFunction.LERP -> lerp(args[0], args[1], args[2])
        BuiltinFunction.SMOOTHSTEP -> {
            val span = args[1] - args[0]
            val t = if (span == 0.0) 0.0 else ((args[2] - args[0]) / span).coerceIn(0.0, 1.0)
            t * t * (3.0 - 2.0 * t)
        }
        BuiltinFunction.SMOOTHERSTEP -> {
            val span = args[1] - args[0]
            val t = if (span == 0.0) 0.0 else ((args[2] - args[0]) / span).coerceIn(0.0, 1.0)
            t * t * t * (t * (t * 6.0 - 15.0) + 10.0)
        }
        BuiltinFunction.EASE_IN -> args[0].coerceIn(0.0, 1.0).pow(2.0)
        BuiltinFunction.EASE_OUT -> 1.0 - (1.0 - args[0].coerceIn(0.0, 1.0)).pow(2.0)
        BuiltinFunction.EASE_IN_OUT -> {
            val t = args[0].coerceIn(0.0, 1.0)
            if (t < 0.5) 4.0 * t * t * t else 1.0 - (-2.0 * t + 2.0).pow(3.0) / 2.0
        }
        BuiltinFunction.SINE_WAVE -> (sin(waveAngle(elapsedMs, args)) + 1.0) / 2.0
        BuiltinFunction.TRIANGLE_WAVE -> {
            val p = waveProgress(elapsedMs, args)
            1.0 - abs(2.0 * p - 1.0)
        }
        BuiltinFunction.SAW_WAVE -> waveProgress(elapsedMs, args)
        BuiltinFunction.SQUARE_WAVE -> {
            val period = positive(args[0], "period")
            val phase = args.getOrElse(2) { 0.0 }
            val p = ((elapsedMs / period + phase) % 1.0 + 1.0) % 1.0
            if (p < args.getOrElse(1) { 0.5 }.coerceIn(0.0, 1.0)) 1.0 else 0.0
        }
        BuiltinFunction.CYCLE -> cycle(elapsedMs, args[0])
        BuiltinFunction.BEAT_PHASE -> cycle(elapsedMs, 60_000.0 / positive(args[0], "BPM"))
        BuiltinFunction.BAR_PHASE -> {
            val beatMs = 60_000.0 / positive(args[0], "BPM")
            val beats = positive(args.getOrElse(1) { 4.0 }, "beatsPerBar")
            val unit = positive(args.getOrElse(2) { 4.0 }, "beatUnit")
            cycle(elapsedMs, beatMs * beats * 4.0 / unit)
        }
        BuiltinFunction.DEADZONE -> {
            val threshold = abs(args[1])
            if (abs(args[0]) <= threshold) 0.0
            else (abs(args[0]) - threshold) / (1.0 - threshold).coerceAtLeast(1e-9) *
                if (args[0] < 0) -1.0 else 1.0
        }
        BuiltinFunction.NOISE_1D -> valueNoise(args[0], args.getOrElse(1) { 0.0 }.toLong())
        BuiltinFunction.FBM_NOISE -> {
            val octaves = args.getOrElse(1) { 3.0 }.toInt().also {
                if (it !in 1..4) throw EffectRuntimeException("噪声层数必须为1到4 / ノイズのオクターブは1～4です")
            }
            val seed = args.getOrElse(2) { 0.0 }.toLong()
            var frequency = 1.0
            var amplitude = 0.5
            var sum = 0.0
            var weight = 0.0
            repeat(octaves) {
                sum += valueNoise(args[0] * frequency, seed + it * 1013L) * amplitude
                weight += amplitude
                frequency *= 2.0
                amplitude *= 0.5
            }
            sum / weight.coerceAtLeast(1e-9)
        }
        else -> error("$function is not a pure numeric builtin")
    }

    fun lerp(start: Double, end: Double, amount: Double): Double =
        start + (end - start) * amount.coerceIn(0.0, 1.0)

    fun mixHsv(first: EffectColour, second: EffectColour, amount: Double): EffectColour {
        val t = amount.coerceIn(0.0, 1.0)
        val hueDelta = ((second.hue - first.hue + 540) % 360) - 180
        return EffectColour(
            wrapHue(first.hue + (hueDelta * t).toInt()),
            lerp(first.saturation.toDouble(), second.saturation.toDouble(), t).toInt().coerceIn(0, 255),
            lerp(first.value.toDouble(), second.value.toDouble(), t).toInt().coerceIn(0, 255),
        )
    }

    fun mixRgb(first: EffectColour, second: EffectColour, amount: Double): EffectColour {
        val a = hsvToRgb(first)
        val b = hsvToRgb(second)
        val t = amount.coerceIn(0.0, 1.0)
        return rgbToHsv(
            lerp(a[0].toDouble(), b[0].toDouble(), t).toInt(),
            lerp(a[1].toDouble(), b[1].toDouble(), t).toInt(),
            lerp(a[2].toDouble(), b[2].toDouble(), t).toInt(),
        )
    }

    fun rgbToHsv(red: Int, green: Int, blue: Int): EffectColour {
        val r = red.coerceIn(0, 255) / 255.0
        val g = green.coerceIn(0, 255) / 255.0
        val b = blue.coerceIn(0, 255) / 255.0
        val high = max(r, max(g, b))
        val low = min(r, min(g, b))
        val delta = high - low
        var hue = when {
            delta == 0.0 -> 0.0
            high == r -> 60.0 * (((g - b) / delta) % 6.0)
            high == g -> 60.0 * ((b - r) / delta + 2.0)
            else -> 60.0 * ((r - g) / delta + 4.0)
        }
        if (hue < 0.0) hue += 360.0
        return EffectColour(
            hue.toInt().mod(360),
            (if (high == 0.0) 0.0 else delta / high * 255.0).toInt().coerceIn(0, 255),
            (high * 255.0).toInt().coerceIn(0, 255),
        )
    }

    fun hsvToRgb(colour: EffectColour): IntArray {
        val hue = wrapHue(colour.hue).toDouble()
        val saturation = colour.saturation.coerceIn(0, 255) / 255.0
        val value = colour.value.coerceIn(0, 255) / 255.0
        val chroma = value * saturation
        val x = chroma * (1 - abs((hue / 60.0) % 2 - 1))
        val offset = value - chroma
        val rgb = when {
            hue < 60 -> doubleArrayOf(chroma, x, 0.0)
            hue < 120 -> doubleArrayOf(x, chroma, 0.0)
            hue < 180 -> doubleArrayOf(0.0, chroma, x)
            hue < 240 -> doubleArrayOf(0.0, x, chroma)
            hue < 300 -> doubleArrayOf(x, 0.0, chroma)
            else -> doubleArrayOf(chroma, 0.0, x)
        }
        return IntArray(3) { ((rgb[it] + offset) * 255.0).toInt().coerceIn(0, 255) }
    }

    private fun waveAngle(elapsedMs: Long, args: List<Double>): Double =
        waveProgress(elapsedMs, args) * PI * 2.0

    private fun waveProgress(elapsedMs: Long, args: List<Double>): Double {
        val period = positive(args[0], "period")
        val phase = args.getOrElse(1) { 0.0 }
        return ((elapsedMs / period + phase) % 1.0 + 1.0) % 1.0
    }

    private fun cycle(elapsedMs: Long, periodMs: Double): Double {
        val period = positive(periodMs, "period")
        return (elapsedMs % period) / period
    }

    private fun valueNoise(x: Double, seed: Long): Double {
        val left = floor(x).toLong()
        val t = x - floor(x)
        val smooth = t * t * (3.0 - 2.0 * t)
        return lerp(hashNoise(left, seed), hashNoise(left + 1, seed), smooth)
    }

    private fun positive(value: Double, name: String): Double {
        if (!value.isFinite() || value <= 0.0) {
            throw EffectRuntimeException("$name 必须大于0 / $name は0より大きい必要があります")
        }
        return value
    }

    private fun hashNoise(index: Long, seed: Long): Double {
        var value = index * -7046029254386353131L + seed * -4658895280553007687L
        value = (value xor (value ushr 30)) * -4658895280553007687L
        value = (value xor (value ushr 27)) * -7723592293110705685L
        value = value xor (value ushr 31)
        return (value ushr 11).toDouble() / (1L shl 53).toDouble()
    }

    fun wrapHue(value: Int): Int = ((value % 360) + 360) % 360
}
