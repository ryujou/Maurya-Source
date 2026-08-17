package com.example.peacock.ui.i18n

import android.content.Context
import android.content.SharedPreferences
import android.content.res.Resources
import androidx.appcompat.app.AppCompatDelegate
import androidx.core.os.LocaleListCompat
import java.util.Locale

object AppLanguageManager {
    private const val PREFS_NAME = "peacock_i18n"
    private const val KEY_LANGUAGE = "app_language"
    private const val ZH_TAG = "zh-CN"
    private const val JA_TAG = "ja"

    fun initialize(context: Context, allowManualOverride: Boolean) {
        val selection = if (allowManualOverride) {
            loadSelection(context)
        } else {
            persistSelection(context, AppLanguage.SYSTEM)
            AppLanguage.SYSTEM
        }
        applySelection(context, selection, allowManualOverride)
    }

    fun loadSelection(context: Context): AppLanguage {
        return AppLanguage.fromStorage(
            prefs(context).getString(KEY_LANGUAGE, AppLanguage.SYSTEM.storageValue),
        )
    }

    fun applySelection(
        context: Context,
        selection: AppLanguage,
        allowManualOverride: Boolean,
    ) {
        val normalized = if (allowManualOverride) selection else AppLanguage.SYSTEM
        persistSelection(context, normalized)
        val languageTag = resolveLanguageTag(context, normalized)
        val current = AppCompatDelegate.getApplicationLocales().toLanguageTags()
        if (current != languageTag) {
            AppCompatDelegate.setApplicationLocales(LocaleListCompat.forLanguageTags(languageTag))
        }
    }

    fun currentDisplayLanguage(context: Context): DisplayLanguage {
        val locale = context.resources.configuration.locales[0] ?: Locale.getDefault()
        return if (locale.language == "ja") DisplayLanguage.JA_JP else DisplayLanguage.ZH_CN
    }

    private fun resolveLanguageTag(context: Context, selection: AppLanguage): String {
        return when (selection) {
            AppLanguage.ZH_CN -> ZH_TAG
            AppLanguage.JA_JP -> JA_TAG
            AppLanguage.SYSTEM -> {
                val systemLocale = Resources.getSystem().configuration.locales[0] ?: Locale.getDefault()
                if (systemLocale.language == "ja") JA_TAG else ZH_TAG
            }
        }
    }

    private fun persistSelection(context: Context, selection: AppLanguage) {
        prefs(context).edit().putString(KEY_LANGUAGE, selection.storageValue).apply()
    }

    private fun prefs(context: Context): SharedPreferences {
        return context.applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    }
}
