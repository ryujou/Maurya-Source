#pragma once

#include <stdbool.h>

#include "esp_err.h"
#include "led_tdm.h"

#ifdef __cplusplus
extern "C" {
#endif

esp_err_t lumia_led_tdm_scan_init(void);
esp_err_t lumia_led_tdm_scan_flush(void);
esp_err_t lumia_led_tdm_scan_step(void);
bool lumia_led_tdm_scan_is_initialized(void);
void lumia_led_tdm_scan_get_diagnostics(LumiaLedTdmDiagnostics *diagnostics);
void lumia_led_tdm_scan_clear_diagnostics(void);
void lumia_led_tdm_scan_set_paused(bool paused);

#ifdef __cplusplus
}
#endif
