#pragma once

#include <stdbool.h>
#include <stdint.h>

#include "effect_types.h"

void lumia_effect_config_default(LumiaEffectConfig *config);
bool lumia_effect_inner_mode_is_valid(uint8_t mode);
bool lumia_effect_scene_mode_is_valid(uint8_t mode);

void lumia_effect_engine_init(LumiaEffectEngine *engine);
void lumia_effect_engine_reset(LumiaEffectEngine *engine);

/*
 * Call once for every elapsed millisecond. The frame tick consumes the
 * accumulated time, so delayed or skipped frame calls preserve effect speed.
 */
void lumia_effect_engine_tick_1ms(LumiaEffectEngine *engine);

/*
 * Advance the selected effect and render one corrected linear RGB frame.
 * Invalid input clears out_frame and returns false.
 */
bool lumia_effect_engine_tick_frame(
    LumiaEffectEngine *engine,
    const LumiaEffectConfig *config,
    RgbFrame *out_frame);

LumiaRgb lumia_effect_hsv_to_rgb(uint16_t hue, uint8_t saturation, uint8_t value);
LumiaRgb lumia_effect_apply_color_correction(
    LumiaRgb color,
    const LumiaEffectConfig *config);
