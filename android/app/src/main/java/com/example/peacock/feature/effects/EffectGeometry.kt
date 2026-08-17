package com.example.peacock.feature.effects

/** Physical layout shared by effect compilation, preview, and wire encoding. */
object EffectGeometry {
    const val GROUP_COUNT = 7
    const val PIXELS_PER_GROUP = 6
    const val PIXEL_COUNT = GROUP_COUNT * PIXELS_PER_GROUP
    const val PIXEL_FRAME_BYTES = 14 + PIXEL_COUNT * 3
}
