package com.example.peacock.feature.effects

import com.example.peacock.feature.runtime.GroupState
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.abs

class EffectAlgorithmsTest {
    @Test
    fun waveformsRespectPeriodPhaseAndRange() {
        assertEquals(0.5, EffectMath.number(BuiltinFunction.SINE_WAVE, listOf(1_000.0, 0.0), 0), 1e-9)
        assertEquals(1.0, EffectMath.number(BuiltinFunction.SINE_WAVE, listOf(1_000.0, 0.0), 250), 1e-9)
        assertEquals(0.0, EffectMath.number(BuiltinFunction.TRIANGLE_WAVE, listOf(1_000.0, 0.0), 0), 1e-9)
        assertEquals(0.75, EffectMath.number(BuiltinFunction.SAW_WAVE, listOf(1_000.0, 0.0), 750), 1e-9)
        assertEquals(1.0, EffectMath.number(BuiltinFunction.SQUARE_WAVE, listOf(1_000.0, 0.25, 0.0), 100), 1e-9)
        assertEquals(0.0, EffectMath.number(BuiltinFunction.SQUARE_WAVE, listOf(1_000.0, 0.25, 0.0), 300), 1e-9)
    }

    @Test
    fun interpolationAndColourUseStableEndpoints() {
        assertEquals(10.0, EffectMath.lerp(10.0, 20.0, 0.0), 1e-9)
        assertEquals(20.0, EffectMath.lerp(10.0, 20.0, 1.0), 1e-9)
        assertEquals(0.5, EffectMath.number(BuiltinFunction.SMOOTHSTEP, listOf(0.0, 1.0, 0.5), 0), 1e-9)
        val mixed = EffectMath.mixHsv(
            EffectColour(350, 255, 255),
            EffectColour(10, 255, 255),
            0.5,
        )
        assertTrue(mixed.hue == 0 || mixed.hue == 359)
    }

    @Test
    fun seededRandomAndNoiseAreReproducibleAndContinuous() {
        val first = DeterministicRandom(42)
        val second = DeterministicRandom(42)
        repeat(32) { assertEquals(first.nextDouble(), second.nextDouble(), 0.0) }
        val different = DeterministicRandom(43)
        assertNotEquals(DeterministicRandom(42).nextDouble(), different.nextDouble(), 0.0)
        val a = EffectMath.number(BuiltinFunction.NOISE_1D, listOf(12.0, 7.0), 0)
        val b = EffectMath.number(BuiltinFunction.NOISE_1D, listOf(12.01, 7.0), 0)
        assertTrue(abs(a - b) < 0.1)
        assertTrue(
            EffectMath.number(BuiltinFunction.FBM_NOISE, listOf(4.2, 4.0, 9.0), 0) in 0.0..1.0,
        )
    }

    @Test
    fun sevenGroupPatternsProduceExpectedOrder() {
        val compiled = EffectScriptCompiler.compile(
            """
            effect "patterns" {
                let values: number[] = [0, 1, 2, 3, 4, 5, 6];
                let mirrored: number[] = mirror(values);
                for (i from 0 to 6 step 1) {
                    group(i + 1).hsv(mirrored[i] * 30, 255, 255);
                }
                wait(1s);
            }
            """.trimIndent(),
        )
        val frame = EffectInterpreter(compiled, List(7) { GroupState() }).frameAt(0)
        assertEquals(listOf(0, 30, 60, 90, 60, 30, 0), frame.groups.map { it.hue })
    }

    @Test
    fun runtimeSnapshotTracksPerInputFreshness() {
        val snapshot = EffectRuntimeSnapshot(
            capturedAtMs = 2_000,
            values = mapOf(RuntimeInputKey.SENSOR_LIGHT to EffectValue.Number(100.0)),
            updatedAtMs = mapOf(RuntimeInputKey.SENSOR_LIGHT to 1_500),
        )
        assertTrue(!snapshot.isStale(RuntimeInputKey.SENSOR_LIGHT, 2_000))
        assertTrue(snapshot.isStale(RuntimeInputKey.SENSOR_LIGHT, 2_501))
        assertTrue(snapshot.isStale(RuntimeInputKey.AUDIO_LEVEL, 2_000))
    }

    @Test
    fun blocklyProcedureDefinitionAndCallShareTheRuntimeInterpreter() {
        val compiled = EffectCompiler.compile(
            """
            {
              "blocks":{"languageVersion":0,"blocks":[
                {"type":"maurya_start","id":"start","next":{"block":{
                  "type":"maurya_function_call","id":"call","fields":{"NAME":"paint"},
                  "next":{"block":{"type":"maurya_wait","id":"wait","fields":{"DURATION":1000,"UNIT":"MS"}}}
                }}},
                {"type":"maurya_function_def","id":"def","fields":{"NAME":"paint"},"inputs":{"BODY":{"block":{
                  "type":"maurya_set_color","id":"colour","fields":{"TARGET":"ALL","COLOR":"#1677FF"}
                }}}}
              ]}
            }
            """.trimIndent(),
        )
        val frame = EffectInterpreter(compiled, List(7) { GroupState() }).frameAt(0)
        assertEquals(List(7) { 215 }, frame.groups.map { it.hue })
    }
}
