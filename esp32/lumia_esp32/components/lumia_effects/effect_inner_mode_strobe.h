#pragma once

#include <stdint.h>

#include "effect_engine.h"

void lumia_effect_inner_mode_strobe_advance(LumiaInnerState *state,
                                            uint8_t speed,
                                            uint32_t elapsed_ms);
LumiaRgb lumia_effect_inner_mode_strobe_render(const LumiaInnerState *state,
                                               const LumiaGroupEffectConfig *config);
