#pragma once

#include <stdbool.h>
#include <stdint.h>

#include "effect_engine.h"

bool lumia_effect_scene_mode_is_valid_impl(uint8_t mode);
void lumia_effect_scene_enter(LumiaEffectEngine *engine, uint8_t mode);
void lumia_effect_scene_advance(LumiaEffectEngine *engine,
                                uint8_t mode,
                                uint8_t param,
                                uint32_t elapsed_ms);
void lumia_effect_scene_render_gains(const LumiaEffectEngine *engine,
                                     uint8_t mode,
                                     uint8_t gains[LUMIA_EFFECT_GROUP_COUNT]);
