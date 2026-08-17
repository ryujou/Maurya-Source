#pragma once

#include <stdint.h>

#include "effect_engine.h"

void lumia_effect_scene_mode_pingpong_render(
    const LumiaSceneState *state,
    uint8_t gains[LUMIA_EFFECT_GROUP_COUNT]);
