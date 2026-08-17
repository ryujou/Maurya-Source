#pragma once

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "esp_err.h"

#ifdef __cplusplus
extern "C" {
#endif

#define LUMIA_OTA_TOKEN_LEN 16u
#define LUMIA_OTA_NONCE_LEN 16u
#define LUMIA_OTA_SSID_MAX_LEN 32u

typedef struct {
    char ssid[LUMIA_OTA_SSID_MAX_LEN + 1u];
    uint8_t bssid[6];
    uint8_t token[LUMIA_OTA_TOKEN_LEN];
    uint32_t timeout_seconds;
} LumiaOtaSession;

esp_err_t lumia_ota_session_prepare(const uint8_t nonce[LUMIA_OTA_NONCE_LEN],
                                    LumiaOtaSession *session);
esp_err_t lumia_ota_session_cancel_prepare(void);
esp_err_t lumia_ota_session_take_boot(LumiaOtaSession *session,
                                      bool *requested);
esp_err_t lumia_ota_session_force_ble_next_boot(void);
esp_err_t lumia_ota_session_take_force_ble(bool *force_ble);
esp_err_t lumia_ota_session_clear(void);

#ifdef __cplusplus
}
#endif
