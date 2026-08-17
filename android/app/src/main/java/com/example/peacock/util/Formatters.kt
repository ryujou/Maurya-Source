package com.example.peacock.util

import android.content.Context
import com.example.peacock.R
import java.util.Locale

object Formatters {
    fun saveStateLabel(context: Context, value: Int): String = when (value) {
        0 -> context.getString(R.string.save_state_saved)
        1 -> context.getString(R.string.save_state_pending)
        2 -> context.getString(R.string.save_state_saving)
        3 -> context.getString(R.string.save_state_failed)
        else -> context.getString(R.string.unknown_with_value, value)
    }

    fun tempLabel(tempCx100: Int): String =
        if (tempCx100 == 0) "--" else String.format(Locale.getDefault(), "%.2f C", tempCx100 / 100f)

    fun voltageLabel(vddaMv: Int): String = if (vddaMv == 0) "--" else "$vddaMv mV"
}
