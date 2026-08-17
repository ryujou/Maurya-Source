package com.example.peacock.ui.screen.effects

import com.example.peacock.feature.effects.EffectCompileIssue
import com.example.peacock.ui.i18n.AppLanguage
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Test

class EditorErrorLocalizationTest {
    private val issue = EffectCompileIssue(
        code = "syntax",
        messageZh = "第12行：group后需要“(”",
        messageJa = "12行目：groupの後に「(」が必要です",
    )

    @Test
    fun chineseEditorShowsOnlyChineseDiagnostic() {
        val message = localizedEditorError(
            AppLanguage.ZH_CN,
            issue.combinedMessage,
            issue,
        )
        assertEquals(issue.messageZh, message)
        assertFalse(message.contains(issue.messageJa))
    }

    @Test
    fun japaneseEditorShowsOnlyJapaneseDiagnostic() {
        val message = localizedEditorError(
            AppLanguage.JA_JP,
            issue.combinedMessage,
            issue,
        )
        assertEquals(issue.messageJa, message)
        assertFalse(message.contains(issue.messageZh))
    }

    @Test
    fun unstructuredFailureUsesFallbackMessage() {
        assertEquals(
            "transport failed",
            localizedEditorError(AppLanguage.ZH_CN, "transport failed", null),
        )
    }
}
