#pragma once

#include <stdbool.h>
#include <stdint.h>

#include "esp_err.h"

#define SERIAL_TRANSPORT_MAX_FRAME_LEN  64u
#define SERIAL_TRANSPORT_RX_BUFFER_CAP  128u

typedef void (*serial_transport_frame_handler_t)(const uint8_t *data,
                                                 uint16_t len,
                                                 void *user_ctx);

typedef enum {
    SERIAL_TRANSPORT_DIAG_RX_OVERFLOW = 0,
    SERIAL_TRANSPORT_DIAG_PARSE_ERROR,
} SerialTransportDiagEvent;

typedef void (*serial_transport_diag_handler_t)(SerialTransportDiagEvent event,
                                                void *user_ctx);

typedef struct {
    serial_transport_frame_handler_t on_frame;
    serial_transport_diag_handler_t on_diag;
    void *user_ctx;
} SerialTransportConfig;

esp_err_t lumia_serial_transport_init(const SerialTransportConfig *config);
esp_err_t lumia_serial_transport_send(const uint8_t *data, uint16_t len);
bool lumia_serial_transport_is_connected(void);
