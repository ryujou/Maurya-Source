package com.example.peacock.feature.effects

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test
import org.json.JSONArray
import org.json.JSONObject

class EffectCompilerTest {
    @Test
    fun compilesNestedProgramAndCalculatesDuration() {
        val json = """{"blocks":{"languageVersion":0,"blocks":[
          {"type":"maurya_start","id":"s","next":{"block":{
            "type":"maurya_repeat","id":"r","fields":{"COUNT":3},
            "inputs":{"DO":{"block":{"type":"maurya_adjust_hsv","id":"a",
              "fields":{"TARGET":"ALL","H":6,"S":0,"V":0},
              "next":{"block":{"type":"maurya_wait","id":"w",
                "fields":{"DURATION":100,"UNIT":"MS"}}}}}}
          }}}
        ]}}"""
        val compiled = EffectCompiler.compile(json)
        assertEquals(4, compiled.blockCount)
        assertEquals(300L, compiled.estimatedDurationMs)
    }

    @Test
    fun infiniteLoopHasNoDuration() {
        val json = """{"blocks":{"languageVersion":0,"blocks":[
          {"type":"maurya_start","id":"s","next":{"block":{
            "type":"maurya_forever","id":"f","inputs":{"DO":{"block":{
              "type":"maurya_wait","id":"w","fields":{"DURATION":100,"UNIT":"MS"}
            }}}
          }}}
        ]}}"""
        assertNull(EffectCompiler.compile(json).estimatedDurationMs)
    }

    @Test
    fun rejectsOrphanBlocks() {
        val json = """{"blocks":{"languageVersion":0,"blocks":[
          {"type":"maurya_start","id":"s"},
          {"type":"maurya_wait","id":"w","fields":{"DURATION":100,"UNIT":"MS"}}
        ]}}"""
        assertThrows(EffectCompileException::class.java) { EffectCompiler.compile(json) }
    }

    @Test
    fun compilesTypedVariableForLoopAndCalculatesFiniteDuration() {
        val json = """{
          "variables":[{"name":"i","id":"var-i","type":"Number"}],
          "blocks":{"languageVersion":0,"blocks":[{
            "type":"maurya_start","id":"start","next":{"block":{
              "type":"maurya_for","id":"for","fields":{"VAR":{"id":"var-i"}},
              "inputs":{
                "FROM":{"shadow":{"type":"math_number","id":"from","fields":{"NUM":0}}},
                "TO":{"shadow":{"type":"math_number","id":"to","fields":{"NUM":10}}},
                "BY":{"shadow":{"type":"math_number","id":"by","fields":{"NUM":5}}},
                "DO":{"block":{"type":"maurya_wait_value","id":"wait","fields":{"UNIT":"MS"},
                  "inputs":{"DURATION":{"shadow":{"type":"math_number","id":"duration","fields":{"NUM":100}}}}
                }}
              }
            }}
          }]}
        }"""
        val compiled = EffectCompiler.compile(json)
        assertEquals(300L, compiled.estimatedDurationMs)
        assertEquals(EffectValueType.NUMBER, compiled.variables["var-i"])
        assertTrue(EffectCompiler.canonicalJson(compiled).contains("\"op\":\"for\""))
    }

    @Test
    fun rejectsBreakOutsideLoopAndTypedInputMismatch() {
        val breakProgram = """{"blocks":{"languageVersion":0,"blocks":[{
          "type":"maurya_start","id":"s","next":{"block":{"type":"maurya_break","id":"b"}}
        }]}}"""
        assertThrows(EffectCompileException::class.java) { EffectCompiler.compile(breakProgram) }

        val mismatch = """{
          "variables":[{"name":"flag","id":"flag","type":"Boolean"}],
          "blocks":{"languageVersion":0,"blocks":[{
            "type":"maurya_start","id":"s","next":{"block":{
              "type":"maurya_wait_value","id":"w","fields":{"UNIT":"MS"},
              "inputs":{"DURATION":{"block":{"type":"maurya_var_get_boolean","id":"g","fields":{"VAR":{"id":"flag"}}}}}
            }}
          }]}
        }"""
        assertThrows(EffectCompileException::class.java) { EffectCompiler.compile(mismatch) }
    }

    @Test
    fun rejectsLoopTailColourThatIsOverwrittenBeforeNextYield() {
        fun next(block: JSONObject) = JSONObject().put("block", block)
        val blue = JSONObject().put("type", "maurya_set_color").put("id", "blue")
            .put("fields", JSONObject().put("TARGET", "ALL").put("COLOR", "#0000FF"))
        val wait = JSONObject().put("type", "maurya_wait").put("id", "wait-red")
            .put("fields", JSONObject().put("DURATION", 2).put("UNIT", "SEC"))
            .put("next", next(blue))
        val red = JSONObject().put("type", "maurya_set_color").put("id", "red")
            .put("fields", JSONObject().put("TARGET", "ALL").put("COLOR", "#FF0000"))
            .put("next", next(wait))
        val mode = JSONObject().put("type", "maurya_mode").put("id", "mode")
            .put("fields", JSONObject().put("TARGET", "ALL").put("MODE", 3).put("PARAM", 128))
            .put("next", next(red))
        val forever = JSONObject().put("type", "maurya_forever").put("id", "forever")
            .put("inputs", JSONObject().put("DO", next(mode)))
        val start = JSONObject().put("type", "maurya_start").put("id", "start")
            .put("next", next(forever))
        val json = JSONObject().put(
            "blocks",
            JSONObject().put("languageVersion", 0).put("blocks", JSONArray().put(start)),
        ).toString()
        val error = assertThrows(EffectCompileException::class.java) { EffectCompiler.compile(json) }
        val issue = error.diagnostics.single()
        assertEquals("EFFECT_STATE_NOT_OBSERVABLE", issue.code)
        assertEquals("blue", issue.sourceId)
        assertEquals(2_000L, issue.quickFixWaitMs)
    }
}
