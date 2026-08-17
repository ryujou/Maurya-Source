#pragma once

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "effect_types.h"
#include "esp_err.h"

#ifdef __cplusplus
extern "C" {
#endif

#define LUMIA_LED_TDM_CHANNEL_COUNT 7u

typedef struct {
    uint8_t gpio_num;
    uint16_t led_count;
    uint16_t offset;
} LumiaLedTdmChannelConfig;

typedef struct {
    size_t channel_count;
    size_t total_leds;
    LumiaLedTdmChannelConfig channels[LUMIA_LED_TDM_CHANNEL_COUNT];
} LumiaLedTdmConfig;

typedef struct {
    uint32_t tx_error_count;
    uint32_t gpio_switch_error_count;
    uint32_t init_error_count;
    uint32_t max_scan_gap_us;
} LumiaLedTdmDiagnostics;

esp_err_t lumia_led_tdm_init(const LumiaLedTdmConfig *config);
esp_err_t lumia_led_tdm_set_linear_frame(const LumiaRgb *pixels, size_t pixel_count);
esp_err_t lumia_led_tdm_set_pixel(uint8_t channel,
                                  uint16_t index,
                                  uint8_t r,
                                  uint8_t g,
                                  uint8_t b);
esp_err_t lumia_led_tdm_set_channel_frame(uint8_t channel,
                                          const LumiaRgb *pixels,
                                          uint16_t count);
esp_err_t lumia_led_tdm_flush(void);
esp_err_t lumia_led_tdm_clear(void);
size_t lumia_led_tdm_total_leds(void);
bool lumia_led_tdm_is_initialized(void);
void lumia_led_tdm_get_diagnostics(LumiaLedTdmDiagnostics *diagnostics);
void lumia_led_tdm_clear_diagnostics(void);

#ifdef __cplusplus
}
#endif
