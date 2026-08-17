package com.example.peacock.feature.share

import com.example.peacock.feature.effects.EffectProgram
import com.example.peacock.feature.effects.EffectProgramCompiler
import com.example.peacock.feature.effects.EffectProgramSchemas
import org.junit.Assert.assertEquals
import org.junit.Assert.assertSame
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test
import org.json.JSONObject

class ShareValidationTest {
    @Test
    fun `built in rainbow can be validated and encoded for temporary sharing`() {
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
        val program = EffectProgramCompiler.normalise(
            EffectProgram(
                id = "example-rainbow",
                nameZh = "无限彩虹",
                nameJa = "無限レインボー",
                workspaceJson = workspace,
                astJson = "",
                astSha256 = "",
                blockCount = 0,
                estimatedDurationMs = null,
                createdAt = 1L,
                updatedAt = 1L,
                editorSchema = EffectProgramSchemas.EDITOR,
                programSchema = EffectProgramSchemas.PROGRAM,
            ),
        )

        val envelope = ShareEnvelopeCodec.forEffect(program)
        assertSame(ShareModeration.Result.Accepted, ShareModeration.check(envelope))
        assertEquals("blocks", envelope.payload.getString("sourceKind"))
        assertTrue(envelope.payload.getString("source").contains("maurya_forever"))
    }

    @Test
    fun `script sharing permits layout characters but rejects unsafe controls`() {
        fun program(source: String) = EffectProgram(
            id = "script-share-test",
            nameZh = "测试",
            nameJa = "テスト",
            workspaceJson = "",
            astJson = "",
            astSha256 = "",
            blockCount = 0,
            estimatedDurationMs = null,
            createdAt = 1L,
            updatedAt = 1L,
            editorSchema = EffectProgramSchemas.EDITOR,
            programSchema = EffectProgramSchemas.PROGRAM,
            sourceKind = com.example.peacock.feature.effects.EffectSourceKind.SCRIPT,
            scriptSource = source,
        )

        val multiline = "effect \"rainbow\" {\r\n\tall.adjustHsv(2, 0, 0);\n\twait(50ms);\r\n}"
        ShareEnvelopeCodec.forEffect(program(multiline))

        assertThrows(IllegalArgumentException::class.java) {
            ShareEnvelopeCodec.forEffect(program(multiline + '\u0000'))
        }
        assertThrows(IllegalArgumentException::class.java) {
            ShareEnvelopeCodec.forEffect(program(multiline + '\u202E'))
        }
    }

    @Test
    fun `token parser accepts only canonical host path or Base58 code`() {
        assertEquals("K8F3Q7D2PX", ShareRepository.parseToken("K8F3Q-7D2PX"))
        assertEquals(
            "K8F3Q7D2PX",
            ShareRepository.parseToken("https://xtbang.top/maurya/s/K8F3Q7D2PX"),
        )
        assertThrows(IllegalArgumentException::class.java) {
            ShareRepository.parseToken("https://example.com/maurya/s/K8F3Q7D2PX")
        }
        assertThrows(IllegalArgumentException::class.java) {
            ShareRepository.parseToken("K8F3Q7D2P0")
        }
    }

    @Test
    fun `strict json rejects duplicate keys and trailing data`() {
        assertThrows(IllegalArgumentException::class.java) {
            StrictJson.validate("{\"a\":1,\"a\":2}", 32)
        }
        assertThrows(IllegalArgumentException::class.java) {
            StrictJson.validate("{}[]", 32)
        }
    }

    @Test
    fun `strict json enforces nesting depth`() {
        val depth32 = "[".repeat(32) + "0" + "]".repeat(32)
        StrictJson.validate(depth32, 32)
        val depth33 = "[".repeat(33) + "0" + "]".repeat(33)
        assertThrows(IllegalArgumentException::class.java) {
            StrictJson.validate(depth33, 32)
        }
    }

    @Test
    fun `content hash matches Python canonical protocol vector`() {
        val payload = JSONObject()
            .put("sourceKind", "script")
            .put("editorSchema", 4)
            .put("programSchema", 6)
            .put("source", "effect \"星空\" { wait(1s); }")
        assertEquals(
            "3c601b0d69f73de53db28a4ef8525094cdd8cf4bacc87c4eb33c909ac23b4b4f",
            ShareEnvelopeCodec.computeContentHash(
                ShareKind.EFFECT,
                ShareDisplayName("测试", "テスト"),
                payload,
            ),
        )
    }

    @Test
    fun `content hash matches Python escaping for slash separators and non BMP`() {
        val payload = JSONObject()
            .put("sourceKind", "script")
            .put("editorSchema", 4)
            .put("programSchema", 6)
            .put("source", "</script>\u2028😀\n")
        assertEquals(
            "c7c512390d163daddf80c420d53bf8162e107600601a18e7f1d7d023a455ae12",
            ShareEnvelopeCodec.computeContentHash(
                ShareKind.EFFECT,
                ShareDisplayName("名字😀", ""),
                payload,
            ),
        )
    }
}
