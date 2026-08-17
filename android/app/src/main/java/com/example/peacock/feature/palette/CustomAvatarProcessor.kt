package com.example.peacock.feature.palette

import android.content.ContentResolver
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.ImageDecoder
import android.graphics.Matrix
import android.net.Uri
import java.io.ByteArrayOutputStream
import kotlin.math.abs
import kotlin.math.cbrt
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.roundToInt

data class AvatarTransform(
    val zoom: Float = 1f,
    val panX: Float = 0f,
    val panY: Float = 0f,
    val rotation: Int = 0,
)

object CustomAvatarProcessor {
    fun decode(resolver: ContentResolver, uri: Uri): Bitmap {
        val source = ImageDecoder.createSource(resolver, uri)
        return ImageDecoder.decodeBitmap(source) { decoder, info, _ ->
            decoder.allocator = ImageDecoder.ALLOCATOR_SOFTWARE
            val largest = max(info.size.width, info.size.height)
            var sample = 1
            while (largest / sample > 2048) sample *= 2
            decoder.setTargetSampleSize(sample)
        }
    }

    fun crop(source: Bitmap, transform: AvatarTransform): Bitmap {
        val output = Bitmap.createBitmap(96, 96, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(output)
        canvas.drawColor(Color.TRANSPARENT)
        val rotated = abs(transform.rotation % 180) == 90
        val logicalWidth = if (rotated) source.height else source.width
        val logicalHeight = if (rotated) source.width else source.height
        val scale = max(96f / logicalWidth, 96f / logicalHeight) * transform.zoom.coerceIn(1f, 6f)
        val matrix = Matrix().apply {
            postTranslate(-source.width / 2f, -source.height / 2f)
            postRotate(transform.rotation.toFloat())
            postScale(scale, scale)
            postTranslate(48f + transform.panX * 96f / 320f, 48f + transform.panY * 96f / 320f)
        }
        canvas.drawBitmap(source, matrix, null)
        return output
    }

    fun compress(bitmap: Bitmap): ByteArray {
        for (quality in listOf(78, 68, 58, 48, 38, 30)) {
            val bytes = ByteArrayOutputStream().use { output ->
                bitmap.compress(Bitmap.CompressFormat.WEBP_LOSSY, quality, output)
                output.toByteArray()
            }
            if (bytes.size <= CustomPaletteRepository.MAX_AVATAR_BYTES) return bytes
        }
        val quantized = bitmap.copy(Bitmap.Config.ARGB_8888, true)
        val pixels = IntArray(96 * 96)
        quantized.getPixels(pixels, 0, 96, 0, 0, 96, 96)
        pixels.indices.forEach { index ->
            val color = pixels[index]
            pixels[index] = Color.argb(Color.alpha(color),
                (Color.red(color) / 16f).roundToInt().coerceAtMost(15) * 16,
                (Color.green(color) / 16f).roundToInt().coerceAtMost(15) * 16,
                (Color.blue(color) / 16f).roundToInt().coerceAtMost(15) * 16)
        }
        quantized.setPixels(pixels, 0, 96, 0, 0, 96, 96)
        val bytes = ByteArrayOutputStream().use { output ->
            quantized.compress(Bitmap.CompressFormat.WEBP_LOSSY, 28, output)
            output.toByteArray()
        }
        quantized.recycle()
        require(bytes.size <= CustomPaletteRepository.MAX_AVATAR_BYTES) { "avatar exceeds 6 KiB" }
        return bytes
    }

    fun candidateColors(bitmap: Bitmap, maximum: Int = 5): List<String> {
        data class Point(val lab: DoubleArray, val rgb: IntArray)
        val pixels = IntArray(96 * 96)
        bitmap.getPixels(pixels, 0, 96, 0, 0, 96, 96)
        val points = pixels.filterIndexed { index, color ->
            index % 4 == 0 && Color.alpha(color) >= 160 && run {
                val high = max(Color.red(color), max(Color.green(color), Color.blue(color)))
                val low = min(Color.red(color), min(Color.green(color), Color.blue(color)))
                high in 18..246 && !(high - low < 7 && (high > 224 || high < 36))
            }
        }.map { color -> Point(rgbToOKLab(Color.red(color), Color.green(color), Color.blue(color)),
            intArrayOf(Color.red(color), Color.green(color), Color.blue(color))) }
        if (points.isEmpty()) return listOf("#66CCFF")
        val centers = mutableListOf(points.maxBy { it.lab[1] * it.lab[1] + it.lab[2] * it.lab[2] }.lab.copyOf())
        while (centers.size < min(maximum, points.size)) {
            centers += points.maxBy { point -> centers.minOf { distance(point.lab, it) } }.lab.copyOf()
        }
        var assignments = IntArray(points.size)
        repeat(8) {
            assignments = IntArray(points.size) { index -> centers.indices.minBy { distance(points[index].lab, centers[it]) } }
            centers.indices.forEach { cluster ->
                val members = points.indices.filter { assignments[it] == cluster }
                if (members.isNotEmpty()) for (axis in 0..2) {
                    centers[cluster][axis] = members.sumOf { points[it].lab[axis] } / members.size
                }
            }
        }
        return centers.indices.mapNotNull { cluster ->
            val members = points.indices.filter { assignments[it] == cluster }
            if (members.isEmpty()) null else {
                val rgb = IntArray(3) { axis -> members.map { points[it].rgb[axis] }.average().roundToInt() }
                val chroma = centers[cluster][1].pow(2) + centers[cluster][2].pow(2)
                Triple(String.format("#%02X%02X%02X", rgb[0], rgb[1], rgb[2]), members.size, chroma)
            }
        }.sortedByDescending { it.second * (0.4 + it.third * 8) }
            .map { it.first }.distinct().take(maximum)
    }

    private fun linear(value: Int): Double {
        val channel = value / 255.0
        return if (channel <= 0.04045) channel / 12.92 else ((channel + 0.055) / 1.055).pow(2.4)
    }

    private fun rgbToOKLab(r: Int, g: Int, b: Int): DoubleArray {
        val lr = linear(r); val lg = linear(g); val lb = linear(b)
        val l = cbrt(0.4122214708 * lr + 0.5363325363 * lg + 0.0514459929 * lb)
        val m = cbrt(0.2119034982 * lr + 0.6806995451 * lg + 0.1073969566 * lb)
        val s = cbrt(0.0883024619 * lr + 0.2817188376 * lg + 0.6299787005 * lb)
        return doubleArrayOf(0.2104542553 * l + 0.793617785 * m - 0.0040720468 * s,
            1.9779984951 * l - 2.428592205 * m + 0.4505937099 * s,
            0.0259040371 * l + 0.7827717662 * m - 0.808675766 * s)
    }
    private fun distance(left: DoubleArray, right: DoubleArray) =
        (left[0] - right[0]).pow(2) + (left[1] - right[1]).pow(2) + (left[2] - right[2]).pow(2)
}
