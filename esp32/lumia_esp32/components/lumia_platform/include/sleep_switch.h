#pragma once

#include <stdbool.h>
#include <stdint.h>

#include "esp_err.h"

#ifdef __cplusplus
extern "C" {
#endif

esp_err_t lumia_sleep_switch_init(uint32_t now_ms, bool *sleep_requested);
esp_err_t lumia_sleep_switch_service(uint32_t now_ms, bool *sleep_requested);
esp_err_t lumia_sleep_switch_prepare_high_wakeup(void);

#ifdef __cplusplus
}
#endif
