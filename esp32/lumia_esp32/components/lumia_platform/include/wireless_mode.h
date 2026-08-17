#pragma once

#include "esp_err.h"

typedef enum {
    LUMIA_WIRELESS_MODE_BLE = 0,
    LUMIA_WIRELESS_MODE_WIFI = 1,
} LumiaWirelessMode;

esp_err_t lumia_wireless_mode_store_init(void);
esp_err_t lumia_wireless_mode_load(LumiaWirelessMode *mode);
esp_err_t lumia_wireless_mode_save(LumiaWirelessMode mode);
const char *lumia_wireless_mode_name(LumiaWirelessMode mode);
