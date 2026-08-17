#pragma once

#include <stdbool.h>
#include <stdint.h>

#include "esp_err.h"

#define LUMIA_BLE_SERVICE_UUID16      0xFFE0u
#define LUMIA_BLE_RX_UUID16           0xFFE1u
#define LUMIA_BLE_TX_UUID16           0xFFE2u
#define BLE_TRANSPORT_MAX_FRAME_LEN   244u
#define BLE_TRANSPORT_RX_BUFFER_CAP   BLE_TRANSPORT_MAX_FRAME_LEN

typedef void (*ble_transport_frame_handler_t)(const uint8_t *data, uint16_t len, void *user_ctx);

typedef enum {
    BLE_TRANSPORT_DIAG_RX_OVERFLOW = 0,
    BLE_TRANSPORT_DIAG_PARSE_ERROR,
} BleTransportDiagEvent;

typedef void (*ble_transport_diag_handler_t)(BleTransportDiagEvent event,
                                             void *user_ctx);

typedef struct {
    ble_transport_frame_handler_t on_frame;
    ble_transport_diag_handler_t on_diag;
    void *user_ctx;
} BleTransportConfig;

esp_err_t lumia_ble_transport_init(const BleTransportConfig *config);
esp_err_t lumia_ble_transport_notify(const uint8_t *data, uint16_t len);
bool lumia_ble_transport_is_connected(void);
const char *lumia_ble_transport_service_uuid(void);
const char *lumia_ble_transport_rx_uuid(void);
const char *lumia_ble_transport_tx_uuid(void);
