#pragma once

#include <stddef.h>
#include <stdint.h>

#include "esp_err.h"

#ifdef __cplusplus
extern "C" {
#endif

esp_err_t lumia_led_route_init(size_t max_leds, int initial_gpio);
esp_err_t lumia_led_route_select(int gpio_num);
esp_err_t lumia_led_route_write(const uint8_t (*grb)[3], size_t led_count);
esp_err_t lumia_led_route_clear(void);

#ifdef __cplusplus
}
#endif
