package com.example.peacock.ui.screen.effects

import org.junit.Assert.assertEquals
import org.junit.Test

class EffectLibraryStatusTest {
    @Test
    fun bilingualStatus_usesOnlyTheSelectedLanguage() {
        val status = "已复制并打开代码程序 / コード版を作成して開きました"

        assertEquals("已复制并打开代码程序", localizedTransferStatus(status, japanese = false))
        assertEquals("コード版を作成して開きました", localizedTransferStatus(status, japanese = true))
    }

    @Test
    fun unilingualStatus_isPreserved() {
        assertEquals(
            "导入文件损坏",
            localizedTransferStatus("导入文件损坏", japanese = true),
        )
    }
}
