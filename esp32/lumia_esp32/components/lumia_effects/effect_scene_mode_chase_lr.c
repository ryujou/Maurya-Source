#include "effect_scene_mode_chase_lr.h"

#include <string.h>

void lumia_effect_scene_mode_chase_lr_render(
    const LumiaSceneState *state,
    uint8_t gains[LUMIA_EFFECT_GROUP_COUNT])
{
    uint8_t active_group = (uint8_t)(state->position_q8 / 256u);

    memset(gains, 0, LUMIA_EFFECT_GROUP_COUNT);
    gains[active_group % LUMIA_EFFECT_GROUP_COUNT] = 255u;
}
