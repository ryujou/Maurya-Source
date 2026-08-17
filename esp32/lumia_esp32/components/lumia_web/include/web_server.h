#pragma once

#include "esp_err.h"
#include "web_control.h"

typedef struct {
    lumia_web_control_exchange_fn exchange;
    void *user_ctx;
} LumiaWebServerConfig;

esp_err_t lumia_web_server_start(const LumiaWebServerConfig *config);
esp_err_t lumia_web_server_start_ota(void);
const char *lumia_web_server_ssid(void);
