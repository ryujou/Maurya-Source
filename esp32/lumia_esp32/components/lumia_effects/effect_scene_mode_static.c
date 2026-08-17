#include "effect_scene_mode_static.h"

void lumia_effect_scene_mode_static_render(
    uint8_t gains[LUMIA_EFFECT_GROUP_COUNT])
{
    uint8_t group;

    for (group = 0u; group < LUMIA_EFFECT_GROUP_COUNT; ++group) {
        gains[group] = 255u;
    }
}
