package com.example.peacock.feature.effects

import android.Manifest
import android.os.SystemClock
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.rule.GrantPermissionRule
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class EffectSensorHubInstrumentedTest {
    @get:Rule
    val microphonePermission: GrantPermissionRule =
        GrantPermissionRule.grant(Manifest.permission.RECORD_AUDIO)

    @Test
    fun physicalSensorsEmitFreshFiniteValues() {
        val required = setOf(
            RuntimeInputKey.SENSOR_ACCEL_X,
            RuntimeInputKey.SENSOR_ACCEL_Y,
            RuntimeInputKey.SENSOR_ACCEL_Z,
            RuntimeInputKey.SENSOR_MOTION,
            RuntimeInputKey.SENSOR_SHAKE,
            RuntimeInputKey.SENSOR_GYRO_X,
            RuntimeInputKey.SENSOR_GYRO_Y,
            RuntimeInputKey.SENSOR_GYRO_Z,
            RuntimeInputKey.SENSOR_PITCH,
            RuntimeInputKey.SENSOR_ROLL,
            RuntimeInputKey.SENSOR_YAW,
            RuntimeInputKey.SENSOR_HEADING,
            RuntimeInputKey.SENSOR_LIGHT,
            RuntimeInputKey.SENSOR_NEAR,
        )
        val hub = EffectSensorHub(ApplicationProvider.getApplicationContext())
        try {
            assertEquals(emptySet<RuntimeInputKey>(), hub.start(required, allowMicrophone = false))
            SystemClock.sleep(2_000)
            val snapshot = hub.snapshot()
            assertTrue(snapshot.available.containsAll(required))
            required.forEach { key ->
                assertTrue("$key is stale", !snapshot.isStale(key, SystemClock.elapsedRealtime()))
                when (val value = snapshot.values[key]) {
                    is EffectValue.Number ->
                        assertTrue("$key is not finite", value.value.isFinite())
                    is EffectValue.Boolean ->
                        assertTrue("$key is present", key == RuntimeInputKey.AUDIO_BEAT)
                    else -> assertTrue("$key is missing", false)
                }
            }
        } finally {
            hub.stop()
        }
    }

    @Test
    fun microphoneAnalyzerEmitsFreshFiniteBands() {
        val required = setOf(
            RuntimeInputKey.AUDIO_LEVEL,
            RuntimeInputKey.AUDIO_PEAK,
            RuntimeInputKey.AUDIO_BASS,
            RuntimeInputKey.AUDIO_MID,
            RuntimeInputKey.AUDIO_TREBLE,
            RuntimeInputKey.AUDIO_BEAT,
            RuntimeInputKey.AUDIO_BPM,
        )
        val hub = EffectSensorHub(ApplicationProvider.getApplicationContext())
        try {
            assertEquals(emptySet<RuntimeInputKey>(), hub.start(required, allowMicrophone = true))
            SystemClock.sleep(2_500)
            val snapshot = hub.snapshot()
            assertTrue(snapshot.available.containsAll(required))
            required.forEach { key ->
                assertTrue("$key is stale", !snapshot.isStale(key, SystemClock.elapsedRealtime()))
                when (val value = snapshot.values[key]) {
                    is EffectValue.Number ->
                        assertTrue("$key is not finite", value.value.isFinite())
                    is EffectValue.Boolean ->
                        assertTrue("$key is present", key == RuntimeInputKey.AUDIO_BEAT)
                    else -> assertTrue("$key is missing", false)
                }
            }
        } finally {
            hub.stop()
        }
    }
}
