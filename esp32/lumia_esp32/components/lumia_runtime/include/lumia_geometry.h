#pragma once

/*
 * Canonical geometry for the production Maurya hardware.
 *
 * The seven logical groups are flattened group-by-group. Each group owns six
 * consecutive RGB pixels, so valid linear indexes are 0 through 41. Keep
 * transport framing, effects, runtime state, and the physical strip adapter
 * derived from these constants instead of introducing local geometry values.
 */
#define LUMIA_GEOMETRY_GROUP_COUNT       7u
#define LUMIA_GEOMETRY_PIXELS_PER_GROUP  6u
#define LUMIA_GEOMETRY_PIXEL_COUNT       \
    (LUMIA_GEOMETRY_GROUP_COUNT * LUMIA_GEOMETRY_PIXELS_PER_GROUP)

#if LUMIA_GEOMETRY_GROUP_COUNT != 7u || \
    LUMIA_GEOMETRY_PIXELS_PER_GROUP != 6u || \
    LUMIA_GEOMETRY_PIXEL_COUNT != 42u
#error "Maurya production geometry must remain 7 groups x 6 pixels = 42 pixels"
#endif
