#pragma once

#include <stdbool.h>
#include <stdint.h>

typedef struct {
    const uint8_t *data;
    uint16_t len;
} ModbusFrameView;

typedef enum {
    MODBUS_FRAME_UNSUPPORTED = 0,
    MODBUS_FRAME_INCOMPLETE,
    MODBUS_FRAME_COMPLETE,
} ModbusFrameStatus;

bool modbus_frame_is_supported_candidate(const uint8_t *data, uint16_t len);
bool modbus_frame_is_supported_function(uint8_t func);
ModbusFrameStatus modbus_frame_expected_request_length(const uint8_t *data, uint16_t len, uint16_t *expected_len);
bool modbus_frame_crc_ok(const uint8_t *data, uint16_t len);
