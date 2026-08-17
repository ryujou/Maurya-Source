#include "effect_scene_mode_pingpong.h"

#include <string.h>

void lumia_effect_scene_mode_pingpong_render(
    const LumiaSceneState *state,
    uint8_t gains[LUMIA_EFFECT_GROUP_COUNT])
{
    uint16_t position_q8 = state->position_q8;
    uint8_t active_group;

    if (state->direction < 0) {
        active_group = (uint8_t)((position_q8 + 255u) / 256u);
    } else {
        active_group = (uint8_t)(position_q8 / 256u);
    }
    if (active_group >= LUMIA_EFFECT_GROUP_COUNT) {
        active_group = (uint8_t)(LUMIA_EFFECT_GROUP_COUNT - 1u);
    }

    memset(gains, 0, LUMIA_EFFECT_GROUP_COUNT);
    gains[active_group] = 255u;
}
