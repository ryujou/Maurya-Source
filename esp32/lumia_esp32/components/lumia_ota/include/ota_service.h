#pragma once

#include <stdbool.h>
#include <stdint.h>

#include "esp_err.h"
#include "esp_http_server.h"
#include "ota_session.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef enum {
    LUMIA_OTA_WAITING = 0,
    LUMIA_OTA_RECEIVING,
    LUMIA_OTA_VERIFYING,
    LUMIA_OTA_VERIFIED,
    LUMIA_OTA_REBOOTING,
    LUMIA_OTA_FAILED,
} LumiaOtaState;

typedef struct {
    LumiaOtaState state;
    uint32_t received_bytes;
    uint32_t expected_bytes;
    esp_err_t error;
} LumiaOtaStatus;

typedef void (*lumia_ota_activity_fn)(bool receiving, void *user_ctx);

typedef struct {
    LumiaOtaSession session;
    uint32_t secure_version;
    bool session_timeout_enabled;
    lumia_ota_activity_fn on_activity;
    void *user_ctx;
} LumiaOtaServiceConfig;

esp_err_t lumia_ota_service_start(const LumiaOtaServiceConfig *config);
esp_err_t lumia_ota_service_register_http(httpd_handle_t server);
esp_err_t lumia_ota_service_begin(uint32_t expected_bytes,
                                  const uint8_t expected_sha[32]);
esp_err_t lumia_ota_service_write(uint32_t offset,
                                  const uint8_t *data,
                                  size_t length,
                                  uint32_t *next_offset);
esp_err_t lumia_ota_service_commit(void);
esp_err_t lumia_ota_service_cancel(void);
void lumia_ota_service_get_status(LumiaOtaStatus *status);
bool lumia_ota_service_is_receiving(void);
const char *lumia_ota_state_name(LumiaOtaState state);

#ifdef __cplusplus
}
#endif
