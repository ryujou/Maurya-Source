package com.example.peacock.util

data class HsvColor(val h: Int, val s: Int, val v: Int)

object ColorUtils {
    fun parseHexColor(input: String): Triple<Int, Int, Int>? {
        val raw = input.trim().removePrefix("#")
        if (!raw.matches(Regex("[0-9a-fA-F]{6}"))) return null
        return Triple(
            raw.substring(0, 2).toInt(16),
            raw.substring(2, 4).toInt(16),
            raw.substring(4, 6).toInt(16),
        )
    }

    fun toHex(hsv: HsvColor): String {
        val rgb = hsvToRgb(hsv.h, hsv.s, hsv.v)
        return "#${toHex2(rgb.first)}${toHex2(rgb.second)}${toHex2(rgb.third)}"
    }

    fun rgbToHsv(r: Int, g: Int, b: Int): HsvColor {
        val rn = r / 255f
        val gn = g / 255f
        val bn = b / 255f
        val max = maxOf(rn, gn, bn)
        val min = minOf(rn, gn, bn)
        val delta = max - min
        var h = 0f
        if (delta > 0f) {
            h = when (max) {
                rn -> ((gn - bn) / delta) % 6f
                gn -> (bn - rn) / delta + 2f
                else -> (rn - gn) / delta + 4f
            } * 60f
            if (h < 0f) h += 360f
        }
        val s = if (max == 0f) 0f else delta / max
        return HsvColor(h.toInt(), (s * 255f).toInt(), (max * 255f).toInt())
    }

    fun hsvToRgb(h: Int, s: Int, v: Int): Triple<Int, Int, Int> {
        val hue = ((h % 360) + 360) % 360
        val sat = s.coerceIn(0, 255) / 255f
        val value = v.coerceIn(0, 255) / 255f
        val c = value * sat
        val x = c * (1f - kotlin.math.abs(((hue / 60f) % 2f) - 1f))
        val m = value - c
        val (r1, g1, b1) = when {
            hue < 60 -> Triple(c, x, 0f)
            hue < 120 -> Triple(x, c, 0f)
            hue < 180 -> Triple(0f, c, x)
            hue < 240 -> Triple(0f, x, c)
            hue < 300 -> Triple(x, 0f, c)
            else -> Triple(c, 0f, x)
        }
        return Triple(
            ((r1 + m) * 255f).toInt().coerceIn(0, 255),
            ((g1 + m) * 255f).toInt().coerceIn(0, 255),
            ((b1 + m) * 255f).toInt().coerceIn(0, 255),
        )
    }

    private fun toHex2(value: Int): String = value.coerceIn(0, 255).toString(16).padStart(2, '0').uppercase()
}
