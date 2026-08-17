#pragma once

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "effect_types.h"
#include "esp_err.h"
#include "led_tdm.h"

#ifdef __cplusplus
extern "C" {
#endif

esp_err_t lumia_led_tdm_framebuffer_init(const LumiaLedTdmConfig *config);
esp_err_t lumia_led_tdm_framebuffer_set_linear(const LumiaRgb *pixels, size_t pixel_count);
esp_err_t lumia_led_tdm_framebuffer_set_pixel(uint8_t channel,
                                              uint16_t index,
                                              uint8_t r,
                                              uint8_t g,
                                              uint8_t b);
esp_err_t lumia_led_tdm_framebuffer_set_channel(uint8_t channel,
                                                const LumiaRgb *pixels,
                                                uint16_t count);
bool lumia_led_tdm_framebuffer_publish(void);
bool lumia_led_tdm_framebuffer_consume_pending(void);
const LumiaRgb *lumia_led_tdm_framebuffer_front_channel(uint8_t channel,
                                                        uint16_t *led_count,
                                                        uint8_t *gpio_num);
void lumia_led_tdm_framebuffer_clear_all(void);
size_t lumia_led_tdm_framebuffer_total_leds(void);
size_t lumia_led_tdm_framebuffer_channel_count(void);
bool lumia_led_tdm_framebuffer_is_initialized(void);

#ifdef __cplusplus
}
#endif
