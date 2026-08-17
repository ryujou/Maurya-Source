package com.example.peacock.feature.effects

import com.example.peacock.feature.runtime.GroupState
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

class EffectScriptCompilerTest {
    private val functionalSamples = listOf(
        "01-常亮频闪与颜色.maurya",
        "02-七组独立颜色.maurya",
        "03-渐变与HSV调节.maurya",
        "04-for彩虹与Hue回绕.maurya",
        "05-变量与if判断.maurya",
        "06-while与break.maurya",
        "07-repeat与continue.maurya",
        "08-运算状态与结束.maurya",
    )

    @Test
    fun nebulaPrismAnimatesAllFortyTwoPixelsIndependently() {
        val compiled = EffectScriptCompiler.compile(BuiltinEffectSources.NEBULA_PRISM)
        val interpreter = EffectInterpreter(compiled, List(7) { GroupState() })
        val first = requireNotNull(interpreter.frameAt(1_234).pixels)
        val second = requireNotNull(interpreter.frameAt(1_284).pixels)

        assertTrue(compiled.requiresPixelEffect)
        assertEquals(42, first.size)
        assertTrue(first.distinct().size >= 30)
        assertTrue(first.zip(second).count { (before, after) -> before != after } >= 35)
    }

    @Test
    fun builtInRainbowRoundTripsToScriptAndKeepsAdvancing() {
        val workspace = """{"blocks":{"languageVersion":0,"blocks":[{
          "type":"maurya_start","id":"start","next":{"block":{
            "type":"maurya_forever","id":"forever","inputs":{"DO":{"block":{
              "type":"maurya_adjust_hsv","id":"adjust",
              "fields":{"TARGET":"ALL","H":2,"S":0,"V":0},
              "next":{"block":{"type":"maurya_wait","id":"wait",
                "fields":{"DURATION":50,"UNIT":"MS"}}}
            }}}
          }}
        }]}}"""
        val source = EffectScriptFormatter.fromCompiled(
            "无限彩虹 代码版",
            EffectCompiler.compile(workspace),
        )
        val compiled = EffectScriptCompiler.compile(source)
        val interpreter = EffectInterpreter(compiled, List(7) { GroupState() })

        assertTrue(source.contains("forever"))
        assertTrue(source.contains("all.adjustHsv(2, 0, 0)"))
        assertTrue(source.contains("wait(50ms)"))
        assertEquals(32, interpreter.frameAt(0).groups.first().hue)
        assertEquals(32, interpreter.frameAt(49).groups.first().hue)
        assertEquals(34, interpreter.frameAt(50).groups.first().hue)
        assertEquals(36, interpreter.frameAt(100).groups.first().hue)
    }

    @Test
    fun reportsZeroDurationTailWithSourceRangeAndSuggestedWait() {
        val source = """
            effect "test" {
                forever {
                    all.mode(STROBE, 128);
                    all.color("#FF0000");
                    wait(2s);
                    all.color("#0000FF");
                }
            }
        """.trimIndent()
        val error = assertThrows(EffectCompileException::class.java) {
            EffectScriptCompiler.compile(source)
        }
        val issue = error.diagnostics.single()
        assertEquals("EFFECT_STATE_NOT_OBSERVABLE", issue.code)
        assertEquals(2_000L, issue.quickFixWaitMs)
        assertTrue(issue.sourceStart!! < issue.sourceEnd!!)
    }

    @Test
    fun redAndBlueRemainVisibleForTwoSecondsAfterFix() {
        val compiled = EffectScriptCompiler.compile(
            """
            effect "test" {
                forever {
                    all.mode(STROBE, 128);
                    all.color("#FF0000");
                    wait(2s);
                    all.color("#0000FF");
                    wait(2s);
                }
            }
            """.trimIndent(),
        )
        val interpreter = EffectInterpreter(
            compiled,
            List(7) { GroupState(innerMode = 1, hue = 0, sat = 255, value = 255) },
        )
        assertEquals(0, interpreter.frameAt(0).groups.first().hue)
        assertEquals(3, interpreter.frameAt(0).groups.first().innerMode)
        assertEquals(0, interpreter.frameAt(1_999).groups.first().hue)
        assertEquals(240, interpreter.frameAt(2_000).groups.first().hue)
        assertEquals(240, interpreter.frameAt(3_999).groups.first().hue)
        assertEquals(0, interpreter.frameAt(4_000).groups.first().hue)
    }

    @Test
    fun compilesVariablesConditionsForAndWhileIntoSharedAst() {
        val source = """
            effect "logic" {
                let hue: number = 0;
                for (i from 0 to 10 step 5) {
                    hue += 5;
                    if (hue >= 10) {
                        all.color(hsv(hue, 255, 255));
                        wait(100ms);
                    } else {
                        all.color("#FF0000");
                        wait(100ms);
                    }
                }
                while (group(1).value < 255) {
                    all.adjustHsv(0, 0, 5);
                    wait(100ms);
                }
            }
        """.trimIndent()
        val compiled = EffectScriptCompiler.compile(source)
        assertEquals(EffectValueType.NUMBER, compiled.variables["hue"])
        assertEquals(EffectValueType.NUMBER, compiled.variables["i"])
        assertTrue(EffectCompiler.canonicalJson(compiled).contains("\"op\":\"for\""))
        assertTrue(EffectCompiler.canonicalJson(compiled).contains("\"op\":\"while\""))
    }

    @Test
    fun exportedProgramIsRecompiledAndHashIsNotTrusted() {
        val now = 1L
        val source = EffectScriptCompiler.template("export")
        val compiled = EffectScriptCompiler.compile(source)
        val program = EffectProgram(
            id = "script-one",
            nameZh = "代码示例",
            nameJa = "コード例",
            workspaceJson = "",
            astJson = EffectCompiler.canonicalJson(compiled),
            astSha256 = compiled.astSha256,
            blockCount = compiled.blockCount,
            estimatedDurationMs = compiled.estimatedDurationMs,
            createdAt = now,
            updatedAt = now,
            editorSchema = 1,
            programSchema = 4,
            sourceKind = EffectSourceKind.SCRIPT,
            scriptSource = source,
        )
        val exported = EffectProgramTransfer.exportSingle(program).replace(compiled.astSha256, "bad-hash")
        val preview = EffectProgramTransfer.preview(exported, setOf("script-one"))
        assertTrue(preview.errors.isEmpty())
        assertEquals(setOf("script-one"), preview.conflictIds)
        assertEquals(compiled.astSha256, preview.programs.single().astSha256)
    }

    @Test
    fun allFunctionalSampleProgramsCompileAndProduceFrames() {
        val initial = List(7) {
            GroupState(innerMode = 1, hue = it * 45, sat = 192, value = 160)
        }
        functionalSamples.forEach { name ->
            val source = loadSample(name)
            val compiled = EffectScriptCompiler.compile(source)
            assertTrue("$name should contain operations", compiled.operations.isNotEmpty())
            val interpreter = EffectInterpreter(compiled, initial)
            assertEquals("$name must keep seven groups", 7, interpreter.frameAt(0).groups.size)
            assertEquals("$name must keep seven groups", 7, interpreter.frameAt(1_000).groups.size)
        }
    }

    @Test
    fun functionalSampleBundleCanBeExportedAndImportedAtomically() {
        val programs = functionalSamples.mapIndexed { index, name ->
            val source = loadSample(name)
            EffectProgramCompiler.normalise(
                EffectProgram(
                    id = "functional-sample-${index + 1}",
                    nameZh = name.substringAfter('-').removeSuffix(".maurya"),
                    nameJa = "機能テスト${index + 1}",
                    workspaceJson = "",
                    astJson = "",
                    astSha256 = "",
                    blockCount = 0,
                    estimatedDurationMs = null,
                    createdAt = index.toLong(),
                    updatedAt = index.toLong(),
                    editorSchema = 1,
                    programSchema = 4,
                    sourceKind = EffectSourceKind.SCRIPT,
                    scriptSource = source,
                ),
            )
        }
        val preview = EffectProgramTransfer.preview(
            EffectProgramTransfer.exportBundle(programs),
            emptySet(),
        )
        assertTrue(preview.errors.isEmpty())
        assertEquals(functionalSamples.size, preview.programs.size)
        assertEquals(programs.map { it.astSha256 }, preview.programs.map { it.astSha256 })
    }

    @Test
    fun algorithmsListsAndDynamicGroupsDriveAllSevenChannels() {
        val compiled = EffectScriptCompiler.compile(
            """
            effect "algorithms" {
                let palette: color[] = ["#FF0000", "#00FF00", "#0000FF"];
                seedRandom(410);
                for (i from 0 to 6 step 1) {
                    group(i + 1).color(
                        mixHsv(
                            palette[i % palette.length],
                            complement(palette[i % palette.length]),
                            smoothstep(0, 1, i / 6)
                        )
                    );
                }
                wait(100ms);
            }
            """.trimIndent(),
        )
        val frame = EffectInterpreter(compiled, List(7) { GroupState() }).frameAt(0)
        assertEquals(7, frame.groups.size)
        assertTrue(frame.groups.map { it.hue }.distinct().size >= 3)
        assertTrue(EffectCompiler.canonicalJson(compiled).contains("setListItem").not())
    }

    @Test
    fun cStyleForLoopSupportsSevenGroupPaletteSyntax() {
        val compiled = EffectScriptCompiler.compile(
            """
            effect "c-style" {
                let palette: color[] = ["#FF0000", "#00FF00", "#0000FF"];
                for (let i = 0; i < 7; i += 1) {
                    group(i + 1).color(palette[i % palette.length]);
                }
                wait(100ms);
            }
            """.trimIndent(),
        )
        val frame = EffectInterpreter(compiled, List(7) { GroupState() }).frameAt(0)
        assertEquals(listOf(0, 120, 240, 0, 120, 240, 0), frame.groups.map { it.hue })
    }

    @Test
    fun sensorAndAudioInputsAreCollectedAndEvaluated() {
        val compiled = EffectScriptCompiler.compile(
            """
            effect "inputs" {
                forever {
                    all.hsv(
                        sensor.heading + audio.bass * 120,
                        255,
                        clamp(audio.level * 255 + sensor.motion * 64, 0, 255)
                    );
                    wait(100ms);
                }
            }
            """.trimIndent(),
        )
        assertEquals(
            setOf(
                RuntimeInputKey.SENSOR_HEADING,
                RuntimeInputKey.SENSOR_MOTION,
                RuntimeInputKey.AUDIO_BASS,
                RuntimeInputKey.AUDIO_LEVEL,
            ),
            compiled.requiredInputs,
        )
        val snapshot = EffectRuntimeSnapshot(
            capturedAtMs = 10,
            values = mapOf(
                RuntimeInputKey.SENSOR_HEADING to EffectValue.Number(90.0),
                RuntimeInputKey.SENSOR_MOTION to EffectValue.Number(0.5),
                RuntimeInputKey.AUDIO_BASS to EffectValue.Number(0.5),
                RuntimeInputKey.AUDIO_LEVEL to EffectValue.Number(0.5),
            ),
        )
        val frame = EffectInterpreter(compiled, List(7) { GroupState() }).frameAt(0, snapshot)
        assertEquals(150, frame.groups.first().hue)
        assertEquals(160, frame.groups.first().value)
    }

    @Test
    fun waveAndNoiseAreDeterministicAndFinite() {
        val source = """
            effect "wave" {
                forever {
                    all.hsv(
                        noise1D(time.cycle(2s) * 8, 17) * 359,
                        255,
                        sineWave(2s, 0.25) * 255
                    );
                    wait(100ms);
                }
            }
        """.trimIndent()
        val first = EffectInterpreter(
            EffectScriptCompiler.compile(source), List(7) { GroupState() },
        ).frameAt(750)
        val second = EffectInterpreter(
            EffectScriptCompiler.compile(source), List(7) { GroupState() },
        ).frameAt(750)
        assertEquals(first.groups, second.groups)
        assertTrue(first.groups.first().hue in 0..359)
        assertTrue(first.groups.first().value in 0..255)
    }

    @Test
    fun declaredVariableMayUseGroupKeywordWithoutBecomingALightTarget() {
        val source = """
            effect "reserved variable" {
                forever {
                    let group: number = 1;
                    group += 1;
                    pixel(group, 1).hsv(group * 30, 255, 255);
                    wait(50ms);
                }
            }
        """.trimIndent()

        val compiled = EffectScriptCompiler.compile(source)
        val frame = EffectInterpreter(compiled, List(7) { GroupState() }).frameAt(0)
        val pixels = requireNotNull(frame.pixels)

        assertTrue(compiled.variables.containsKey("group"))
        assertEquals(42, pixels.size)
        assertTrue(pixels[6].red > 200 && pixels[6].green > 200)
    }

    @Test
    fun longPixelStormScriptCompilesAndProducesFortyTwoPixels() {
        val source = """
            effect "量子星云·超新星风暴" {
                allPixels.color("#000000");
                wait(300ms);
                forever {
                    let t: number = time.elapsedMs / 1000;
                    for (let i = 1; i <= 42; i += 1) {
                        let arm: number = floor((i - 1) / 6);
                        let position: number = (i - 1) % 6;
                        let radius: number = position / 5;
                        let spiral: number =
                            sineWave(2100ms, radius * 1.35 - arm / 7) * 0.65 +
                            sineWave(1300ms, radius * 2.10 + arm / 7) * 0.35;
                        let shockPosition: number = sawWave(3200ms, arm / 25);
                        let shock: number =
                            pow(clamp(1 - abs(radius - shockPosition) * 7, 0, 1), 2);
                        let cloud: number = fbmNoise(t * 0.55 + i * 0.071, 3, 493);
                        let hue: number =
                            (t * 72 + arm * 51 + position * 9 + spiral * 70 +
                                cloud * 48) % 360;
                        let value: number =
                            clamp(22 + cloud * 82 + spiral * 48 + shock * 165, 0, 255);
                        pixelAt(i).hsv(
                            hue,
                            clamp(235 - shock * 100, 125, 255),
                            value
                        );
                    }
                    wait(50ms);
                }
            }
        """.trimIndent()

        val compiled = EffectScriptCompiler.compile(source)
        val frame = EffectInterpreter(compiled, List(7) { GroupState() }).frameAt(600)

        assertEquals(42, frame.pixels?.size)
        assertTrue(frame.pixels.orEmpty().distinct().size > 20)
    }

    @Test
    fun customValueAndFlowFunctionsExecuteWithTypedArguments() {
        val source = """
            fn paletteColor(number index): color {
                let colors: color[] = ["#FF0000", "#00FF00", "#0000FF"];
                return colors[index % colors.length];
            }

            fn pulse(target lamp, color c, number duration) {
                lamp.mode(STROBE, 180);
                lamp.color(c);
                wait(duration);
                lamp.mode(STEADY, 0);
            }

            effect "functions" {
                pulse(group(4), paletteColor(2), 500ms);
                wait(100ms);
            }
        """.trimIndent()
        val compiled = EffectScriptCompiler.compile(source)
        assertEquals(setOf("paletteColor", "pulse"), compiled.functions.keys)
        val frame = EffectInterpreter(compiled, List(7) { GroupState() }).frameAt(250)
        assertEquals(240, frame.groups[3].hue)
        assertEquals(3, frame.groups[3].innerMode)
        val completed = EffectInterpreter(compiled, List(7) { GroupState() }).frameAt(550)
        assertEquals(1, completed.groups[3].innerMode)
    }

    @Test
    fun directFunctionRecursionIsRejected() {
        val source = """
            fn bad(number value): number {
                return bad(value);
            }
            effect "bad" {
                all.color("#FF0000");
                wait(1s);
            }
        """.trimIndent()
        assertThrows(EffectCompileException::class.java) { EffectScriptCompiler.compile(source) }
    }

    @Test
    fun listLiteralRejectsMoreThanFortyTwoItems() {
        val items = List(43) { it.toString() }.joinToString(", ")
        val source = """
            effect "oversized list" {
                let values: number[] = [$items];
                all.hsv(values[0], 255, 255);
                wait(100ms);
            }
        """.trimIndent()

        assertThrows(EffectCompileException::class.java) { EffectScriptCompiler.compile(source) }
    }

    private fun loadSample(name: String): String {
        val loader = requireNotNull(javaClass.classLoader)
        return requireNotNull(
            loader.getResourceAsStream("maurya-script/$name"),
        ) { "missing functional sample: $name" }
            .bufferedReader(Charsets.UTF_8)
            .use { it.readText() }
    }
}
