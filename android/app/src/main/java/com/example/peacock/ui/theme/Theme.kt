package com.example.peacock.ui.theme

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

private val MauryaColorScheme = darkColorScheme(
    primary = MauryaPrimary,
    onPrimary = MauryaBackground,
    primaryContainer = Color(0xFF293253),
    onPrimaryContainer = MauryaPrimary,
    secondary = MauryaGold,
    onSecondary = MauryaBackground,
    secondaryContainer = Color(0xFF3C3222),
    onSecondaryContainer = Color(0xFFE8D1A7),
    tertiary = MauryaSuccess,
    onTertiary = MauryaBackground,
    background = MauryaBackground,
    onBackground = MauryaOnSurface,
    surface = MauryaSurface,
    onSurface = MauryaOnSurface,
    surfaceVariant = MauryaSurfaceHigh,
    onSurfaceVariant = MauryaOnSurfaceVariant,
    outline = MauryaOutline,
    outlineVariant = Color(0xFF242A3B),
)

@Composable
fun MauryaTheme(
    content: @Composable () -> Unit,
) {
    MaterialTheme(
        colorScheme = MauryaColorScheme,
        typography = Typography,
        content = content,
    )
}
