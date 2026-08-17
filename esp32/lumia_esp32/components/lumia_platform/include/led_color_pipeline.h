#pragma once

#include <stddef.h>
#include <stdint.h>

#include "effect_types.h"

#ifdef __cplusplus
extern "C" {
#endif

void lumia_led_color_pipeline_prepare(const LumiaRgb *input,
                                      uint8_t (*output_grb)[3],
                                      size_t led_count);

#ifdef __cplusplus
}
#endif
