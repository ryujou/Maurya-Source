#pragma once

#include <stdbool.h>
#include <stdint.h>

#include "effect_types.h"
#include "esp_err.h"

#ifdef __cplusplus
extern "C" {
#endif

#define LUMIA_LED_STRIP_RGB_COMPONENTS 3u

typedef uint8_t LumiaLedStripFrame[LUMIA_EFFECT_LED_COUNT][LUMIA_LED_STRIP_RGB_COMPONENTS];

esp_err_t lumia_led_strip_init(void);
esp_err_t lumia_led_strip_write(const LumiaLedStripFrame rgb);
esp_err_t lumia_led_strip_clear(void);
void lumia_led_strip_set_paused(bool paused);

#ifdef __cplusplus
}
#endif
