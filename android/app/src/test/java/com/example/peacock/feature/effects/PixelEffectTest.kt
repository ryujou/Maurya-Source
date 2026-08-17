package com.example.peacock.feature.effects

import com.example.peacock.feature.runtime.GroupState
import com.example.peacock.protocol.ModbusCodec
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class PixelEffectTest {
    @Test
    fun pixelFrameIsExactly140BytesAndUsesGroupMajorRgbOrder() {
        val pixels = List(42) { index ->
            EffectRgb(index, 255 - index, (index * 3) and 0xff)
        }

        val frame = EffectProtocol.pixelFrameRequest(
            address = 1,
            sessionId = 0x78563412,
            sequence = 0x9abc,
            pixels = pixels,
        )

        assertEquals(140, frame.size)
        assertEquals(1, frame[0].toInt() and 0xff)
        assertEquals(0x41, frame[1].toInt() and 0xff)
        assertEquals(135, frame[2].toInt() and 0xff)
        assertEquals(0x24, frame[3].toInt() and 0xff)
        assertEquals(1, frame[10].toInt() and 0xff)
        assertEquals(42, frame[11].toInt() and 0xff)
        assertEquals(0, frame[12].toInt() and 0xff)
        assertEquals(255, frame[13].toInt() and 0xff)
        assertEquals(0, frame[14].toInt() and 0xff)
        val last = 12 + 41 * 3
        assertEquals(41, frame[last].toInt() and 0xff)
        assertEquals(214, frame[last + 1].toInt() and 0xff)
        assertEquals(123, frame[last + 2].toInt() and 0xff)
        assertTrue(ModbusCodec.validateCrc(frame))
    }

    @Test
    fun oldGroupFrameFormatIsUnchanged() {
        val frame = EffectProtocol.frameRequest(1, 7, 9, List(7) { GroupState() })
        assertEquals(54, frame.size)
        assertEquals(49, frame[2].toInt() and 0xff)
        assertEquals(0x21, frame[3].toInt() and 0xff)
        assertTrue(ModbusCodec.validateCrc(frame))
    }

    @Test
    fun scriptPixelTargetSelectsPixelProtocolAndMapsGroupThenPixel() {
        val compiled = EffectScriptCompiler.compile(
            """
            effect "pixel" {
                all.color("#000000");
                pixel(2, 3).color("#FF0000");
                pixelAt(42).color("#0000FF");
                wait(100ms);
            }
            """.trimIndent(),
        )
        assertTrue(compiled.requiresPixelEffect)

        val frame = EffectInterpreter(compiled, List(7) { GroupState() }).frameAt(0)
        val pixels = requireNotNull(frame.pixels)
        assertEquals(42, pixels.size)
        assertEquals(EffectRgb(255, 0, 0), pixels[8])
        assertEquals(EffectRgb(0, 0, 255), pixels[41])
        assertEquals(EffectRgb(0, 0, 0), pixels[0])
    }

    @Test
    fun ordinaryGroupScriptStillUsesLegacyMode() {
        val compiled = EffectScriptCompiler.compile(
            """
            effect "group" {
                group(2).color("#FF0000");
                wait(100ms);
            }
            """.trimIndent(),
        )
        assertFalse(compiled.requiresPixelEffect)
        assertEquals(null, EffectInterpreter(compiled, List(7) { GroupState() }).frameAt(0).pixels)
    }

    @Test
    fun pixelProgramRejectsHardwareMode() {
        val result = runCatching {
            EffectScriptCompiler.compile(
                """
                effect "invalid" {
                    pixelAt(1).color("#FFFFFF");
                    all.mode(STROBE, 128);
                    wait(100ms);
                }
                """.trimIndent(),
            )
        }
        assertTrue(result.exceptionOrNull() is EffectCompileException)
    }

    @Test
    fun blockPixelTargetUsesGroupMajorIndexing() {
        val json = """
            {"blocks":{"languageVersion":0,"blocks":[{
              "type":"maurya_start","id":"start","next":{"block":{
                "type":"maurya_set_pixel_color_value","id":"pixel",
                "inputs":{
                  "GROUP":{"shadow":{"type":"math_number","fields":{"NUM":7}}},
                  "PIXEL":{"shadow":{"type":"math_number","fields":{"NUM":6}}},
                  "COLOR":{"shadow":{"type":"maurya_colour_literal","fields":{"COLOR":"#39C5BB"}}}
                },
                "next":{"block":{"type":"maurya_wait","id":"wait",
                  "fields":{"DURATION":100,"UNIT":"MS"}}}
              }}
            }]}}
        """.trimIndent()

        val compiled = EffectCompiler.compile(json)
        assertTrue(compiled.requiresPixelEffect)
        val pixels = requireNotNull(
            EffectInterpreter(compiled, List(7) { GroupState() }).frameAt(0).pixels,
        )
        // The interpreter deliberately stores HSV, so RGB round-tripping follows
        // the same integer conversion used by the physical playback path.
        assertEquals(EffectRgb(57, 197, 185), pixels[41])
    }

    @Test
    fun allAndGroupTargetsExpandToPixelsOnlyInsidePixelProgram() {
        val compiled = EffectScriptCompiler.compile(
            """
            effect "expanded" {
                all.color("#010203");
                group(4).color("#AABBCC");
                pixelAt(1).color("#FFFFFF");
                wait(100ms);
            }
            """.trimIndent(),
        )

        val pixels = requireNotNull(
            EffectInterpreter(compiled, List(7) { GroupState() }).frameAt(0).pixels,
        )
        assertEquals(EffectRgb(255, 255, 255), pixels[0])
        assertEquals(EffectRgb(1, 2, 3), pixels[17])
        assertEquals(EffectRgb(170, 187, 204), pixels[18])
        assertEquals(EffectRgb(170, 187, 204), pixels[23])
        assertEquals(EffectRgb(1, 2, 3), pixels[24])
    }

    @Test
    fun constantPixelCoordinatesAreRejectedBeforePlayback() {
        val invalidGroup = runCatching {
            EffectScriptCompiler.compile(
                """effect "bad" { pixel(8, 1).color("#FFFFFF"); wait(100ms); }""",
            )
        }
        val invalidGlobal = runCatching {
            EffectScriptCompiler.compile(
                """effect "bad" { pixelAt(43).color("#FFFFFF"); wait(100ms); }""",
            )
        }
        val invalidPixelInGroup = runCatching {
            EffectScriptCompiler.compile(
                """effect "bad" { pixel(1, 7).color("#FFFFFF"); wait(100ms); }""",
            )
        }

        assertTrue(invalidGroup.exceptionOrNull() is EffectCompileException)
        assertTrue(invalidGlobal.exceptionOrNull() is EffectCompileException)
        assertTrue(invalidPixelInGroup.exceptionOrNull() is EffectCompileException)
    }

    @Test
    fun dynamicPixelChaseCanAddressAllFortyTwoPixels() {
        val compiled = EffectScriptCompiler.compile(
            """
            effect "42 pixel mapping" {
                allPixels.color("#000000");
                for (let index = 1; index <= 42; index += 1) {
                    pixelAt(index).color("#FFFFFF");
                    wait(50ms);
                    pixelAt(index).color("#000000");
                }
                wait(50ms);
            }
            """.trimIndent(),
        )

        assertTrue(compiled.requiresPixelEffect)
        val first = requireNotNull(
            EffectInterpreter(compiled, List(7) { GroupState() }).frameAt(0).pixels,
        )
        assertEquals(42, first.size)
        assertEquals(EffectRgb(255, 255, 255), first[0])
        assertEquals(EffectRgb(0, 0, 0), first[1])
    }

    @Test
    fun allPixelsHsvCreatesFortyTwoPixelFrame() {
        val compiled = EffectScriptCompiler.compile(
            """
            effect "all pixels" {
                allPixels.hsv(210, 255, 255);
                wait(100ms);
            }
            """.trimIndent(),
        )

        val pixels = requireNotNull(
            EffectInterpreter(compiled, List(7) { GroupState() }).frameAt(0).pixels,
        )
        assertEquals(42, pixels.size)
        assertTrue(pixels.all { it == EffectRgb(0, 128, 255) })
    }

    @Test
    fun nestedLoopPixelRainbowCompilesAndProducesDistinctPixels() {
        val compiled = EffectScriptCompiler.compile(
            """
            effect "pixel rainbow" {
                forever {
                    for (let offset = 0; offset < 360; offset += 6) {
                        for (let index = 1; index <= 42; index += 1) {
                            pixelAt(index).hsv(offset + (index - 1) * 13, 255, 255);
                        }
                        wait(50ms);
                    }
                }
            }
            """.trimIndent(),
        )

        assertTrue(compiled.requiresPixelEffect)
        val pixels = requireNotNull(
            EffectInterpreter(compiled, List(7) { GroupState() }).frameAt(0).pixels,
        )
        assertEquals(42, pixels.size)
        assertTrue(pixels.distinct().size > 20)
    }

    @Test
    fun blockColourListCyclesAcrossAllFortyTwoPixels() {
        val colours = (1..7).joinToString(",") { index ->
            """"C$index":{"shadow":{"type":"maurya_colour_literal","fields":{"COLOR":"#${index}00000"}}}"""
        }
        val json = """
            {"blocks":{"languageVersion":0,"blocks":[{
              "type":"maurya_start","id":"start","next":{"block":{
                "type":"maurya_apply_pixel_colour_list","id":"list",
                "inputs":{"LIST":{"block":{"type":"maurya_colour_list7","inputs":{$colours}}}},
                "next":{"block":{"type":"maurya_wait","id":"wait",
                  "fields":{"DURATION":100,"UNIT":"MS"}}}
              }}
            }]}}
        """.trimIndent()

        val pixels = requireNotNull(
            EffectInterpreter(
                EffectCompiler.compile(json),
                List(7) { GroupState() },
            ).frameAt(0).pixels,
        )
        assertEquals(42, pixels.size)
        assertEquals(pixels[0], pixels[7])
        assertEquals(pixels[6], pixels[41])
    }
}
