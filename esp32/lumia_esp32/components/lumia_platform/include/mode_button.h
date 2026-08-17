#pragma once

#include <stdbool.h>
#include <stdint.h>

#include "esp_err.h"
#include "mode_button_logic.h"

#ifdef __cplusplus
extern "C" {
#endif

esp_err_t lumia_mode_button_init(uint32_t now_ms);
esp_err_t lumia_mode_button_service(uint32_t now_ms,
                                    LumiaModeButtonEvent *event);

#ifdef __cplusplus
}
#endif
