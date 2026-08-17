#pragma once

#include <stdbool.h>
#include <stdint.h>

#include "esp_err.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef enum {
    LUMIA_STATUS_LED_OFF = 0,
    LUMIA_STATUS_LED_SOLID,
    LUMIA_STATUS_LED_WIFI_BLINK,
    LUMIA_STATUS_LED_SWITCHING,
    LUMIA_STATUS_LED_OTA,
} LumiaStatusLedPattern;

esp_err_t lumia_ble_status_led_init(void);
esp_err_t lumia_ble_status_led_set_connected(bool connected);
esp_err_t lumia_status_led_set_pattern(LumiaStatusLedPattern pattern,
                                       uint32_t now_ms);
esp_err_t lumia_status_led_service(uint32_t now_ms);

#ifdef __cplusplus
}
#endif
