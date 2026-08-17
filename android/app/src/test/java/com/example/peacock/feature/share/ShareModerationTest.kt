package com.example.peacock.feature.share

import org.json.JSONObject
import org.junit.Assert.assertSame
import org.junit.Test

class ShareModerationTest {
    @Test
    fun safeEffectPassesLocalPrecheck() {
        assertSame(ShareModeration.Result.Accepted, ShareModeration.check(effect("星空彩虹")))
    }

    @Test
    fun nfkcZeroWidthAndPunctuationCannotBypassTrie() {
        val envelope = effect("六\u200B四-事 件")
        assertSame(ShareModeration.Result.Rejected, ShareModeration.check(envelope))
    }

    @Test
    fun directionMarksAndCjkPunctuationCannotBypassTrie() {
        val envelope = effect("六\u200E四、事，件")
        assertSame(ShareModeration.Result.Rejected, ShareModeration.check(envelope))
    }

    @Test
    fun sourceIsCheckedAsWellAsDisplayName() {
        val envelope = effect("普通灯效", "effect \"demo\" { // 法轮功\n wait(1s); }")
        assertSame(ShareModeration.Result.Rejected, ShareModeration.check(envelope))
    }

    private fun effect(name: String, source: String = "effect \"safe\" { wait(1s); }") = ShareEnvelope(
        kind = ShareKind.EFFECT,
        displayName = ShareDisplayName(name, ""),
        payload = JSONObject()
            .put("sourceKind", "script")
            .put("editorSchema", 4)
            .put("programSchema", 6)
            .put("source", source),
        contentHash = "0".repeat(64),
    )
}
