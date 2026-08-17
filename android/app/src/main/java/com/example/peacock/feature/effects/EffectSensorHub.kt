package com.example.peacock.feature.effects

import android.annotation.SuppressLint
import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.os.SystemClock
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.hypot
import kotlin.math.ln
import kotlin.math.max
import kotlin.math.sin
import kotlin.math.sqrt

class EffectSensorHub(context: Context) : SensorEventListener, EffectInputProvider {
    private val sensorManager = context.getSystemService(SensorManager::class.java)
    private val lock = Any()
    private val values = linkedMapOf<RuntimeInputKey, EffectValue>()
    private val updatedAt = linkedMapOf<RuntimeInputKey, Long>()
    private val supported = linkedSetOf<RuntimeInputKey>()
    private val activeSensorInputs = linkedSetOf<RuntimeInputKey>()
    private val latchedSensorInputs = linkedSetOf<RuntimeInputKey>()
    private val running = AtomicBoolean(false)
    private var audioThread: Thread? = null
    private var audioRecord: AudioRecord? = null
    private var lastMotion = 0.0
    private var lastAudioPeak = 0.0
    private var lastBeatAt = 0L
    private val beatIntervals = ArrayDeque<Long>()
    private val attitudeOffset = mutableMapOf<RuntimeInputKey, Double>()
    @Volatile private var audioSensitivity = 1.0

    init {
        mapOf(
            Sensor.TYPE_ACCELEROMETER to setOf(
                RuntimeInputKey.SENSOR_ACCEL_X, RuntimeInputKey.SENSOR_ACCEL_Y,
                RuntimeInputKey.SENSOR_ACCEL_Z, RuntimeInputKey.SENSOR_MOTION,
                RuntimeInputKey.SENSOR_SHAKE,
            ),
            Sensor.TYPE_GYROSCOPE to setOf(
                RuntimeInputKey.SENSOR_GYRO_X, RuntimeInputKey.SENSOR_GYRO_Y,
                RuntimeInputKey.SENSOR_GYRO_Z,
            ),
            Sensor.TYPE_ROTATION_VECTOR to setOf(
                RuntimeInputKey.SENSOR_PITCH, RuntimeInputKey.SENSOR_ROLL,
                RuntimeInputKey.SENSOR_YAW, RuntimeInputKey.SENSOR_HEADING,
            ),
            Sensor.TYPE_LIGHT to setOf(RuntimeInputKey.SENSOR_LIGHT),
            Sensor.TYPE_PROXIMITY to setOf(RuntimeInputKey.SENSOR_NEAR),
            Sensor.TYPE_PRESSURE to setOf(RuntimeInputKey.SENSOR_PRESSURE),
        ).forEach { (type, keys) ->
            if (sensorManager.getDefaultSensor(type) != null) supported += keys
        }
        supported += AUDIO_KEYS
    }

    fun start(required: Set<RuntimeInputKey>, allowMicrophone: Boolean): Set<RuntimeInputKey> {
        stop()
        running.set(true)
        val sensorKeys = required - AUDIO_KEYS
        register(Sensor.TYPE_ACCELEROMETER, sensorKeys)
        register(Sensor.TYPE_GYROSCOPE, sensorKeys)
        register(Sensor.TYPE_ROTATION_VECTOR, sensorKeys)
        register(Sensor.TYPE_LIGHT, sensorKeys, SensorManager.SENSOR_DELAY_NORMAL)
        register(Sensor.TYPE_PROXIMITY, sensorKeys, SensorManager.SENSOR_DELAY_NORMAL)
        register(Sensor.TYPE_PRESSURE, sensorKeys, SensorManager.SENSOR_DELAY_NORMAL)
        val audioRequired = required.any(AUDIO_KEYS::contains)
        if (audioRequired && allowMicrophone) startAudio()
        return required.filterTo(linkedSetOf()) {
            it !in supported ||
                it in AUDIO_KEYS && (!allowMicrophone || audioThread == null) ||
                it !in AUDIO_KEYS && it !in activeSensorInputs
        }
    }

    fun stop() {
        running.set(false)
        sensorManager.unregisterListener(this)
        audioRecord?.runCatching { stop() }
        audioRecord?.release()
        audioRecord = null
        audioThread?.interrupt()
        audioThread = null
        synchronized(lock) {
            values.clear()
            updatedAt.clear()
            activeSensorInputs.clear()
            latchedSensorInputs.clear()
            beatIntervals.clear()
            lastAudioPeak = 0.0
        }
    }

    fun zeroAttitude() = synchronized(lock) {
        listOf(
            RuntimeInputKey.SENSOR_PITCH,
            RuntimeInputKey.SENSOR_ROLL,
            RuntimeInputKey.SENSOR_YAW,
        ).forEach { key ->
            attitudeOffset[key] = (values[key] as? EffectValue.Number)?.value ?: 0.0
        }
    }

    fun setAudioSensitivity(value: Double) {
        audioSensitivity = value.coerceIn(0.25, 4.0)
    }

    override fun snapshot(): EffectRuntimeSnapshot = synchronized(lock) {
        val now = SystemClock.elapsedRealtime()
        // Light, proximity and pressure sensors are commonly implemented as
        // on-change sensors. A stable environment legitimately produces no
        // callback, so keep the last valid sample fresh while registration is
        // active instead of treating an unchanged value as a dead sensor.
        if (running.get()) {
            latchedSensorInputs.filter(values::containsKey).forEach { updatedAt[it] = now }
        }
        EffectRuntimeSnapshot(
            now,
            values.toMap(),
            availableInputs(),
            updatedAt.toMap(),
        )
    }

    override fun availableInputs(): Set<RuntimeInputKey> = synchronized(lock) { values.keys.toSet() }

    override fun onSensorChanged(event: SensorEvent) {
        if (!running.get()) return
        synchronized(lock) {
            when (event.sensor.type) {
                Sensor.TYPE_ACCELEROMETER -> {
                    val x = event.values[0].toDouble()
                    val y = event.values[1].toDouble()
                    val z = event.values[2].toDouble()
                    val magnitude = sqrt(x * x + y * y + z * z)
                    val motion = (abs(magnitude - SensorManager.GRAVITY_EARTH) / SensorManager.GRAVITY_EARTH)
                        .coerceIn(0.0, 4.0)
                    val shake = (abs(motion - lastMotion) * 2.5).coerceIn(0.0, 1.0)
                    lastMotion = lastMotion * 0.7 + motion * 0.3
                    number(RuntimeInputKey.SENSOR_ACCEL_X, x / SensorManager.GRAVITY_EARTH)
                    number(RuntimeInputKey.SENSOR_ACCEL_Y, y / SensorManager.GRAVITY_EARTH)
                    number(RuntimeInputKey.SENSOR_ACCEL_Z, z / SensorManager.GRAVITY_EARTH)
                    number(RuntimeInputKey.SENSOR_MOTION, motion)
                    number(RuntimeInputKey.SENSOR_SHAKE, shake)
                }
                Sensor.TYPE_GYROSCOPE -> {
                    number(RuntimeInputKey.SENSOR_GYRO_X, event.values[0].toDouble())
                    number(RuntimeInputKey.SENSOR_GYRO_Y, event.values[1].toDouble())
                    number(RuntimeInputKey.SENSOR_GYRO_Z, event.values[2].toDouble())
                }
                Sensor.TYPE_ROTATION_VECTOR -> {
                    val matrix = FloatArray(9)
                    val orientation = FloatArray(3)
                    SensorManager.getRotationMatrixFromVector(matrix, event.values)
                    SensorManager.getOrientation(matrix, orientation)
                    val yaw = Math.toDegrees(orientation[0].toDouble())
                    number(RuntimeInputKey.SENSOR_YAW, yaw - (attitudeOffset[RuntimeInputKey.SENSOR_YAW] ?: 0.0))
                    number(RuntimeInputKey.SENSOR_HEADING, (yaw + 360.0) % 360.0)
                    number(
                        RuntimeInputKey.SENSOR_PITCH,
                        Math.toDegrees(orientation[1].toDouble()) -
                            (attitudeOffset[RuntimeInputKey.SENSOR_PITCH] ?: 0.0),
                    )
                    number(
                        RuntimeInputKey.SENSOR_ROLL,
                        Math.toDegrees(orientation[2].toDouble()) -
                            (attitudeOffset[RuntimeInputKey.SENSOR_ROLL] ?: 0.0),
                    )
                }
                Sensor.TYPE_LIGHT -> number(RuntimeInputKey.SENSOR_LIGHT, event.values[0].toDouble())
                Sensor.TYPE_PROXIMITY -> {
                    values[RuntimeInputKey.SENSOR_NEAR] =
                        EffectValue.Number(if (event.values[0] < event.sensor.maximumRange) 1.0 else 0.0)
                    updatedAt[RuntimeInputKey.SENSOR_NEAR] = SystemClock.elapsedRealtime()
                }
                Sensor.TYPE_PRESSURE -> number(RuntimeInputKey.SENSOR_PRESSURE, event.values[0].toDouble())
            }
        }
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) = Unit

    private fun register(type: Int, required: Set<RuntimeInputKey>, delay: Int = SensorManager.SENSOR_DELAY_GAME) {
        val sensor = sensorManager.getDefaultSensor(type) ?: return
        val requestedKeys = required.intersect(keysForSensor(type))
        if (requestedKeys.isEmpty()) return
        if (sensorManager.registerListener(this, sensor, delay)) {
            synchronized(lock) {
                activeSensorInputs += requestedKeys
                if (type == Sensor.TYPE_LIGHT ||
                    type == Sensor.TYPE_PROXIMITY ||
                    type == Sensor.TYPE_PRESSURE
                ) {
                    latchedSensorInputs += requestedKeys
                }
            }
        }
    }

    private fun keysForSensor(type: Int): Set<RuntimeInputKey> = when (type) {
        Sensor.TYPE_ACCELEROMETER -> setOf(
            RuntimeInputKey.SENSOR_ACCEL_X, RuntimeInputKey.SENSOR_ACCEL_Y,
            RuntimeInputKey.SENSOR_ACCEL_Z, RuntimeInputKey.SENSOR_MOTION, RuntimeInputKey.SENSOR_SHAKE,
        )
        Sensor.TYPE_GYROSCOPE -> setOf(
            RuntimeInputKey.SENSOR_GYRO_X, RuntimeInputKey.SENSOR_GYRO_Y, RuntimeInputKey.SENSOR_GYRO_Z,
        )
        Sensor.TYPE_ROTATION_VECTOR -> setOf(
            RuntimeInputKey.SENSOR_PITCH, RuntimeInputKey.SENSOR_ROLL,
            RuntimeInputKey.SENSOR_YAW, RuntimeInputKey.SENSOR_HEADING,
        )
        Sensor.TYPE_LIGHT -> setOf(RuntimeInputKey.SENSOR_LIGHT)
        Sensor.TYPE_PROXIMITY -> setOf(RuntimeInputKey.SENSOR_NEAR)
        Sensor.TYPE_PRESSURE -> setOf(RuntimeInputKey.SENSOR_PRESSURE)
        else -> emptySet()
    }

    private fun number(key: RuntimeInputKey, value: Double) {
        values[key] = EffectValue.Number(value.takeIf(Double::isFinite) ?: 0.0)
        updatedAt[key] = SystemClock.elapsedRealtime()
    }

    @SuppressLint("MissingPermission")
    private fun startAudio() {
        runCatching {
            val minBuffer = AudioRecord.getMinBufferSize(SAMPLE_RATE, CHANNEL, ENCODING)
            val bufferSize = max(minBuffer, FFT_SIZE * 4)
            val record = AudioRecord(
                MediaRecorder.AudioSource.UNPROCESSED,
                SAMPLE_RATE,
                CHANNEL,
                ENCODING,
                bufferSize,
            )
            check(record.state == AudioRecord.STATE_INITIALIZED)
            record.startRecording()
            audioRecord = record
            audioThread = Thread({ audioLoop(record) }, "MauryaAudioAnalysis").apply {
                priority = Thread.NORM_PRIORITY + 1
                start()
            }
        }
    }

    private fun audioLoop(record: AudioRecord) {
        val pcm = ShortArray(FFT_SIZE)
        while (running.get() && !Thread.currentThread().isInterrupted) {
            var count = 0
            while (count < pcm.size && running.get()) {
                val read = record.read(pcm, count, pcm.size - count, AudioRecord.READ_BLOCKING)
                if (read <= 0) break
                count += read
            }
            if (count == pcm.size) analyseAudio(pcm)
        }
    }

    private fun analyseAudio(pcm: ShortArray) {
        val real = DoubleArray(FFT_SIZE)
        val imaginary = DoubleArray(FFT_SIZE)
        var sum = 0.0
        var peak = 0.0
        for (index in pcm.indices) {
            val sample = pcm[index] / 32768.0
            val window = 0.5 - 0.5 * cos(2.0 * PI * index / (FFT_SIZE - 1))
            real[index] = sample * window
            sum += sample * sample
            peak = max(peak, abs(sample))
        }
        fft(real, imaginary)
        fun band(low: Double, high: Double): Double {
            val from = (low * FFT_SIZE / SAMPLE_RATE).toInt().coerceAtLeast(1)
            val to = (high * FFT_SIZE / SAMPLE_RATE).toInt().coerceAtMost(FFT_SIZE / 2)
            if (from >= to) return 0.0
            var energy = 0.0
            for (bin in from until to) energy += hypot(real[bin], imaginary[bin])
            return (energy / (to - from) / 20.0).coerceIn(0.0, 1.0)
        }
        val sensitivity = audioSensitivity
        val level = (sqrt(sum / pcm.size) * sensitivity).coerceIn(0.0, 1.0)
        peak = (peak * sensitivity).coerceIn(0.0, 1.0)
        val now = SystemClock.elapsedRealtime()
        synchronized(lock) {
            val adaptive = max(0.08, lastAudioPeak * 0.92)
            val beat = peak > adaptive * 1.45 && now - lastBeatAt > 240
            if (beat) {
                if (lastBeatAt > 0) {
                    beatIntervals += now - lastBeatAt
                    while (beatIntervals.size > 8) beatIntervals.removeFirst()
                }
                lastBeatAt = now
            }
            lastAudioPeak = max(peak, adaptive)
            number(RuntimeInputKey.AUDIO_LEVEL, level)
            number(RuntimeInputKey.AUDIO_PEAK, peak)
            number(RuntimeInputKey.AUDIO_BASS, (band(40.0, 250.0) * sensitivity).coerceIn(0.0, 1.0))
            number(RuntimeInputKey.AUDIO_MID, (band(250.0, 2_000.0) * sensitivity).coerceIn(0.0, 1.0))
            number(RuntimeInputKey.AUDIO_TREBLE, (band(2_000.0, 7_500.0) * sensitivity).coerceIn(0.0, 1.0))
            values[RuntimeInputKey.AUDIO_BEAT] = EffectValue.Boolean(beat)
            updatedAt[RuntimeInputKey.AUDIO_BEAT] = now
            val average = beatIntervals.takeIf { it.isNotEmpty() }?.average() ?: 500.0
            number(RuntimeInputKey.AUDIO_BPM, (60_000.0 / average).coerceIn(40.0, 240.0))
        }
    }

    private fun fft(real: DoubleArray, imaginary: DoubleArray) {
        var j = 0
        for (i in 1 until real.size) {
            var bit = real.size shr 1
            while (j and bit != 0) {
                j = j xor bit
                bit = bit shr 1
            }
            j = j xor bit
            if (i < j) {
                real[i] = real[j].also { real[j] = real[i] }
                imaginary[i] = imaginary[j].also { imaginary[j] = imaginary[i] }
            }
        }
        var length = 2
        while (length <= real.size) {
            val angle = -2.0 * PI / length
            val wLengthReal = cos(angle)
            val wLengthImaginary = sin(angle)
            var offset = 0
            while (offset < real.size) {
                var wr = 1.0
                var wi = 0.0
                for (index in 0 until length / 2) {
                    val even = offset + index
                    val odd = even + length / 2
                    val tr = real[odd] * wr - imaginary[odd] * wi
                    val ti = real[odd] * wi + imaginary[odd] * wr
                    real[odd] = real[even] - tr
                    imaginary[odd] = imaginary[even] - ti
                    real[even] += tr
                    imaginary[even] += ti
                    val nextWr = wr * wLengthReal - wi * wLengthImaginary
                    wi = wr * wLengthImaginary + wi * wLengthReal
                    wr = nextWr
                }
                offset += length
            }
            length = length shl 1
        }
    }

    private companion object {
        const val SAMPLE_RATE = 16_000
        const val FFT_SIZE = 512
        const val CHANNEL = AudioFormat.CHANNEL_IN_MONO
        const val ENCODING = AudioFormat.ENCODING_PCM_16BIT
        val AUDIO_KEYS = setOf(
            RuntimeInputKey.AUDIO_LEVEL, RuntimeInputKey.AUDIO_PEAK, RuntimeInputKey.AUDIO_BASS,
            RuntimeInputKey.AUDIO_MID, RuntimeInputKey.AUDIO_TREBLE, RuntimeInputKey.AUDIO_BEAT,
            RuntimeInputKey.AUDIO_BPM,
        )
    }
}
