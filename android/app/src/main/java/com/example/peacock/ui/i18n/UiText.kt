package com.example.peacock.ui.i18n

import android.content.Context
import androidx.annotation.StringRes
import androidx.compose.runtime.Composable
import androidx.compose.ui.res.stringResource
import com.example.peacock.R

@Composable
fun sceneModeLabel(mode: Int): String = when (mode) {
    1 -> stringResource(R.string.scene_mode_static)
    2 -> stringResource(R.string.scene_mode_left)
    3 -> stringResource(R.string.scene_mode_right)
    4 -> stringResource(R.string.scene_mode_pingpong)
    else -> mode.toString()
}

@Composable
fun innerModeLabel(mode: Int): String = when (mode) {
    1 -> stringResource(R.string.group_mode_steady)
    3 -> stringResource(R.string.group_mode_strobe)
    else -> stringResource(R.string.group_mode_steady)
}

fun sceneModeLabel(context: Context, mode: Int): String = context.getString(sceneModeLabelRes(mode))

fun innerModeLabel(context: Context, mode: Int): String = context.getString(innerModeLabelRes(mode))

@StringRes
fun sceneModeLabelRes(mode: Int): Int = when (mode) {
    1 -> R.string.scene_mode_static
    2 -> R.string.scene_mode_left
    3 -> R.string.scene_mode_right
    4 -> R.string.scene_mode_pingpong
    else -> R.string.scene_mode_static
}

@StringRes
fun innerModeLabelRes(mode: Int): Int = when (mode) {
    1 -> R.string.group_mode_steady
    3 -> R.string.group_mode_strobe
    else -> R.string.group_mode_steady
}
