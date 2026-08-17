package com.example.peacock.ui.component

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.width
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import com.example.peacock.R
import com.example.peacock.ui.i18n.AppLanguage

@Composable
fun DebugControlPanel(
    debugMode: Boolean,
    appLanguage: AppLanguage,
    showDebugToggle: Boolean,
    showLanguageSelector: Boolean,
    onDebugModeChange: (Boolean) -> Unit,
    onAppLanguageChange: (AppLanguage) -> Unit,
) {
    Column(
        horizontalAlignment = Alignment.End,
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        if (showDebugToggle) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(stringResource(R.string.debug))
                Spacer(Modifier.width(8.dp))
                Switch(
                    checked = debugMode,
                    onCheckedChange = onDebugModeChange,
                    modifier = Modifier.testTag("debug-toggle"),
                )
            }
        }

        if (showLanguageSelector) {
            LanguageSelector(
                appLanguage = appLanguage,
                onLanguageChange = onAppLanguageChange,
            )
        }
    }
}

@Composable
private fun LanguageSelector(
    appLanguage: AppLanguage,
    onLanguageChange: (AppLanguage) -> Unit,
) {
    var expanded by remember { mutableStateOf(false) }
    OutlinedButton(
        onClick = { expanded = true },
        modifier = Modifier.testTag("language-selector"),
    ) {
        Text(languageLabel(appLanguage))
    }
    DropdownMenu(
        expanded = expanded,
        onDismissRequest = { expanded = false },
    ) {
        AppLanguage.entries.forEach { entry ->
            DropdownMenuItem(
                text = { Text(languageLabel(entry)) },
                modifier = Modifier.testTag("language-${entry.name}"),
                onClick = {
                    expanded = false
                    onLanguageChange(entry)
                },
            )
        }
    }
}

@Composable
private fun languageLabel(appLanguage: AppLanguage): String = when (appLanguage) {
    AppLanguage.SYSTEM -> stringResource(R.string.language_follow_system)
    AppLanguage.ZH_CN -> stringResource(R.string.language_chinese)
    AppLanguage.JA_JP -> stringResource(R.string.language_japanese)
}
