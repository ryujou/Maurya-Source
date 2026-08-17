#pragma once

#include <stdbool.h>
#include <stdint.h>

#include "effect_engine.h"

bool lumia_effect_inner_mode_is_valid_impl(uint8_t mode);
void lumia_effect_inner_enter(LumiaEffectEngine *engine,
                              uint8_t group_index,
                              uint8_t mode);
void lumia_effect_inner_advance(LumiaEffectEngine *engine,
                                const LumiaGroupEffectConfig *config,
                                uint8_t group_index,
                                uint32_t elapsed_ms);
LumiaRgb lumia_effect_inner_render_color(const LumiaEffectEngine *engine,
                                         const LumiaGroupEffectConfig *config,
                                         uint8_t group_index);
