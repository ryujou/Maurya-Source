package com.example.peacock.ui.i18n

enum class AppLanguage(val storageValue: String) {
    SYSTEM("system"),
    ZH_CN("zh-CN"),
    JA_JP("ja-JP");

    companion object {
        fun fromStorage(value: String?): AppLanguage {
            return entries.firstOrNull { it.storageValue == value } ?: SYSTEM
        }
    }
}

enum class DisplayLanguage {
    ZH_CN,
    JA_JP,
}
